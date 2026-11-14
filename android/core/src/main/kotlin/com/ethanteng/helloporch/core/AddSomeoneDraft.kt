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
    /** The invitation saving made, and its link. Kept, so trying again after a failure doesn't make another. */
    val invitationID: String? = null,
    val link: String? = null,
) : java.io.Serializable {
    val fromKeyTile: Boolean get() = tile != null
    val member: Boolean get() = memberID != null
    /** Someone new who gets an invitation to Porch. */
    val inviting: Boolean get() = viaApp && memberID == null
    val firstName: String get() = name.trim().split(" ").firstOrNull { it.isNotEmpty() } ?: name.trim()
    /** Porch can reach them: on Porch, invited to it, or by phone. */
    val reachable: Boolean get() = viaApp || member || numbers.isNotEmpty()

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

    /** Step 2's typed number becomes the one Porch calls, and the rest stay. Throws with [badNumber]. */
    fun reaching(typed: String, region: String): AddSomeoneDraft {
        val number = normalized(typed, region)
        return copy(numbers = listOf(number) + numbers.drop(1).filter { it != number }, viaPhone = true)
    }

    /** One more number, from the Phone screen. Throws with why it can't be added. */
    fun adding(typed: String, region: String): AddSomeoneDraft {
        val number = normalized(typed, region)
        if (number in numbers) throw ValidationException(repeatedNumber)
        if (numbers.size >= CallContact.maximumPhoneNumbers) throw ValidationException(ContactError.tooManyPhoneNumbers)
        return copy(numbers = numbers + number)
    }

    fun makingPrimary(number: String): AddSomeoneDraft = if (number !in numbers) this else copy(numbers = listOf(number) + (numbers - number))

    fun removing(number: String): AddSomeoneDraft = copy(numbers = numbers - number)

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

        const val badNumber = "Check this number. For other countries, start with +."
        const val repeatedNumber = "That number is already saved for them."
        const val unreachable = "Choose Phone or Porch app."

        private fun normalized(typed: String, region: String): String =
            try { PhoneNumberNormalization.e164(typed.trim(), region) } catch (_: ValidationException) { throw ValidationException(badNumber) }
    }
}
