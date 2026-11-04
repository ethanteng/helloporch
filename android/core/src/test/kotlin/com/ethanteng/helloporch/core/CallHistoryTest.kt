package com.ethanteng.helloporch.core

import com.ethanteng.helloporch.core.ModelFixtures.parsed
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class CallHistoryTest {
    private fun entry(json: String): CallHistoryEntry = parsed(json)

    @Test fun callsReadAsTheyWentFromTheBedsidesSide() {
        val talked = entry("""{"id":"a","direction":"incoming","via":"porch","name":"Ethan","memberID":"m","mode":"video","startedAt":100,"answeredAt":104,"endedAt":844,"outcome":"answered"}""")
        assertEquals("Incoming video call", talked.kindText); assertEquals("Talked 12 min", talked.outcomeText)
        assertFalse(talked.isMissed)
        val missed = entry("""{"id":"b","direction":"incoming","via":"porch","name":"Ethan","mode":"voice","startedAt":100,"outcome":"missed"}""")
        assertEquals("Missed", missed.outcomeText); assertTrue(missed.isMissed)
        val unanswered = entry("""{"id":"c","direction":"outgoing","via":"porch","name":"Ethan","mode":"voice","startedAt":100,"endedAt":130,"outcome":"missed"}""")
        assertEquals("Outgoing audio call", unanswered.kindText); assertEquals("No answer", unanswered.outcomeText)
        assertFalse(unanswered.isMissed, "only calls to the bedside count as missed")
        assertEquals("No answer · Their phone showed the call",
            entry("""{"id":"c2","direction":"outgoing","via":"porch","name":"Ethan","mode":"voice","startedAt":100,"outcome":"missed","reached":true}""").outcomeText)
        assertEquals("No answer · Didn't reach their phone",
            entry("""{"id":"c3","direction":"outgoing","via":"porch","name":"Ethan","mode":"voice","startedAt":100,"outcome":"missed","reached":false}""").outcomeText)
        val dropIn = entry("""{"id":"d","direction":"incoming","via":"porch","name":"Ethan","mode":"video","dropIn":true,"startedAt":100,"answeredAt":105,"outcome":"answered"}""")
        assertEquals("Video drop-in", dropIn.kindText); assertEquals("Answered", dropIn.outcomeText, "older calls have no end time")
        val dialed = entry("""{"id":"e","direction":"outgoing","via":"phone","name":"David","number":"+14155550123","mode":"voice","startedAt":100,"outcome":"dialed"}""")
        assertEquals("Called their phone", dialed.kindText); assertNull(dialed.outcomeText)
        val phone = entry("""{"id":"f","direction":"incoming","via":"phone","name":"+14155550999","number":"+14155550999","mode":"voice","startedAt":100,"outcome":"declined"}""")
        assertEquals("Phone call", phone.kindText); assertEquals("Declined", phone.outcomeText)
        assertEquals("Couldn't reach their Porch",
            entry("""{"id":"g","direction":"outgoing","via":"porch","name":"Ethan","mode":"voice","startedAt":100,"outcome":"unavailable"}""").outcomeText)
        assertEquals("Ringing now", entry("""{"id":"h","direction":"outgoing","via":"porch","name":"Ethan","mode":"voice","startedAt":100,"outcome":"ringing"}""").outcomeText)
    }

    @Test fun durationsRoundToWholeMinutes() {
        assertEquals("0 sec", CallHistoryEntry.duration(0.0))
        assertEquals("45 sec", CallHistoryEntry.duration(45.0))
        assertEquals("1 min", CallHistoryEntry.duration(60.0))
        assertEquals("1 min", CallHistoryEntry.duration(89.0))
        assertEquals("2 min", CallHistoryEntry.duration(90.0))
        assertEquals("1 hr", CallHistoryEntry.duration(3600.0))
        assertEquals("1 hr 5 min", CallHistoryEntry.duration(3900.0))
    }
}
