import { Router } from 'express';
import { withTransaction } from '../db/pool.js';
import { upsertUserFromAuth } from '../db/users.js';
import { notifyFamilyCaregivers } from '../utils/notify.js';
import { sendInvitationEmail } from '../utils/mailer.js';
import { validateBody, validateParams, required, string, positiveInt } from '../middleware/validate.js';
import { requireRole } from '../middleware/rbac.js';
import multer from 'multer';
import path from 'node:path';
import fs from 'node:fs';
import { fileURLToPath } from 'node:url';
import { inviteLinksRouter } from './inviteLinks.js';
import * as familyService from '../services/familyService.js';
import * as memberService from '../services/memberService.js';
import { getFamilyEntitlements } from '../services/entitlementService.js';
import { assertActiveMember } from '../db/users.js';
import { sendServiceError, serviceError, sendError } from '../utils/httpError.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const ALLOWED_MIME_TYPES = ['image/jpeg', 'image/png', 'image/webp'];
const storage = multer.diskStorage({
  destination(req, file, cb) {
    const safeFamilyId = String(Number(req.params.familyId));
    const safeActorId = String(Number(req.params.actorId));
    if (safeFamilyId === 'NaN' || safeActorId === 'NaN') return cb(new Error('Invalid ID.'));
    const dir = path.join(__dirname, '../../uploads/families', safeFamilyId, 'actors', safeActorId);
    fs.mkdirSync(dir, { recursive: true });
    cb(null, dir);
  },
  filename(_req, file, cb) {
    cb(null, 'avatar' + path.extname(file.originalname).toLowerCase());
  },
});
const upload = multer({
  storage,
  limits: { fileSize: 2 * 1024 * 1024 },
  fileFilter(_req, file, cb) {
    ALLOWED_MIME_TYPES.includes(file.mimetype) ? cb(null, true) : cb(new Error('Only JPEG, PNG, and WebP images are allowed.'));
  },
});

export const familiesRouter = Router();

familiesRouter.get('/', async (req, res) => {
  try {
    const result = await withTransaction(async (client) => {
      const user = await upsertUserFromAuth(client, req.auth);
      return familyService.listFamilies(client, user.id);
    });
    return res.json(result.data);
  } catch {
    return sendError(res, 500, 'internal', 'Failed to load families.');
  }
});

familiesRouter.get('/:familyId/budget', async (req, res) => {
  const familyId = Number(req.params.familyId);
  if (!familyId) return sendError(res, 400, 'familyIdInvalid', 'Invalid familyId.');
  try {
    const result = await withTransaction(async (client) => {
      const user = await upsertUserFromAuth(client, req.auth);
      return familyService.getFamilyBudget(client, user.id, familyId);
    });
    if (result.error) return sendServiceError(res, result.error);
    return res.json(result.data);
  } catch (err) {
    console.error('Failed to get family budget:', err);
    return sendError(res, 500, 'internal', 'Failed to fetch family budget.');
  }
});

// What the family may do under its plan (docs/admin-family-management-plan.md
// Phase 4). Clients read entitlements HERE, never from a store SDK — that is
// what makes one caregiver's purchase apply to every member on any platform.
familiesRouter.get('/:familyId/entitlements', validateParams('familyId'), async (req, res) => {
  const familyId = Number(req.params.familyId);
  try {
    const result = await withTransaction(async (client) => {
      const user = await upsertUserFromAuth(client, req.auth);
      if (!await assertActiveMember(client, familyId, user.id)) {
        return serviceError(403, 'familyNotMember', 'Not a family member.');
      }
      return { data: await getFamilyEntitlements(client, familyId) };
    });
    if (result.error) return sendServiceError(res, result.error);
    return res.json(result.data);
  } catch (err) {
    console.error('Failed to fetch entitlements:', err);
    return sendError(res, 500, 'internal', 'Failed to fetch entitlements.');
  }
});

familiesRouter.post('/', validateBody({
  name: [required(), string(1, 100)],
  mainCaretakerName: [string(1, 100)],
  alias: [string(1, 50)],
}), async (req, res) => {
  const { name, mainCaretakerName, caretakers, objectsOfCare, alias, starterTasks } = req.body;
  if (!name || typeof name !== 'string') return sendError(res, 400, 'familyNameRequired', 'name is required.', { field: 'name' });
  try {
    const result = await withTransaction(async (client) => {
      const user = await upsertUserFromAuth(client, req.auth);
      return familyService.createFamily(client, user, { name, mainCaretakerName, alias, caretakers, objectsOfCare, starterTasks });
    });
    if (result.error) return sendServiceError(res, result.error);
    return res.status(201).json({ family: result.data });
  } catch (err) {
    console.error(err);
    return sendError(res, 500, 'internal', 'Failed to create family.');
  }
});

familiesRouter.post('/join-request', validateBody({
  familyId: [required(), positiveInt()],
  alias: [string(1, 50)],
}), async (req, res) => {
  const { familyId, alias } = req.body;
  try {
    const result = await withTransaction(async (client) => {
      const user = await upsertUserFromAuth(client, req.auth);
      return memberService.joinByInvitation(client, user, { familyId, alias });
    });
    if (result.error) return sendServiceError(res, result.error);
    notifyFamilyCaregivers(result.familyId, result.userId, {
      title: 'Invitation accepted',
      body: `${result.displayName} joined your family.`,
      url: '/dashboard',
      prefKey: 'family_events',
    });
    return res.status(200).json(result.data);
  } catch (err) {
    console.error(err);
    return sendError(res, 500, 'internal', 'Failed to accept invitation.');
  }
});

familiesRouter.post('/join-by-token', validateBody({
  token: [required(), string(1, 500)],
  alias: [string(1, 50)],
}), async (req, res) => {
  const { token, alias } = req.body;
  try {
    const result = await withTransaction(async (client) => {
      const user = await upsertUserFromAuth(client, req.auth);
      return memberService.joinByToken(client, user, { token, alias });
    });
    if (result.error) return sendServiceError(res, result.error);
    notifyFamilyCaregivers(result.familyId, result.userId, {
      title: 'New member joined',
      body: `${result.displayName} joined your family via invite link.`,
      url: '/dashboard',
      prefKey: 'family_events',
    });
    return res.json(result.data);
  } catch (err) {
    console.error(err);
    return sendError(res, 500, 'internal', 'Failed to join family.');
  }
});

familiesRouter.patch('/:familyId/members/:userId/role',
  validateParams('familyId', 'userId'),
  requireRole('caregiver', r => r.params.familyId),
  async (req, res) => {
    const familyId = Number(req.params.familyId);
    const userId = Number(req.params.userId);
    const { role } = req.body;
    if (!['caregiver', 'member'].includes(role)) return sendError(res, 400, 'memberRoleInvalid', 'Invalid role.');
    try {
      const result = await withTransaction(async (client) => {
        await upsertUserFromAuth(client, req.auth);
        return memberService.updateMemberRole(client, familyId, userId, role);
      });
      if (result.error) return sendServiceError(res, result.error);
      return res.json(result.data);
    } catch {
      return sendError(res, 500, 'internal', 'Failed to update role.');
    }
  });

familiesRouter.post('/:familyId/members/:userId/approve',
  validateParams('familyId', 'userId'),
  requireRole('caregiver', r => r.params.familyId),
  async (req, res) => {
    const familyId = Number(req.params.familyId);
    const userId = Number(req.params.userId);
    try {
      const result = await withTransaction(async (client) => {
        await upsertUserFromAuth(client, req.auth);
        return memberService.approveMember(client, familyId, userId);
      });
      if (result.error) return sendServiceError(res, result.error);
      return res.json(result.data);
    } catch (err) {
      console.error(err);
      return sendError(res, 500, 'internal', 'Failed to approve member.');
    }
  });

familiesRouter.post('/:familyId/actors',
  validateParams('familyId'),
  validateBody({ name: [required(), string(1, 100)] }),
  requireRole('caregiver', r => r.params.familyId),
  async (req, res) => {
    const familyId = Number(req.params.familyId);
    const { name, actorType, careTime } = req.body;
    try {
      const result = await withTransaction(async (client) => {
        await upsertUserFromAuth(client, req.auth);
        return memberService.addActor(client, familyId, { name, actorType, careTime });
      });
      if (result.error) return sendServiceError(res, result.error);
      return res.status(201).json(result.data);
    } catch (err) {
      console.error(err);
      return sendError(res, 500, 'internal', 'Failed to add object of care.');
    }
  });

familiesRouter.delete('/:familyId/actors/:actorId',
  validateParams('familyId', 'actorId'),
  requireRole('caregiver', r => r.params.familyId),
  async (req, res) => {
    const familyId = Number(req.params.familyId);
    const actorId = Number(req.params.actorId);
    try {
      const result = await withTransaction(async (client) => {
        await upsertUserFromAuth(client, req.auth);
        return memberService.removeActor(client, familyId, actorId);
      });
      if (result.error) return sendServiceError(res, result.error);
      return res.json({ message: 'Pet removed successfully.' });
    } catch (err) {
      console.error(err);
      return sendError(res, 500, 'internal', 'Failed to remove pet.');
    }
  });

familiesRouter.post('/:familyId/actors/:actorId/avatar',
  (req, res, next) => {
    upload.single('avatar')(req, res, (err) => {
      if (err instanceof multer.MulterError && err.code === 'LIMIT_FILE_SIZE') {
        return sendError(res, 400, 'fileTooLarge', 'File too large. Maximum size is 2 MB.', { maxSize: '2 MB' });
      }
      if (err) {
        if (err.message === 'Only JPEG, PNG, and WebP images are allowed.') {
          return sendError(res, 400, 'fileInvalidType', err.message);
        }
        return sendError(res, 400, 'invalidInput', err.message);
      }
      next();
    });
  },
  validateParams('familyId', 'actorId'),
  requireRole('caregiver', r => r.params.familyId),
  async (req, res) => {
    if (!req.file) return sendError(res, 400, 'fileNoAvatar', 'No avatar image uploaded.');
    const familyId = Number(req.params.familyId);
    const actorId = Number(req.params.actorId);
    const avatarUrl = `/uploads/families/${req.params.familyId}/actors/${req.params.actorId}/${req.file.filename}`;
    try {
      const result = await withTransaction(async (client) => {
        await upsertUserFromAuth(client, req.auth);
        return memberService.updateActorAvatar(client, familyId, actorId, avatarUrl);
      });
      if (result.error) return sendServiceError(res, result.error);
      return res.json(result.data);
    } catch (err) {
      console.error(err);
      return sendError(res, 500, 'internal', 'Failed to upload actor avatar.');
    }
  });

familiesRouter.get('/:familyId/invitations', validateParams('familyId'), async (req, res) => {
  const familyId = Number(req.params.familyId);
  try {
    const result = await withTransaction(async (client) => {
      const user = await upsertUserFromAuth(client, req.auth);
      return memberService.listInvitations(client, user.id, familyId);
    });
    if (result.error) return sendServiceError(res, result.error);
    return res.json(result.data);
  } catch (err) {
    console.error(err);
    return sendError(res, 500, 'internal', 'Failed to fetch invitations.');
  }
});

familiesRouter.get('/:familyId/members', validateParams('familyId'), async (req, res) => {
  const familyId = Number(req.params.familyId);
  try {
    const result = await withTransaction(async (client) => {
      const user = await upsertUserFromAuth(client, req.auth);
      return memberService.listMembers(client, user.id, familyId);
    });
    if (result.error) return sendServiceError(res, result.error);
    return res.json(result.data);
  } catch (err) {
    console.error(err);
    return sendError(res, 500, 'internal', 'Failed to fetch members.');
  }
});

familiesRouter.post('/:familyId/invitations',
  validateParams('familyId'),
  validateBody({ email: [required(), string(1, 255)] }),
  requireRole('caregiver', r => r.params.familyId),
  async (req, res) => {
    const familyId = Number(req.params.familyId);
    const { email, name } = req.body;
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
      return sendError(res, 400, 'invitationEmailInvalid', 'Invalid email address.');
    }
    try {
      const result = await withTransaction(async (client) => {
        const user = await upsertUserFromAuth(client, req.auth);
        return memberService.createInvitation(client, user, familyId, { email, name });
      });
      if (result.error) return sendServiceError(res, result.error);
      sendInvitationEmail({
        toEmail: result.data.invitation.email,
        toName: result.data.invitation.name,
        inviterName: result.data.inviterName,
        familyName: result.data.familyName,
      }).catch(err => console.error('sendInvitationEmail error:', err));
      return res.status(201).json({ invitation: result.data.invitation });
    } catch (err) {
      console.error(err);
      return sendError(res, 500, 'internal', 'Failed to create invitation.');
    }
  });

familiesRouter.delete('/:familyId',
  validateParams('familyId'),
  requireRole('caregiver', r => r.params.familyId),
  async (req, res) => {
    const familyId = Number(req.params.familyId);
    try {
      const result = await withTransaction(async (client) => {
        const user = await upsertUserFromAuth(client, req.auth);
        return familyService.deleteFamily(client, user, familyId);
      });
      if (result.error) return sendServiceError(res, result.error);
      if (result.data.pendingApproval) {
        notifyFamilyCaregivers(result.familyId, result.requesterId, {
          title: 'Family deletion requested',
          body: 'A caregiver has requested to delete the family. Your approval is needed.',
          url: '/dashboard',
          prefKey: 'family_events',
        });
      }
      return res.json(result.data);
    } catch (err) {
      console.error(err);
      return sendError(res, 500, 'internal', 'Failed to delete family.');
    }
  });

familiesRouter.get('/:familyId/deletion-requests',
  validateParams('familyId'),
  requireRole('caregiver', r => r.params.familyId),
  async (req, res) => {
    const familyId = Number(req.params.familyId);
    try {
      const result = await withTransaction(async (client) => {
        await upsertUserFromAuth(client, req.auth);
        return familyService.getDeletionRequests(client, familyId);
      });
      return res.json(result.data);
    } catch (err) {
      console.error(err);
      return sendError(res, 500, 'internal', 'Failed to fetch deletion requests.');
    }
  });

familiesRouter.post('/:familyId/deletion-requests/:requestId/approve',
  validateParams('familyId', 'requestId'),
  requireRole('caregiver', r => r.params.familyId),
  async (req, res) => {
    const familyId = Number(req.params.familyId);
    const requestId = Number(req.params.requestId);
    try {
      const result = await withTransaction(async (client) => {
        await upsertUserFromAuth(client, req.auth);
        return familyService.approveDeletion(client, user.id, familyId, requestId);
      });
      if (result.error) return sendServiceError(res, result.error);
      return res.json(result.data);
    } catch (err) {
      console.error(err);
      return sendError(res, 500, 'internal', 'Failed to approve deletion.');
    }
  });

familiesRouter.post('/:familyId/deletion-requests/:requestId/reject',
  validateParams('familyId', 'requestId'),
  requireRole('caregiver', r => r.params.familyId),
  async (req, res) => {
    const familyId = Number(req.params.familyId);
    const requestId = Number(req.params.requestId);
    try {
      const result = await withTransaction(async (client) => {
        await upsertUserFromAuth(client, req.auth);
        return familyService.rejectDeletion(client, user.id, familyId, requestId);
      });
      if (result.error) return sendServiceError(res, result.error);
      return res.json(result.data);
    } catch (err) {
      console.error(err);
      return sendError(res, 500, 'internal', 'Failed to reject deletion.');
    }
  });

familiesRouter.use(inviteLinksRouter);
