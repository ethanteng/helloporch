package com.ethanteng.helloporch

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import androidx.core.content.edit
import com.ethanteng.helloporch.core.SecretStore
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * Secrets encrypted with AES-GCM under keys that never leave the Android Keystore, saved in the app's own storage.
 * That storage opens at the first unlock after a restart, like the iOS Keychain's AfterFirstUnlock. A WHEN_UNLOCKED
 * secret's key also requires the device to be unlocked, so it can't be read while it's locked. Auto Backup is off,
 * and Keystore keys don't move to a new phone, so a device's identity stays on this device.
 */
class KeystoreSecretStore(context: Context) : SecretStore {
    private val preferences = context.getSharedPreferences("porch.secrets", Context.MODE_PRIVATE)
    private val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }

    @Synchronized override fun read(account: String): ByteArray? {
        val saved = preferences.getString(account, null) ?: return null
        val access = SecretStore.Access.entries.firstOrNull { saved.startsWith("${it.name}:") } ?: return null
        return try {
            val sealed = Base64.decode(saved.substringAfter(':'), Base64.NO_WRAP)
            val cipher = Cipher.getInstance(transformation)
            cipher.init(Cipher.DECRYPT_MODE, key(access), GCMParameterSpec(128, sealed, 0, ivLength))
            cipher.doFinal(sealed, ivLength, sealed.size - ivLength)
        } catch (_: Exception) { null } // Locked, or the key is gone: nothing readable right now.
    }

    @Synchronized override fun write(account: String, value: ByteArray?, access: SecretStore.Access) {
        if (value == null) { preferences.edit(commit = true) { remove(account) }; return }
        val cipher = Cipher.getInstance(transformation)
        cipher.init(Cipher.ENCRYPT_MODE, key(access))
        val sealed = cipher.iv + cipher.doFinal(value)
        // Committed before returning, as a Keychain write is: a pairing must not be lost if Porch is closed right after.
        preferences.edit(commit = true) { putString(account, "${access.name}:" + Base64.encodeToString(sealed, Base64.NO_WRAP)) }
    }

    private fun key(access: SecretStore.Access): SecretKey {
        val alias = "porch.secrets.${access.name.lowercase()}"
        (keyStore.getKey(alias, null) as? SecretKey)?.let { return it }
        val spec = KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setKeySize(256)
            .setUnlockedDeviceRequired(access == SecretStore.Access.WHEN_UNLOCKED)
            .build()
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").apply { init(spec) }.generateKey()
    }

    private companion object {
        const val transformation = "AES/GCM/NoPadding"
        const val ivLength = 12
    }
}
