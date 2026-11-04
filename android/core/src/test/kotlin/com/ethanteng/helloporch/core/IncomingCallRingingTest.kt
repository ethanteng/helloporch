package com.ethanteng.helloporch.core

import java.util.UUID
import kotlin.test.Test
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class IncomingCallRingingTest {
    /** A phone in both sets of parents' families hears about each family's calls on every check-in. */
    @Test fun aCallRingsOnlyWhileNoOtherCallIsUp() {
        val lee = UUID.randomUUID(); val teng = UUID.randomUUID()
        assertTrue(IncomingCallRinging.canRing(lee, current = null, onAnotherCall = false, finished = emptyList()))
        assertFalse(IncomingCallRinging.canRing(lee, current = lee, onAnotherCall = false, finished = emptyList()), "already ringing")
        assertFalse(IncomingCallRinging.canRing(teng, current = lee, onAnotherCall = false, finished = emptyList()), "another family's call waits instead of ringing on every check-in")
        // Hung up here: until its family's next check-in says so, that family still lists it as ringing.
        assertFalse(IncomingCallRinging.canRing(lee, current = null, onAnotherCall = false, finished = listOf(lee)))
        assertTrue(IncomingCallRinging.canRing(teng, current = null, onAnotherCall = false, finished = listOf(lee)), "still ringing once the other call is over")
    }

    /** The phone called one family itself. CallKit doesn't know about that call, so another family's can't ring over it. */
    @Test fun aCallThisPhoneStartedKeepsAnotherFamilysCallFromRinging() {
        val teng = UUID.randomUUID()
        assertFalse(IncomingCallRinging.canRing(teng, current = null, onAnotherCall = true, finished = emptyList()))
        assertTrue(IncomingCallRinging.pushBlocked(teng, current = null, onAnotherCall = true, finished = emptyList()), "a push during it is reported, ended and finished")
    }

    /** The second family's VoIP push is reported and ended while the first call is up. That UUID can't ring again. */
    @Test fun aPushDuringAnotherCallIsFinishedSoALaterCheckInDoesNotReportIt() {
        val lee = UUID.randomUUID(); val teng = UUID.randomUUID()
        assertTrue(IncomingCallRinging.pushBlocked(teng, current = lee, onAnotherCall = false, finished = emptyList()))
        assertFalse(IncomingCallRinging.pushBlocked(teng, current = null, onAnotherCall = false, finished = emptyList()), "nothing else is up, so the push can ring")
        assertFalse(IncomingCallRinging.pushBlocked(lee, current = lee, onAnotherCall = false, finished = emptyList()))
        assertFalse(IncomingCallRinging.pushBlocked(teng, current = lee, onAnotherCall = false, finished = listOf(teng)), "already remembered")
        assertFalse(IncomingCallRinging.canRing(teng, current = null, onAnotherCall = false, finished = listOf(teng)), "already handed to CallKit")
        assertTrue(IncomingCallRinging.canRing(teng, current = null, onAnotherCall = false, finished = listOf(lee)), "a check-in that never reported it still rings once the other call is over")
    }

    /** The push often arrives before the check-in that lists the call. That check-in hangs it up as missed.
     * A guest ring uses the same id in its own snapshot, and ending it would count as a decline. */
    @Test fun aBusyPushIsMissedOnceTheCheckInShowsItAndAGuestRingIsLeftToTimeOut() {
        val id = UUID.randomUUID()
        assertTrue(IncomingCallRinging.endAsMissed(id, snapshotCallID = id.toString().lowercase(), guest = false))
        assertTrue(IncomingCallRinging.endAsMissed(id, snapshotCallID = id.toString().uppercase(), guest = false))
        assertFalse(IncomingCallRinging.endAsMissed(id, snapshotCallID = null, guest = false), "the check-in has not listed it yet")
        assertFalse(IncomingCallRinging.endAsMissed(id, snapshotCallID = UUID.randomUUID().toString(), guest = false))
        assertFalse(IncomingCallRinging.endAsMissed(id, snapshotCallID = id.toString().lowercase(), guest = true), "ending a guest ring counts as a decline")
    }
}
