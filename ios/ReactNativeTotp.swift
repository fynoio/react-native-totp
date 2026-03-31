import Foundation
import CryptoKit
import CommonCrypto
import React

@objc(ReactNativeTotp)
class ReactNativeTotp: NSObject {
  
  private let STATUS_ACTIVE = 1
  private let STATUS_INACTIVE = 0
  
  private let keyStorage = KeyStorage()
  private let dbHelper = try! DatabaseHelper()
  
  // MARK: Init Config
  @objc
  func initFynoConfig(_ wsid: String, distinctId: String, resolver: @escaping RCTPromiseResolveBlock, rejecter: @escaping RCTPromiseRejectBlock) {
    DispatchQueue.global(qos: .userInitiated).async {
      do {
        let uuid = self.getDeviceUuid()
        self.dbHelper.initFynoConfig(wsid: wsid, distinctId: distinctId, uuid: uuid)
        DispatchQueue.main.async { resolver(true) }
      }
    }
  }
  
  private func getDeviceUuid() -> String {
    if let uuid = dbHelper.getDeviceUuid() {
      return uuid
    }
    return UUID().uuidString
  }
  
  // MARK: Register Tenant
  @objc
  func registerTenant(_ tenantId: String, tenantLabel: String, totpToken: String, resolver: @escaping RCTPromiseResolveBlock, rejecter: @escaping RCTPromiseRejectBlock) {
    DispatchQueue.global(qos: .userInitiated).async {
      do {
        self.dbHelper.registerTenant(tenantId: tenantId, tenantLabel: tenantLabel)
        try self.setKeySync(tenantId: tenantId, totpToken: totpToken, status: self.STATUS_ACTIVE)
        DispatchQueue.main.async { resolver(true) }
      } catch {
        DispatchQueue.main.async {
          rejecter("REGISTER_ERROR", error.localizedDescription, error)
        }
      }
    }
  }
  
  // MARK: Store Secret in Keychain + DB
  private func setKeySync(tenantId: String,
                          totpToken: String,
                          status: Int) throws {
    
    guard let secretData = totpToken.data(using: .utf8) else {
      throw NSError(domain: "TOTP", code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Invalid secret"])
    }
    
    try keyStorage.storeSecret(alias: tenantId, secret: secretData)
    
    dbHelper.setKey(
      tenantId: tenantId,
      secretAlias: "fyno_totp_secret_\(tenantId)",
      iv: nil,
      status: status
    )
  }
  
  // MARK: Set Tenant Config
  @objc
  func setConfig(_ tenantId: String,
                 config: NSDictionary,
                 resolver: @escaping RCTPromiseResolveBlock,
                 rejecter: @escaping RCTPromiseRejectBlock) {
    
    DispatchQueue.global(qos: .userInitiated).async {
      do {
        // Parse config from JS
        guard let digits = config["digits"] as? Int,
              let period = config["period"] as? Int,
              let algorithm = config["algorithm"] as? String else {
          throw NSError(domain: "TOTP", code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "Invalid config"])
        }
        
        let totpConfig = TotpConfig(
          digits: digits,
          period: period,
          algorithm: algorithm
        )
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(totpConfig)
        let json = String(data: data, encoding: .utf8) ?? "{}"
        
        self.dbHelper.setConfig(
          tenantId: tenantId,
          configJson: json
        )
        
        DispatchQueue.main.async {
          resolver(true)
        }
        
      } catch {
        DispatchQueue.main.async {
          rejecter("SET_CONFIG_ERROR", error.localizedDescription, error)
        }
      }
    }
  }
  
  // MARK: Get TOTP
  @objc
  func getTotp(_ tenantId: String,
               resolver: @escaping RCTPromiseResolveBlock,
               rejecter: @escaping RCTPromiseRejectBlock) {
    
    DispatchQueue.global(qos: .userInitiated).async {
      do {
        guard let totpData = self.dbHelper.getTotpData(tenantId: tenantId) else {
          DispatchQueue.main.async { resolver(nil) }
          return
        }
        
        if totpData.status != self.STATUS_ACTIVE {
          DispatchQueue.main.async { resolver(nil) }
          return
        }
        
        let storedAlias = totpData.encryptedSecretAlias
        let alias: String
        
        if storedAlias.hasPrefix("fyno_totp_secret_") {
          alias = String(storedAlias.dropFirst("fyno_totp_secret_".count))
        } else {
          alias = storedAlias
        }
        
        let secretData = try self.keyStorage.retrieveSecret(alias: alias)
        
        guard let secretString = String(data: secretData, encoding: .utf8) else {
          throw NSError(domain: "TOTP", code: -2,
                        userInfo: [NSLocalizedDescriptionKey: "Secret encoding failed"])
        }
        
        let config = totpData.config
        
        let otp = try self.generateTOTP(
          secret: Array(secretString.utf8),
          digits: config.digits,
          algorithm: config.algorithm,
          period: config.period
        )
        
        DispatchQueue.main.async { resolver(otp) }
        
      } catch {
        DispatchQueue.main.async {
          rejecter("TOTP_ERROR", error.localizedDescription, error)
        }
      }
    }
  }
  
  // MARK: Delete Tenant
  @objc
  func deleteTenant(_ tenantId: String,
                    resolver: @escaping RCTPromiseResolveBlock,
                    rejecter: @escaping RCTPromiseRejectBlock) {
    
    dbHelper.deleteTenant(tenantId: tenantId)
    keyStorage.deleteSecret(alias: tenantId)
    
    resolver(true)
  }
  
  // MARK: Fetch active tenants
  @objc
  func fetchActiveTenants(_ resolver: @escaping RCTPromiseResolveBlock,
                          rejecter: @escaping RCTPromiseRejectBlock) {
    
    DispatchQueue.global(qos: .userInitiated).async {
      let tenants = self.dbHelper.getActiveTenants()
      
      let result = tenants.map { tenant -> [String: Any] in
        var dict: [String: Any] = [
          "tenantId": tenant.tenantId,
          "tenantLabel": tenant.tenantLabel
        ]
        
        if let config = tenant.config {
          dict["config"] = [
            "digits": config.digits,
            "period": config.period,
            "algorithm": config.algorithm
          ]
        } else {
          dict["config"] = NSNull()
        }
        
        return dict
      }
      
      DispatchQueue.main.async {
        resolver(result)
      }
    }
  }
  
  // MARK: TOTP Generation
  private func generateTOTP(secret: [UInt8],
                            digits: Int,
                            algorithm: String,
                            period: Int) throws -> String {
    
    let time = UInt64(Date().timeIntervalSince1970)
    let counter = time / UInt64(period)
    
    var counterBe = counter.bigEndian
    let counterData = withUnsafeBytes(of: &counterBe) { Data($0) }
    
    let hash: [UInt8]
    
    switch algorithm.uppercased() {
    case "SHA1":
      hash = hmacSHA1(key: secret, message: [UInt8](counterData))
    case "SHA256":
      hash = hmacSHA256(key: secret, message: [UInt8](counterData))
    case "SHA512":
      hash = hmacSHA512(key: secret, message: [UInt8](counterData))
    default:
      throw NSError(domain: "TOTP", code: -3,
                    userInfo: [NSLocalizedDescriptionKey: "Unsupported algorithm"])
    }
    
    guard let offset = hash.last.map({ Int($0 & 0x0f) }) else {
      throw NSError(domain: "TOTP", code: -4,
                    userInfo: [NSLocalizedDescriptionKey: "Hash error"])
    }
    
    let slice = Array(hash[offset..<(offset+4)])
    
    var truncated: UInt32 = 0
    truncated |= UInt32(slice[0]) << 24
    truncated |= UInt32(slice[1]) << 16
    truncated |= UInt32(slice[2]) << 8
    truncated |= UInt32(slice[3])
    
    truncated = truncated & 0x7fffffff
    
    let mod = UInt32(pow(10.0, Double(digits)))
    let otp = Int(truncated % mod)
    
    return String(format: "%0\(digits)d", otp)
  }
  
  // MARK: HMAC
  private func hmacSHA1(key: [UInt8], message: [UInt8]) -> [UInt8] {
    var mac = [UInt8](repeating: 0, count: Int(CC_SHA1_DIGEST_LENGTH))
    
    key.withUnsafeBytes { keyBuf in
      message.withUnsafeBytes { msgBuf in
        CCHmac(CCHmacAlgorithm(kCCHmacAlgSHA1),
               keyBuf.baseAddress, key.count,
               msgBuf.baseAddress, message.count,
               &mac)
      }
    }
    return mac
  }
  
  private func hmacSHA256(key: [UInt8], message: [UInt8]) -> [UInt8] {
    let key = SymmetricKey(data: Data(key))
    let mac = HMAC<SHA256>.authenticationCode(for: Data(message), using: key)
    return Array(mac)
  }
  
  private func hmacSHA512(key: [UInt8], message: [UInt8]) -> [UInt8] {
    let key = SymmetricKey(data: Data(key))
    let mac = HMAC<SHA512>.authenticationCode(for: Data(message), using: key)
    return Array(mac)
  }
  
  @objc
  static func requiresMainQueueSetup() -> Bool {
    return false
  }
}
