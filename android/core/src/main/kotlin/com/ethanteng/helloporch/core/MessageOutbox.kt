package com.ethanteng.helloporch.core

import kotlinx.serialization.Serializable

/** A message the bedside recorded for a family member, kept on the tablet until it's sent. */
@Serializable
data class OutboxItem(
    val id: String,
    /** The recording's name in the outbox's folder. */
    val file: String,
    /** The family member it's for. */
    val to: String,
    /** "audio" or "video". */
    val mode: String,
    val contentType: String,
    val durationSeconds: Double,
    /** Epoch seconds. */
    val createdAt: Long,
    val attempts: Int = 0,
    /** Epoch seconds. Not tried again before then. */
    val retryAt: Long = 0,
)

/** What becomes of an outbox message after a try at sending it. */
enum class OutboxOutcome {
    /** Sent: it's gone from the outbox. */
    SENT,
    /** Refused for good, or still not sent after two days: it's gone from the outbox. */
    DROPPED,
    /** Tried again later, carrying on with the same message on the server. */
    RETRY,
    /** Tried again later as a new message: its upload expired or was rejected. */
    RETRY_NEW_UPLOAD,
}

/**
 * How the bedside's outbox sends, as iOS's BedsideOutbox does: one message at a time, oldest due first, and a failed one
 * waits 15 seconds, then twice as long each time, up to 15 minutes, for two days.
 */
object MessageOutbox {
    /** A message that still can't be sent after two days is dropped. */
    const val GIVE_UP_SECONDS = 2 * 86_400L

    /** The next message due to be sent at `now`. */
    fun next(items: List<OutboxItem>, now: Long): OutboxItem? = items.firstOrNull { it.retryAt <= now }

    /** How long to wait after the `attempts`th failed try. */
    fun retryDelaySeconds(attempts: Int): Long = minOf(900L, 15L shl (attempts - 1).coerceIn(0, 16))

    /** `item` after a failed try at `now`. */
    fun retried(item: OutboxItem, now: Long): OutboxItem {
        val attempts = item.attempts + 1
        return item.copy(attempts = attempts, retryAt = now + retryDelaySeconds(attempts))
    }

    /**
     * After a try at sending `item`: `failed`, with the server's `status` and `code` when it answered. A refusal that
     * won't change (the person no longer has access, or the recording can't be accepted) drops it; a failed upload
     * doesn't count as one.
     */
    fun outcome(item: OutboxItem, failed: Boolean, status: Int?, code: String?, now: Long): OutboxOutcome {
        if (!failed) return OutboxOutcome.SENT
        val refused = code != "upload" && status in listOf(400, 401, 403, 404, 413)
        if (refused || item.createdAt + GIVE_UP_SECONDS < now) return OutboxOutcome.DROPPED
        return if (code == "upload" || status == 409) OutboxOutcome.RETRY_NEW_UPLOAD else OutboxOutcome.RETRY
    }
}

/** Whether a message the bedside recorded is worth sending, as iOS's BedsideMessageRecorder decides. */
object MessageRecordingCheck {
    /** Messages are up to two minutes long. */
    const val MAX_SECONDS = 120.0

    /** Louder than a quiet room (−40 dBFS): `amplitude` is the loudest sample since the last check, from 0 to 1. */
    fun loud(amplitude: Double): Boolean = amplitude > 0.01

    /** At least 2 seconds long, with sound heard on at least two checks, such as someone speaking. */
    fun keep(durationSeconds: Double, loudChecks: Int): Boolean = durationSeconds >= 2 && loudChecks >= 2
}
