package com.ethanteng.helloporch.core

/** The words on a person's card on the family Messages tab, as iOS's MessagesWaitingText says them. */
object MessagesWaiting {
    /** Messages the bedside left for this phone that haven't been played. */
    fun new(count: Int, from: String): String? = when {
        count <= 0 -> null
        count == 1 -> "1 new message from $from"
        else -> "$count new messages from $from"
    }

    /** This phone's own messages still waiting on the bedside. */
    fun waiting(count: Int): String? = if (count <= 0) null else "$count of yours not played yet"

    /** When none are waiting: when the bedside last played one of this phone's messages, such as "today at 4:02 PM". */
    fun played(whenPlayed: String?, waiting: Int): String? = if (waiting > 0 || whenPlayed == null) null else "Played your message $whenPlayed"

    /** Phone voicemail and texts from numbers that aren't on the keypad, waiting for a caregiver: a title and what they are. */
    fun needsOK(voicemails: Int, texts: Int): Pair<String, String>? {
        val total = voicemails + texts
        if (total <= 0) return null
        val parts = listOfNotNull(
            when { voicemails <= 0 -> null; voicemails == 1 -> "1 voicemail"; else -> "$voicemails voicemails" },
            when { texts <= 0 -> null; texts == 1 -> "1 text"; else -> "$texts texts" })
        return "$total ${if (total == 1) "needs" else "need"} your OK" to parts.joinToString(", ")
    }
}
