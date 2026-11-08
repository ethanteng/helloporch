package com.ethanteng.helloporch.core

import java.util.Locale

/** One message in a family phone's thread with the bedside: one this phone sent, or one the bedside left for it. */
sealed class ThreadEntry {
    data class Sent(val message: SentMessage) : ThreadEntry()
    data class Received(val message: ReceivedMessage) : ThreadEntry()

    val id: String get() = when (this) { is Sent -> message.id; is Received -> message.id }
    /** When it was sent, in epoch seconds: a message still sending goes by when it was recorded. */
    val time: Long get() = when (this) { is Sent -> message.sentAt ?: message.createdAt; is Received -> message.sentAt }
    /** One of theirs that hasn't been played. */
    val isNew: Boolean get() = this is Received && message.state == "queued" && message.available
    /** The action that gives its recording's link. */
    val mediaAction: String get() = if (this is Received) "receivedMessageMedia" else "sentMessageMedia"
    val video: Boolean get() = when (this) { is Sent -> message.mode == "video"; is Received -> message.mode == "video" }
    val durationSeconds: Int get() = when (this) { is Sent -> message.durationSeconds; is Received -> message.durationSeconds }
    /** Whether its recording can still be played here. */
    val playable: Boolean get() = when (this) { is Sent -> message.replayable == true; is Received -> message.available }
}

/** Whether a message has been played, as iOS's MessageStatus tags it under the message. */
data class MessageStatus(val text: String, val tone: Tone, val note: String? = null) {
    /** New is filled, played is green, waiting is amber, gone is gray, and failed is red. */
    enum class Tone { NEW, PLAYED, WAITING, ENDED, FAILED }
}

/**
 * A family phone's messages with the bedside, as iOS's MessageThreadViewController shows them: both ways in one thread,
 * oldest first, each with whether it was played. `played` says when one was played, such as "today at 4:02 PM".
 */
object FamilyMessageThread {
    fun entries(sent: List<SentMessage>, received: List<ReceivedMessage>): List<ThreadEntry> =
        (sent.map { ThreadEntry.Sent(it) } + received.map { ThreadEntry.Received(it) }).sortedBy { it.time }

    /** What a message this phone sent to `name`'s Porch has come to. */
    fun status(message: SentMessage, name: String, played: (Long?) -> String): MessageStatus = when (message.state) {
        "uploading" -> MessageStatus("Still sending", MessageStatus.Tone.WAITING, "Keep Porch open until it finishes.")
        "queued" -> MessageStatus("Not played yet", MessageStatus.Tone.WAITING,
            if (message.deliveredAt != null) "Waiting on $name's Porch." else "Waiting for $name's Porch to download it.")
        "played" -> MessageStatus("Played ${played(message.playedAt)}", MessageStatus.Tone.PLAYED,
            if (message.replayable == true) null else "The recording was deleted after 90 days.")
        "expired" -> MessageStatus("Never played", MessageStatus.Tone.ENDED, "Not played within a week, so it was removed.")
        "removed" -> MessageStatus("Removed by a caregiver", MessageStatus.Tone.ENDED)
        "unsent" -> MessageStatus("You unsent it", MessageStatus.Tone.ENDED)
        else -> MessageStatus("Didn't send", MessageStatus.Tone.FAILED, "This message didn't finish sending.")
    }

    /** Whether a message the bedside left here was played. */
    fun status(message: ReceivedMessage, played: (Long?) -> String): MessageStatus = when (message.state) {
        "queued" -> if (message.available) MessageStatus("New", MessageStatus.Tone.NEW)
            else MessageStatus("Never played", MessageStatus.Tone.ENDED, "It was deleted after 90 days.")
        "played" -> MessageStatus("Played ${played(message.playedAt)}", MessageStatus.Tone.PLAYED,
            if (message.available) null else "The recording was deleted after 90 days.")
        else -> MessageStatus("Never played", MessageStatus.Tone.ENDED, "Not played within 90 days, so it was deleted.")
    }

    /** "Voicemail", "Video message" or "Audio message". */
    fun type(entry: ThreadEntry): String = when {
        entry is ThreadEntry.Sent && entry.message.kind == "voicemail" -> "Voicemail"
        entry.video -> "Video message"
        else -> "Audio message"
    }

    /** "1:05" */
    fun length(seconds: Int): String = String.format(Locale.ROOT, "%d:%02d", seconds / 60, seconds % 60)

    /** Only a message still waiting on the bedside can be unsent. */
    fun canUnsend(message: SentMessage): Boolean = message.state == "uploading" || message.state == "queued"
}
