package io.fyno.reactnativetotp

import android.os.Build
import android.util.Base64
import android.util.Log
import androidx.annotation.RequiresApi
import com.facebook.react.bridge.Promise
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.bridge.ReadableMap
import com.facebook.react.bridge.ReadableType
import io.fyno.reactnativetotp.helpers.DatabaseHelper
import com.google.gson.Gson
import io.fyno.reactnativetotp.models.TotpConfig
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.nio.ByteBuffer
import java.security.InvalidKeyException
import java.security.NoSuchAlgorithmException
import java.util.UUID
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec
import kotlin.experimental.and
import kotlin.math.pow

class ReactNativeTotpModule(reactContext: ReactApplicationContext) :
  NativeReactNativeTotpSpec(reactContext) {


  private val TAG = "FynoTOTP"

  private val keyStorage = KeyStorage()
  private val dbHelper = DatabaseHelper.getInstance(reactContext)
  private val gson = Gson()

  // Define status as constants
  private val STATUS_ACTIVE = 1
  private val STATUS_INACTIVE = 0

  override fun initFynoConfig(
    wsid: String?,
    distinctId: String?,
    promise: Promise?
  ) {
    if (wsid.isNullOrBlank() || distinctId.isNullOrBlank()) {
      promise?.reject("INIT_ERROR", "wsid and distinct_id are required")
    } else {
      CoroutineScope(Dispatchers.IO).launch {
        try {
          val uuid = getDeviceUuid()
          dbHelper.initFynoConfig(wsid, distinctId, uuid)

          withContext(Dispatchers.Main) {
            promise?.resolve(null) // success
          }
        } catch (e: Exception) {
          withContext(Dispatchers.Main) {
            promise?.reject("INIT_ERROR", e) // failure
          }
        }
      }
    }
  }

  private fun getDeviceUuid(): String {
    return dbHelper.getDeviceUuid() ?: UUID.randomUUID().toString()
  }

  override fun registerTenant(
    tenantId: String?,
    tenantLabel: String?,
    totpToken: String?,
    promise: Promise?
  ) {
    if (tenantId.isNullOrBlank() || tenantLabel.isNullOrBlank() || totpToken.isNullOrBlank()) {
      promise?.reject("INIT_ERROR", "tenantId, tenantLabel and totpToken are required")
    } else {
      CoroutineScope(Dispatchers.IO).launch {
        try {
          dbHelper.registerTenant(tenantId, tenantLabel)
          Log.d(TAG, "dbHelper.registerTenant completed for $tenantId")
          setKey(tenantId, totpToken, STATUS_ACTIVE).getOrThrow()
          Log.d(TAG, "setKey succeeded for $tenantId")
          withContext(Dispatchers.Main) {
            promise?.resolve(null) // success
          }
        } catch (e: Exception) {
          Log.e(TAG, "registerTenant failed for $tenantId", e)
          withContext(Dispatchers.Main) {
            promise?.reject("REGISTER_TENANT_ERROR", e) // failure
          }
        }
      }
    }
  }

  private suspend fun setKey(tenantId: String, totpToken: String, status: Int): Result<Unit> = withContext(Dispatchers.IO) {
    try {
      val alias = "fyno_totp_secret_$tenantId"
      Log.d(
        TAG,
        "setKey encrypting for $tenantId alias=$alias tokenPresent=${totpToken.isNotBlank()}"
      )
      val (encryptedSecret, iv) = keyStorage.encryptSecret(alias, totpToken)
      val encryptedSecretBase64 = Base64.encodeToString(encryptedSecret, Base64.NO_WRAP)
      val ivBase64 = Base64.encodeToString(iv, Base64.NO_WRAP)
      dbHelper.setKey(tenantId, encryptedSecretBase64, ivBase64, status)
      Log.d(TAG, "dbHelper.setKey saved for $tenantId")
      Result.success(Unit)
    } catch (e: Exception) {
      Log.e(TAG, "setKey failed for $tenantId", e)
      Result.failure(e)
    }
  }

  override fun setConfig(
    tenantId: String?,
    config: ReadableMap?,
    promise: Promise?
  ) {
    if (tenantId.isNullOrBlank() || config == null) {
      promise?.reject("SET_CONFIG_ERROR", "tenantId and config are required")
      return
    }

    CoroutineScope(Dispatchers.IO).launch {
      try {
        val configObj = TotpConfig(
          tenant_id = config.getString("tenant_id") ?: "",
          tenant_name = config.getString("tenant_name") ?: "",
          digits = config.getInt("digits"),
          period = config.getInt("period"),
          algorithm = config.getString("algorithm") ?: "SHA1"
        )

        val configJson = gson.toJson(configObj)

        dbHelper.setConfig(tenantId, configJson)

        withContext(Dispatchers.Main) {
          promise?.resolve(null)
        }

      } catch (e: Exception) {
        withContext(Dispatchers.Main) {
          promise?.reject("SET_CONFIG_ERROR", e)
        }
      }
    }
  }

  override fun getTotp(tenantId: String?, promise: Promise?) {
    if (tenantId.isNullOrBlank()) {
      promise?.reject("GET_TOTP_ERROR", "tenantID is required")
    } else {

      CoroutineScope(Dispatchers.IO).launch {
        try {
          val totpData = dbHelper.getTotpData(tenantId)
          if (totpData == null || totpData.status != STATUS_ACTIVE) {
            withContext(Dispatchers.Main) { promise?.resolve(null) }
            return@launch
          }

          val encryptedSecret = Base64.decode(totpData.encryptedSecret, Base64.NO_WRAP)
          val iv = Base64.decode(totpData.iv, Base64.NO_WRAP)

          val alias = "fyno_totp_secret_$tenantId"
          val secretStr = keyStorage.decryptSecret(alias, encryptedSecret, iv)

          // Treat the decrypted secret as ASCII text (raw bytes) for HMAC key
          val secretBytes = try {
            secretStr.toByteArray(Charsets.US_ASCII)
          } catch (e: Exception) {
            // fallback to platform default encoding
            secretStr.toByteArray()
          }

          val config = totpData.config

          val otp = generateTOTP(
            secret = secretBytes,
            digits = config.digits,
            algorithm = config.algorithm,
            period = config.period
          )
          withContext(Dispatchers.Main) {
            promise?.resolve(otp)
          }
        } catch (e: Exception) {
          Log.e(TAG, "getTotp failed for $tenantId", e)
          withContext(Dispatchers.Main) {
            promise?.reject("GET_TOTP_ERROR", e)
          }
        }
      }
    }
  }

  @Throws(NoSuchAlgorithmException::class, InvalidKeyException::class)
  private fun generateTOTP(
    secret: ByteArray,
    time: Long = System.currentTimeMillis() / 1000,
    digits: Int,
    algorithm: String,
    period: Int
  ): String {
    val counter = time / period
    val counterBytes = ByteBuffer.allocate(8).putLong(counter).array()
    val mac = Mac.getInstance("Hmac$algorithm")
    // Use matching Hmac key algorithm
    mac.init(SecretKeySpec(secret, "Hmac$algorithm"))
    val hash = mac.doFinal(counterBytes)
    val offset = (hash[hash.size - 1] and 0x0F).toInt()
    val truncatedHash = ByteBuffer.wrap(hash, offset, 4).int and 0x7FFFFFFF
    val otp = truncatedHash % (10.0.pow(digits.toDouble())).toInt()
    return otp.toString().padStart(digits, '0')
  }

  override fun deleteTenant(tenantId: String?, promise: Promise?) {
    if(tenantId.isNullOrBlank()){
      promise?.reject("DELETE_TENANT_ERROR","tenantId is required")
    }else {

      CoroutineScope(Dispatchers.IO).launch {
        try {
          val alias = "fyno_totp_secret_$tenantId"

          // Attempt to remove stored secret from KeyStorage (ignore failures but log)
          try {
            keyStorage.deleteKey(alias)
            Log.d(TAG, "keyStorage.deleteKey succeeded for $tenantId")
          } catch (e: Exception) {
            Log.w(TAG, "keyStorage.deleteKey failed for $tenantId", e)
          }

          // Remove tenant enrolment data from database
          dbHelper.deleteTenant(tenantId)
          Log.d(TAG, "dbHelper.deleteTenant completed for $tenantId")

          withContext(Dispatchers.Main) {
            promise?.resolve(null)
          }
        } catch (e: Exception) {
          Log.e(TAG, "revokeTenant failed for $tenantId", e)
          withContext(Dispatchers.Main) {
            promise?.reject("DELETE_TENANT_ERROR",e)
          }
        }
      }
    }
  }

  override fun fetchActiveTenants(promise: Promise?) {
    CoroutineScope(Dispatchers.IO).launch {
      try {
        val tenants = dbHelper.fetchActiveTenants()

        withContext(Dispatchers.Main) {
          promise?.resolve(tenants)
        }
      } catch (e: Exception) {
        withContext(Dispatchers.Main) {
          promise?.reject("FETCH_ACTIVE_TENANTS_ERROR", e)
        }
      }
    }
  }

  companion object {
    const val NAME = NativeReactNativeTotpSpec.NAME
  }
}
