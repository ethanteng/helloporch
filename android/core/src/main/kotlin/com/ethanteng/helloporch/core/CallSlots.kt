package com.ethanteng.helloporch.core

import java.text.Normalizer
import java.time.Instant
import java.util.Locale
import kotlinx.serialization.EncodeDefault
import kotlinx.serialization.ExperimentalSerializationApi
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.SerializationException
import kotlinx.serialization.builtins.ListSerializer

@Serializable
enum class KeypadAction(val title: String) {
    @SerialName("unassigned") UNASSIGNED("No action"),
    @SerialName("person") PERSON("Call a person"),
    @SerialName("callControl") CALL_CONTROL("Answer / decline / hang up"),
    @SerialName("toggleVideo") TOGGLE_VIDEO("Turn video off / on"),
    @SerialName("messages") MESSAGES("Play / stop messages"),
}

/**
 * Stable physical keys: the digits in telephone order, then * and #, numbered 10 and 11 as DTMF
 * events are. 9 and 0 are initially reserved for call controls, and the other keys start with no action.
 *
 * Changing a keypad changes it in place; [copy] it first to keep the original.
 */
class CallSlots private constructor(private val slots: MutableList<Slot>) {
    /** A key with no action is saved as a person key with no one on it, as the iOS app saves it. */
    private data class Slot(val action: KeypadAction, val contact: CallContact? = null)

    constructor() : this(digits.map { Slot(if (it == 0) KeypadAction.CALL_CONTROL else if (it == 9) KeypadAction.TOGGLE_VIDEO else KeypadAction.PERSON) }.toMutableList())

    fun copy() = CallSlots(slots.toMutableList())

    val contacts: List<CallContact?> get() = slots.map { if (it.action == KeypadAction.PERSON) it.contact else null }

    private fun index(digit: Int): Int? = digits.indexOf(digit).takeIf { it >= 0 }

    fun action(digit: Int): KeypadAction? = index(digit)?.let { index ->
        val slot = slots[index]
        if (slot.action == KeypadAction.PERSON && slot.contact == null) KeypadAction.UNASSIGNED else slot.action
    }

    fun contact(digit: Int): CallContact? {
        val index = index(digit) ?: return null
        return slots[index].takeIf { it.action == KeypadAction.PERSON }?.contact
    }

    fun digit(action: KeypadAction): Int? = digits.firstOrNull { this.action(it) == action }

    fun setAction(action: KeypadAction, digit: Int) {
        val index = index(digit) ?: throw ValidationException(invalidSlot)
        slots[index] = Slot(if (action == KeypadAction.UNASSIGNED) KeypadAction.PERSON else action, if (action == KeypadAction.PERSON) slots[index].contact else null)
    }

    fun setContact(contact: CallContact?, digit: Int) {
        val index = index(digit) ?: throw ValidationException(invalidSlot)
        val validated = contact?.let {
            CallContact(name = it.customName, nativeCall = it.nativeCall, phoneNumber = it.phoneNumber, otherPhoneNumbers = it.otherPhoneNumbers,
                familyMemberID = it.familyMemberID, invitationID = it.invitationID, memberName = it.memberName, buttonColorHex = it.buttonColorHex).preservingPhoto(it)
        }
        slots[index] = Slot(KeypadAction.PERSON, validated)
    }

    /** Pair by the server-issued invitation identity, never a name the person chose.
     * Removal of a member also removes their stale calling target.
     * Also keeps each contact showing its family member's current name and photo, once the
     * photo is in `memberPhotos`. A removed member's last name and photo stay until the caregiver edits the key.
     * First, a key still waiting for someone takes up the invitation sent for them (see [followInvitations]). */
    fun reconcile(state: FamilySnapshot, memberPhotos: ContactPhotoStore) {
        if (state.me.role != PorchExperience.BEDSIDE) return
        followInvitations(state)
        for (digit in digits) {
            val contact = contact(digit) ?: continue
            val member = member(contact, state)
            // Until the invitation is accepted, a contact goes by the name the caregiver gave it.
            // A blank invitation name isn't one, so the name typed for the key stands until they choose their own.
            val recorded = if (member != null) null else contact.invitationID?.let { id -> state.invitations?.firstOrNull { it.id == id }?.name }?.trim()
            val invited = recorded?.ifEmpty { null }
            val name = member?.name ?: invited ?: contact.memberName
            var photoID = contact.memberPhotoID
            if (member != null) {
                // A new photo replaces the previous one once it has downloaded. This checks for the file without reading it.
                photoID = member.photoID?.let { if (memberPhotos.contains(it)) it else contact.memberPhotoID }
            }
            if (member?.id != contact.familyMemberID || name != contact.memberName || photoID != contact.memberPhotoID) {
                setContact(CallContact(name = contact.customName, nativeCall = contact.nativeCall, phoneNumber = contact.phoneNumber,
                    otherPhoneNumbers = contact.otherPhoneNumbers, familyMemberID = member?.id, invitationID = contact.invitationID, memberName = name,
                    buttonColorHex = contact.buttonColorHex).preservingPhoto(contact).showingMember(name, photoID, memberPhotos), digit)
            }
        }
    }

    /** A key waiting for someone takes up the invitation sent for them, wherever it was sent from: People, a caregiver's
     * phone, or again after the key's own invitation ran out. Once they join, the key calls their Porch app, so no
     * caregiver has to link them by hand.
     *
     * A key is waiting when no family member on Porch is on it and its own invitation, if it has one, isn't open. It takes
     * up an invitation that's open, or was accepted in the last day by someone not on a key, when the invitation's name is
     * the key's name, ignoring case, accents and spacing. Only the name a caregiver gave the invitation counts, never one
     * the person chose, and only when that name belongs to exactly one key and one invitation. The key then goes by their
     * Porch name and photo, as one linked by hand does, and follows the invitation's identity from then on. */
    internal fun followInvitations(state: FamilySnapshot) {
        val keyed = contacts.filterNotNull()
        val open = state.invitations.orEmpty()
        fun onKey(invitation: String, member: String? = null) = keyed.any { it.invitationID == invitation || (member != null && it.familyMemberID == member) }
        val invitations = open.mapNotNull { invitation ->
            val name = invitation.name?.trim()
            if (name.isNullOrEmpty() || onKey(invitation.id)) null else invitation.id to name
        }.toMutableList()
        for (person in state.people) {
            if (person.role != PorchExperience.FAMILY) continue
            val id = person.invitationID ?: continue
            val joined = person.joinedAt ?: continue
            val name = person.invitedName?.trim()
            if (state.serverTime - joined >= joinedRecentlySeconds || name.isNullOrEmpty() || onKey(id, person.id)) continue
            invitations += id to name
        }
        if (invitations.isEmpty()) return
        // Two keys with one name, such as two Lisas, leave an invitation for "Lisa" to the caregiver, even if one is linked.
        val names = keyed.map { matchingName(it.name) }
        val waiting = digits.mapNotNull { digit ->
            val contact = contact(digit) ?: return@mapNotNull null
            if (member(contact, state) != null || open.any { it.id == contact.invitationID }) return@mapNotNull null
            matchingName(contact.name).takeIf { it.isNotEmpty() }?.let { digit to it }
        }
        for ((digit, name) in waiting) {
            if (names.count { it == name } != 1) continue
            val (id, invited) = invitations.filter { matchingName(it.second) == name }.singleOrNull() ?: continue
            val contact = contact(digit) ?: continue
            setContact(CallContact(name = "", nativeCall = contact.nativeCall, phoneNumber = contact.phoneNumber, otherPhoneNumbers = contact.otherPhoneNumbers,
                invitationID = id, memberName = invited, buttonColorHex = contact.buttonColorHex).preservingCaregiverPhoto(contact), digit)
        }
    }

    /** The caregiver's saved name also labels incoming calls and announcements.
     * Resolve through the same identities as pairing, including newly accepted invites. */
    fun incomingCallerName(call: FamilyCallRecord, state: FamilySnapshot): String = incomingContact(call, state)?.name ?: call.callerName

    /** Every keypad contact's phone numbers, sorted and without repeats. These can ring while unknown callers are blocked. */
    val phoneNumbers: List<String> get() = contacts.flatMap { it?.phoneNumbers ?: emptyList() }.distinct().sorted()

    /** The keypad contact saved with this phone number, primary or not, which names (and releases) a phone voicemail. */
    fun contact(phoneNumber: String?): CallContact? {
        if (phoneNumber.isNullOrEmpty()) return null
        return contacts.firstOrNull { it != null && phoneNumber in it.phoneNumbers }
    }

    fun incomingContact(call: FamilyCallRecord, state: FamilySnapshot): CallContact? {
        if (state.me.role != PorchExperience.BEDSIDE || call.to != state.me.id) return null
        if (call.source == "phone") {
            // Only a server-verified telephone drop-in borrows a saved person's name and photo;
            // an ordinary phone call keeps showing its number, which anyone can fake.
            val number = call.callerNumber
            if (call.kind != "dropIn" || number == null) return null
            return contacts.firstOrNull { it != null && number in it.phoneNumbers }
        }
        return contacts.firstOrNull { it != null && member(it, state)?.id == call.from }
    }

    fun save(settings: PorchSettings, photoStore: ContactPhotoStore) {
        // Saving stores new photos. Finish both halves before either write, so a photo on * or #
        // that cannot be stored does not leave the ten digits already replaced.
        val saved = slots.map { SavedSlot(it.action, it.contact?.saving(photoStore)) }
        val serializer = ListSerializer(SavedSlot.serializer())
        val digits = PorchJson.encodeToString(serializer, saved.take(digitSlots))
        val symbols = PorchJson.encodeToString(serializer, saved.drop(digitSlots))
        settings.putString(storageKey, digits)
        settings.putString(symbolsStorageKey, symbols)
        photoStore.prune(keeping = contacts.mapNotNull { it?.photoID }.toSet())
    }

    override fun equals(other: Any?) = other is CallSlots && other.slots == slots
    override fun hashCode() = slots.hashCode()
    override fun toString() = "CallSlots(${digits.zip(slots).joinToString { (digit, slot) -> "${symbol(digit)}: ${slot.action} ${slot.contact ?: ""}".trim() }})"

    companion object {
        const val star = 10
        const val pound = 11
        val digits = listOf(1, 2, 3, 4, 5, 6, 7, 8, 9, 0, star, pound)
        val count = digits.size

        /** How long after someone accepts an invitation a key can still take it up: a day, as long as an invitation lasts.
         * It covers a bedside that was offline the whole time the invitation was open. */
        const val joinedRecentlySeconds = 86_400L

        /** A name as keys and invitations are matched: "lisa  ", "Lisa" and "Lísa" are the same. */
        fun matchingName(name: String): String =
            Normalizer.normalize(name, Normalizer.Form.NFD).replace(Regex("\\p{Mn}+"), "").lowercase(Locale.ROOT)
                .split(Regex("\\s+")).filter { it.isNotEmpty() }.joinToString(" ")

        /** The key as the keypad labels it. */
        fun symbol(digit: Int): String = when (digit) {
            star -> "*"
            pound -> "#"
            else -> digit.toString()
        }

        /** The key a keypad or phone symbol names: "0" to "9", "*" or "#". */
        fun digit(symbol: String): Int? = digits.firstOrNull { this.symbol(it) == symbol }

        private const val storageKey = "porch.slots.v2"
        /** 0–9 stay under `storageKey` as ten slots, and * and # go beside them, as the iOS app saves them, where a build
         * from before those two keys can still read the keypad. */
        private const val digitSlots = 10
        private const val symbolsStorageKey = "porch.slots.v2.symbols"

        /** Whether this device has kept a keypad: a sign it has been a bedside. */
        fun isSaved(settings: PorchSettings): Boolean = settings.contains(storageKey)

        /** Removes the saved keypad and every keypad photo, such as when this device becomes someone else's
         * bedside. Loading it again gives a new keypad. */
        fun forget(settings: PorchSettings, photoStore: ContactPhotoStore) {
            settings.remove(storageKey)
            settings.remove(symbolsStorageKey)
            photoStore.prune(keeping = emptySet(), olderThan = Instant.MAX)
        }

        fun load(settings: PorchSettings, photoStore: ContactPhotoStore): CallSlots {
            val data = settings.getString(storageKey) ?: return CallSlots()
            return restoring(decoded(data) + (settings.getString(symbolsStorageKey)?.let(::decoded) ?: emptyList()), photoStore)
        }

        /** Read a saved setup for a preview without settings writes, photo persistence, or pruning the app's photo store.
         * `symbols` is the * and # data saved beside it, which a setup from before those keys doesn't have. */
        fun snapshot(data: String, symbols: String?, photoStore: ContactPhotoStore): CallSlots =
            restoring(decoded(data) + (symbols?.let(::decoded) ?: emptyList()), photoStore)

        /** Saved slots in `digits` order. Setups from before * and # have only the ten digits,
         * and those two keys keep their defaults. */
        private fun restoring(saved: List<SavedSlot>, photoStore: ContactPhotoStore): CallSlots {
            if (saved.size != count && saved.size != digitSlots) throw ValidationException(invalidSavedSlots)
            val result = CallSlots()
            for ((digit, slot) in digits.zip(saved)) {
                if (slot.action != KeypadAction.PERSON && slot.contact != null) throw ValidationException(invalidSavedSlots)
                result.setContact(slot.contact?.let { CallContact.restored(it, photoStore) }, digit)
                result.setAction(slot.action, digit)
            }
            return result
        }

        private fun decoded(json: String): List<SavedSlot> =
            try { PorchJson.decodeFromString(ListSerializer(SavedSlot.serializer()), json) } catch (_: SerializationException) { throw ValidationException(invalidSavedSlots) }

        private fun member(contact: CallContact, state: FamilySnapshot): FamilyPerson? =
            contact.invitationID?.let { id -> state.people.firstOrNull { it.invitationID == id } }
                ?: contact.familyMemberID?.let { id -> state.people.firstOrNull { it.id == id } }

        private const val invalidSlot = "Choose a keypad key: 0 to 9, * or #."
        private const val invalidSavedSlots = "The saved keypad settings could not be read. Please check them in caregiver mode."
    }
}

@OptIn(ExperimentalSerializationApi::class)
@Serializable
private class SavedSlot(val action: KeypadAction, @EncodeDefault(EncodeDefault.Mode.NEVER) val contact: SavedContact? = null)
