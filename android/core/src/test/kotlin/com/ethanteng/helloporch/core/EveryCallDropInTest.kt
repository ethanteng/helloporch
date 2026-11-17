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
