package com.ethanteng.helloporch.core

import java.time.Instant
import java.time.ZoneId
import java.util.Locale
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonNull

class BedsidePhoneTest {
    private val zone = ZoneId.of("America/Los_Angeles")
    /** 2:14 PM on Nov 25, 2026, in Los Angeles. */
    private val out = Instant.parse("2026-11-25T22:14:00Z").epochSecond

    /** Newer JDKs and Android put a narrow no-break space before AM/PM. */
    private fun String.plain() = replace(' ', ' ')

    @Test fun theBedsideReportsItsPhoneOnlyWhilePorchCanTell() {
        assertNull(BedsidePhoneReport.of(inFront = false, setUp = true, connected = true), "the Cell2Jack only runs in front")
        assertEquals(BedsidePhoneReport.NotSetUp, BedsidePhoneReport.of(inFront = true, setUp = false, connected = false))
        assertEquals(BedsidePhoneReport.Cell2Jack(connected = false), BedsidePhoneReport.of(inFront = true, setUp = true, connected = false))
        assertEquals(BedsidePhoneReport.Cell2Jack(connected = true), BedsidePhoneReport.of(inFront = true, setUp = true, connected = true))
        assertEquals(JsonNull, BedsidePhoneReport.NotSetUp.json)
        assertEquals(Json.parseToJsonElement("""{"kind":"cell2jack","connected":false}"""), BedsidePhoneReport.Cell2Jack(false).json)
    }

    @Test fun theStepsFollowHowThePhoneIsPluggedIn() {
        assertEquals(listOf("Phone cord into the Cell2Jack", "Cell2Jack into the adapter", "Adapter into the hub by the iPad"),
            BedsidePhone(out, "adapter").steps("iPad"))
        assertEquals(listOf("Phone cord into the Cell2Jack", "Cell2Jack into the iPad or its hub"), BedsidePhone(out, "cell2jack").steps("iPad"))
        assertEquals(listOf("Phone cord into the Cell2Jack", "Cell2Jack into the hub by the tablet"), BedsidePhone(out, "cell2jack").steps("tablet"))
        assertEquals("https://helloporch.store/pilot/ios#phone", BedsidePhone(out, "adapter").guideURL("iPad"))
        assertEquals("https://helloporch.store/pilot/android#phone", BedsidePhone(out, "cell2jack").guideURL("tablet"))
    }

    @Test fun sinceSaysTheTimeTodayAndTheDayBefore() {
        val phone = BedsidePhone(out, "cell2jack")
        val later = Instant.parse("2026-11-26T02:00:00Z")
        assertEquals("2:14 PM", phone.time(later, zone, Locale.US).plain())
        assertEquals("Nov 25, 2:14 PM", phone.time(Instant.parse("2026-11-26T09:00:00Z"), zone, Locale.US).plain(), "the next day")
        assertEquals("Since 2:14 PM", BedsidePhone.since(phone.time(later, zone, Locale.US)).plain())
        assertEquals("Not connected · since 2:14 PM", BedsidePhone.notConnected(phone.time(later, zone, Locale.US)).plain())
        assertEquals("Rose’s phone isn’t connected. Since 2:14 PM", BedsidePhone.notConnectedDescription("Rose", "2:14 PM"))
    }

    @Test fun theSheetAndWhatItSharesNameTheBedside() {
        assertEquals("Reconnect Rose’s phone", BedsidePhone.reconnect("Rose"))
        assertEquals("At Rose’s tablet, check each plug:", BedsidePhone.checkEachPlug("Rose", "tablet"))
        assertEquals("""
            Rose’s phone isn’t connected to Porch. At Rose’s tablet, please check each plug:
            1. Phone cord into the Cell2Jack
            2. Cell2Jack into the hub by the tablet
            Step-by-step: https://helloporch.store/pilot/android#phone
        """.trimIndent(), BedsidePhone(out, "cell2jack").shareText("Rose", "tablet"))
        assertEquals("""
            Rose’s phone isn’t connected to Porch. At Rose’s iPad, please check each plug:
            1. Phone cord into the Cell2Jack
            2. Cell2Jack into the adapter
            3. Adapter into the hub by the iPad
            Step-by-step: https://helloporch.store/pilot/ios#phone
        """.trimIndent(), BedsidePhone(out, "adapter").shareText("Rose", "iPad"))
    }
}
