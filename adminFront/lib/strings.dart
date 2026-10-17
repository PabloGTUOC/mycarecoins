/// English-only user-facing strings for the CareCoins Operator Console.
/// Every user-facing string and error message mapping lives here.
class Strings {
  Strings._();

  // ─── App & Navigation ────────────────────────────────────────────────────────
  static const appTitle = 'CareCoins Operator';
  static const navOverview = 'Overview';
  static const navFamilies = 'Families';
  static const navPlans = 'Plans';
  static const navAppStore = 'App Store';
  static const signOut = 'Sign out';

  // ─── Auth ────────────────────────────────────────────────────────────────────
  static const signInTitle = 'CareCoins Operator Console';
  static const signInSubtitle =
      'Sign in with an authorized operator account to manage families and plans.';
  static const signInWithGoogle = 'Sign in with Google';
  static const orDivider = 'or sign in with email';
  static const emailLabel = 'Operator Email';
  static const passwordLabel = 'Password';
  static const signInButton = 'Sign in with Password';
  static const notAnOperatorTitle = 'Access Denied';
  static const notAnOperatorMessage =
      'This account is not an operator. Contact an administrator to grant platform operator access.';
  static const authLoading = 'Checking operator authorization...';
  static const retry = 'Retry';
  static const reauthRequiredTitle = 'Sign in again to make this change';
  static const reauthRequiredBody =
      'A recent sign-in (within 30 minutes) is required to perform administrative mutations. Please confirm your credentials.';
  static const reauthGoogleBtn = 'Confirm with Google';
  static const reauthPasswordBtn = 'Confirm with Password';
  static const reauthPasswordPrompt =
      'Please enter your password to confirm this action:';
  static const reauthCancelled =
      'Change cancelled. Re-authentication was not completed.';

  // ─── Common / Controls ───────────────────────────────────────────────────────
  static const cancel = 'Cancel';
  static const confirm = 'Confirm';
  static const save = 'Save';
  static const close = 'Close';
  static const loading = 'Loading...';
  static const noData = 'No data available';
  static const emptyDash = '—';
  static const filterAll = 'All';
  static const statusActive = 'Active';
  static const statusDormant = 'Dormant';
  static const statusInactive = 'Inactive';
  static const badgeDefault = 'Default';
  static const badgeActive = 'Active';
  static const badgeInactive = 'Inactive';
  static const priceFree = 'Free';
  static const periodMonthly = 'Monthly';
  static const periodYearly = 'Yearly';

  // ─── Overview ────────────────────────────────────────────────────────────────
  static const overviewTitle = 'Overview';
  static const refreshBtn = 'Refresh';

  static const cardFamiliesTitle = 'Families';
  static const cardFreePlansTitle = 'Active Free Plans';
  static const cardMirrorTitle = 'Mirror Health';
  static const cardWebhooksTitle = 'Webhook Health';
  static const cardRevenueCatTitle = 'RevenueCat Metrics';

  static const labelTotal = 'Total';
  static const labelActive = 'Active';
  static const labelDormant = 'Dormant';
  static const labelInactive = 'Inactive';

  static const labelActiveGrants = 'Active grants';
  static const labelFamiliesWithGrant = 'Families with grant';

  static const labelMirrorStatus = 'Mirror status';
  static const labelMirrorOn = 'On';
  static const labelMirrorOff = 'Off';
  static const labelSynced = 'Synced';
  static const labelPending = 'Pending';
  static const labelFailed = 'Failed';
  static const labelOldestPending = 'Oldest pending';

  static const labelLastEvent = 'Last event';
  static const labelEvents30Days = 'Events (last 30d)';
  static const labelUnattributed30Days = 'Unattributed (last 30d)';
  static const labelUnprocessed30Days = 'Unprocessed (last 30d)';
  static const recentWebhookIssues = 'Recent issues (unattributed or unprocessed)';
  static const noRecentWebhookIssues = 'No recent webhook issues.';
  static const reprocessBtn = 'Re-process';
  static const reprocessConfirmTitle = 'Re-process Webhook Event';
  static String reprocessConfirmBody(dynamic id) =>
      'Are you sure you want to re-process webhook event #$id on the public backend?';
  static String reprocessOutcomeMessage(String outcome) =>
      'Webhook event re-processed: $outcome';

  static const byPlanTitle = 'Families by Plan';
  static const byStatusTitle = 'Families by Status';
  static const byStoreTitle = 'Families by Store';

  static const colStore = 'Store';
  static const colCount = 'Count';
  static const colEventId = 'ID';
  static const colEventType = 'Event';
  static const colTimestamp = 'Timestamp';

  static const revenueCatNotConfigured = 'RevenueCat not configured';
  static const revenueCatUnavailable = 'RevenueCat unavailable';
  static const revenueCatRejected = 'RevenueCat rejected';
  static const noMetricsAvailable = 'No metrics available';

  static const colMetric = 'Metric';
  static const colValue = 'Value';
  static const colPeriod = 'Period';

  static const timeAgoJustNow = 'just now';

  // ─── Families List ───────────────────────────────────────────────────────────
  static const familiesTitle = 'Families';
  static const searchPlaceholder = 'Search by name or family ID...';
  static const prevPage = 'Previous';
  static const nextPage = 'Next';
  static const noFamiliesFound = 'No families found matching current criteria.';
  static const viewFamily = 'View';

  // Columns for Families table
  static const colId = 'ID';
  static const colName = 'Name';
  static const colHeartbeat = 'Heartbeat';
  static const colPlan = 'Plan';
  static const colSubscription = 'Subscription';
  static const colMembers = 'Members';
  static const colPending = 'Pending';
  static const colActors = 'Actors';
  static const colCreated = 'Created';
  static const colLastActive = 'Last Active';
  static const colActions = 'Actions';

  // ─── Family Detail ───────────────────────────────────────────────────────────
  static const familyDetailTitle = 'Family Detail';
  static const backToFamilies = 'Back to Families';
  static const registryCardTitle = 'Registry Overview';
  static const billingCardTitle = 'Subscription & Billing';
  static const grantsCardTitle = 'Plan Grants';
  static const eventsCardTitle = 'Recent Billing Events';

  static const notifyInactiveBtn = 'Notify Inactive';
  static const notifyInactiveConfirmTitle = 'Send Inactivity Notice';
  static const notifyInactiveConfirmBody =
      'Are you sure you want to queue an inactivity notice for this family? Caregivers will receive a push notification.';
  static const notifyInactiveQueued =
      'Notice queued. The app sends it within a minute.';

  static const noSubscription = 'No store subscription on file.';
  static const subPlan = 'Plan';
  static const subStatus = 'Status';
  static const subPlatform = 'Platform';
  static const subProvider = 'Provider';
  static const subRenewal = 'Current Period End';
  static const subBillingOwner = 'Billing owner';

  static const noGrants = 'No plan grants recorded for this family.';
  static const grantPlanBtn = 'Grant Plan';
  static const grantPlanDialogTitle = 'Grant Free Plan';
  static const grantPlanPickerLabel = 'Plan';
  static const grantReasonLabel = 'Reason (optional)';
  static const grantExpiresDaysLabel = 'Expires in (days, optional)';
  static const grantSuccess = 'Plan grant created successfully.';
  static const revokeGrantBtn = 'Revoke';
  static const revokeGrantConfirmTitle = 'Revoke Plan Grant';
  static const revokeGrantConfirmBody =
      'Are you sure you want to revoke this plan grant immediately?';
  static const revokeGrantSuccess = 'Grant revoked successfully.';

  static const colReason = 'Reason';
  static const colGranted = 'Granted';
  static const colExpires = 'Expires';
  static const colStatus = 'Status';
  static const colRevenueCat = 'RevenueCat';

  static const grantStatusActive = 'Active';
  static const grantStatusExpired = 'Expired';
  static const grantStatusRevoked = 'Revoked';

  static const rcSyncSynced = 'Synced';
  static const rcSyncPending = 'Pending';
  static const rcSyncFailed = 'Failed';
  static const rcSyncRetryBtn = 'Retry';
  static const rcSyncRetrySuccess = 'Sync retry triggered.';

  static const noEvents = 'No recent billing events found.';
  static const eventType = 'Event';
  static const eventProvider = 'Provider';
  static const eventDate = 'Timestamp';
  static const eventProcessed = 'Processed';
  static const eventProcessedYes = 'Yes';
  static const eventProcessedNo = 'No';

  // ─── RevenueCat Card (Family Detail) ─────────────────────────────────────────
  static const rcCardTitle = 'RevenueCat';
  static const rcFamilyCustomerTitle = 'Family Customer';
  static const rcBillingOwnerCustomerTitle = 'Billing Owner Customer';
  static const rcCustomerIdLabel = 'Customer ID';
  static const rcLastSeenLabel = 'Last Seen';
  static const rcStatusLabel = 'Status';
  static const rcStatusFound = 'Found in RevenueCat';
  static const rcStatusNotFound = 'Not in RevenueCat';
  static const rcNoBillingOwner = 'No billing owner assigned to this family.';
  static const rcActiveEntitlementsTitle = 'Active Entitlements';
  static const rcNoActiveEntitlements = 'No active entitlements.';
  static const rcMismatchesTitle = 'Mismatch Flags';
  static const rcNoMismatches = 'No mismatches detected.';
  static const rcRefreshBtn = 'Refresh';
  static const rcOpenInDashboard = 'Open in RevenueCat';
  static const rcLoading = 'Loading RevenueCat state...';
  static const rcCustomerDashboardUrlPattern = 'https://app.revenuecat.com/customers';
  static String rcCustomerDashboardUrl(String customerId) =>
      '$rcCustomerDashboardUrlPattern?query=${Uri.encodeComponent(customerId)}';

  // ─── Plans ───────────────────────────────────────────────────────────────────
  static const plansTitle = 'Plan Catalogue';
  static const newPlanBtn = 'New Plan';
  static const editPlanBtn = 'Edit';
  static const newPlanDialogTitle = 'Create Plan';
  static const editPlanDialogTitle = 'Edit Plan';
  static const planCodeLabel = 'Plan Code';
  static const planNameLabel = 'Plan Name';
  static const planPriceLabel = 'Price in Cents (e.g. 999 for 9.99)';
  static const planCurrencyLabel = 'Currency (e.g. EUR)';
  static const planPeriodLabel = 'Billing Period';
  static const planLimitMembersLabel = 'Max Members (optional)';
  static const planLimitActorsLabel = 'Max Actors (optional)';
  static const planLimitRewardsLabel = 'Max Active Rewards (optional)';
  static const planDefaultLabel = 'Default Plan';
  static const planActiveLabel = 'Active';
  static const planSaveSuccess = 'Plan saved successfully.';

  static const colPlanCode = 'Code';
  static const colPlanName = 'Name';
  static const colPlanPrice = 'Price';
  static const colPlanPeriod = 'Period';
  static const colPlanDefault = 'Default';
  static const colPlanActive = 'Active';

  // ─── App Store ───────────────────────────────────────────────────────────────
  static const appStoreTitle = 'App Store';
  static const catalogTitle = 'Subscription Catalog';
  static const refreshCatalogBtn = 'Refresh';
  static const lookupTitle = 'Transaction Lookup';
  static const lookupBtn = 'Look up';
  static const transactionIdLabel = 'Transaction ID';
  static const envProduction = 'Production';
  static const envSandbox = 'Sandbox';

  static const linkAppStoreConnect = 'App Store Connect';
  static const linkRevenueCat = 'RevenueCat Customers';
  static const appStoreConnectUrl = 'https://appstoreconnect.apple.com/apps';
  static const revenueCatCustomersUrl = 'https://app.revenuecat.com/customers';

  static const appStoreNotConfiguredTitle = 'App Store Not Configured';
  static const appStoreNotConfiguredBody =
      'App Store keys are not configured. Set ASC_KEY_ID, ASC_ISSUER_ID, ASC_PRIVATE_KEY, IAP_KEY_ID, IAP_PRIVATE_KEY, and APP_BUNDLE_ID in the backend environment to enable.';

  static const colGroup = 'Subscription Group';
  static const colProduct = 'Product ID';
  static const colState = 'State';
  static const colPrice = 'Price';
  static const colTerritory = 'Territory';
  static const noSubscriptionsFound = 'No subscriptions found in catalog.';
  static const noSubscriptionGroups = 'No subscription groups found.';

  static const colTxId = 'Transaction ID';
  static const colOrigTxId = 'Original Transaction ID';
  static const colPurchaseDate = 'Purchase Date';
  static const colExpiresDate = 'Expires Date';
  static const colEnvironment = 'Environment';
  static const colType = 'Type';
  static const colOwnership = 'Ownership Type';
  static const colRevocationDate = 'Revocation Date';
  static const colRevocationReason = 'Revocation Reason';
  static const colAutoRenew = 'Auto-Renew Status';
  static const colAutoRenewProduct = 'Auto-Renew Product ID';
  static const colExpirationIntent = 'Expiration Intent';
  static const txNotFound = 'Transaction not found.';
  static const autoRenewOn = 'On';
  static const autoRenewOff = 'Off';

  // ─── Error Mappings ──────────────────────────────────────────────────────────
  static const errAdminOnly =
      'Admin access required. This account is not an operator.';
  static const errAdminReauthRequired =
      'Sign in again to make changes. Recent sign-in expired.';
  static const errAccessMissing =
      'Missing Cloudflare Access token. Operator console API only.';
  static const errAccessInvalid =
      'Invalid Cloudflare Access token. Operator console API only.';
  static const errAuthMissingToken =
      'Authentication required. No ID token provided.';
  static const errNotFound = 'The requested resource was not found.';
  static const errRateLimited = 'Too many requests. Please try again later.';
  static const errAppStoreNotConfigured = 'App Store API is not configured.';
  static const errAppStoreUnavailable =
      'App Store service is temporarily unavailable.';
  static const errAppStoreRejected = 'App Store request failed.';
  static const errRevenueCatNotConfigured = 'RevenueCat is not configured.';
  static const errRevenueCatUnavailable =
      'RevenueCat service is temporarily unavailable.';
  static const errRevenueCatRejected = 'RevenueCat request failed.';
  static const errReprocessAlreadyProcessed =
      'This event was already applied.';
  static const errReprocessNotConfigured =
      'Webhook re-processing is not configured.';
  static const errReprocessUnavailable =
      'Webhook re-processing service is temporarily unavailable.';
  static const errGenericFallback =
      'An unexpected error occurred. Please try again.';

  static const errWrongPasswordRetry = 'Password is wrong. Try again.';

  static const errInvalidCredential = 'Email or password is wrong.';
  static const errInvalidEmail = 'The email address is invalid.';
  static const errUserDisabled = 'This user account has been disabled.';
  static const errTooManyRequests =
      'Too many failed attempts. Please try again later.';
  static const errNetworkRequestFailed =
      'Network error. Please check your connection.';
  static const errPopupBlocked =
      'The sign-in popup was blocked by your browser. Please allow popups.';

  /// Maps a Firebase Auth error code to an English message,
  /// or returns null if the action was merely dismissed by the operator.
  static String? authErrorForCode(String code) {
    switch (code) {
      case 'invalid-credential':
      case 'wrong-password':
      case 'user-not-found':
        return errInvalidCredential;
      case 'invalid-email':
        return errInvalidEmail;
      case 'user-disabled':
        return errUserDisabled;
      case 'too-many-requests':
        return errTooManyRequests;
      case 'network-request-failed':
        return errNetworkRequestFailed;
      case 'popup-closed-by-user':
      case 'cancelled-popup-request':
        return null;
      case 'popup-blocked':
        return errPopupBlocked;
      default:
        return errGenericFallback;
    }
  }

  /// Maps any caught auth error/exception.
  static String? authErrorFor(Object error) {
    if (error is String) {
      return authErrorForCode(error);
    }
    try {
      final dynamic e = error;
      final dynamic code = e.code;
      if (code != null) {
        return authErrorForCode(code.toString());
      }
    } catch (_) {}
    return errGenericFallback;
  }

  /// Maps a server error code or HTTP status to an English message.
  static String errorFor({
    String? code,
    int? statusCode,
    String? serverMessage,
  }) {
    if (statusCode == 429 || code == 'rateLimited') {
      return errRateLimited;
    }
    if (code == 'adminOnly') {
      return errAdminOnly;
    }
    if (code == 'adminReauthRequired') {
      return errAdminReauthRequired;
    }
    if (code == 'accessMissing') {
      return errAccessMissing;
    }
    if (code == 'accessInvalid') {
      return errAccessInvalid;
    }
    if (code == 'authMissingToken') {
      return errAuthMissingToken;
    }
    if (code == 'notFound' || statusCode == 404) {
      return errNotFound;
    }
    if (code == 'appStoreNotConfigured') {
      return errAppStoreNotConfigured;
    }
    if (code == 'appStoreUnavailable') {
      return errAppStoreUnavailable;
    }
    if (code == 'appStoreRejected') {
      return errAppStoreRejected;
    }
    if (code == 'revenueCatNotConfigured') {
      return errRevenueCatNotConfigured;
    }
    if (code == 'revenueCatUnavailable') {
      return errRevenueCatUnavailable;
    }
    if (code == 'revenueCatRejected') {
      return errRevenueCatRejected;
    }
    if (code == 'reprocessAlreadyProcessed') {
      return errReprocessAlreadyProcessed;
    }
    if (code == 'reprocessNotConfigured') {
      return errReprocessNotConfigured;
    }
    if (code == 'reprocessUnavailable') {
      return errReprocessUnavailable;
    }
    if (serverMessage != null && serverMessage.trim().isNotEmpty) {
      return serverMessage.trim();
    }
    return errGenericFallback;
  }

  // ─── Dynamic Formatters ──────────────────────────────────────────────────────
  static String pageInfo(int page, int totalPages, int totalItems) {
    final familyWord = totalItems == 1 ? '1 family' : '$totalItems families';
    return 'Page $page of $totalPages ($familyWord)';
  }

  static String formatId(dynamic id) => '#$id';

  static String count(dynamic n) => '${n ?? 0}';

  static String planOption(dynamic name, dynamic code) => '$name ($code)';

  static String familyHeader(String name, int id) => '$name · #$id';

  static String formatBillingOwner(dynamic userId) =>
      userId != null ? 'User #$userId' : emptyDash;

  static String formatPrice(int priceCents, String currency, String period) {
    if (priceCents == 0) return priceFree;
    final amount = (priceCents / 100).toStringAsFixed(2);
    final periodName = period == 'yearly' ? periodYearly : periodMonthly;
    return '$amount $currency / $periodName';
  }

  static String formatDate(dynamic iso) {
    if (iso == null) return emptyDash;
    final d = DateTime.tryParse(iso.toString())?.toLocal();
    if (d == null) return emptyDash;
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    final hh = d.hour.toString().padLeft(2, '0');
    final mm = d.minute.toString().padLeft(2, '0');
    return '$y-$m-$day $hh:$mm';
  }

  static String grantSummary({
    required String planCode,
    String? reason,
    dynamic expiresAt,
    dynamic revokedAt,
  }) {
    final parts = <String>[planCode];
    if (reason != null && reason.trim().isNotEmpty) {
      parts.add(reason.trim());
    }
    if (expiresAt != null) {
      parts.add('Expires: ${formatDate(expiresAt)}');
    }
    if (revokedAt != null) {
      parts.add('Revoked: ${formatDate(revokedAt)}');
    }
    return parts.join(' · ');
  }

  static String formatCatalogPrice(
      dynamic customerPrice, dynamic currency, dynamic territory) {
    if (customerPrice == null && currency == null && territory == null) {
      return emptyDash;
    }
    final priceStr = customerPrice?.toString() ?? '';
    final currStr = currency?.toString() ?? '';
    final terrStr = territory?.toString() ?? '';
    final parts = <String>[];
    if (priceStr.isNotEmpty || currStr.isNotEmpty) {
      parts.add('$priceStr $currStr'.trim());
    }
    if (terrStr.isNotEmpty) {
      parts.add('($terrStr)');
    }
    return parts.join(' ');
  }

  static String formatAutoRenew(dynamic status) {
    if (status == null) return emptyDash;
    if (status == 1 || status == '1' || status == true) return autoRenewOn;
    if (status == 0 || status == '0' || status == false) return autoRenewOff;
    return status.toString();
  }

  static String formatTimeAgo(dynamic iso, {DateTime? now}) {
    if (iso == null) return emptyDash;
    final dt = DateTime.tryParse(iso.toString())?.toUtc();
    if (dt == null) return emptyDash;
    final current = (now ?? DateTime.now()).toUtc();
    final diff = current.difference(dt);
    if (diff.isNegative || diff.inMinutes < 1) {
      return timeAgoJustNow;
    }
    if (diff.inMinutes < 60) {
      final m = diff.inMinutes;
      return m == 1 ? '1 minute ago' : '$m minutes ago';
    }
    if (diff.inHours < 24) {
      final h = diff.inHours;
      return h == 1 ? '1 hour ago' : '$h hours ago';
    }
    final d = diff.inDays;
    return d == 1 ? '1 day ago' : '$d days ago';
  }

  static String formatAgeMinutes(dynamic minutes) {
    if (minutes == null) return emptyDash;
    final n = int.tryParse(minutes.toString()) ?? 0;
    if (n <= 0) return '0m';
    if (n < 60) return '${n}m';
    if (n < 1440) {
      final h = n ~/ 60;
      final m = n % 60;
      return m == 0 ? '${h}h' : '${h}h ${m}m';
    }
    final d = n ~/ 1440;
    final h = (n % 1440) ~/ 60;
    return h == 0 ? '${d}d' : '${d}d ${h}h';
  }

  static String formatMetricValue(dynamic value, dynamic unit) {
    if (value == null) return emptyDash;
    final valStr = value is num
        ? (value % 1 == 0 ? value.toInt().toString() : value.toString())
        : value.toString();
    if (unit != null && unit.toString().isNotEmpty) {
      return '$valStr ${unit.toString()}';
    }
    return valStr;
  }

  static String rcEntitlementSummary({
    required String id,
    dynamic expiresAt,
    String? store,
    String? grantType,
  }) {
    final parts = <String>[id];
    if (store != null && store.isNotEmpty) parts.add(store);
    if (grantType != null && grantType.isNotEmpty) parts.add(grantType);
    if (expiresAt != null) {
      parts.add('Expires: ${formatDate(expiresAt)}');
    }
    return parts.join(' · ');
  }

  static String rcMismatchTitle(String code) {
    switch (code) {
      case 'freePlanNotMirrored':
        return 'Free plan not mirrored';
      case 'mirrorStale':
        return 'Mirror stale';
      case 'subscriptionMissingInRevenueCat':
        return 'Subscription missing in RevenueCat';
      case 'subscriptionMissingHere':
        return 'Subscription missing in CareCoins';
      default:
        return 'RevenueCat mismatch';
    }
  }
}
