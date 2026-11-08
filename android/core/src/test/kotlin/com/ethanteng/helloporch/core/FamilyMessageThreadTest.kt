package com.ethanteng.helloporch.core

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class FamilyMessageThreadTest {
    private fun sent(id: String, state: String = "queued", createdAt: Long = 100, sentAt: Long? = null, kind: String = "message", mode: String = "audio",
        deliveredAt: Long? = null, replayable: Boolean? = null) =
        SentMessage(id, kind, mode, 65, createdAt, state, sentAt = sentAt, deliveredAt = deliveredAt, playedAt = 500, replayable = replayable)
    private fun received(id: String, state: String = "queued", sentAt: Long = 100, available: Boolean = true, mode: String = "audio") =
        ReceivedMessage(id, "Mom", "voicemail", mode, 12, sentAt, state, playedAt = 600, available = available)
    private val played: (Long?) -> String = { "at $it" }

    @Test
    fun bothWaysInOneThreadOldestFirst() {
        val entries = FamilyMessageThread.entries(listOf(sent("b", createdAt = 50, sentAt = 300), sent("d", createdAt = 400)),
            listOf(received("a", sentAt = 200), received("c", sentAt = 350)))
        // A message still sending goes by when it was recorded.
        assertEquals(listOf("a", "b", "c", "d"), entries.map { it.id })
    }

    @Test
    fun onlyTheirUnplayedMessagesAreNew() {
        assertTrue(ThreadEntry.Received(received("a")).isNew)
        assertFalse(ThreadEntry.Received(received("a", state = "played")).isNew)
        assertFalse(ThreadEntry.Received(received("a", available = false)).isNew)
        assertFalse(ThreadEntry.Sent(sent("b")).isNew)
        assertEquals("receivedMessageMedia", ThreadEntry.Received(received("a")).mediaAction)
        assertEquals("sentMessageMedia", ThreadEntry.Sent(sent("b")).mediaAction)
    }

    @Test
    fun sentMessagesSayWhatBecameOfThem() {
        val waiting = FamilyMessageThread.status(sent("a"), "Mom", played)
        assertEquals("Not played yet", waiting.text)
        assertEquals("Waiting for Mom's Porch to download it.", waiting.note)
        assertEquals("Waiting on Mom's Porch.", FamilyMessageThread.status(sent("a", deliveredAt = 150), "Mom", played).note)
        val heard = FamilyMessageThread.status(sent("a", state = "played", replayable = true), "Mom", played)
        assertEquals("Played at 500", heard.text)
        assertEquals(MessageStatus.Tone.PLAYED, heard.tone)
        assertNull(heard.note)
        assertEquals("The recording was deleted after 90 days.", FamilyMessageThread.status(sent("a", state = "played"), "Mom", played).note)
        assertEquals("Removed by a caregiver", FamilyMessageThread.status(sent("a", state = "removed"), "Mom", played).text)
        assertEquals("You unsent it", FamilyMessageThread.status(sent("a", state = "unsent"), "Mom", played).text)
        assertEquals(MessageStatus.Tone.FAILED, FamilyMessageThread.status(sent("a", state = "failed"), "Mom", played).tone)
    }

    @Test
    fun receivedMessagesSayWhetherTheyWerePlayed() {
        assertEquals(MessageStatus("New", MessageStatus.Tone.NEW), FamilyMessageThread.status(received("a"), played))
        assertEquals("It was deleted after 90 days.", FamilyMessageThread.status(received("a", available = false), played).note)
        assertEquals("Played at 600", FamilyMessageThread.status(received("a", state = "played"), played).text)
        assertEquals("Not played within 90 days, so it was deleted.", FamilyMessageThread.status(received("a", state = "expired"), played).note)
    }

    @Test
    fun typesLengthsAndUnsending() {
        assertEquals("Voicemail", FamilyMessageThread.type(ThreadEntry.Sent(sent("a", kind = "voicemail", mode = "video"))))
        assertEquals("Video message", FamilyMessageThread.type(ThreadEntry.Received(received("a", mode = "video"))))
        assertEquals("Audio message", FamilyMessageThread.type(ThreadEntry.Sent(sent("a"))))
        assertEquals("1:05", FamilyMessageThread.length(65))
        assertTrue(FamilyMessageThread.canUnsend(sent("a", state = "uploading")))
        assertTrue(FamilyMessageThread.canUnsend(sent("a")))
        assertFalse(FamilyMessageThread.canUnsend(sent("a", state = "played")))
    }
}
