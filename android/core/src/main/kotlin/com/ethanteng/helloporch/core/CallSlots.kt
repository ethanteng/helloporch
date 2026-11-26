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
import kotlinx.serialization.builtins.MapSerializer
import kotlinx.serialization.builtins.serializer

@Serializable
enum class KeypadAction(val title: String) {
    @SerialName("unassigned") UNASSIGNED("No action"),
    @SerialName("person") PERSON("Call a person"),
    @SerialName("callControl") CALL_CONTROL("Answer / decline / hang up"),
    @SerialName("toggleVideo") TOGGLE_VIDEO("Turn video off / on"),
    @SerialName("messages") MESSAGES("Play / stop messages"),
    /** Rings two family members at once ([CallGroup]). Saved beside the keypad, never in a slot, so a build from before
     * group calls reads the key as empty. */
    @SerialName("group") GROUP("Call a group"),
}

/**
 * Stable physical keys: the digits in telephone order, then * and #, numbered 10 and 11 as DTMF
 * events are. 9 and 0 are initially reserved for call controls, and the other keys start with no action.
 *
 * Changing a keypad changes it in place; [copy] it first to keep the original.
 */
class CallSlots private constructor(
    private val slots: MutableList<Slot>,
    /** Group keys by key. A group's own slot is kept empty. */
    private val groups: MutableMap<Int, CallGroup> = mutableMapOf(),
) {
    /** A key with no action is saved as a person key with no one on it, as the iOS app saves it. */
    private data class Slot(val action: KeypadAction, val contact: CallContact? = null)

    constructor() : this(digits.map { Slot(if (it == 0) KeypadAction.CALL_CONTROL else if (it == 9) KeypadAction.TOGGLE_VIDEO else KeypadAction.PERSON) }.toMutableList())

    fun copy() = CallSlots(slots.toMutableList(), groups.toMutableMap())

    val contacts: List<CallContact?> get() = slots.map { if (it.action == KeypadAction.PERSON) it.contact else null }

    /** Every group key's group, in key order. */
    val allGroups: List<Pair<Int, CallGroup>> get() = digits.mapNotNull { digit -> groups[digit]?.let { digit to it } }

    private fun index(digit: Int): Int? = digits.indexOf(digit).takeIf { it >= 0 }

    fun action(digit: Int): KeypadAction? = index(digit)?.let { index ->
        val slot = slots[index]
        if (digit in groups) KeypadAction.GROUP
        else if (slot.action == KeypadAction.PERSON && slot.contact == null) KeypadAction.UNASSIGNED else slot.action
    }

    fun group(digit: Int): CallGroup? = groups[digit]

    /** Puts a group on a key, in place of whatever was there, or takes it off (null), leaving the key empty. */
    fun setGroup(group: CallGroup?, digit: Int) {
        val index = index(digit) ?: throw ValidationException(invalidSlot)
        slots[index] = Slot(KeypadAction.PERSON)
        if (group == null) groups.remove(digit) else groups[digit] = group
    }

    fun contact(digit: Int): CallContact? {
        val index = index(digit) ?: return null
        return slots[index].takeIf { it.action == KeypadAction.PERSON }?.contact
    }

    fun digit(action: KeypadAction): Int? = digits.firstOrNull { this.action(it) == action }

    fun setAction(action: KeypadAction, digit: Int) {
        val index = index(digit) ?: throw ValidationException(invalidSlot)
        // A group goes on a key with [setGroup]. Choosing it here keeps the group there is.
        if (action == KeypadAction.GROUP) { if (digit !in groups) throw ValidationException(invalidSlot); return }
        groups.remove(digit)
        slots[index] = Slot(if (action == KeypadAction.UNASSIGNED) KeypadAction.PERSON else action, if (action == KeypadAction.PERSON) slots[index].contact else null)
    }

    fun setContact(contact: CallContact?, digit: Int) {
        val index = index(digit) ?: throw ValidationException(invalidSlot)
        val validated = contact?.let {
            CallContact(name = it.customName, nativeCall = it.nativeCall, phoneNumber = it.phoneNumber, otherPhoneNumbers = it.otherPhoneNumbers,
                familyMemberID = it.familyMemberID, invitationID = it.invitationID, memberName = it.memberName, buttonColorHex = it.buttonColorHex).preservingPhoto(it)
        }
        slots[index] = Slot(KeypadAction.PERSON, validated)
        groups.remove(digit)
    }

    /** Pair by the server-issued invitation identity, never a name the person chose.
     * Removal of a member also removes their stale calling target.
     * Also keeps each contact showing its family member's current name and photo, once the
     * photo is in `memberPhotos`. A removed member's last name and photo stay until the caregiver edits the key.
     * First, a key still waiting for someone takes up the invitation sent for them (see [followInvitations]). */
    fun reconcile(state: FamilySnapshot, memberPhotos: ContactPhotoStore) {
        if (state.me.role != PorchExperience.BEDSIDE) return
        followInvitations(state)
        // A group shows its people's current names.
        val names = state.people.distinctBy { it.id }.associate { it.id to it.name }
        for (entry in groups) entry.setValue(entry.value.showing(names))
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
     * phone, or again after the key's own invitation ran out or went astray. Once they join, the key calls their Porch app,
     * so no caregiver has to link them by hand.
     *
     * A key is waiting when no family member on Porch is on it. It goes by the name a caregiver gave an invitation,
     * ignoring case, accents and spacing, never by one the person chose, and only when no other key has that name.
     * Someone who accepted an invitation with the key's name in the last day takes the key, even over an invitation still
     * open for it: an invitation sent again is most often for the same person. Otherwise a key with no open invitation of
     * its own takes up an open one with its name. Either way exactly one person, or one invitation, must have the name.
     * The key then goes by their Porch name, as one linked by hand does, and follows the invitation's identity from then on. */
    internal fun followInvitations(state: FamilySnapshot) {
        val keyed = contacts.filterNotNull()
        val open = state.invitations.orEmpty()
        fun onKey(invitation: String, member: String? = null) = keyed.any { it.invitationID == invitation || (member != null && it.familyMemberID == member) }
        val pending = open.mapNotNull { invitation ->
            val name = invitation.name?.trim()
            if (name.isNullOrEmpty() || onKey(invitation.id)) null else invitation.id to name
        }
        val joined = state.people.mapNotNull { person ->
            val id = person.invitationID
            val at = person.joinedAt
            val name = person.invitedName?.trim()
            if (person.role != PorchExperience.FAMILY || id == null || at == null || state.serverTime - at >= joinedRecentlySeconds ||
                name.isNullOrEmpty() || onKey(id, person.id)) null else id to name
        }
        if (pending.isEmpty() && joined.isEmpty()) return
        // Two keys with one name, such as two Lisas, leave an invitation for "Lisa" to the caregiver, even if one is linked.
        val names = keyed.map { matchingName(it.name) }
        for (digit in digits) {
            val contact = contact(digit) ?: continue
            if (member(contact, state) != null) continue
            val name = matchingName(contact.name)
            if (name.isEmpty() || names.count { it == name } != 1) continue
            fun named(invitations: List<Pair<String, String>>) = invitations.filter { matchingName(it.second) == name }
            val ownOpen = open.any { it.id == contact.invitationID }
            val people = named(joined)
            val (id, invited) = (if (people.isNotEmpty()) people else if (ownOpen) emptyList() else named(pending)).singleOrNull() ?: continue
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
        val groups = allGroups.associate { (digit, group) -> symbol(digit) to group.saving(photoStore) }
            .takeIf { it.isNotEmpty() }?.let { PorchJson.encodeToString(groupsSerializer, it) }
        settings.putString(storageKey, digits)
        settings.putString(symbolsStorageKey, symbols)
        if (groups == null) settings.remove(groupsStorageKey) else settings.putString(groupsStorageKey, groups)
        photoStore.prune(keeping = contacts.mapNotNull { it?.photoID }.toSet() + this.groups.values.mapNotNull { it.photoID })
    }

    /** Saved group keys, by key symbol, on keys that are otherwise empty. */
    private fun restoreGroups(saved: Map<String, SavedGroup>, photoStore: ContactPhotoStore) {
        for ((symbol, group) in saved) {
            val digit = digit(symbol)
            if (digit == null || action(digit) != KeypadAction.UNASSIGNED) throw ValidationException(invalidSavedSlots)
            setGroup(CallGroup.restored(group, photoStore), digit)
        }
    }

    override fun equals(other: Any?) = other is CallSlots && other.slots == slots && other.groups == groups
    override fun hashCode() = 31 * slots.hashCode() + groups.hashCode()
    override fun toString() = "CallSlots(${digits.zip(slots).joinToString { (digit, slot) ->
        groups[digit]?.let { "${symbol(digit)}: $it" } ?: "${symbol(digit)}: ${slot.action} ${slot.contact ?: ""}".trim() }})"

    companion object {
        const val star = 10
        const val pound = 11
        val digits = listOf(1, 2, 3, 4, 5, 6, 7, 8, 9, 0, star, pound)
        val count = digits.size

        /** How long after someone accepts an invitation a key can still take it up: a day, as long as an invitation lasts.
         * It covers a bedside that was offline the whole time the invitation was open. */
        const val joinedRecentlySeconds = 86_400L

        /** A name as keys and invitations are matched: "lisa  ", "Lisa" and "Lísa" are the same. It folds names as iOS's
         * `CallSlots.matchingName` does, so a name matches on both bedsides: case folded fully ("Straße" and "GROẞ" are
         * "strasse" and "gross", while a dotless "ı" stays), no accents, and any space between words, a non-breaking one
         * included. Letters such as "ø" and "ł" aren't accented letters, and stay on both. */
        fun matchingName(name: String): String {
            val folded = name.split('ı').joinToString("ı") { it.uppercase(Locale.ROOT).lowercase(Locale.ROOT) }.replace("ß", "ss")
            return Normalizer.normalize(folded, Normalizer.Form.NFD).replace(Regex("\\p{Mn}+"), "")
                .split(Regex("[\\s\\p{Z}]+")).filter { it.isNotEmpty() }.joinToString(" ")
        }

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
        /** Group keys, by key symbol, beside the slots, as the iOS app saves them: a build from before group calls sees
         * those keys as empty. */
        private const val groupsStorageKey = "porch.slots.v2.groups"
        private val groupsSerializer = MapSerializer(String.serializer(), SavedGroup.serializer())

        /** Whether this device has kept a keypad: a sign it has been a bedside. */
        fun isSaved(settings: PorchSettings): Boolean = settings.contains(storageKey)

        /** Removes the saved keypad and every keypad photo, such as when this device becomes someone else's
         * bedside. Loading it again gives a new keypad. */
        fun forget(settings: PorchSettings, photoStore: ContactPhotoStore) {
            settings.remove(storageKey)
            settings.remove(symbolsStorageKey)
            settings.remove(groupsStorageKey)
            photoStore.prune(keeping = emptySet(), olderThan = Instant.MAX)
        }

        fun load(settings: PorchSettings, photoStore: ContactPhotoStore): CallSlots {
            val data = settings.getString(storageKey) ?: return CallSlots()
            val result = restoring(decoded(data) + (settings.getString(symbolsStorageKey)?.let(::decoded) ?: emptyList()), photoStore)
            settings.getString(groupsStorageKey)?.let { groups ->
                val saved = try { PorchJson.decodeFromString(groupsSerializer, groups) } catch (_: SerializationException) { throw ValidationException(invalidSavedSlots) }
                // A group Porch won't take, such as one with three people, is a keypad that can't be read.
                try { result.restoreGroups(saved, photoStore) } catch (_: ValidationException) { throw ValidationException(invalidSavedSlots) }
            }
            return result
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
                // A group is saved beside the slots, never in one.
                if (slot.action == KeypadAction.GROUP || (slot.action != KeypadAction.PERSON && slot.contact != null)) throw ValidationException(invalidSavedSlots)
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
