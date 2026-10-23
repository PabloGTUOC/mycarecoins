import Foundation
import Security

public enum DeviceKeyStore {
  @discardableResult
  public static func storeKey(_ key: String, accessGroup: String? = nil) -> Bool {
    deleteKey(accessGroup: accessGroup)
    guard let data = key.data(using: .utf8) else { return false }
    var query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrAccount as String: CareCoinsShared.deviceKeyAccount,
      kSecValueData as String: data,
      kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
    ]
    if let accessGroup = accessGroup, !accessGroup.isEmpty, !accessGroup.hasPrefix("$") {
      query[kSecAttrAccessGroup as String] = accessGroup
    }
    var status = SecItemAdd(query as CFDictionary, nil)
    if status != noErr && query[kSecAttrAccessGroup as String] != nil {
      query.removeValue(forKey: kSecAttrAccessGroup as String)
      status = SecItemAdd(query as CFDictionary, nil)
    }
    return status == noErr
  }

  public static func readKey(accessGroup: String? = nil) -> String? {
    var query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrAccount as String: CareCoinsShared.deviceKeyAccount,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    if let accessGroup = accessGroup, !accessGroup.isEmpty, !accessGroup.hasPrefix("$") {
      query[kSecAttrAccessGroup as String] = accessGroup
    }
    var item: CFTypeRef?
    var status = SecItemCopyMatching(query as CFDictionary, &item)
    if status != noErr && query[kSecAttrAccessGroup as String] != nil {
      query.removeValue(forKey: kSecAttrAccessGroup as String)
      status = SecItemCopyMatching(query as CFDictionary, &item)
    }
    guard status == noErr, let data = item as? Data else { return nil }
    return String(data: data, encoding: .utf8)
  }

  @discardableResult
  public static func deleteKey(accessGroup: String? = nil) -> Bool {
    var query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrAccount as String: CareCoinsShared.deviceKeyAccount,
    ]
    if let accessGroup = accessGroup, !accessGroup.isEmpty, !accessGroup.hasPrefix("$") {
      query[kSecAttrAccessGroup as String] = accessGroup
    }
    var status = SecItemDelete(query as CFDictionary)
    if status != noErr && status != errSecItemNotFound && query[kSecAttrAccessGroup as String] != nil {
      query.removeValue(forKey: kSecAttrAccessGroup as String)
      status = SecItemDelete(query as CFDictionary)
    }
    return status == noErr || status == errSecItemNotFound
  }
}
