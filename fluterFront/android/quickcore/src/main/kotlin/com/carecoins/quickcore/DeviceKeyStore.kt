package com.carecoins.quickcore

import android.content.Context
import android.content.SharedPreferences
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

object DeviceKeyStore {
    const val KEY_ALIAS = QuickCore.KEY_ALIAS
    const val PREFS_NAME = QuickCore.PREFS_NAME
    const val PREF_DEVICE_KEY_ID = QuickCore.PREF_DEVICE_KEY_ID
    const val PREF_API_BASE = QuickCore.PREF_API_BASE

    private const val PREF_CIPHERTEXT = "deviceKeyCiphertext"
    private const val PREF_IV = "deviceKeyIv"
    private const val KEYSTORE_PROVIDER = "AndroidKeyStore"
    private const val TRANSFORMATION = "AES/GCM/NoPadding"
    private const val GCM_TAG_BITS = 128

    internal fun prefs(context: Context): SharedPreferences =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    private fun getOrCreateSecretKey(): SecretKey {
        val keyStore = KeyStore.getInstance(KEYSTORE_PROVIDER).apply { load(null) }
        val existing = keyStore.getEntry(KEY_ALIAS, null) as? KeyStore.SecretKeyEntry
        if (existing != null) {
            return existing.secretKey
        }
        val keyGenerator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, KEYSTORE_PROVIDER)
        val spec = KeyGenParameterSpec.Builder(
            KEY_ALIAS,
            KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
        )
            .setKeySize(256)
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .build()
        keyGenerator.init(spec)
        return keyGenerator.generateKey()
    }

    fun store(
        context: Context,
        key: String,
        deviceKeyId: String? = null,
        apiBase: String? = null,
    ): Boolean {
        return try {
            val secretKey = getOrCreateSecretKey()
            val cipher = Cipher.getInstance(TRANSFORMATION)
            cipher.init(Cipher.ENCRYPT_MODE, secretKey)
            val cipherBytes = cipher.doFinal(key.toByteArray(Charsets.UTF_8))
            val ivBytes = cipher.iv

            val cipherB64 = Base64.encodeToString(cipherBytes, Base64.NO_WRAP)
            val ivB64 = Base64.encodeToString(ivBytes, Base64.NO_WRAP)

            prefs(context).edit().apply {
                putString(PREF_CIPHERTEXT, cipherB64)
                putString(PREF_IV, ivB64)
                if (deviceKeyId != null) {
                    putString(PREF_DEVICE_KEY_ID, deviceKeyId)
                }
                if (apiBase != null) {
                    putString(PREF_API_BASE, apiBase)
                }
            }.apply()
            true
        } catch (_: Exception) {
            false
        }
    }

    fun read(context: Context): String? {
        val sp = prefs(context)
        val cipherB64 = sp.getString(PREF_CIPHERTEXT, null)
        val ivB64 = sp.getString(PREF_IV, null)
        if (cipherB64.isNullOrEmpty() || ivB64.isNullOrEmpty()) {
            return null
        }
        return try {
            val keyStore = KeyStore.getInstance(KEYSTORE_PROVIDER).apply { load(null) }
            val entry = keyStore.getEntry(KEY_ALIAS, null) as? KeyStore.SecretKeyEntry
            if (entry == null) {
                delete(context)
                return null
            }
            val cipherBytes = Base64.decode(cipherB64, Base64.NO_WRAP)
            val ivBytes = Base64.decode(ivB64, Base64.NO_WRAP)
            val cipher = Cipher.getInstance(TRANSFORMATION)
            cipher.init(Cipher.DECRYPT_MODE, entry.secretKey, GCMParameterSpec(GCM_TAG_BITS, ivBytes))
            val plainBytes = cipher.doFinal(cipherBytes)
            String(plainBytes, Charsets.UTF_8)
        } catch (_: Exception) {
            delete(context)
            null
        }
    }

    fun readDeviceKeyId(context: Context): String? =
        prefs(context).getString(PREF_DEVICE_KEY_ID, null)?.takeIf { it.isNotEmpty() }

    fun readApiBase(context: Context): String? =
        prefs(context).getString(PREF_API_BASE, null)?.takeIf { it.isNotEmpty() }

    fun delete(context: Context) {
        runCatching {
            prefs(context).edit()
                .remove(PREF_CIPHERTEXT)
                .remove(PREF_IV)
                .remove(PREF_DEVICE_KEY_ID)
                .remove(PREF_API_BASE)
                .apply()
        }
        runCatching {
            val keyStore = KeyStore.getInstance(KEYSTORE_PROVIDER).apply { load(null) }
            if (keyStore.containsAlias(KEY_ALIAS)) {
                keyStore.deleteEntry(KEY_ALIAS)
            }
        }
    }

    fun isConnected(context: Context): Boolean {
        val key = read(context)
        return !key.isNullOrEmpty()
    }
}
