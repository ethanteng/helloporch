package com.ethanteng.helloporch.core

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

class MessagesWaitingTest {
    @Test fun saysWhatsWaitingAsIOSDoes() {
        assertEquals("1 new message from Rose", MessagesWaiting.new(1, "Rose"))
        assertEquals("3 new messages from Rose", MessagesWaiting.new(3, "Rose"))
        assertNull(MessagesWaiting.new(0, "Rose"))
        assertEquals("2 of yours not played yet", MessagesWaiting.waiting(2))
        assertNull(MessagesWaiting.waiting(0))
        assertNull(MessagesWaiting.played("today at 4:02 PM", waiting = 1), "only once none of yours are waiting")
        assertNull(MessagesWaiting.played(null, waiting = 0))
        assertEquals("Played your message today at 4:02 PM", MessagesWaiting.played("today at 4:02 PM", waiting = 0))
        assertEquals("1 needs your OK" to "1 voicemail", MessagesWaiting.needsOK(1, 0))
        assertEquals("2 need your OK" to "1 voicemail, 1 text", MessagesWaiting.needsOK(1, 1))
        assertEquals("2 need your OK" to "2 texts", MessagesWaiting.needsOK(0, 2))
        assertNull(MessagesWaiting.needsOK(0, 0))
    }
}
