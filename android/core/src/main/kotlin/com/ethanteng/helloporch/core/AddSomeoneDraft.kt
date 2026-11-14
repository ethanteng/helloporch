package com.ethanteng.helloporch.core

/**
 * Someone a caregiver is adding on the bedside, a step at a time: who they are, how Porch reaches them, and their key.
 * Each screen of Add someone changes it, and its Step 3 saves it. Kept across a rotation. Their photo isn't kept here: a
 * photo can be close to 1 MB, more than a screen may keep when it turns.
 */
data class AddSomeoneDraft(
    /** The key they go on, or null for not on the keypad. */
    val key: Int?,
    /** The key tile Add someone was opened from. That key may be taken over even when it does something else. */
    val tile: Int? = null,
    /** A family member already on Porch, chosen in Step 1, and the invitation that brought them. */
    val memberID: String? = null,
    val memberInvitationID: String? = null,
    val name: String = "",
    /** Their phone numbers, the one Porch calls first. */
    val numbers: List<String> = emptyList(),
    val viaPhone: Boolean = false,
    val viaApp: Boolean = false,
    /** Calls start with video unless the caregiver changes it. */
    val video: Boolean = true,
    /** Family can drop in unless the caregiver turns it off for them, as an invitation from People allows. */
    val dropInAudio: Boolean = true,
    val dropInVideo: Boolean = true,
    /** The key's button color, or null for the default. */
    val colorHex: String? = null,
    /** The invitation saving made, and its link, for the name and drop-in it was made with. Trying again after a
     * failure reuses it. A different name or drop-in makes another, and it isn't used when they aren't being invited. */
    val invitationID: String? = null,
    val link: String? = null,
    val invitationName: String? = null,
    val invitationAudio: Boolean? = null,
    val invitationVideo: Boolean? = null,
) : java.io.Serializable {
    val fromKeyTile: Boolean get() = tile != null
    val member: Boolean get() = memberID != null
    /** Someone new who gets an invitation to Porch. */
    val inviting: Boolean get() = viaApp && memberID == null
    val firstName: String get() = name.trim().split(" ").firstOrNull { it.isNotEmpty() } ?: name.trim()
    /** Porch can reach them: on Porch, invited to it, or by phone. */
    val reachable: Boolean get() = viaApp || member || numbers.isNotEmpty()

    /** The invitation already made for this name and drop-in, so a failed save can be tried again without making another. */
    fun reusableInvitation(): String? {
        if (!inviting || invitationName != name.trim() || invitationAudio != dropInAudio || invitationVideo != dropInVideo) return null
        return invitationID
    }

    /** A family member already on Porch. They go by their Porch name, and only Porch calls them until a number is added. */
    fun choosing(person: FamilyPerson): AddSomeoneDraft =
        copy(memberID = person.id, memberInvitationID = person.invitationID, name = person.name, viaApp = true, viaPhone = false, numbers = emptyList())

    /** Someone new, as Step 1's Next and Choose from Contacts make them. */
    fun someoneNew(name: String = this.name): AddSomeoneDraft = copy(memberID = null, memberInvitationID = null, name = name)

    /** Step 3's Porch app row: connected for a family member, otherwise the drop-in their invitation approves. */
    val porchAppValue: String get() = when {
        member -> "Connected"
        dropInAudio && dropInVideo -> "Drop-in on"
        dropInAudio -> "Audio drop-in"
        dropInVideo -> "Video drop-in"
        else -> "Drop-in off"
    }

    /** Step 3's Phone row: the number Porch calls, and how many others there are. Null when there's none. */
    fun phoneValue(region: String): String? = numbers.firstOrNull()?.let { first ->
        PhoneNumberNormalization.display(first, region) + if (numbers.size > 1) " +${numbers.size - 1}" else ""
    }

    /** Step 2's typed number becomes the one Porch calls, and the rest stay. Throws with [PhoneNumberList.badNumber]. */
    fun reaching(typed: String, region: String): AddSomeoneDraft {
        val number = PhoneNumberList.normalized(typed, region)
        return copy(numbers = listOf(number) + numbers.drop(1).filter { it != number }, viaPhone = true)
    }

    /**
     * Their key. A family member goes by their Porch name and photo, and someone invited by the name their invitation
     * was made with, until they choose their own. `invitationID` is the one saving just made, and `room` is the key's
     * own call room.
     */
    fun contact(invitationID: String?, room: String, photo: ByteArray?): CallContact {
        val invited = inviting && invitationID != null
        return CallContact(name = if (member || invited) "" else name, nativeCall = NativeCall(room, if (video) NativeCall.Mode.VIDEO else NativeCall.Mode.VOICE),
            phoneNumber = numbers.firstOrNull(), otherPhoneNumbers = numbers.drop(1), familyMemberID = memberID,
            invitationID = if (member) memberInvitationID else if (invited) invitationID else null,
            memberName = name.trim().takeIf { member || invited }, buttonColorHex = colorHex, photoData = if (member) null else photo)
    }

    companion object {
        /** The keys as the keypad lays them out: 1 2 3, 4 5 6, 7 8 9, * 0 #. */
        val keypadOrder = listOf(1, 2, 3, 4, 5, 6, 7, 8, 9, CallSlots.star, 0, CallSlots.pound)

        /** The first key with nothing on it, in keypad order. Null when the keypad is full. */
        fun firstFreeKey(slots: CallSlots): Int? = keypadOrder.firstOrNull { slots.action(it) == KeypadAction.UNASSIGNED }

        const val unreachable = "Choose Phone or Porch app."
    }
}

/**
 * Someone's phone numbers as the Phone screen changes them, the one Porch calls first. Add someone changes its draft's
 * numbers this way, and a person's page the numbers on their key. Each change that can't be made throws with why, for the
 * screen to show under its field.
 */
object PhoneNumberList {
    const val badNumber = "Check this number. For other countries, start with +."
    const val repeatedNumber = "That number is already saved for them."

    /** One more number, typed, after the others. */
    fun adding(numbers: List<String>, typed: String, region: String): List<String> {
        val number = normalized(typed, region)
        if (number in numbers) throw ValidationException(repeatedNumber)
        if (numbers.size >= CallContact.maximumPhoneNumbers) throw ValidationException(ContactError.tooManyPhoneNumbers)
        return numbers + number
    }

    /** A number picked from Contacts becomes the one Porch calls. One already saved moves there rather than repeating. */
    fun picking(numbers: List<String>, picked: String, region: String): List<String> {
        val number = normalized(picked, region)
        if (number in numbers) return makingPrimary(numbers, number)
        if (numbers.size >= CallContact.maximumPhoneNumbers) throw ValidationException(ContactError.tooManyPhoneNumbers)
        return listOf(number) + numbers
    }

    fun makingPrimary(numbers: List<String>, number: String): List<String> = if (number !in numbers) numbers else listOf(number) + (numbers - number)

    /**
     * Why `contact`'s key can't have `numbers`, or null when it can. Someone on the keypad only by phone needs a number
     * left, or Porch couldn't reach them. Someone on Porch, or invited to it, can do without.
     */
    fun missing(numbers: List<String>, contact: CallContact): String? {
        if (numbers.isNotEmpty() || contact.familyMemberID != null || contact.invitationID != null) return null
        val first = contact.name.split(" ").firstOrNull { it.isNotEmpty() } ?: contact.name
        return "Add a number so Porch can reach $first."
    }

    internal fun normalized(typed: String, region: String): String =
        try { PhoneNumberNormalization.e164(typed.trim(), region) } catch (_: ValidationException) { throw ValidationException(badNumber) }
}
