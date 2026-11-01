import Foundation
import UserNotifications

public final class WatchNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
  public static let shared = WatchNotificationDelegate()

  public func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    completionHandler([.banner, .sound])
  }

  public func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    defer { completionHandler() }
    if response.actionIdentifier == "SNOOZE" {
      let content = response.notification.request.content
      let upcomingId = (content.userInfo["upcomingId"] as? String)
        ?? response.notification.request.identifier
          .replacingOccurrences(of: WatchReminders.prefix, with: "")
          .replacingOccurrences(of: ".snooze", with: "")
      let identifier = "\(WatchReminders.prefix)\(upcomingId).snooze"
      let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5 * 60, repeats: false)
      let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
      center.add(request) { _ in }
    }
  }
}

public enum WatchReminders {
  public static let enabledKey = "watch.reminders.enabled"
  public static let categoryIdentifier = "CARECOINS_REMINDER"
  public static let prefix = "carecoins.reminder."
  private static let authRequestedKey = "watch.reminders.authRequested"

  public static var isEnabled: Bool {
    get {
      let defaults = UserDefaults(suiteName: CareCoinsShared.appGroup)
      if defaults?.object(forKey: enabledKey) == nil {
        return true
      }
      return defaults?.bool(forKey: enabledKey) ?? true
    }
    set {
      let defaults = UserDefaults(suiteName: CareCoinsShared.appGroup)
      defaults?.set(newValue, forKey: enabledKey)
    }
  }

  public static func setupAtLaunch() {
    UNUserNotificationCenter.current().delegate = WatchNotificationDelegate.shared
    registerCategories()
  }

  public static func registerCategories() {
    let startAction = UNNotificationAction(
      identifier: "START",
      title: L10n.t("watch.reminder.open"),
      options: [.foreground]
    )
    let snoozeAction = UNNotificationAction(
      identifier: "SNOOZE",
      title: L10n.t("watch.reminder.snooze"),
      options: []
    )
    let category = UNNotificationCategory(
      identifier: categoryIdentifier,
      actions: [startAction, snoozeAction],
      intentIdentifiers: [],
      options: []
    )
    UNUserNotificationCenter.current().setNotificationCategories([category])
  }

  public static func requestAuthorizationIfNeeded() {
    registerCategories()
    let defaults = UserDefaults(suiteName: CareCoinsShared.appGroup)
    if defaults?.bool(forKey: authRequestedKey) == true {
      return
    }
    defaults?.set(true, forKey: authRequestedKey)
    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
  }

  public static func reschedule(from snapshot: QuickSnapshot?, now: Date = .now) {
    let center = UNUserNotificationCenter.current()
    center.getPendingNotificationRequests { requests in
      let toRemove = requests
        .map(\.identifier)
        .filter { $0.hasPrefix(prefix) }
      if !toRemove.isEmpty {
        center.removePendingNotificationRequests(withIdentifiers: toRemove)
      }

      guard isEnabled, QuickAPI.fromStore() != nil, let snapshot = snapshot else {
        return
      }

      let excludedStatuses: Set<String> = ["completed", "rejected", "cancelled", "canceled"]
      let eligible = snapshot.upcoming
        .filter { !excludedStatuses.contains($0.status.lowercased()) }
        .filter { $0.startsAt.addingTimeInterval(-15 * 60) > now }
        .prefix(20)

      for item in eligible {
        let reminderDate = item.startsAt.addingTimeInterval(-15 * 60)
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: reminderDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)

        let content = UNMutableNotificationContent()
        content.title = item.title
        content.body = L10n.t("watch.reminder.body", formatShortTime(item.startsAt))
        content.sound = .default
        content.categoryIdentifier = categoryIdentifier
        content.userInfo = ["upcomingId": item.id]

        let request = UNNotificationRequest(
          identifier: "\(prefix)\(item.id)",
          content: content,
          trigger: trigger
        )
        center.add(request) { _ in }
      }
    }
  }

  public static func formatShortTime(_ date: Date) -> String {
    let defaults = UserDefaults(suiteName: CareCoinsShared.appGroup)
    let lang = defaults?.string(forKey: CareCoinsShared.languageDefault)
    let df = DateFormatter()
    df.timeStyle = .short
    df.dateStyle = .none
    if let lang = lang, !lang.isEmpty {
      df.locale = Locale(identifier: lang)
    } else {
      df.locale = Locale.current
    }
    return df.string(from: date)
  }
}
