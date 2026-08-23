package com.vibekits.vibekits

import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel
import java.nio.ByteBuffer
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

class MainActivity : FlutterActivity() {
    private val channelName = "vibekits/credentials"
    private val keyAlias = "VibekitsAndroidCredentialKey"
    private val preferencesName = "vibekits_secure_credentials"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                try {
                    val key = call.argument<String>("key") ?: ""
                    require(key.matches(Regex("[A-Za-z0-9._-]{1,128}"))) {
                        "Invalid credential key"
                    }
                    when (call.method) {
                        "read" -> result.success(readCredential(key))
                        "write" -> {
                            val value = call.argument<String>("value") ?: ""
                            require(value.toByteArray(Charsets.UTF_8).size <= 8192) {
                                "Credential is too large"
                            }
                            if (value.isEmpty()) deleteCredential(key) else writeCredential(key, value)
                            result.success(null)
                        }
                        "delete" -> {
                            deleteCredential(key)
                            result.success(null)
                        }
                        else -> result.notImplemented()
                    }
                } catch (error: Exception) {
                    result.error("CREDENTIAL_ERROR", error.message, null)
                }
            }
    }

    private fun secretKey(): SecretKey {
        val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        val existing = keyStore.getKey(keyAlias, null) as? SecretKey
        if (existing != null) return existing
        val generator = KeyGenerator.getInstance(
            KeyProperties.KEY_ALGORITHM_AES,
            "AndroidKeyStore",
        )
        generator.init(
            KeyGenParameterSpec.Builder(
                keyAlias,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
            )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setRandomizedEncryptionRequired(true)
                .build(),
        )
        return generator.generateKey()
    }

    private fun writeCredential(key: String, value: String) {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, secretKey())
        val encrypted = cipher.doFinal(value.toByteArray(Charsets.UTF_8))
        val packed = ByteBuffer.allocate(4 + cipher.iv.size + encrypted.size)
            .putInt(cipher.iv.size)
            .put(cipher.iv)
            .put(encrypted)
            .array()
        getSharedPreferences(preferencesName, MODE_PRIVATE)
            .edit()
            .putString(key, Base64.encodeToString(packed, Base64.NO_WRAP))
            .apply()
    }

    private fun readCredential(key: String): String? {
        val encoded = getSharedPreferences(preferencesName, MODE_PRIVATE)
            .getString(key, null) ?: return null
        val packed = ByteBuffer.wrap(Base64.decode(encoded, Base64.NO_WRAP))
        val ivSize = packed.int
        require(ivSize in 12..32 && packed.remaining() > ivSize) { "Invalid credential data" }
        val iv = ByteArray(ivSize).also { packed.get(it) }
        val encrypted = ByteArray(packed.remaining()).also { packed.get(it) }
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, secretKey(), GCMParameterSpec(128, iv))
        return String(cipher.doFinal(encrypted), Charsets.UTF_8)
    }

    private fun deleteCredential(key: String) {
        getSharedPreferences(preferencesName, MODE_PRIVATE).edit().remove(key).apply()
    }
}
