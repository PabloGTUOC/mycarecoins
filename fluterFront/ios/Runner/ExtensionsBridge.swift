import Flutter
import Foundation
import WatchConnectivity
import WidgetKit

public final class ExtensionsBridge: NSObject, WCSessionDelegate {
  private static var shared: ExtensionsBridge?

  public static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "carecoins/extensions", binaryMessenger: messenger)
    let bridge = ExtensionsBridge()
    shared = bridge
    channel.setMethodCallHandler { [weak bridge] call, result in
      bridge?.handle(call, result: result)
    }
  }

  override init() {
    super.init()
    if WCSession.isSupported() {
      let session = WCSession.default
      session.delegate = self
      session.activate()
    }
  }

  // MARK: - WCSessionDelegate
  public func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}
  public func sessionDidBecomeInactive(_ session: WCSession) {}
  public func sessionDidDeactivate(_ session: WCSession) {
    WCSession.default.activate()
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "isSupported":
      result(true)

    case "storeDeviceKey":
      guard let args = call.arguments as? [String: Any],
            let key = args["key"] as? String,
            let deviceKeyId = args["deviceKeyId"] as? String,
            let apiBase = args["apiBase"] as? String else {
        result(FlutterError(code: "invalid_arguments", message: "Missing arguments for storeDeviceKey", details: nil))
        return
      }
      DeviceKeyStore.storeKey(key, accessGroup: CareCoinsShared.keychainAccessGroup)
      if let defaults = UserDefaults(suiteName: CareCoinsShared.appGroup) {
        defaults.set(deviceKeyId, forKey: CareCoinsShared.deviceKeyIdDefault)
        defaults.set(apiBase, forKey: CareCoinsShared.apiBaseDefault)
      }
      refresh(result: result)

    case "status":
      let key = DeviceKeyStore.readKey(accessGroup: CareCoinsShared.keychainAccessGroup)
      let defaults = UserDefaults(suiteName: CareCoinsShared.appGroup)
      let deviceKeyId = defaults?.string(forKey: CareCoinsShared.deviceKeyIdDefault)
      let connected = key != nil && !(key?.isEmpty ?? true) && deviceKeyId != nil && !(deviceKeyId?.isEmpty ?? true)
      var statusMap: [String: Any] = [
        "connected": connected
      ]
      if connected, let deviceKeyId = deviceKeyId {
        statusMap["deviceKeyId"] = deviceKeyId
      } else {
        statusMap["deviceKeyId"] = NSNull()
      }
      result(statusMap)

    case "refresh":
      refresh(result: result)

    case "clear":
      clearInternal()
      result(nil)

    case "setLanguage":
      let args = call.arguments as? [String: Any]
      let code = args?["code"] as? String
      if let defaults = UserDefaults(suiteName: CareCoinsShared.appGroup) {
        if let code = code, !code.isEmpty {
          defaults.set(code, forKey: CareCoinsShared.languageDefault)
        } else {
          defaults.removeObject(forKey: CareCoinsShared.languageDefault)
        }
      }
      WidgetCenter.shared.reloadAllTimelines()
      result(nil)

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func clearInternal() {
    CareCoinsShared.disconnectLocally()
    #if canImport(ActivityKit)
    if #available(iOS 17.0, *) {
      QuickLiveActivities.endAll()
    }
    #endif
    if WCSession.isSupported() {
      do {
        try WCSession.default.updateApplicationContext([:])
      } catch {
        // ignore errors
      }
    }
  }

  private func refresh(result: @escaping FlutterResult) {
    guard let key = DeviceKeyStore.readKey(accessGroup: CareCoinsShared.keychainAccessGroup), !key.isEmpty,
          let defaults = UserDefaults(suiteName: CareCoinsShared.appGroup),
          let apiBase = defaults.string(forKey: CareCoinsShared.apiBaseDefault), !apiBase.isEmpty else {
      result("none")
      return
    }
    let base = apiBase.hasSuffix("/") ? String(apiBase.dropLast()) : apiBase
    guard let url = URL(string: "\(base)/api/quick") else {
      result("failed")
      return
    }
    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    request.setValue("Device \(key)", forHTTPHeaderField: "Authorization")

    let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
      if let httpResponse = response as? HTTPURLResponse {
        if httpResponse.statusCode == 200 {
          if let data = data {
            SnapshotStore.save(data)
            #if canImport(ActivityKit)
            if #available(iOS 17.0, *) {
              if let snapshot = try? JSONDecoder.quick.decode(QuickSnapshot.self, from: data) {
                QuickLiveActivities.sync(with: snapshot, now: Date())
              }
            }
            #endif
          }
          WidgetCenter.shared.reloadAllTimelines()
          if WCSession.isSupported() {
            let jsonString = data.flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
            let language = defaults.string(forKey: CareCoinsShared.languageDefault) ?? ""
            do {
              try WCSession.default.updateApplicationContext([
                "deviceKey": key,
                "apiBase": apiBase,
                "snapshot": jsonString,
                "language": language
              ])
            } catch {
              // ignore errors
            }
          }
          DispatchQueue.main.async {
            result("ok")
          }
          return
        } else if httpResponse.statusCode == 401 {
          self?.clearInternal()
          DispatchQueue.main.async {
            result("revoked")
          }
          return
        }
      }
      DispatchQueue.main.async {
        result("failed")
      }
    }
    task.resume()
  }
}
