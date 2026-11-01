import Foundation
import WatchConnectivity

/// Handles communication between the iPhone and the Apple Watch via WatchConnectivity
/// (docs/ios-widget-watch-plan.md §3.4 and §5).
final class WatchConnector: NSObject, WCSessionDelegate {
  static let shared = WatchConnector()

  private override init() {
    super.init()
  }

  func activate() {
    if WCSession.isSupported() {
      let session = WCSession.default
      session.delegate = self
      session.activate()
    }
  }

  // MARK: - WCSessionDelegate

  func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
    guard activationState == .activated else { return }
    let context = session.receivedApplicationContext
    if let key = context["deviceKey"] as? String, !key.isEmpty {
      handleContext(context)
    } else if !context.isEmpty {
      handleContext(context)
    }
  }

  func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
    handleContext(applicationContext)
  }

  private func handleContext(_ context: [String: Any]) {
    guard let key = context["deviceKey"] as? String, !key.isEmpty,
          let apiBase = context["apiBase"] as? String, !apiBase.isEmpty else {
      CareCoinsShared.disconnectLocally()
      Task { @MainActor in
        WatchStore.shared.reloadFromDisk()
        WatchReminders.reschedule(from: nil, now: .now)
        SnapshotStore.reloadWidgets()
      }
      return
    }

    DeviceKeyStore.storeKey(key, accessGroup: CareCoinsShared.keychainAccessGroup)
    if let defaults = UserDefaults(suiteName: CareCoinsShared.appGroup) {
      defaults.set(apiBase, forKey: CareCoinsShared.apiBaseDefault)
      if let lang = context["language"] as? String, !lang.isEmpty {
        defaults.set(lang, forKey: CareCoinsShared.languageDefault)
      } else {
        defaults.removeObject(forKey: CareCoinsShared.languageDefault)
      }
    }

    if let snapshotString = context["snapshot"] as? String,
       let snapshotData = snapshotString.data(using: .utf8) {
      SnapshotStore.save(snapshotData)
    }

    Task { @MainActor in
      WatchStore.shared.reloadFromDisk()
      WatchReminders.requestAuthorizationIfNeeded()
      WatchReminders.reschedule(from: WatchStore.shared.snapshot, now: .now)
      SnapshotStore.reloadWidgets()
      await WatchStore.shared.refresh()
    }
  }
}
