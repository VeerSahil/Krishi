package com.sahil.krishi.krishi

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

class MainActivity: FlutterActivity() {
    private fun key(): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (store.getKey("krishi-local", null) as? SecretKey)?.let { return it }
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").apply {
            init(KeyGenParameterSpec.Builder("krishi-local", KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).build())
        }.generateKey()
    }
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "krishi/private_store").setMethodCallHandler { call, result ->
            try {
                val name = call.argument<String>("key") ?: error("Missing key")
                require(name.matches(Regex("[a-zA-Z0-9_-]{1,180}")))
                val prefs = getSharedPreferences("krishi_private", MODE_PRIVATE)
                when (call.method) {
                    "read" -> {
                        val saved = prefs.getString(name, null)
                        if (saved == null) result.success(null) else {
                            val parts = saved.split(":")
                            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
                            cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, Base64.decode(parts[0], Base64.NO_WRAP)))
                            cipher.updateAAD(name.toByteArray(Charsets.UTF_8))
                            result.success(String(cipher.doFinal(Base64.decode(parts[1], Base64.NO_WRAP)), Charsets.UTF_8))
                        }
                    }
                    "write" -> {
                        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
                        cipher.init(Cipher.ENCRYPT_MODE, key())
                        cipher.updateAAD(name.toByteArray(Charsets.UTF_8))
                        val encrypted = cipher.doFinal(call.argument<String>("value")!!.toByteArray(Charsets.UTF_8))
                        val value = Base64.encodeToString(cipher.iv, Base64.NO_WRAP) + ":" + Base64.encodeToString(encrypted, Base64.NO_WRAP)
                        if (!prefs.edit().putString(name, value).commit()) error("Save failed")
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) { result.error("LOCAL_STORAGE", "Unable to access private local data", null) }
        }
    }
}
