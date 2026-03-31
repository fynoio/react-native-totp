package io.fyno.reactnativetotp

import android.os.Build
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import androidx.annotation.RequiresApi
import java.security.*
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

class KeyStorage {
    private val keyStore = KeyStore.getInstance("AndroidKeyStore").apply {
        load(null)
    }

    @RequiresApi(Build.VERSION_CODES.M)
    fun encryptSecret(alias: String, secret: String): Pair<ByteArray, ByteArray> {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        val secretKey = getOrCreateSecretKey(alias)
        cipher.init(Cipher.ENCRYPT_MODE, secretKey)

        val encrypted = cipher.doFinal(secret.toByteArray())
        return Pair(encrypted, cipher.iv)
    }

    @RequiresApi(Build.VERSION_CODES.M)
    fun decryptSecret(alias: String, encryptedSecret: ByteArray, iv: ByteArray): String {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        val secretKey = getOrCreateSecretKey(alias)
        val spec = GCMParameterSpec(128, iv)
        cipher.init(Cipher.DECRYPT_MODE, secretKey, spec)

        val decrypted = cipher.doFinal(encryptedSecret)
        return String(decrypted)
    }

    @RequiresApi(Build.VERSION_CODES.M)
    private fun getOrCreateSecretKey(alias: String): SecretKey {
        val existingKey = keyStore.getKey(alias, null) as? SecretKey
        if (existingKey != null) {
            return existingKey
        }

        val keyGenerator = KeyGenerator.getInstance("AES", "AndroidKeyStore")
        val parameterSpec = KeyGenParameterSpec.Builder(
            alias,
            KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT
        ).run {
            setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            build()
        }

        keyGenerator.init(parameterSpec)
        return keyGenerator.generateKey()
    }

    @RequiresApi(Build.VERSION_CODES.M)
    fun deleteKey(alias: String) {
        keyStore.deleteEntry(alias)
    }
}
