# Error Codes Catalog

All non-admin backend routes, middleware, and services respond to refusals with a structured error payload:

```json
{
  "error": "English error message",
  "code": "keyName",
  "params": { ... }
}
```

The Flutter mobile application maps `code` to an ARB localization key formatted as `srvErr<Key>` (implemented in P6-6) and injects `params` where present. Unknown or missing codes fall back to the English `error` message string sent by the server.

---

## Catalog

| Key | HTTP Status | Params | English Message |
|---|---|---|---|
| `absenceActivityConflict` | 400 | `{ title }` | You have scheduled activities ("{title}") during this period. Please cancel or transfer them first. |
| `absenceDeleteForbidden` | 403 | — | You do not have permission to delete this absence. |
| `absenceNotFound` | 404 | — | Absence not found. |
| `absenceTooShort` | 400 | `{ hours }` | Absences must be at least 24 hours. For shorter breaks, use Personal Time. |
| `absentDuringTime` | 409 | `{ title }` | You are marked as absent ("{title}") during this time. |
| `activityAlreadyOwnShift` | 400 | — | You cannot accept your own shift. |
| `activityApprovedTemplateNotFound` | 404 | — | Approved template not found. |
| `activityBountyAmountRequired` | 400 | — | bountyAmount must be a positive integer. |
| `activityBountyAssigneeOnly` | 403 | — | Only the assigned caregiver can claim the bounty upon completion. |
| `activityBountyCompletedOrPendingValidation` | 400 | — | Cannot offer bounty on an activity that is completed or pending validation. |
| `activityBountyInsufficientCoins` | 409 | — | Insufficient coin balance to offer this bounty. |
| `activityCannotValidateOwn` | 403 | — | You cannot validate your own completed activity. |
| `activityCoverageOrPersonalCannotBounty` | 400 | — | Cannot add a bounty to a coverage shift or personal time. |
| `activityIdInvalid` | 400 | `{ field }` | activityId: must be a positive integer |
| `activityIdRequired` | 400 | — | activityId is required. |
| `activityInstanceNotFoundOrCompleted` | 404 | — | Activity instance not found or already completed. |
| `activityMinDuration` | 400 | — | Activity duration must be at least 5 minutes. |
| `activityMoveNotYours` | 403 | — | You can only move activities assigned to you. |
| `activityMoveOnlyUpcoming` | 400 | — | Only upcoming (approved) activities can be moved. |
| `activityNoBountyAvailable` | 400 | — | No bounty available on this activity. |
| `activityNotCompleted` | 400 | — | Activity is not completed. |
| `activityNotFound` | 404 | — | Activity not found. |
| `activityNotPendingValidation` | 400 | — | Activity is not pending validation. |
| `activityNotUpcoming` | 400 | — | Only upcoming (approved) activities can be reverted to pool. |
| `activityNotYours` | 403 | — | You can only complete activities assigned to you. |
| `activityRecurrentInstanceNotFound` | 404 | — | Recurrent instance not found. |
| `activityRescheduleAbsent` | 409 | `{ title }` | You are marked as absent ("{title}") during the new time. |
| `activityRescheduleOverlap` | 409 | `{ title }` | You already have "{title}" scheduled during the new time. |
| `activityRevertNotYours` | 403 | — | You can only revert your own assignments. |
| `activityTemplateDeleteUnauthorized` | 403 | — | You do not have permission to delete this template. |
| `activityTemplateNotFound` | 404 | — | Template not found. |
| `activityTemplateNotPending` | 400 | — | Template is not pending approval. |
| `activityTimeInPast` | 400 | — | Cannot schedule activity in the past. |
| `accessInvalid` | 403 | — | Invalid Cloudflare Access token. Operator console API only. |
| `accessMissing` | 403 | — | Missing Cloudflare Access token. Operator console API only. |
| `actorNotFound` | 404 | — | Actor not found. |
| `actorOnlyPetsRemovable` | 403 | — | Only pets can be removed. Human members must leave or be deleted. |
| `adminOnly` | 403 | — | Admin access required. |
| `adminReauthRequired` | 401 | `maxAgeMinutes` | Sign in again to make changes. Operator console API only. |
| `authInvalidToken` | 401 | — | Invalid token. |
| `authMissingToken` | 401 | — | No token provided. |
| `billingMalformedEvent` | 400 | — | Webhook error: Malformed event payload. |
| `billingMissingEvent` | 400 | — | No event provided. |
| `billingUnauthorized` | 401 | — | Unauthorized. |
| `coverageAlreadyPaid` | 400 | — | Coverage shifts cannot be moved once completed. |
| `coverageEndsWithPersonalTime` | 400 | — | Coverage ends when the personal time ends; delete the personal time instead. |
| `coverageMovesWithPersonalTime` | 400 | — | Coverage shifts move with their personal time — move the personal time instead. |
| `eventDetailNotObject` | 400 | — | detail must be an object. |
| `eventDetailTooLarge` | 400 | — | detail payload too large. |
| `eventUnknown` | 400 | — | Unknown event name. |
| `familyApprovalNotFound` | 404 | — | Pending approval not found. |
| `familyDeletionAlreadyPending` | 409 | — | A deletion request is already pending for this family. |
| `familyDeletionRequestNotFound` | 404 | — | Deletion request not found or already processed. |
| `familyIdInvalid` | 400 | — | Invalid family ID. |
| `familyIdRequired` | 400 | — | familyId query param is required. |
| `familyMemberNotFound` | 404 | — | Member not found. |
| `familyNameRequired` | 400 | — | name is required. |
| `familyNotFound` | 404 | — | Family not found. |
| `familyNotFoundOrNotMember` | 404 | — | Family not found or not a member. |
| `familyNotMember` | 403 | — | Not a family member. |
| `familyNotMemberOrForbidden` | 403 | — | Not a family member or forbidden. |
| `familyStarterTasksInvalid` | 400 | `{ index, reason }` | starterTasks[{index}] is invalid: {reason} |
| `fileInvalidType` | 400 | — | Only JPEG, PNG, and WebP images are allowed. |
| `fileNoAvatar` | 400 | — | No avatar file provided. |
| `fileTooLarge` | 400 | — | Avatar must be under 2 MB. |
| `internal` | 500 | — | Internal server error. |
| `invalidInput` | 400 | `{ field }` | {field}: {reason} |
| `invitationEmailInvalid` | 400 | — | A valid email is required. |
| `invitationNotFound` | 403 | — | No pending invitation found for your email address. |
| `inviteLinkExpired` | 410 | — | This invite link has expired. |
| `inviteLinkInvalid` | 404 | — | Invalid invite link. |
| `inviteLinkMaxUsesReached` | 410 | — | This invite link has reached its maximum uses. |
| `inviteLinkNotFound` | 404 | — | Invite link not found. |
| `inviteLinkRevoked` | 410 | — | This invite link has been revoked. |
| `ledgerParamsRequired` | 400 | — | familyId and memberId query parameters are required. |
| `memberAlreadyActive` | 409 | — | You are already an active member of this family. |
| `memberNoEmail` | 400 | — | Your account must have an email address to accept an invitation. |
| `memberPendingNotFound` | 404 | — | Pending member not found. |
| `memberRoleInvalid` | 400 | — | Invalid role. |
| `notFound` | 404 | — | Not found. |
| `notificationPreferencesBooleanRequired` | 400 | — | push_enabled and email_enabled must be booleans. |
| `notificationPreferencesCoverageRequestsBoolean` | 400 | — | notify_coverage_requests must be a boolean. |
| `personalTimeAddressedToOther` | 403 | — | This request was addressed to someone else. |
| `personalTimeCannotAskSelf` | 400 | — | You cannot ask yourself to cover. |
| `personalTimeCannotCoverSelf` | 400 | — | You cannot cover your own personal time. |
| `personalTimeCaregiverNotFound` | 400 | — | That person is not an active caregiver in this family. |
| `personalTimeCovererAway` | 409 | `{ title }` | You are away ("{title}") during this time. |
| `personalTimeHasCoverageCannotMove` | 400 | — | Personal time with confirmed coverage cannot be moved. |
| `personalTimeInPast` | 400 | — | Personal time must be in the future. |
| `personalTimeInvalidType` | 400 | — | type must be one of: sport, social, rest, appointment, other. |
| `personalTimeNoOneToCover` | 400 | — | There is no one else to cover for you. |
| `personalTimeOnlyCaregiversCanCover` | 403 | — | Only caregivers can cover. |
| `personalTimeOwnerCanMove` | 403 | — | Only the owner can move personal time. |
| `personalTimeOwnerOnly` | 403 | — | Only the owner can delete personal time. |
| `personalTimeRequestAlreadySettled` | 409 | — | This request is no longer pending. |
| `personalTimeRequestExpired` | 409 | — | This request has expired. |
| `personalTimeRequestNotFound` | 404 | — | Request not found. |
| `personalTimeRequesterBusy` | 409 | `{ title }` | You already have "{title}" during this time. |
| `personalTimeRequesterConflict` | 409 | `{ title }` | They already have "{title}" during this time. |
| `personalTimeSeriesBlocked` | 409 | `{ occurrences, reasonCode, reasonParams }` | None of the {occurrences} occurrences work — {reason} |
| `personalTimeSweetenerInsufficientCoins` | 409 | — | You do not have enough coins to sweeten this offer. |
| `personalTimeSweetenerSeriesTooExpensive` | 409 | `{ occurrences, escrow }` | Sweetening all {occurrences} occurrences costs {escrow} coins, which is more than you have. |
| `personalTimeTooLong` | 400 | `{ hours }` | Personal time cannot exceed 24 hours — log time off instead. |
| `personalTimeTooShort` | 400 | `{ minutes }` | Personal time must last at least 15 minutes. |
| `personalTimeWithdrawInsteadOfDecline` | 403 | — | Withdraw your own request instead of declining it. |
| `personalTimeWithdrawOwnerOnly` | 403 | — | Only the person who asked can withdraw a request. |
| `rateLimited` | 429 | — | Too many requests. Please try again later. Operator console API only. |
| `recurrenceEndBeforeStart` | 400 | — | The repeat end date is before the first occurrence. |
| `recurrenceInvalidDate` | 400 | — | The repeat end date is not a valid date. |
| `recurrenceInvalidType` | 400 | — | Repeat must be one of: daily, weekdays, weekly. |
| `recurrenceMissingUntil` | 400 | — | A repeating request needs a date to repeat until. |
| `recurrenceTooManyOccurrences` | 400 | `{ max }` | A repeating request cannot cover more than 60 occurrences — pick a nearer end date. |
| `recurrenceWeekdaysOnWeekend` | 400 | — | A weekdays repeat has to start on a weekday. |
| `retentionFamilyBecameActive` | 409 | — | Family became active again — skipped. |
| `rewardExpired` | 409 | — | Reward has expired. |
| `rewardFieldsRequired` | 400 | — | familyId, title and cost are required. |
| `rewardIdInvalidUuid` | 400 | `{ field }` | rewardId: must be a valid UUID |
| `rewardInsufficientCoins` | 409 | — | Insufficient coins. |
| `rewardNotActive` | 409 | — | Reward is no longer active. |
| `rewardNotFound` | 404 | — | Reward not found. |
| `rewardNotYetAvailable` | 409 | — | Reward is not yet available. |
| `rewardSoldOut` | 409 | — | Reward is sold out. |
| `roleRequired` | 403 | `{ role }` | Requires {role} role. |
| `scheduleOverlap` | 409 | `{ title }` | You already have "{title}" scheduled during this time. |
| `subscriptionPaymentPastDue` | 402 | — | Payment for this family's subscription is past due. Please update payment method to continue. |
| `timeWindowEndBeforeStart` | 400 | — | End time must be after start time. |
| `timeWindowInvalidDates` | 400 | — | Start and end must be valid date/time values. |
| `tokenRequired` | 400 | `{ field }` | token is required. |
