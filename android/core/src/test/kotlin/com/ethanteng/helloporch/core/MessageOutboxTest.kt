package com.ethanteng.helloporch.core

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class MessageOutboxTest {
    private fun item(id: String = "a", createdAt: Long = 1_000, retryAt: Long = 0, attempts: Int = 0) =
        OutboxItem(id, "$id.m4a", "member", "audio", "audio/mp4", 12.0, createdAt, attempts, retryAt)

    @Test
    fun retriesWaitFifteenSecondsDoublingToFifteenMinutes() {
        assertEquals(listOf(15L, 30, 60, 120, 240, 480, 900, 900), (1..8).map(MessageOutbox::retryDelaySeconds))
        assertEquals(900, MessageOutbox.retryDelaySeconds(60))
    }

    @Test
    fun aFailedTryCountsAndWaits() {
        val once = MessageOutbox.retried(item(), now = 2_000)
        assertEquals(1, once.attempts)
        assertEquals(2_015, once.retryAt)
        assertEquals(2_030, MessageOutbox.retried(once, now = 2_000).retryAt)
    }

    @Test
    fun theNextMessageIsTheFirstOneDue() {
        val items = listOf(item("waiting", retryAt = 5_000), item("due", retryAt = 900), item("later", retryAt = 0))
        assertEquals("due", MessageOutbox.next(items, now = 1_000)?.id)
        assertNull(MessageOutbox.next(listOf(item(retryAt = 5_000)), now = 1_000))
    }

    @Test
    fun sentOrRefusedMessagesLeaveTheOutbox() {
        val fresh = item()
        assertEquals(OutboxOutcome.SENT, MessageOutbox.outcome(fresh, failed = false, status = null, code = null, now = 1_100))
        for (status in listOf(400, 401, 403, 404, 413)) {
            assertEquals(OutboxOutcome.DROPPED, MessageOutbox.outcome(fresh, failed = true, status = status, code = null, now = 1_100))
        }
    }

    @Test
    fun failedUploadsAndConflictsStartOverAsANewMessage() {
        val fresh = item()
        // A storage refusal is the upload's, not the server's word on the message.
        assertEquals(OutboxOutcome.RETRY_NEW_UPLOAD, MessageOutbox.outcome(fresh, failed = true, status = 403, code = "upload", now = 1_100))
        assertEquals(OutboxOutcome.RETRY_NEW_UPLOAD, MessageOutbox.outcome(fresh, failed = true, status = 409, code = null, now = 1_100))
    }

    @Test
    fun otherFailuresRetryUntilTwoDaysHavePassed() {
        val fresh = item(createdAt = 1_000)
        assertEquals(OutboxOutcome.RETRY, MessageOutbox.outcome(fresh, failed = true, status = 0, code = null, now = 1_100))
        assertEquals(OutboxOutcome.RETRY, MessageOutbox.outcome(fresh, failed = true, status = 503, code = null, now = 1_100))
        assertEquals(OutboxOutcome.RETRY, MessageOutbox.outcome(fresh, failed = true, status = null, code = null, now = 1_000 + 2 * 86_400))
        assertEquals(OutboxOutcome.DROPPED, MessageOutbox.outcome(fresh, failed = true, status = null, code = null, now = 1_001 + 2 * 86_400))
    }

    @Test
    fun aRecordingIsKeptWhenLongEnoughAndSomethingWasHeard() {
        assertTrue(MessageRecordingCheck.keep(2.0, 2))
        assertFalse(MessageRecordingCheck.keep(1.9, 10))
        assertFalse(MessageRecordingCheck.keep(30.0, 1))
        assertTrue(MessageRecordingCheck.loud(0.02))
        assertFalse(MessageRecordingCheck.loud(0.01))
    }

    @Test
    fun aVideoMessagesSoundLinesUpWithItsPicture() {
        // The picture stopped at 15 s with 10 s recorded, so it started at 5 s. The sound stopped 1 ms later with
        // 10.081 s, so it started at 4.92 s, 80 ms before the picture: its first 80 ms are dropped and the rest moves
        // earlier.
        val shift = MessageSoundSync.shiftMicros(pictureStopNanos = 15_000_000_000, pictureMicros = 10_000_000,
            soundStopNanos = 15_001_000_000, soundMicros = 10_081_000)
        assertEquals(80_000L, shift)
        assertNull(MessageSoundSync.soundTime(79_999, shift))
        assertEquals(0L, MessageSoundSync.soundTime(80_000, shift))
        assertEquals(920_000L, MessageSoundSync.soundTime(1_000_000, shift))
        // The sound started 30 ms after the picture: it starts later in the message.
        val later = MessageSoundSync.shiftMicros(pictureStopNanos = 15_000_000_000, pictureMicros = 10_000_000,
            soundStopNanos = 15_000_000_000, soundMicros = 9_970_000)
        assertEquals(-30_000L, later)
        assertEquals(30_000L, MessageSoundSync.soundTime(0, later))
        // Without a time or length, nothing moves.
        assertEquals(0L, MessageSoundSync.shiftMicros(0, 10_000_000, 15_000_000_000, 10_000_000))
        assertEquals(0L, MessageSoundSync.shiftMicros(15_000_000_000, 0, 15_000_000_000, 10_000_000))
        assertEquals(0L, MessageSoundSync.shiftMicros(15_000_000_000, 10_000_000, 0, 10_000_000))
        assertEquals(0L, MessageSoundSync.shiftMicros(15_000_000_000, 10_000_000, 15_000_000_000, 0))
    }
}
