package com.ethanteng.helloporch.core

import com.ethanteng.helloporch.core.NativeCall.Mode.VOICE
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

class BedsideMessageQueueTest {
    private fun message(id: String, sentAt: Long, from: String = "6f1c2a4e-3b5d-4e7f-9a1b-2c3d4e5f6a7b", fromName: String = "Ethan", callerNumber: String? = null,
        callerVerified: Boolean? = null, held: Boolean? = null, kind: String = "message") =
        FamilyMessage(id, from, fromName, kind, "audio", "audio/mp4", 12, sentAt, delivered = false, callerNumber = callerNumber,
            callerVerified = callerVerified, held = held)

    private fun slots() = CallSlots().apply {
        setContact(CallContact("Dad", NativeCall("ethan", VOICE), familyMemberID = "6f1c2a4e-3b5d-4e7f-9a1b-2c3d4e5f6a7b"), 1)
        setContact(CallContact("David", NativeCall("david", VOICE), phoneNumber = "+14155550200"), 2)
    }

    @Test
    fun waitingIsOldestFirstWithoutHeldOrPlayed() {
        val all = listOf(message("b", 200), message("a", 100), message("held", 50, held = true), message("played", 10))
        assertEquals(listOf("a", "b"), BedsideMessageQueue.waiting(all, played = setOf("played")).map { it.id })
    }

    @Test
    fun onlyVerifiedKnownCallersAreReleasedHere() {
        val all = listOf(
            message("known", 1, from = "phone", callerNumber = "+14155550200", callerVerified = true, held = true, kind = "voicemail"),
            message("unverified", 2, from = "phone", callerNumber = "+14155550200", callerVerified = false, held = true, kind = "voicemail"),
            message("stranger", 3, from = "phone", callerNumber = "+14155550999", callerVerified = true, held = true, kind = "voicemail"),
            message("asked", 4, from = "phone", callerNumber = "+14155550200", callerVerified = true, held = true, kind = "voicemail"),
        )
        assertEquals(listOf("known"), BedsideMessageQueue.releasable(all, slots(), releasing = setOf("asked")).map { it.id })
        assertEquals(emptyList(), BedsideMessageQueue.releasable(all, null, emptySet()))
    }

    @Test
    fun senderPrefersTheKeypadName() {
        val slots = slots()
        assertEquals("Dad", BedsideMessageQueue.sender(message("m", 1), slots) { it }.name)
        assertEquals("Ethan", BedsideMessageQueue.sender(message("m", 1, from = "0a1b2c3d-4e5f-4a6b-8c7d-9e0f1a2b3c4d", fromName = "Ethan"), slots) { it }.name)
    }

    @Test
    fun aPhoneCallerBorrowsAContactOnlyWhenVerified() {
        val slots = slots()
        val verified = BedsideMessageQueue.sender(message("v", 1, from = "phone", callerNumber = "+14155550200", callerVerified = true), slots) { "($it)" }
        assertEquals("David", verified.name)
        val unverified = BedsideMessageQueue.sender(message("u", 1, from = "phone", callerNumber = "+14155550200", callerVerified = false), slots) { "($it)" }
        assertEquals("(+14155550200)", unverified.name)
        assertNull(unverified.contact)
        assertNull(BedsideMessageQueue.sender(message("n", 1, from = "phone"), slots) { it }.name)
    }
}
