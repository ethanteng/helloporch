package com.ethanteng.helloporch.core

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class CallGuestRulesTest {
    private fun call(from: String = "me", to: String = "mom", state: String = "accepted", guest: Boolean? = null, bedsideLeft: Boolean? = null) =
        FamilyCallRecord(id = "call", from = from, to = to, mode = NativeCall.Mode.VIDEO, kind = "call", state = state, createdAt = 1,
            expiresAt = 100, callerName = "Mom", source = "porch", guest = guest, bedsideLeft = bedsideLeft)
    private val david = FamilyRelative("david", "David", canReceiveCalls = true)
    private val ann = FamilyRelative("ann", "Ann", canReceiveCalls = false)

    @Test fun theBedsideIsTheCallsOtherEndUnlessThisPhoneWasRungIn() {
        assertEquals("mom", CallGuestRules.bedsideID(call(), "me"))
        assertEquals("mom", CallGuestRules.bedsideID(call(from = "mom", to = "me"), "me"))
        assertNull(CallGuestRules.bedsideID(call(from = "me", to = "mom", guest = true), "me"))
        assertNull(CallGuestRules.bedsideID(call(from = "ethan", to = "mom"), "me"))
    }

    @Test fun addSomeoneOffersFamilyWhoCanRingOneAtATime() {
        assertEquals(listOf(david), CallGuestRules.ringable(listOf(david, ann), guest = null))
        assertEquals(listOf(david), CallGuestRules.ringable(listOf(david, ann), FamilyPorchGuest("g", "david", "David", "declined")))
        assertEquals(emptyList(), CallGuestRules.ringable(listOf(david), FamilyPorchGuest("g", "david", "David", "ringing")))
        assertEquals(emptyList(), CallGuestRules.ringable(listOf(david), FamilyPorchGuest("g", "david", "David", "joined")))
    }

    @Test fun addSomeoneShowsOnlyOnAnAnsweredCallWithTheBedsideThere() {
        val people = listOf(david)
        assertTrue(CallGuestRules.showsAdd(call(), bedsideHere = true, people))
        assertFalse(CallGuestRules.showsAdd(null, bedsideHere = true, people))
        assertFalse(CallGuestRules.showsAdd(call(state = "pending"), bedsideHere = true, people))
        assertFalse(CallGuestRules.showsAdd(call(), bedsideHere = false, people), "not until the bedside is in the room")
        assertFalse(CallGuestRules.showsAdd(call(bedsideLeft = true), bedsideHere = true, people))
        assertFalse(CallGuestRules.showsAdd(call(guest = true), bedsideHere = true, people), "someone rung in can't add anyone")
        assertFalse(CallGuestRules.showsAdd(call(), bedsideHere = true, emptyList()))
    }

    @Test fun eachChangeHasItsWord() {
        fun guest(state: String) = FamilyPorchGuest("g", "david", "David", state)
        assertEquals("David joined the call.", CallGuestRules.notice(guest("joined")))
        assertEquals("David declined.", CallGuestRules.notice(guest("declined")))
        assertEquals("David didn't answer.", CallGuestRules.notice(guest("missed")))
        assertEquals("David left the call.", CallGuestRules.notice(guest("left")))
        assertEquals("Stopped ringing David.", CallGuestRules.notice(guest("cancelled")))
        assertNull(CallGuestRules.notice(guest("ringing")))
    }
}
