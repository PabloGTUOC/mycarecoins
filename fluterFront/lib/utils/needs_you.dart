import '../state/app_state.dart';
import 'json.dart';

/// One thing on "Needs you": something this user can act on right now.
sealed class NeedsYouItem {}

/// A completed task waiting for a caregiver (not the doer) to validate.
class NeedsValidation extends NeedsYouItem {
  final Map<String, dynamic> activity;
  NeedsValidation(this.activity);
}

/// A personal-time cover request asked of this user, or of anyone.
class NeedsCoverRequest extends NeedsYouItem {
  final Map<String, dynamic> request;
  NeedsCoverRequest(this.request);
}

/// A member waiting for caregiver approval.
class NeedsMemberApproval extends NeedsYouItem {
  final Map<String, dynamic> member;
  NeedsMemberApproval(this.member);
}

/// An open bounty offer this caregiver could take.
class NeedsTakeOverOffer extends NeedsYouItem {
  final Map<String, dynamic> activity;
  NeedsTakeOverOffer(this.activity);
}

/// The single source of truth for what needs the current user. Today lists
/// these; Family only asks whether the list is empty.
List<NeedsYouItem> needsYouItems({
  required AppState app,
  required List<Map<String, dynamic>> activities,
  required List<Map<String, dynamic>> requests,
  required List<Map<String, dynamic>> pendingMembers,
}) {
  final items = <NeedsYouItem>[];
  final me = app.userId?.toString();

  // 1. Validations they can give (pending_validation, not theirs, user is caregiver)
  if (app.isCaregiver) {
    for (final a in activities) {
      if (a['is_template'] == true) continue;
      if (a['status'] == 'pending_validation' &&
          a['assigned_to']?.toString() != me) {
        items.add(NeedsValidation(a));
      }
    }
  }

  // 2. Cover requests asked of them or of anyone (status pending, not their own)
  for (final r in requests) {
    if (r['status'] == 'pending' && r['requester_id']?.toString() != me) {
      final reqOf = r['requested_of'];
      if (reqOf == null || reqOf.toString() == me) {
        items.add(NeedsCoverRequest(r));
      }
    }
  }

  // 3. Pending member approvals (caregivers only)
  if (app.isCaregiver) {
    for (final m in pendingMembers) {
      if (m['status'] == 'pending') {
        items.add(NeedsMemberApproval(m));
      }
    }
  }

  // 4. Open offers they could take (caregivers only, bounty > 0, not completed/rejected, not mine)
  if (app.isCaregiver) {
    for (final a in activities) {
      if (a['is_template'] == true) continue;
      // A coverage shift's bounty is the requester's sweetener, not an offer.
      if (a['type'] == 'coverage' || a['category'] == 'self') continue;
      if (toNum(a['bounty_amount']) > 0 &&
          a['status'] != 'completed' &&
          a['status'] != 'rejected' &&
          a['status'] != 'cancelled' &&
          a['status'] != 'pending_validation' &&
          a['assigned_to']?.toString() != me) {
        items.add(NeedsTakeOverOffer(a));
      }
    }
  }

  return items;
}
