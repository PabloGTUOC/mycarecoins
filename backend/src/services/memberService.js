import { assertActiveMember } from '../db/users.js';
import { getFamilyEntitlements, limitWarning, assertFamilyWritable } from './entitlementService.js';
import { serviceError } from '../utils/httpError.js';

// Soft enforcement (plan §3.4): computed after the admission so the count
// reflects the result; the count query is skipped while the limit is
// unbounded (the free default), which is the common case.
async function memberLimitWarning(client, familyId) {
  const entitlements = await getFamilyEntitlements(client, familyId);
  if (entitlements.limits.max_members == null) return null;
  const { rows } = await client.query(
    `SELECT COUNT(*)::int AS n FROM family_members WHERE family_id = $1 AND status = 'active'`,
    [familyId]
  );
  return limitWarning(entitlements, 'max_members', rows[0].n, 'member_limit_exceeded');
}

export async function listMembers(client, userId, familyId) {
  if (!await assertActiveMember(client, familyId, userId)) {
    return serviceError(403, 'familyNotMember', 'Not a family member.');
  }
  const { rows } = await client.query(
    `SELECT fm.user_id as id, COALESCE(fm.alias, u.display_name, u.email) as name,
            fm.role, fm.status, u.avatar_url
     FROM family_members fm JOIN users u ON u.id = fm.user_id
     WHERE fm.family_id = $1 AND fm.status = 'active'
     ORDER BY u.created_at ASC`,
    [familyId]
  );
  return { data: { members: rows } };
}

export async function listInvitations(client, userId, familyId) {
  if (!await assertActiveMember(client, familyId, userId)) {
    return serviceError(403, 'familyNotMember', 'Not a family member.');
  }
  const { rows } = await client.query(
    `SELECT id, email, name, status, created_at FROM family_invitations
     WHERE family_id = $1 AND status = 'pending' ORDER BY created_at DESC`,
    [familyId]
  );
  return { data: { invitations: rows } };
}

export async function createInvitation(client, user, familyId, { email, name }) {
  const { rows: familyRows } = await client.query(`SELECT name FROM families WHERE id = $1`, [familyId]);
  const fName = familyRows[0]?.name || 'your family';
  const iName = user.display_name || user.email || 'A caregiver';

  const { rows } = await client.query(
    `INSERT INTO family_invitations (family_id, email, name, invited_by)
     VALUES ($1, $2, $3, $4)
     ON CONFLICT (family_id, email) DO UPDATE
       SET status = 'pending', name = EXCLUDED.name, invited_by = EXCLUDED.invited_by
     RETURNING id, email, name, status, created_at`,
    [familyId, email.toLowerCase().trim(), name?.trim() || null, user.id]
  );
  return { data: { invitation: rows[0], inviterName: iName, familyName: fName } };
}

export async function approveMember(client, familyId, userId) {
  const gate = await assertFamilyWritable(client, familyId);
  if (gate) return gate;

  const { rowCount } = await client.query(
    `UPDATE family_members SET status = 'active', role = 'caregiver'
     WHERE family_id = $1 AND user_id = $2 AND status = 'pending'`,
    [familyId, userId]
  );
  if (rowCount === 0) return serviceError(404, 'memberPendingNotFound', 'Pending member not found.');

  const warning = await memberLimitWarning(client, familyId);
  return { data: { success: true, ...(warning && { warning }) } };
}

export async function updateMemberRole(client, familyId, userId, role) {
  const { rows, rowCount } = await client.query(
    `UPDATE family_members SET role = $1 WHERE family_id = $2 AND user_id = $3
     RETURNING family_id, user_id, role`,
    [role, familyId, userId]
  );
  if (!rowCount) return serviceError(404, 'familyMemberNotFound', 'Family member not found.');
  return { data: { member: rows[0] } };
}

export async function joinByInvitation(client, user, { familyId, alias }) {
  if (!user.email) {
    return serviceError(400, 'memberNoEmail', 'Your account has no email address. Use an invite link instead.');
  }
  const { rows: invRows } = await client.query(
    `SELECT id FROM family_invitations WHERE family_id = $1 AND email = $2 AND status = 'pending'`,
    [familyId, user.email.toLowerCase()]
  );
  if (!invRows.length) {
    return serviceError(403, 'invitationNotFound', 'No pending invitation found for your email address.');
  }
  const gate = await assertFamilyWritable(client, familyId);
  if (gate) return gate;

  await client.query(
    `INSERT INTO family_members (family_id, user_id, role, status, alias)
     VALUES ($1, $2, 'caregiver', 'active', $3)
     ON CONFLICT (family_id, user_id) DO UPDATE
       SET status = 'active', alias = COALESCE(EXCLUDED.alias, family_members.alias)`,
    [familyId, user.id, alias ? alias.trim() : null]
  );
  await client.query(`UPDATE family_invitations SET status = 'accepted' WHERE id = $1`, [invRows[0].id]);
  await client.query(
    `INSERT INTO actors (family_id, user_id, actor_type, name)
     VALUES ($1, $2, 'person', $3) ON CONFLICT (family_id, user_id) DO NOTHING`,
    [familyId, user.id, user.display_name || user.email]
  );
  const warning = await memberLimitWarning(client, familyId);
  return {
    data: { success: true, status: 'active', ...(warning && { warning }) },
    userId: user.id, familyId, displayName: user.display_name || user.email,
  };
}

export async function joinByToken(client, user, { token, alias }) {
  const { rows: linkRows } = await client.query(
    `SELECT id, family_id, max_uses, uses, expires_at, revoked FROM invite_links WHERE id = $1 FOR UPDATE`,
    [token]
  );
  if (!linkRows.length) return serviceError(404, 'inviteLinkInvalid', 'Invalid invite link.');
  const link = linkRows[0];
  if (link.revoked) return serviceError(410, 'inviteLinkRevoked', 'This invite link has been revoked.');
  if (link.expires_at && new Date(link.expires_at) < new Date()) {
    return serviceError(410, 'inviteLinkExpired', 'This invite link has expired.');
  }
  if (link.max_uses !== null && link.uses >= link.max_uses) {
    return serviceError(410, 'inviteLinkMaxUsesReached', 'This invite link has reached its maximum uses.');
  }
  const { rows: existing } = await client.query(
    `SELECT status FROM family_members WHERE family_id = $1 AND user_id = $2`,
    [link.family_id, user.id]
  );
  if (existing.length && existing[0].status === 'active') {
    return serviceError(409, 'memberAlreadyActive', 'You are already an active member of this family.');
  }
  const gate = await assertFamilyWritable(client, link.family_id);
  if (gate) return gate;

  await client.query(
    `INSERT INTO family_members (family_id, user_id, role, status, alias)
     VALUES ($1, $2, 'caregiver', 'active', $3)
     ON CONFLICT (family_id, user_id) DO UPDATE
       SET status = 'active', alias = COALESCE(EXCLUDED.alias, family_members.alias)`,
    [link.family_id, user.id, alias ? alias.trim() : null]
  );
  await client.query(
    `INSERT INTO actors (family_id, user_id, actor_type, name)
     VALUES ($1, $2, 'person', $3) ON CONFLICT (family_id, user_id) DO NOTHING`,
    [link.family_id, user.id, user.display_name || user.email]
  );
  await client.query(`UPDATE invite_links SET uses = uses + 1 WHERE id = $1`, [link.id]);
  const warning = await memberLimitWarning(client, link.family_id);
  return {
    data: { success: true, familyId: link.family_id, ...(warning && { warning }) },
    userId: user.id, familyId: link.family_id,
    displayName: user.display_name || user.email,
  };
}

export async function addActor(client, familyId, { name, actorType, careTime }) {
  const gate = await assertFamilyWritable(client, familyId);
  if (gate) return gate;

  const type = ['child', 'pet', 'elderly', 'person'].includes(actorType) ? actorType : 'child';
  const time = ['full_time', 'part_time'].includes(careTime) ? careTime : 'full_time';
  const budgetIncrease = time === 'full_time' ? 720 : 360;

  const { rows } = await client.query(
    `INSERT INTO actors (family_id, actor_type, name, care_time) VALUES ($1,$2,$3,$4) RETURNING *`,
    [familyId, type, name, time]
  );
  await client.query(
    `UPDATE families SET monthly_coin_budget = monthly_coin_budget + $1 WHERE id = $2`,
    [budgetIncrease, familyId]
  );

  const entitlements = await getFamilyEntitlements(client, familyId);
  let warning = null;
  if (entitlements.limits.max_actors != null) {
    const { rows: countRows } = await client.query(
      `SELECT COUNT(*)::int AS n FROM actors WHERE family_id = $1 AND user_id IS NULL`,
      [familyId]
    );
    warning = limitWarning(entitlements, 'max_actors', countRows[0].n, 'actor_limit_exceeded');
  }
  return { data: { ...rows[0], ...(warning && { warning }) } };
}

export async function removeActor(client, familyId, actorId) {
  const { rows } = await client.query(
    `SELECT * FROM actors WHERE id = $1 AND family_id = $2`,
    [actorId, familyId]
  );
  if (!rows.length) return serviceError(404, 'actorNotFound', 'Actor not found.');
  const actor = rows[0];
  if (actor.actor_type !== 'pet') return serviceError(403, 'actorOnlyPetsRemovable', 'Only pets can be removed.');

  const budgetDecrease = actor.care_time === 'full_time' ? 720 : 360;
  await client.query(`DELETE FROM actors WHERE id = $1`, [actorId]);
  await client.query(
    `UPDATE families SET monthly_coin_budget = monthly_coin_budget - $1 WHERE id = $2`,
    [budgetDecrease, familyId]
  );
  return { data: { success: true } };
}

export async function updateActorAvatar(client, familyId, actorId, avatarUrl) {
  const { rows } = await client.query(
    `UPDATE actors SET avatar_url = $1 WHERE id = $2 AND family_id = $3 RETURNING *`,
    [avatarUrl, actorId, familyId]
  );
  if (!rows.length) return serviceError(404, 'actorNotFound', 'Actor not found.');
  return { data: { avatar_url: rows[0].avatar_url } };
}
