package com.ethanteng.helloporch.core

import java.io.File
import java.io.IOException
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import java.security.MessageDigest
import java.time.Clock
import java.time.Duration
import java.time.Instant

/** Slot records keep only a content identifier. Image bytes are read when a
 * screen displays the person, never while polling or handling a keypad digit. */
class ContactPhotoStore(val directory: File, private val clock: Clock = Clock.systemUTC()) {
    /** Paired family members' own photos, downloaded from Porch. A separate folder, so saving the
     * keypad never prunes them. */
    val familyMembers: ContactPhotoStore get() = ContactPhotoStore(File(directory, "Family"), clock)

    private fun file(id: String) = File(directory, "$id.jpg")

    fun data(id: String): ByteArray? {
        if (!validID(id)) return null
        val file = file(id)
        if (!file.isFile || file.length() !in 1..maximumBytes) return null
        val data = try { file.readBytes() } catch (_: IOException) { return null }
        return data.takeIf { it.size <= maximumBytes }
    }

    /** Whether a photo is saved, without reading it. */
    fun contains(id: String): Boolean = validID(id) && file(id).exists()

    /** Saves a photo under its content identifier. */
    fun add(data: ByteArray) {
        if (data.isEmpty() || data.size > maximumBytes) throw ValidationException(ContactError.invalidAppearance)
        save(data, id(data))
    }

    internal fun save(data: ByteArray, id: String) {
        if (!validID(id)) throw ValidationException(ContactError.invalidAppearance)
        Files.createDirectories(directory.toPath())
        val temporary = File.createTempFile(id, ".tmp", directory)
        try {
            temporary.writeBytes(data)
            Files.move(temporary.toPath(), file(id).toPath(), StandardCopyOption.ATOMIC_MOVE, StandardCopyOption.REPLACE_EXISTING)
        } finally {
            temporary.delete()
        }
    }

    /** Keep recently written files available to in-flight edits. Prune old,
     * unreferenced files only after a successful settings save. */
    fun prune(keeping: Set<String>, olderThan: Instant = clock.instant().minus(Duration.ofDays(1))) {
        val files = directory.listFiles() ?: return
        for (file in files) {
            if (file.extension != "jpg") continue
            val id = file.nameWithoutExtension
            if (!validID(id) || id in keeping) continue
            val modified = file.lastModified().takeIf { it > 0 } ?: continue
            if (Instant.ofEpochMilli(modified) < olderThan) file.delete()
        }
    }

    override fun equals(other: Any?) = other is ContactPhotoStore && other.directory == directory
    override fun hashCode() = directory.hashCode()
    override fun toString() = "ContactPhotoStore($directory)"

    companion object {
        /** A photo's identifier: the SHA-256 of its bytes, which Porch also uses for family members' photos. */
        fun id(data: ByteArray): String = MessageDigest.getInstance("SHA-256").digest(data).joinToString("") { "%02x".format(it) }

        internal fun validID(id: String) = id.length == 64 && id.all { it in '0'..'9' || it in 'a'..'f' }

        internal const val maximumBytes = 1_000_000L
    }
}

internal class ContactPhoto private constructor(val id: String, private val inlineData: ByteArray?, private val store: ContactPhotoStore?) {
    /** A photo saved in `store`. */
    constructor(id: String, store: ContactPhotoStore) : this(checkedID(id), null, store)

    /** A photo just chosen, which saving the keypad stores. */
    constructor(data: ByteArray) : this(ContactPhotoStore.id(checkedData(data)), data, null)

    val data: ByteArray? get() = inlineData ?: store?.data(id)

    fun persist(destination: ContactPhotoStore) {
        if (inlineData != null) destination.save(inlineData, id)
        else if (store != null && destination != store) store.data(id)?.let { destination.save(it, id) }
    }

    override fun equals(other: Any?) = other is ContactPhoto && other.id == id
    override fun hashCode() = id.hashCode()
    override fun toString() = "ContactPhoto($id)"
}

private fun checkedID(id: String): String {
    if (!ContactPhotoStore.validID(id)) throw ValidationException(ContactError.invalidAppearance)
    return id
}

private fun checkedData(data: ByteArray): ByteArray {
    if (data.isEmpty() || data.size > ContactPhotoStore.maximumBytes) throw ValidationException(ContactError.invalidAppearance)
    return data
}
