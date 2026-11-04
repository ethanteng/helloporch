package com.ethanteng.helloporch.core

/**
 * Small secrets kept encrypted on the device, under the same account names as the iOS Keychain items: pairings, a
 * pairing in progress, the caregiver PIN. Each is readable either from the first unlock after a restart, so a call can
 * ring on a locked phone, or only while the device is unlocked. Unlike the Keychain, none of it survives uninstalling.
 */
interface SecretStore {
    enum class Access { AFTER_FIRST_UNLOCK, WHEN_UNLOCKED }

    /** Null when there's nothing saved, or it can't be read right now (such as a [Access.WHEN_UNLOCKED] secret while
     * the device is locked). */
    fun read(account: String): ByteArray?
    /** Saves the value, or deletes it when it's null. */
    fun write(account: String, value: ByteArray?, access: Access = Access.WHEN_UNLOCKED)
}

/** Secrets kept in memory only, for tests and previews. */
class MemorySecretStore : SecretStore {
    private val values = mutableMapOf<String, ByteArray>()
    override fun read(account: String) = values[account]?.copyOf()
    override fun write(account: String, value: ByteArray?, access: SecretStore.Access) {
        if (value == null) values.remove(account) else values[account] = value.copyOf()
    }
}
