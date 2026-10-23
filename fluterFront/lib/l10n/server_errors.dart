import 'app_localizations.dart';

/// Localizes a server-sent error code and parameters into the active language.
/// Returns null when the code is unknown (caller falls back to serverMessage).
String? localizeServerError(
    AppLocalizations l, String code, Map<String, dynamic> params) {
  switch (code) {
    case 'absenceActivityConflict':
      return l.srvErrAbsenceActivityConflict('${params['title'] ?? ''}');
    case 'absenceDeleteForbidden':
      return l.srvErrAbsenceDeleteForbidden;
    case 'absenceNotFound':
      return l.srvErrAbsenceNotFound;
    case 'absenceTooShort':
      return l.srvErrAbsenceTooShort((params['hours'] as num?)?.toInt() ?? 0);
    case 'absentDuringTime':
      return l.srvErrAbsentDuringTime('${params['title'] ?? ''}');
    case 'activityAlreadyOwnShift':
      return l.srvErrActivityAlreadyOwnShift;
    case 'activityApprovedTemplateNotFound':
      return l.srvErrActivityApprovedTemplateNotFound;
    case 'activityBountyAmountRequired':
      return l.srvErrActivityBountyAmountRequired;
    case 'activityBountyAssigneeOnly':
      return l.srvErrActivityBountyAssigneeOnly;
    case 'activityBountyCompletedOrPendingValidation':
      return l.srvErrActivityBountyCompletedOrPendingValidation;
    case 'activityBountyInsufficientCoins':
      return l.srvErrActivityBountyInsufficientCoins;
    case 'activityCannotValidateOwn':
      return l.srvErrActivityCannotValidateOwn;
    case 'activityCoverageOrPersonalCannotBounty':
      return l.srvErrActivityCoverageOrPersonalCannotBounty;
    case 'activityIdInvalid':
      return l.srvErrActivityIdInvalid;
    case 'activityIdRequired':
      return l.srvErrActivityIdRequired;
    case 'activityInstanceNotFoundOrCompleted':
      return l.srvErrActivityInstanceNotFoundOrCompleted;
    case 'activityMinDuration':
      return l.srvErrActivityMinDuration;
    case 'activityMoveNotYours':
      return l.srvErrActivityMoveNotYours;
    case 'activityMoveOnlyUpcoming':
      return l.srvErrActivityMoveOnlyUpcoming;
    case 'activityNoBountyAvailable':
      return l.srvErrActivityNoBountyAvailable;
    case 'activityNotCompleted':
      return l.srvErrActivityNotCompleted;
    case 'activityNotFound':
      return l.srvErrActivityNotFound;
    case 'activityNotPendingValidation':
      return l.srvErrActivityNotPendingValidation;
    case 'activityNotUpcoming':
      return l.srvErrActivityNotUpcoming;
    case 'activityNotYours':
      return l.srvErrActivityNotYours;
    case 'activityRecurrentInstanceNotFound':
      return l.srvErrActivityRecurrentInstanceNotFound;
    case 'activityRescheduleAbsent':
      return l.srvErrActivityRescheduleAbsent('${params['title'] ?? ''}');
    case 'activityRescheduleOverlap':
      return l.srvErrActivityRescheduleOverlap('${params['title'] ?? ''}');
    case 'activityRevertNotYours':
      return l.srvErrActivityRevertNotYours;
    case 'activityTemplateDeleteUnauthorized':
      return l.srvErrActivityTemplateDeleteUnauthorized;
    case 'activityTemplateNotFound':
      return l.srvErrActivityTemplateNotFound;
    case 'activityTemplateNotPending':
      return l.srvErrActivityTemplateNotPending;
    case 'activityTimeInPast':
      return l.srvErrActivityTimeInPast;
    case 'actorNotFound':
      return l.srvErrActorNotFound;
    case 'actorOnlyPetsRemovable':
      return l.srvErrActorOnlyPetsRemovable;
    case 'adminOnly':
      return null;
    case 'authInvalidToken':
      return l.srvErrAuthInvalidToken;
    case 'authMissingToken':
      return l.srvErrAuthMissingToken;
    case 'billingMalformedEvent':
      return l.srvErrBillingMalformedEvent;
    case 'billingMissingEvent':
      return l.srvErrBillingMissingEvent;
    case 'billingUnauthorized':
      return l.srvErrBillingUnauthorized;
    case 'coverageAlreadyPaid':
      return l.srvErrCoverageAlreadyPaid;
    case 'coverageEndsWithPersonalTime':
      return l.srvErrCoverageEndsWithPersonalTime;
    case 'coverageMovesWithPersonalTime':
      return l.srvErrCoverageMovesWithPersonalTime;
    case 'deviceKeyCaregiverOnly':
      return l.srvErrDeviceKeyCaregiverOnly;
    case 'deviceKeyInvalid':
      return l.srvErrDeviceKeyInvalid;
    case 'deviceKeyLimit':
      return l.srvErrDeviceKeyLimit((params['max'] as num?)?.toInt() ?? 0);
    case 'deviceKeyNotFound':
      return l.srvErrDeviceKeyNotFound;
    case 'deviceKeyRevoked':
      return l.srvErrDeviceKeyRevoked;
    case 'eventDetailNotObject':
      return l.srvErrEventDetailNotObject;
    case 'eventDetailTooLarge':
      return l.srvErrEventDetailTooLarge;
    case 'eventUnknown':
      return l.srvErrEventUnknown;
    case 'familyApprovalNotFound':
      return l.srvErrFamilyApprovalNotFound;
    case 'familyDeletionAlreadyPending':
      return l.srvErrFamilyDeletionAlreadyPending;
    case 'familyDeletionRequestNotFound':
      return l.srvErrFamilyDeletionRequestNotFound;
    case 'familyIdInvalid':
      return l.srvErrFamilyIdInvalid;
    case 'familyIdRequired':
      return l.srvErrFamilyIdRequired;
    case 'familyMemberNotFound':
      return l.srvErrFamilyMemberNotFound;
    case 'familyNameRequired':
      return l.srvErrFamilyNameRequired;
    case 'familyNotFound':
      return l.srvErrFamilyNotFound;
    case 'familyNotFoundOrNotMember':
      return l.srvErrFamilyNotFoundOrNotMember;
    case 'familyNotMember':
      return l.srvErrFamilyNotMember;
    case 'familyNotMemberOrForbidden':
      return l.srvErrFamilyNotMemberOrForbidden;
    case 'familyStarterTasksInvalid':
      return l.srvErrFamilyStarterTasksInvalid(
        (params['index'] as num?)?.toInt() ?? 0,
        '${params['reason'] ?? ''}',
      );
    case 'fileInvalidType':
      return l.srvErrFileInvalidType;
    case 'fileNoAvatar':
      return l.srvErrFileNoAvatar;
    case 'fileTooLarge':
      return l.srvErrFileTooLarge;
    case 'internal':
      return l.errServerTrouble;
    case 'invalidInput':
      return l.srvErrInvalidInput;
    case 'invitationEmailInvalid':
      return l.srvErrInvitationEmailInvalid;
    case 'invitationNotFound':
      return l.srvErrInvitationNotFound;
    case 'inviteLinkExpired':
      return l.srvErrInviteLinkExpired;
    case 'inviteLinkInvalid':
      return l.srvErrInviteLinkInvalid;
    case 'inviteLinkMaxUsesReached':
      return l.srvErrInviteLinkMaxUsesReached;
    case 'inviteLinkNotFound':
      return l.srvErrInviteLinkNotFound;
    case 'inviteLinkRevoked':
      return l.srvErrInviteLinkRevoked;
    case 'ledgerParamsRequired':
      return l.srvErrLedgerParamsRequired;
    case 'memberAlreadyActive':
      return l.srvErrMemberAlreadyActive;
    case 'memberNoEmail':
      return l.srvErrMemberNoEmail;
    case 'memberPendingNotFound':
      return l.srvErrMemberPendingNotFound;
    case 'memberRoleInvalid':
      return l.srvErrMemberRoleInvalid;
    case 'notFound':
      return l.srvErrNotFound;
    case 'notificationPreferencesBooleanRequired':
      return l.srvErrNotificationPreferencesBooleanRequired;
    case 'notificationPreferencesCoverageRequestsBoolean':
      return l.srvErrNotificationPreferencesCoverageRequestsBoolean;
    case 'personalTimeAddressedToOther':
      return l.srvErrPersonalTimeAddressedToOther;
    case 'personalTimeCannotAskSelf':
      return l.srvErrPersonalTimeCannotAskSelf;
    case 'personalTimeCannotCoverSelf':
      return l.srvErrPersonalTimeCannotCoverSelf;
    case 'personalTimeCaregiverNotFound':
      return l.srvErrPersonalTimeCaregiverNotFound;
    case 'personalTimeCovererAway':
      return l.srvErrPersonalTimeCovererAway('${params['title'] ?? ''}');
    case 'personalTimeHasCoverageCannotMove':
      return l.srvErrPersonalTimeHasCoverageCannotMove;
    case 'personalTimeInPast':
      return l.srvErrPersonalTimeInPast;
    case 'personalTimeInvalidType':
      return l.srvErrPersonalTimeInvalidType;
    case 'personalTimeNoOneToCover':
      return l.srvErrPersonalTimeNoOneToCover;
    case 'personalTimeOnlyCaregiversCanCover':
      return l.srvErrPersonalTimeOnlyCaregiversCanCover;
    case 'personalTimeOwnerCanMove':
      return l.srvErrPersonalTimeOwnerCanMove;
    case 'personalTimeOwnerOnly':
      return l.srvErrPersonalTimeOwnerOnly;
    case 'personalTimeRequestAlreadySettled':
      return l.srvErrPersonalTimeRequestAlreadySettled;
    case 'personalTimeRequestExpired':
      return l.srvErrPersonalTimeRequestExpired;
    case 'personalTimeRequestNotFound':
      return l.srvErrPersonalTimeRequestNotFound;
    case 'personalTimeRequesterBusy':
      return l.srvErrPersonalTimeRequesterBusy('${params['title'] ?? ''}');
    case 'personalTimeRequesterConflict':
      return l.srvErrPersonalTimeRequesterConflict('${params['title'] ?? ''}');
    case 'personalTimeSeriesBlocked':
      final reasonCode = params['reasonCode']?.toString();
      if (reasonCode == null) return null;
      final rawReasonParams = params['reasonParams'];
      final reasonParams = rawReasonParams is Map<String, dynamic>
          ? rawReasonParams
          : (rawReasonParams is Map
              ? Map<String, dynamic>.from(rawReasonParams)
              : const <String, dynamic>{});
      final reason = localizeServerError(l, reasonCode, reasonParams);
      if (reason == null) return null;
      final occurrences = (params['occurrences'] as num?)?.toInt() ?? 0;
      return l.srvErrPersonalTimeSeriesBlocked(occurrences, reason);
    case 'personalTimeSweetenerInsufficientCoins':
      return l.srvErrPersonalTimeSweetenerInsufficientCoins;
    case 'personalTimeSweetenerSeriesTooExpensive':
      return l.srvErrPersonalTimeSweetenerSeriesTooExpensive(
        (params['occurrences'] as num?)?.toInt() ?? 0,
        (params['escrow'] as num?)?.toInt() ?? 0,
      );
    case 'personalTimeTooLong':
      return l.srvErrPersonalTimeTooLong(
          (params['hours'] as num?)?.toInt() ?? 0);
    case 'personalTimeTooShort':
      return l.srvErrPersonalTimeTooShort(
          (params['minutes'] as num?)?.toInt() ?? 0);
    case 'personalTimeWithdrawInsteadOfDecline':
      return l.srvErrPersonalTimeWithdrawInsteadOfDecline;
    case 'personalTimeWithdrawOwnerOnly':
      return l.srvErrPersonalTimeWithdrawOwnerOnly;
    case 'quickClientRefRequired':
      return l.srvErrQuickClientRefRequired;
    case 'quickStartInvalid':
      return l.srvErrQuickStartInvalid;
    case 'quickTaskAlreadyRunning':
      return l.srvErrQuickTaskAlreadyRunning('${params['title'] ?? ''}');
    case 'quickTaskNotRunning':
      return l.srvErrQuickTaskNotRunning;
    case 'quickUndoExpired':
      return l.srvErrQuickUndoExpired;
    case 'recurrenceEndBeforeStart':
      return l.srvErrRecurrenceEndBeforeStart;
    case 'recurrenceInvalidDate':
      return l.srvErrRecurrenceInvalidDate;
    case 'recurrenceInvalidType':
      return l.srvErrRecurrenceInvalidType;
    case 'recurrenceMissingUntil':
      return l.srvErrRecurrenceMissingUntil;
    case 'recurrenceTooManyOccurrences':
      return l.srvErrRecurrenceTooManyOccurrences(
          (params['max'] as num?)?.toInt() ?? 0);
    case 'recurrenceWeekdaysOnWeekend':
      return l.srvErrRecurrenceWeekdaysOnWeekend;
    case 'retentionFamilyBecameActive':
      return l.srvErrRetentionFamilyBecameActive;
    case 'rewardExpired':
      return l.srvErrRewardExpired;
    case 'rewardFieldsRequired':
      return l.srvErrRewardFieldsRequired;
    case 'rewardIdInvalidUuid':
      return l.srvErrRewardIdInvalidUuid;
    case 'rewardInsufficientCoins':
      return l.srvErrRewardInsufficientCoins;
    case 'rewardNotActive':
      return l.srvErrRewardNotActive;
    case 'rewardNotFound':
      return l.srvErrRewardNotFound;
    case 'rewardNotYetAvailable':
      return l.srvErrRewardNotYetAvailable;
    case 'rewardSoldOut':
      return l.srvErrRewardSoldOut;
    case 'roleRequired':
      return l.srvErrRoleRequired('${params['role'] ?? ''}');
    case 'scheduleOverlap':
      return l.srvErrScheduleOverlap('${params['title'] ?? ''}');
    case 'subscriptionPaymentPastDue':
      return l.srvErrSubscriptionPaymentPastDue;
    case 'timeWindowEndBeforeStart':
      return l.srvErrTimeWindowEndBeforeStart;
    case 'timeWindowInvalidDates':
      return l.srvErrTimeWindowInvalidDates;
    case 'tokenRequired':
      return l.srvErrTokenRequired;
    default:
      return null;
  }
}
