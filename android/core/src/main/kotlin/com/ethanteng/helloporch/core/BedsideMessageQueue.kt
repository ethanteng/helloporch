package com.ethanteng.helloporch.core

/** Who a message is from, as the bedside shows and says it. `name` is null for phone voicemail with no caller ID, which
 * the bedside calls "Unknown caller" in its own language. */
data class MessageSender(val name: String?, val contact: CallContact?)

/**
 * The bedside's waiting messages, as iOS's BedsideMessages decides them: which play and in what order, which phone
 * voicemails it lets through itself, and who each one is from.
 */
object BedsideMessageQueue {
    /** What plays, oldest first: not held for a caregiver, and not already played here (the server hears of it shortly). */
    fun waiting(all: List<FamilyMessage>, played: Set<String>): List<FamilyMessage> =
        all.filter { it.held != true && it.id !in played }.sortedBy { it.sentAt }

    /** Texts that show after the messages, oldest first: not held for a caregiver, and not already read here. */
    fun waitingTexts(all: List<FamilyText>, read: Set<String>): List<FamilyText> =
        all.filter { !it.held && it.id !in read }.sortedBy { it.sentAt }

    /** Whether two BCP 47 tags are one language for reading aloud: every written Chinese counts as the Chinese choices'
     * language, and Filipino (`fil`) as Tagalog. */
    fun sameLanguage(a: String, b: String): Boolean = family(a) == family(b)

    private fun family(tag: String): String = when (val base = tag.substringBefore('-').lowercase()) {
        "zh", "yue", "cmn" -> "zh"
        "fil" -> "tl"
        else -> base
    }

    /**
     * Held phone voicemail the bedside releases itself: the phone company verified the caller, and that number is saved on
     * the keypad. Other held voicemail waits for a caregiver. `releasing` are the ones already asked for.
     */
    fun releasable(all: List<FamilyMessage>, slots: CallSlots?, releasing: Set<String>): List<FamilyMessage> {
        if (slots == null) return emptyList()
        return all.filter { it.held == true && it.callerVerified == true && it.id !in releasing && slots.contact(it.callerNumber) != null }
    }

    /**
     * The keypad contact's name first, then the family member's name, or the caller's number for phone voicemail. A phone
     * caller borrows a contact's name and photo only when the caller ID was verified. `display` formats a phone number.
     */
    fun sender(message: FamilyMessage, slots: CallSlots, display: (String) -> String): MessageSender {
        val contact = if (message.fromPhone) slots.contact(message.callerNumber).takeIf { message.callerVerified == true }
            else slots.contacts.firstOrNull { it != null && it.familyMemberID == message.from }
        if (contact != null) return MessageSender(contact.name, contact)
        if (!message.fromPhone) return MessageSender(message.fromName, null)
        return MessageSender(message.callerNumber?.let(display), null)
    }
}
