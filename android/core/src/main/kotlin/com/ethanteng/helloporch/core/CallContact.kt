package com.ethanteng.helloporch.core

import java.text.BreakIterator
import kotlinx.serialization.EncodeDefault
import kotlinx.serialization.ExperimentalSerializationApi
import kotlinx.serialization.KSerializer
import kotlinx.serialization.Serializable
import kotlinx.serialization.descriptors.SerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder

/** A person on the keypad. Porch calls them through `nativeCall`, and rings `phoneNumber` when that isn't answered. */
class CallContact private constructor(
    /** The name the caregiver typed. Empty for a Porch contact that goes by its family member's name. */
    val customName: String,
    /** The paired family member's name and photo as Porch shows them: their own, or what a caregiver chose
     * for them. `CallSlots.reconcile` keeps these current; the caregiver's keypad name and photo come first. */
    val memberName: String?,
    private val memberPhoto: ContactPhoto?,
    val nativeCall: NativeCall,
    /** The primary number: the only one Porch calls when it isn't answered. */
    val phoneNumber: String?,
    /** The person's other numbers, such as home and mobile. They can call in like the primary number, but Porch never dials them. */
    val otherPhoneNumbers: List<String>,
    val familyMemberID: String?,
    val invitationID: String?,
    val buttonColorHex: String?,
    internal val photo: ContactPhoto?,
) {
    /** What Porch shows and speaks: the caregiver's name, or else the paired family member's. */
    val name: String get() = customName.ifEmpty { memberName ?: "" }
    /** Every number saved for this person, primary first. */
    val phoneNumbers: List<String> get() = phoneNumber?.let { listOf(it) + otherPhoneNumbers } ?: emptyList()
    /** The keypad photo the caregiver chose. */
    val photoID: String? get() = photo?.id
    val customPhotoData: ByteArray? get() = photo?.data
    val memberPhotoID: String? get() = memberPhoto?.id
    /** What Porch shows: the caregiver's keypad photo, or else the family member's. */
    val photoData: ByteArray? get() = photo?.data ?: memberPhoto?.data

    // Metadata validation and pairing must preserve the reference without
    // reading the image file on the main thread.
    internal fun preservingPhoto(original: CallContact) = copy(photo = original.photo, memberPhoto = original.memberPhoto)

    /** The same contact showing its family member's current name and photo, which must be in `photos`. */
    internal fun showingMember(name: String?, photoID: String?, photos: ContactPhotoStore) =
        copy(memberName = name, memberPhoto = photoID?.let { storedPhoto(it, photos) })

    /** The same contact with some details changed. Its photos stay, and an empty `name` makes a Porch contact go by its
     * family member's name. */
    fun updating(name: String = customName, mode: NativeCall.Mode = nativeCall.mode, buttonColorHex: String? = this.buttonColorHex): CallContact =
        CallContact(name = name, nativeCall = NativeCall(nativeCall.room, mode), phoneNumber = phoneNumber, otherPhoneNumbers = otherPhoneNumbers,
            familyMemberID = familyMemberID, invitationID = invitationID, memberName = memberName, buttonColorHex = buttonColorHex).preservingPhoto(this)

    /** The same contact with the caregiver's photo replaced, or removed with null, which shows the family member's again. */
    fun updatingPhoto(photoData: ByteArray?): CallContact = copy(photo = photoData?.let { ContactPhoto(it) })

    /** Saves a new photo to `photoStore`, and gives what goes in settings. */
    internal fun saving(photoStore: ContactPhotoStore): SavedContact {
        photo?.persist(photoStore)
        // `name` is what Porch shows, so anything reading these settings has a name for everyone, as on iOS.
        return SavedContact(name = name, customName = customName, memberName = memberName, memberPhotoID = memberPhoto?.id, nativeCall = nativeCall,
            phoneNumber = phoneNumber, otherPhoneNumbers = otherPhoneNumbers.ifEmpty { null }, familyMemberID = familyMemberID,
            invitationID = invitationID, buttonColorHex = buttonColorHex, photoID = photo?.id)
    }

    private fun copy(memberName: String? = this.memberName, memberPhoto: ContactPhoto? = this.memberPhoto, photo: ContactPhoto? = this.photo) =
        CallContact(customName, memberName, memberPhoto, nativeCall, phoneNumber, otherPhoneNumbers, familyMemberID, invitationID, buttonColorHex, photo)

    override fun equals(other: Any?) = other is CallContact && other.customName == customName && other.memberName == memberName &&
        other.memberPhoto == memberPhoto && other.nativeCall == nativeCall && other.phoneNumber == phoneNumber &&
        other.otherPhoneNumbers == otherPhoneNumbers && other.familyMemberID == familyMemberID && other.invitationID == invitationID &&
        other.buttonColorHex == buttonColorHex && other.photo == photo

    override fun hashCode() = listOf(customName, memberName, memberPhoto, nativeCall, phoneNumber, otherPhoneNumbers, familyMemberID, invitationID,
        buttonColorHex, photo).hashCode()

    override fun toString() = "CallContact(customName=$customName, memberName=$memberName, nativeCall=$nativeCall, phoneNumbers=$phoneNumbers, " +
        "familyMemberID=$familyMemberID, invitationID=$invitationID, buttonColorHex=$buttonColorHex, photoID=$photoID, memberPhotoID=$memberPhotoID)"

    companion object {
        /** Numbers per person, the primary one included. */
        const val maximumPhoneNumbers = 5

        /** `name` may be empty for a family member invited or paired with Porch, who then goes by `memberName`. */
        operator fun invoke(name: String, nativeCall: NativeCall, phoneNumber: String? = null, otherPhoneNumbers: List<String> = emptyList(),
            familyMemberID: String? = null, invitationID: String? = null, memberName: String? = null, buttonColorHex: String? = null,
            photoData: ByteArray? = null): CallContact {
            val color = validatedColor(buttonColorHex)
            val photo = photoData?.let { ContactPhoto(it) }
            val customName = name.trim()
            val shownMemberName = memberName?.trim()?.ifEmpty { null }
            if (customName.isEmpty() && (shownMemberName == null || (familyMemberID == null && invitationID == null))) throw ValidationException(ContactError.missingName)
            if (customName.characterCount() > 80) throw ValidationException(ContactError.nameTooLong)
            if (familyMemberID != null && !uuidPattern.matches(familyMemberID)) throw ValidationException(ContactError.invalidFamilyMember)
            if (invitationID != null && !uuidPattern.matches(invitationID)) throw ValidationException(ContactError.invalidFamilyMember)
            val primary = phoneNumber?.let(::normalizedPhoneNumber)
            // Repeats, and the primary number listed again, are dropped.
            val others = otherPhoneNumbers.map(::normalizedPhoneNumber).filter { it != primary }.distinct()
            if (primary == null && others.isNotEmpty()) throw ValidationException(ContactError.missingPrimaryNumber)
            if (others.size >= maximumPhoneNumbers) throw ValidationException(ContactError.tooManyPhoneNumbers)
            return CallContact(customName, shownMemberName, null, nativeCall, primary, others, familyMemberID, invitationID, color, photo)
        }

        fun normalizedPhoneNumber(value: String): String {
            val input = value.trim()
            if (input.any { it !in "+0123456789 ()-." }) throw ValidationException(ContactError.invalidPhoneNumber)
            val number = input.filter { it == '+' || it in '0'..'9' }
            if (!e164Pattern.matches(number)) throw ValidationException(ContactError.invalidPhoneNumber)
            return number
        }

        /** A contact as settings saved it. Its photos are read from `photoStore` when a screen shows them. */
        internal fun restored(saved: SavedContact, photoStore: ContactPhotoStore) = CallContact(
            // Earlier records have only `name`, which was always the caregiver's.
            customName = saved.customName ?: saved.name,
            memberName = saved.memberName,
            memberPhoto = saved.memberPhotoID?.let { storedPhoto(it, photoStore.familyMembers) },
            nativeCall = saved.nativeCall,
            phoneNumber = saved.phoneNumber,
            otherPhoneNumbers = saved.otherPhoneNumbers ?: emptyList(),
            familyMemberID = saved.familyMemberID,
            invitationID = saved.invitationID,
            buttonColorHex = saved.buttonColorHex,
            photo = saved.photoID?.let { ContactPhoto(it, photoStore) },
        )

        private fun validatedColor(value: String?): String? {
            if (value == null) return null
            if (!colorPattern.matches(value)) throw ValidationException(ContactError.invalidAppearance)
            return value.uppercase()
        }

        private fun storedPhoto(id: String, store: ContactPhotoStore) = try { ContactPhoto(id, store) } catch (_: ValidationException) { null }

        private val colorPattern = Regex("^[0-9A-Fa-f]{6}$")
        private val e164Pattern = Regex("^\\+[1-9][0-9]{6,14}$")
        private val uuidPattern = Regex("^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$")
    }
}

/** Saves and reads contacts as the keypad does, with their photos as files in `photoStore`. Saving one stores its new photo. */
class CallContactSerializer(private val photoStore: ContactPhotoStore) : KSerializer<CallContact> {
    override val descriptor: SerialDescriptor = SavedContact.serializer().descriptor
    override fun serialize(encoder: Encoder, value: CallContact) = encoder.encodeSerializableValue(SavedContact.serializer(), value.saving(photoStore))
    override fun deserialize(decoder: Decoder) = CallContact.restored(decoder.decodeSerializableValue(SavedContact.serializer()), photoStore)
}

/** A contact as settings keep it: the iOS app's shape without its iOS-only ways to call. Photos are kept by ID.
 * `address` is always empty here, but iOS reads a contact only with it, so a keypad saved here can move to an iPad. */
@OptIn(ExperimentalSerializationApi::class)
@Serializable
internal class SavedContact(
    val name: String,
    val customName: String? = null,
    @EncodeDefault(EncodeDefault.Mode.NEVER) val memberName: String? = null,
    @EncodeDefault(EncodeDefault.Mode.NEVER) val memberPhotoID: String? = null,
    val nativeCall: NativeCall,
    val address: String = "",
    @EncodeDefault(EncodeDefault.Mode.NEVER) val phoneNumber: String? = null,
    @EncodeDefault(EncodeDefault.Mode.NEVER) val otherPhoneNumbers: List<String>? = null,
    @EncodeDefault(EncodeDefault.Mode.NEVER) val familyMemberID: String? = null,
    @EncodeDefault(EncodeDefault.Mode.NEVER) val invitationID: String? = null,
    @EncodeDefault(EncodeDefault.Mode.NEVER) val buttonColorHex: String? = null,
    @EncodeDefault(EncodeDefault.Mode.NEVER) val photoID: String? = null,
)

/** Why Porch won't take a contact, written for the caregiver. */
internal object ContactError {
    const val invalidAppearance = "Choose a button color and a photo smaller than 1 MB."
    const val invalidFamilyMember = "Choose a paired family member."
    const val missingName = "Enter the person's name."
    const val nameTooLong = "Use a name with 80 characters or fewer."
    const val invalidPhoneNumber = "That phone number doesn't look right. For an international number, start with + and the country code."
    const val missingPrimaryNumber = "Choose which of their numbers Porch calls if it isn't answered."
    val tooManyPhoneNumbers = "Save up to ${CallContact.maximumPhoneNumbers} phone numbers for one person."
}

/** Characters as a person counts them, as Swift counts a String: an emoji made of several code points is one. */
private fun String.characterCount(): Int {
    val characters = BreakIterator.getCharacterInstance()
    characters.setText(this)
    var count = 0
    while (characters.next() != BreakIterator.DONE) count++
    return count
}
