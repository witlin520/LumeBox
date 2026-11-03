package com.lumebox.app

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.io.File
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

internal object DanmakuCredentials {
    private const val alias = "com.lumebox.danmaku.credentials"
    private fun key(): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (store.getKey(alias, null) as? SecretKey)?.let { return it }
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").apply {
            init(KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).build())
        }.generateKey()
    }
    fun register(context: Context, messenger: BinaryMessenger) {
        MethodChannel(messenger, "lumebox/reference_danmaku_credentials").setMethodCallHandler { call, result ->
            val file = File(context.noBackupFilesDir, "danmaku-credentials.enc")
            try {
                when (call.method) {
                    "read" -> {
                        if (!file.exists()) { result.success(null); return@setMethodCallHandler }
                        val encoded = file.readBytes()
                        require(encoded.size >= 28)
                        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
                        cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, encoded.copyOfRange(0, 12)))
                        val json = JSONObject(String(cipher.doFinal(encoded.copyOfRange(12, encoded.size)), Charsets.UTF_8))
                        result.success(json.keys().asSequence().associateWith { json.getString(it) })
                    }
                    "write" -> {
                        val args = call.arguments as? Map<*, *> ?: error("Invalid credential map")
                        require(args.all { it.key is String && it.value is String })
                        val plain = JSONObject(args).toString().toByteArray(Charsets.UTF_8)
                        require(plain.size <= 256 * 1024)
                        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
                        cipher.init(Cipher.ENCRYPT_MODE, key())
                        val temporary = File(context.noBackupFilesDir, "danmaku-credentials.tmp")
                        temporary.writeBytes(cipher.iv + cipher.doFinal(plain))
                        require(temporary.renameTo(file)) { "Unable to save credentials" }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            } catch (_: Exception) {
                result.error("credentials", "Unable to access the device credential store", null)
            }
        }
    }
}
