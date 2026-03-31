import Foundation
import Security
import CommonCrypto

public class KeyStorage {
  public init() {}
  
  private func aliasForTenant(_ alias: String) -> String {
    return "fyno_totp_secret_\(alias)"
  }
  
  @discardableResult
  public func storeSecret(alias: String, secret: Data) throws {
    let key = aliasForTenant(alias)
    // Delete existing
    let queryDelete: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrAccount as String: key
    ]
    SecItemDelete(queryDelete as CFDictionary)
    
    // Add new
    let queryAdd: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrAccount as String: key,
      kSecValueData as String: secret,
      kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
    ]
    let status = SecItemAdd(queryAdd as CFDictionary, nil)
    guard status == errSecSuccess else {
      throw KeychainError.unhandledError(status: status)
    }
  }
  
  public func retrieveSecret(alias: String) throws -> Data {
    let key = aliasForTenant(alias)
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrAccount as String: key,
      kSecReturnData as String: kCFBooleanTrue!,
      kSecMatchLimit as String: kSecMatchLimitOne
    ]
    
    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    
    guard status != errSecItemNotFound else {
      throw KeychainError.itemNotFound
    }
    guard status == errSecSuccess else {
      throw KeychainError.unhandledError(status: status)
    }
    guard let data = item as? Data else {
      throw KeychainError.unexpectedData
    }
    return data
  }
  
  public func deleteSecret(alias: String) {
    let key = aliasForTenant(alias)
    let queryDelete: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrAccount as String: key
    ]
    SecItemDelete(queryDelete as CFDictionary)
  }
}

public enum KeychainError: Error {
  case itemNotFound
  case unexpectedData
  case unhandledError(status: OSStatus)
}
