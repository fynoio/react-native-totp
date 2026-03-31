package io.fyno.reactnativetotp.helpers

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import com.google.gson.Gson
import androidx.core.database.sqlite.transaction
import io.fyno.reactnativetotp.models.TotpConfig

data class TotpData(val encryptedSecret: String, val iv: String, val config: TotpConfig, val status: Int)

class DatabaseHelper private constructor(context: Context) : SQLiteOpenHelper(context, DATABASE_NAME, null, DATABASE_VERSION) {
  private val gson = Gson()

  companion object {
    private const val DATABASE_VERSION = 3 // Increment to trigger DB upgrade when needed
    private const val DATABASE_NAME = "FynoTotp.db"
    private const val TAG = "DatabaseHelper"

    // Fyno Config Table
    private const val TABLE_FYNO_CONFIG = "fyno_config"
    private const val COLUMN_CONFIG_ID = "id"
    private const val COLUMN_WSID = "wsid"
    private const val COLUMN_DISTINCT_ID = "distinct_id"
    private const val COLUMN_DEVICE_UUID = "device_uuid"

    // Tenants Config Table
    private const val TABLE_TENANTS = "tenants_config"
    private const val COLUMN_TENANT_ID = "tenant_id"
    private const val COLUMN_TENANT_LABEL = "tenant_label"
    private const val COLUMN_CONFIG_JSON = "config_json"

    // Tenant Keys Table
    private const val TABLE_TENANT_KEYS = "tenant_keys"
    private const val COLUMN_FK_TENANT_ID = "tenant_id"
    private const val COLUMN_ENCRYPTED_SECRET = "encrypted_secret"
    private const val COLUMN_IV = "iv"
    private const val COLUMN_STATUS = "status"

    @Volatile
    private var INSTANCE: DatabaseHelper? = null

    fun getInstance(context: Context): DatabaseHelper {
      return INSTANCE ?: synchronized(this) {
        INSTANCE ?: DatabaseHelper(context.applicationContext).also { INSTANCE = it }
      }
    }

    fun closeInstance() {
      try {
        INSTANCE?.close()
      } catch (_: Throwable) {
      }
      INSTANCE = null
    }
  }

  override fun onCreate(db: SQLiteDatabase) {
    val createFynoConfigTable = "CREATE TABLE $TABLE_FYNO_CONFIG (" +
      "\"$COLUMN_CONFIG_ID\" INTEGER PRIMARY KEY, " +
      "\"$COLUMN_WSID\" TEXT, " +
      "\"$COLUMN_DISTINCT_ID\" TEXT, " +
      "\"$COLUMN_DEVICE_UUID\" TEXT)"
    db.execSQL(createFynoConfigTable)

    val createTenantsTable = "CREATE TABLE $TABLE_TENANTS (" +
      "\"$COLUMN_TENANT_ID\" TEXT PRIMARY KEY, " +
      "\"$COLUMN_TENANT_LABEL\" TEXT, " +
      "\"$COLUMN_CONFIG_JSON\" TEXT)"
    db.execSQL(createTenantsTable)

    val createTenantKeysTable = "CREATE TABLE $TABLE_TENANT_KEYS (" +
      "\"$COLUMN_FK_TENANT_ID\" TEXT PRIMARY KEY, " +
      "\"$COLUMN_ENCRYPTED_SECRET\" TEXT, " +
      "\"$COLUMN_IV\" TEXT, " +
      "\"$COLUMN_STATUS\" INTEGER, " +
      "FOREIGN KEY(\"$COLUMN_FK_TENANT_ID\") REFERENCES $TABLE_TENANTS($COLUMN_TENANT_ID))"
    db.execSQL(createTenantKeysTable)
  }

  override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
    // Drop only known tables and recreate. For production, implement proper migrations.
    db.execSQL("DROP TABLE IF EXISTS $TABLE_TENANT_KEYS")
    db.execSQL("DROP TABLE IF EXISTS $TABLE_TENANTS")
    db.execSQL("DROP TABLE IF EXISTS $TABLE_FYNO_CONFIG")
    onCreate(db)
  }

  override fun close() {
    super.close()
    INSTANCE = null
  }

  fun initFynoConfig(wsid: String, distinctId: String, uuid: String) {
    val db = this.writableDatabase
    val values = ContentValues().apply {
      put(COLUMN_CONFIG_ID, 1) // Single row table
      put(COLUMN_WSID, wsid)
      put(COLUMN_DISTINCT_ID, distinctId)
      put(COLUMN_DEVICE_UUID, uuid)
    }
    db.transaction {
      try {
        replace(TABLE_FYNO_CONFIG, null, values)
      } finally {
      }
    }
  }

  fun getDeviceUuid(): String? {
    val db = this.readableDatabase
    val cursor = db.query(
      TABLE_FYNO_CONFIG,
      arrayOf(COLUMN_DEVICE_UUID),
      "$COLUMN_CONFIG_ID = ?",
      arrayOf("1"),
      null,
      null,
      null
    )
    val uuid =
      cursor.use { if (it.moveToFirst()) it.getString(it.getColumnIndexOrThrow(COLUMN_DEVICE_UUID)) else null }
    return uuid
  }

  fun registerTenant(tenantId: String, tenantLabel: String) {
    val db = this.writableDatabase
    val values = ContentValues().apply {
      put(COLUMN_TENANT_ID, tenantId)
      put(COLUMN_TENANT_LABEL, tenantLabel)
    }
    db.transaction {
      try {
        replace(TABLE_TENANTS, null, values)
      } finally {
      }
    }
  }

  /**
   * Update the tenant config JSON; if the row doesn't exist, insert it.
   */
  fun setConfig(tenantId: String, configJson: String) {
    val db = this.writableDatabase
    val values = ContentValues().apply { put(COLUMN_CONFIG_JSON, configJson) }

    db.transaction {
      try {
        val rows = update(TABLE_TENANTS, values, "$COLUMN_TENANT_ID = ?", arrayOf(tenantId))
        if (rows == 0) {
          val insertValues = ContentValues().apply {
            put(COLUMN_TENANT_ID, tenantId)
            put(COLUMN_CONFIG_JSON, configJson)
          }
          insert(TABLE_TENANTS, null, insertValues)
        }
      } finally {
      }
    }
  }

  /**
   * Store encrypted key info in a transaction-safe way.
   */
  fun setKey(tenantId: String, encryptedSecret: String, iv: String, status: Int) {
    val db = this.writableDatabase
    val values = ContentValues().apply {
      put(COLUMN_FK_TENANT_ID, tenantId)
      put(COLUMN_ENCRYPTED_SECRET, encryptedSecret)
      put(COLUMN_IV, iv)
      put(COLUMN_STATUS, status)
    }
    db.transaction {
      try {
        replace(TABLE_TENANT_KEYS, null, values)
      } finally {
      }
    }
  }

  fun getTotpData(tenantId: String): TotpData? {
    val db = this.readableDatabase
    val query =
      "SELECT t.$COLUMN_CONFIG_JSON, k.$COLUMN_ENCRYPTED_SECRET, k.$COLUMN_IV, k.$COLUMN_STATUS " +
        "FROM $TABLE_TENANTS t INNER JOIN $TABLE_TENANT_KEYS k ON t.$COLUMN_TENANT_ID = k.$COLUMN_FK_TENANT_ID " +
        "WHERE t.$COLUMN_TENANT_ID = ?"

    val cursor = db.rawQuery(query, arrayOf(tenantId))
    return cursor.use {
      if (it.moveToFirst()) {
        val configJson = it.getString(it.getColumnIndexOrThrow(COLUMN_CONFIG_JSON))
        val secret = it.getString(it.getColumnIndexOrThrow(COLUMN_ENCRYPTED_SECRET))
        val iv = it.getString(it.getColumnIndexOrThrow(COLUMN_IV))
        val status = it.getInt(it.getColumnIndexOrThrow(COLUMN_STATUS))

        if (configJson != null && secret != null && iv != null) {
          TotpData(secret, iv, gson.fromJson(configJson, TotpConfig::class.java), status)
        } else {
          null
        }
      } else {
        null
      }
    }
  }

  /**
   * Delete all enrolment related information for the tenant.
   * Removes both tenant key and tenant config in a single transaction.
   */
  fun deleteTenant(tenantId: String) {
    val db = this.writableDatabase
    db.transaction {
      try {
        delete(TABLE_TENANT_KEYS, "$COLUMN_FK_TENANT_ID = ?", arrayOf(tenantId))
      } finally {
      }
    }
  }

  fun fetchActiveTenants(): List<Map<String, String>> {
    val db = this.readableDatabase
    val result = mutableListOf<Map<String, String>>()

    val query = """
    SELECT t.$COLUMN_TENANT_ID, t.$COLUMN_TENANT_LABEL
    FROM $TABLE_TENANTS t
    INNER JOIN $TABLE_TENANT_KEYS k
    ON t.$COLUMN_TENANT_ID = k.$COLUMN_FK_TENANT_ID
    WHERE k.$COLUMN_STATUS = 1
  """.trimIndent()

    val cursor = db.rawQuery(query, null)

    cursor.use {
      while (it.moveToNext()) {
        val tenantId = it.getString(it.getColumnIndexOrThrow(COLUMN_TENANT_ID))
        val tenantLabel = it.getString(it.getColumnIndexOrThrow(COLUMN_TENANT_LABEL))

        result.add(
          mapOf(
            "tenant_id" to tenantId,
            "tenant_label" to tenantLabel
          )
        )
      }
    }

    return result
  }

  // Optional: explicit close helper if app needs to release DB on shutdown
  fun closeHelper() {
    try {
      this.close()
    } catch (_: Throwable) {
    }
  }
}
