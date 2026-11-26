package com.ethanteng.helloporch.core

import kotlinx.serialization.EncodeDefault
import kotlinx.serialization.ExperimentalSerializationApi
import kotlinx.serialization.Serializable

/**
 * A key that rings two family members on Porch at once, such as Ethan and his brother David. Whoever answers first
 * talks with the bedside, and the other can still answer and join (the server's lib/family/group-calls.ts). As iOS's
 * `CallGroup` keeps it.
 */
class CallGroup private constructor(
    /** The name the caregiver typed. Empty goes by the people's names, "Ethan & David". */
    val customName: String,
    /** The family members it rings, by their Porch IDs, in the order chosen. The first who can ring is called first. */
    val memberIDs: List<String>,
    /** Their names as Porch last showed them, in the same order. `CallSlots.reconcile` keeps these current; someone no
     * longer on Porch keeps the last one. */
    val memberNames: List<String>,
    val mode: NativeCall.Mode,
    val buttonColorHex: String?,
    internal val photo: ContactPhoto?,
) {
    /** What Porch shows and says: the caregiver's name, or else the people's. */
    val name: String get() = customName.ifEmpty { joined(memberNames) }
    val photoID: String? get() = photo?.id
    /** The caregiver's photo for the key, if they chose one. */
    val photoData: ByteArray? get() = photo?.data

    /** The same group with some details changed. Its photo stays: [updatingPhoto] changes it. */
    fun updating(name: String = customName, memberIDs: List<String> = this.memberIDs, memberNames: List<String> = this.memberNames,
        mode: NativeCall.Mode = this.mode, buttonColorHex: String? = this.buttonColorHex): CallGroup =
        CallGroup(name, memberIDs, memberNames, mode, buttonColorHex).copy(photo = photo)

    /** The same group with the caregiver's photo replaced, or removed with null. */
    fun updatingPhoto(photoData: ByteArray?): CallGroup = copy(photo = photoData?.let { ContactPhoto(it) })

    /** The same group showing its people's current names, from Porch's IDs to names. */
    internal fun showing(names: Map<String, String>): CallGroup = copy(memberNames = memberIDs.zip(memberNames).map { (id, name) -> names[id] ?: name })

    /** The key as the call screen and its announcement show it: its name, photo and color. A group has no phone to fall
     * back to. */
    val callContact: CallContact
        // A name, a fixed room and a valid color always make a valid contact.
        get() = CallContact(name = name.ifEmpty { "Family" }, nativeCall = NativeCall("group", mode), buttonColorHex = buttonColorHex).showing(photo)

    /** Saves a new photo to `photoStore`, and gives what goes in settings. */
    internal fun saving(photoStore: ContactPhotoStore): SavedGroup {
        photo?.persist(photoStore)
        return SavedGroup(customName, memberIDs, memberNames, mode, buttonColorHex, photo?.id)
    }

    private fun copy(memberNames: List<String> = this.memberNames, photo: ContactPhoto? = this.photo) =
        CallGroup(customName, memberIDs, memberNames, mode, buttonColorHex, photo)

    override fun equals(other: Any?) = other is CallGroup && other.customName == customName && other.memberIDs == memberIDs &&
        other.memberNames == memberNames && other.mode == mode && other.buttonColorHex == buttonColorHex && other.photo == photo

    override fun hashCode() = listOf(customName, memberIDs, memberNames, mode, buttonColorHex, photo).hashCode()

    override fun toString() = "CallGroup(customName=$customName, memberIDs=$memberIDs, memberNames=$memberNames, mode=$mode, " +
        "buttonColorHex=$buttonColorHex, photoID=$photoID)"

    companion object {
        /** People in a group: with the bedside, the three-person call Porch already has. */
        const val maximumPeople = 2

        /** The people's names as one: "Ethan & David". */
        fun joined(names: List<String>): String = names.joinToString(" & ")

        operator fun invoke(name: String, memberIDs: List<String>, memberNames: List<String>, mode: NativeCall.Mode, buttonColorHex: String? = null,
            photoData: ByteArray? = null): CallGroup {
            val customName = name.trim()
            if (customName.characterCount() > 80) throw ValidationException(ContactError.nameTooLong)
            if (memberIDs.size !in 1..maximumPeople || memberIDs.toSet().size != memberIDs.size || memberIDs.any { !CallContact.uuidPattern.matches(it) } ||
                memberNames.size != memberIDs.size) throw ValidationException(invalidPeople)
            val color = CallContact.validatedColor(buttonColorHex)
            return CallGroup(customName, memberIDs.toList(), memberNames.map { it.trim() }, mode, color, photoData?.let { ContactPhoto(it) })
        }

        /** A group as settings saved it. Its photo is read from `photoStore` when a screen shows it. */
        internal fun restored(saved: SavedGroup, photoStore: ContactPhotoStore): CallGroup =
            CallGroup(saved.customName, saved.memberIDs, saved.memberNames, saved.mode, saved.buttonColorHex)
                .copy(photo = saved.photoID?.let { ContactPhoto(it, photoStore) })

        private const val invalidPeople = "Choose two people on Porch."
    }
}

/** A group as settings keep it, in the iOS app's shape, so a keypad saved here can move to an iPad. Its photo is kept by ID. */
@OptIn(ExperimentalSerializationApi::class)
@Serializable
internal class SavedGroup(
    val customName: String,
    val memberIDs: List<String>,
    val memberNames: List<String>,
    val mode: NativeCall.Mode,
    @EncodeDefault(EncodeDefault.Mode.NEVER) val buttonColorHex: String? = null,
    @EncodeDefault(EncodeDefault.Mode.NEVER) val photoID: String? = null,
)
