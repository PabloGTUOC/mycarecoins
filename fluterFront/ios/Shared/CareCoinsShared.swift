import Foundation
import Security

/// Identifiers shared by the Runner, the widget and the watch targets
/// (docs/ios-widget-watch-plan.md §3.4). Each one must match the targets' entitlements.
enum CareCoinsShared {
  static let appGroup = "group.com.carecoins.carecoinsFlutter"
  /// Keychain access group, without the team prefix the system adds.
  static let keychainGroupSuffix = "com.carecoins.carecoinsFlutter.shared"
  static let deviceKeyAccount = "carecoins.deviceKey"
  static let snapshotFile = "quick.json"
  static let deviceKeyIdDefault = "deviceKeyId"
  static let apiBaseDefault = "apiBase"
  static let languageDefault = "language"

  static var keychainAccessGroup: String? {
    guard let prefix = Bundle.main.object(forInfoDictionaryKey: "CareCoinsAppIdentifierPrefix") as? String,
          !prefix.isEmpty,
          !prefix.hasPrefix("$") else {
      return nil
    }
    return prefix + keychainGroupSuffix
  }

  static func disconnectLocally() {
    DeviceKeyStore.deleteKey(accessGroup: keychainAccessGroup)
    if let defaults = UserDefaults(suiteName: appGroup) {
      defaults.removeObject(forKey: deviceKeyIdDefault)
      defaults.removeObject(forKey: apiBaseDefault)
    }
    if let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) {
      let fileURL = containerURL.appendingPathComponent(snapshotFile)
      try? FileManager.default.removeItem(at: fileURL)
    }
    SnapshotStore.reloadWidgets()
  }
}
