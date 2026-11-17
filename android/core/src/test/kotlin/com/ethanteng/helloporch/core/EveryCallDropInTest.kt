package com.ethanteng.helloporch.core

import com.ethanteng.helloporch.core.ModelFixtures.parsed
import com.ethanteng.helloporch.core.ModelFixtures.snapshot
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

class EveryCallDropInTest {
    /** Servers send it only while every call drops in; older ones never do. */
    @Test fun theSnapshotCarriesEveryCallOnlyWhileItsOn() {
        val on = snapshot(extra = mapOf("everyCall" to mapOf("by" to "Tom Reyes", "at" to 1800000000)))
        assertEquals(EveryCallDropIn("Tom Reyes", 1800000000), on.everyCall)
        assertNull(on.everyCall?.atBedside)
        assertNull(snapshot().everyCall)
    }

    @Test fun caregiverStateCarriesEveryCallTurnedOnAtTheBedside() {
        val admin = parsed<FamilyAdminState>("""{"householdName":"Rose","dropInEnabled":true,"people":[],"everyCall":{"by":"Rose","at":1800000060,"atBedside":true}}""")
        assertEquals(EveryCallDropIn("Rose", 1800000060, atBedside = true), admin.everyCall)
        assertNull(parsed<FamilyAdminState>("""{"householdName":"Rose","dropInEnabled":true,"people":[]}""").everyCall)
    }

    @Test fun saysWhoTurnedItOnShortly() {
        assertEquals("Tom", EveryCallDropIn("Tom Reyes", 0).turnedOnBy("iPad"))
        assertEquals("Linda", EveryCallDropIn(" Linda ", 0).turnedOnBy("tablet"))
        assertEquals("Rose’s tablet", EveryCallDropIn("Rose", 0, atBedside = true).turnedOnBy("tablet"))
        assertEquals("Rose’s iPad", EveryCallDropIn("Rose", 0, atBedside = true).turnedOnBy("iPad"))
    }

    @Test fun personRowSaysEveryCallUnlessPaused() {
        assertEquals("Every call", PersonRows.dropIn(paused = false, app = null, phone = false, everyCall = true))
        assertEquals("Every call", PersonRows.dropIn(paused = false, app = DropInPermissions(audio = true, video = false), phone = true, everyCall = true))
        assertEquals("Paused", PersonRows.dropIn(paused = true, app = null, phone = false, everyCall = true))
    }
}

class BedsideCallTest {
    /** Caregivers' snapshots carry the bedside's phone call while it rings or is connected; older servers never do. */
    @Test fun theSnapshotCarriesTheBedsideCallOnlyWhileThereIsOne() {
        val ringing = snapshot(extra = mapOf("bedsideCall" to mapOf("id" to "c1", "title" to "(510) 555-0162", "kind" to "dropIn", "state" to "pending")))
        assertEquals(BedsideCall("c1", "(510) 555-0162", "dropIn", "pending"), ringing.bedsideCall)
        val answered = snapshot(extra = mapOf("bedsideCall" to mapOf("id" to "c2", "title" to "Carmen", "kind" to "call", "state" to "accepted", "acceptedAt" to 1800000123)))
        assertEquals(1800000123L, answered.bedsideCall?.acceptedAt)
        assertNull(snapshot().bedsideCall)
    }

    @Test fun saysWhetherItsDroppingInRingingOrHowLongItsBeenOn() {
        assertEquals("Dropping in", BedsideCall("c", "Hidden number", "dropIn", "pending").status(100))
        assertEquals("Ringing", BedsideCall("c", "Hidden number", "call", "pending").status(100))
        assertEquals("On a call · 2:14", BedsideCall("c", "Carmen", "dropIn", "accepted", acceptedAt = 1000).status(1134))
        assertEquals("On a call · 0:00", BedsideCall("c", "Carmen", "call", "accepted", acceptedAt = 1000).status(990), "a clock behind the server's")
        assertEquals("On a call · 1:02:05", BedsideCall("c", "Carmen", "call", "accepted", acceptedAt = 0).status(3725))
        assertEquals("On a call", BedsideCall("c", "Carmen", "call", "accepted").status(100), "answered without a time yet")
    }
}
