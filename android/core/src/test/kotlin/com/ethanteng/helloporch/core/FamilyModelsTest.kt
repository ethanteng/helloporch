package com.ethanteng.helloporch.core

import com.ethanteng.helloporch.core.ModelFixtures.decoded
import com.ethanteng.helloporch.core.ModelFixtures.parsed
import com.ethanteng.helloporch.core.ModelFixtures.person
import com.ethanteng.helloporch.core.ModelFixtures.snapshot
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class FamilyModelsTest {
    @Test fun receivedMessagesDecodeWithAndWithoutPlayback() {
        val unplayed = parsed<ReceivedMessage>("""{"id":"a","fromName":"Mom","kind":"voicemail","mode":"video","durationSeconds":42,"sentAt":1800000000,"state":"queued","available":true}""")
        assertNull(unplayed.playedAt); assertTrue(unplayed.available); assertEquals("video", unplayed.mode)
        val played = parsed<ReceivedMessage>("""{"id":"b","fromName":"Mom","kind":"voicemail","mode":"audio","durationSeconds":5,"sentAt":1800000000,"state":"played","playedAt":1800000100,"available":false}""")
        assertEquals(1800000100L, played.playedAt); assertFalse(played.available)
    }

    @Test fun theSnapshotCarriesTheNumberOrHowItsSetupIsGoing() {
        fun snapshot(extra: Map<String, Any?>) = snapshot(me = "bedside", householdName = "Mom", extra = extra)
        val ready = snapshot(mapOf("porchNumber" to "+15105677039"))
        assertEquals("+15105677039", ready.porchNumber); assertNull(ready.phoneSetup)
        val waiting = snapshot(mapOf("phoneSetup" to mapOf("areaCode" to "510", "error" to "Twilio request failed (500).", "needsChoice" to true)))
        assertNull(waiting.porchNumber)
        assertEquals(parsed<PorchNumberSetup>("""{"areaCode":"510","error":"Twilio request failed (500).","needsChoice":true}"""), waiting.phoneSetup)
        val older = snapshot(emptyMap())
        assertNull(older.porchNumber); assertNull(older.phoneSetup)
    }

    /** Servers since Android name each device's platform; older ones don't, and every device was an iPhone or iPad. */
    @Test fun peopleSayWhichPlatformTheyAreOnAndOlderServersMeanIOS() {
        val tablet = person("aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa", "Ethan") + ("platform" to "android")
        val state = snapshot(people = listOf(tablet, person("cccccccc-cccc-4ccc-8ccc-cccccccccccc", "May")))
        assertEquals(listOf("android", "ios"), state.people.map { it.platform })
        assertEquals("ios", state.me.platform)
    }

    /** Calls have no length limit, so an answered one expires at JavaScript's largest exact integer. */
    @Test fun anAnsweredCallDecodesWithNoLengthLimit() {
        val call = decoded<FamilyCallRecord>(mapOf("id" to "c", "from" to "a", "to" to "b", "mode" to "video", "kind" to "call", "state" to "accepted",
            "createdAt" to 1, "acceptedAt" to 2, "expiresAt" to 9_007_199_254_740_991L, "callerName" to "Ethan"))
        assertEquals(9_007_199_254_740_991L, call.expiresAt)
    }
}
