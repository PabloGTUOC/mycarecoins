import Foundation

/// Identifiers shared by the Runner, the widget and the watch targets
/// (docs/ios-widget-watch-plan.md §3.4). Each one must match the targets' entitlements.
enum CareCoinsShared {
  static let appGroup = "group.com.carecoins.carecoinsFlutter"
  /// Keychain access group, without the team prefix the system adds.
  static let keychainGroupSuffix = "com.carecoins.carecoinsFlutter.shared"
  static let deviceKeyAccount = "carecoins.deviceKey"
}
