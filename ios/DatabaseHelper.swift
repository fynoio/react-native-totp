import Foundation
import FMDB

public final class DatabaseHelper {
  
  private let dbQueue: FMDatabaseQueue
  
  // Table names
  private let TABLE_FYNO_CONFIG = "fyno_config"
  private let TABLE_TENANTS = "tenants_config"
  private let TABLE_TENANT_KEYS = "tenant_keys"
  
  // Columns
  private let COLUMN_CONFIG_ID = "id"
  private let COLUMN_WSID = "wsid"
  private let COLUMN_DISTINCT_ID = "distinct_id"
  private let COLUMN_DEVICE_UUID = "device_uuid"
  
  private let COLUMN_TENANT_ID = "tenant_id"
  private let COLUMN_TENANT_LABEL = "tenant_label"
  private let COLUMN_CONFIG_JSON = "config_json"
  
  private let COLUMN_ENCRYPTED_SECRET_ALIAS = "encrypted_secret_alias"
  private let COLUMN_IV = "iv"
  private let COLUMN_STATUS = "status"
  
  // MARK: - Init
  
  public init(filename: String = "FynoTotp.sqlite") throws {
    let fileURL = try Self.databaseURL(filename: filename)
    self.dbQueue = FMDatabaseQueue(url: fileURL)!
    
    createTables()
  }
  
  private static func databaseURL(filename: String) throws -> URL {
    let fm = FileManager.default
    guard let dir = fm.urls(for: .documentDirectory, in: .userDomainMask).first else {
      throw NSError(domain: "Database", code: 1, userInfo: [NSLocalizedDescriptionKey: "Document directory missing"])
    }
    return dir.appendingPathComponent(filename)
  }
  
  // MARK: - Create Tables
  
  private func createTables() {
    dbQueue.inDatabase { db in
      db.executeUpdate("""
                CREATE TABLE IF NOT EXISTS \(TABLE_FYNO_CONFIG) (
                    \(COLUMN_CONFIG_ID) INTEGER PRIMARY KEY,
                    \(COLUMN_WSID) TEXT,
                    \(COLUMN_DISTINCT_ID) TEXT,
                    \(COLUMN_DEVICE_UUID) TEXT
                );
            """, withArgumentsIn: [])
      
      db.executeUpdate("""
                CREATE TABLE IF NOT EXISTS \(TABLE_TENANTS) (
                    \(COLUMN_TENANT_ID) TEXT PRIMARY KEY,
                    \(COLUMN_TENANT_LABEL) TEXT,
                    \(COLUMN_CONFIG_JSON) TEXT
                );
            """, withArgumentsIn: [])
      
      db.executeUpdate("""
                CREATE TABLE IF NOT EXISTS \(TABLE_TENANT_KEYS) (
                    \(COLUMN_TENANT_ID) TEXT PRIMARY KEY,
                    \(COLUMN_ENCRYPTED_SECRET_ALIAS) TEXT,
                    \(COLUMN_IV) TEXT,
                    \(COLUMN_STATUS) INTEGER,
                    FOREIGN KEY(\(COLUMN_TENANT_ID)) REFERENCES \(TABLE_TENANTS)(\(COLUMN_TENANT_ID))
                );
            """, withArgumentsIn: [])
    }
  }
  
  // MARK: - CRUD
  
  public func initFynoConfig(wsid: String, distinctId: String, uuid: String) {
    dbQueue.inDatabase { db in
      db.executeUpdate("""
                REPLACE INTO \(TABLE_FYNO_CONFIG)
                (\(COLUMN_CONFIG_ID), \(COLUMN_WSID), \(COLUMN_DISTINCT_ID), \(COLUMN_DEVICE_UUID))
                VALUES (1, ?, ?, ?)
            """, withArgumentsIn: [wsid, distinctId, uuid])
    }
  }
  
  public func getDeviceUuid() -> String? {
    var result: String?
    dbQueue.inDatabase { db in
      let rs = db.executeQuery("""
                SELECT \(COLUMN_DEVICE_UUID) FROM \(TABLE_FYNO_CONFIG) WHERE \(COLUMN_CONFIG_ID) = 1
            """, withArgumentsIn: [])
      if rs?.next() == true {
        result = rs?.string(forColumn: COLUMN_DEVICE_UUID)
      }
      rs?.close()
    }
    return result
  }
  
  public func registerTenant(tenantId: String, tenantLabel: String) {
    dbQueue.inDatabase { db in
      db.executeUpdate("""
                REPLACE INTO \(TABLE_TENANTS)
                (\(COLUMN_TENANT_ID), \(COLUMN_TENANT_LABEL))
                VALUES (?, ?)
            """, withArgumentsIn: [tenantId, tenantLabel])
    }
  }
  
  public func setConfig(tenantId: String, configJson: String) {
    dbQueue.inDatabase { db in
      db.executeUpdate("""
                UPDATE \(TABLE_TENANTS)
                SET \(COLUMN_CONFIG_JSON) = ?
                WHERE \(COLUMN_TENANT_ID) = ?
            """, withArgumentsIn: [configJson, tenantId])
    }
  }
  
  public func deleteTenant(tenantId: String) {
    dbQueue.inDatabase { db in
      db.executeUpdate("DELETE FROM tenants_config WHERE tenant_id = ?", withArgumentsIn: [tenantId])
      db.executeUpdate("DELETE FROM tenant_keys WHERE tenant_id = ?", withArgumentsIn: [tenantId])
    }
  }
  
  public func setKey(tenantId: String, secretAlias: String, iv: String?, status: Int) {
    dbQueue.inDatabase { db in
      db.executeUpdate("""
                REPLACE INTO \(TABLE_TENANT_KEYS)
                (\(COLUMN_TENANT_ID), \(COLUMN_ENCRYPTED_SECRET_ALIAS), \(COLUMN_IV), \(COLUMN_STATUS))
                VALUES (?, ?, ?, ?)
            """, withArgumentsIn: [tenantId, secretAlias, iv ?? NSNull(), status])
    }
  }
  
  public func getTotpData(tenantId: String) -> TotpData? {
    var result: TotpData?
    dbQueue.inDatabase { db in
      let rs = db.executeQuery("""
                SELECT t.\(COLUMN_CONFIG_JSON), k.\(COLUMN_ENCRYPTED_SECRET_ALIAS),
                       k.\(COLUMN_IV), k.\(COLUMN_STATUS)
                FROM \(TABLE_TENANTS) t
                JOIN \(TABLE_TENANT_KEYS) k ON t.\(COLUMN_TENANT_ID) = k.\(COLUMN_TENANT_ID)
                WHERE t.\(COLUMN_TENANT_ID) = ?
            """, withArgumentsIn: [tenantId])
      
      if rs?.next() == true {
        let configJson = rs?.string(forColumn: COLUMN_CONFIG_JSON) ?? "{}"
        let alias = rs?.string(forColumn: COLUMN_ENCRYPTED_SECRET_ALIAS) ?? ""
        let iv = rs?.string(forColumn: COLUMN_IV)
        let status = Int(rs?.int(forColumn: COLUMN_STATUS) ?? 0)
        
        let config = try! JSONDecoder().decode(TotpConfig.self, from: configJson.data(using: .utf8)!)
        
        result = TotpData(
          encryptedSecretAlias: alias,
          iv: iv,
          config: config,
          status: status
        )
      }
      
      rs?.close()
    }
    return result
  }
  
  public func getActiveTenants() -> [ActiveTenant] {
    var tenants: [ActiveTenant] = []
    
    dbQueue.inDatabase { db in
      let rs = db.executeQuery("""
                SELECT t.\(COLUMN_TENANT_ID),
                       t.\(COLUMN_TENANT_LABEL),
                       t.\(COLUMN_CONFIG_JSON)
                FROM \(TABLE_TENANTS) t
                JOIN \(TABLE_TENANT_KEYS) k
                ON t.\(COLUMN_TENANT_ID) = k.\(COLUMN_TENANT_ID)
                WHERE k.\(COLUMN_STATUS) = 1
            """, withArgumentsIn: [])
      
      while rs?.next() == true {
        let tenantId = rs?.string(forColumn: COLUMN_TENANT_ID) ?? ""
        let label = rs?.string(forColumn: COLUMN_TENANT_LABEL) ?? ""
        let configJson = rs?.string(forColumn: COLUMN_CONFIG_JSON)
        
        var config: TotpConfig? = nil
        if let configJson = configJson,
           let data = configJson.data(using: .utf8) {
          config = try? JSONDecoder().decode(TotpConfig.self, from: data)
        }
        
        tenants.append(
          ActiveTenant(
            tenantId: tenantId,
            tenantLabel: label,
            config: config
          )
        )
      }
      
      rs?.close()
    }
    
    return tenants
  }
}
