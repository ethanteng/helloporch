package com.ethanteng.helloporch.core

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

class MessageBadgeTest {
    /** A notification said 3, counting both families. The first to check in mustn't lower it to its own 1. */
    @Test fun theBadgeWaitsForEveryFamilyToCheckIn() {
        assertNull(MessageBadge.count(listOf(1, null)))
        assertEquals(3, MessageBadge.count(listOf(1, 2)))
        assertEquals(0, MessageBadge.count(listOf(0, 0)))
        assertNull(MessageBadge.count(emptyList()), "no family, nothing to say")
    }
}
