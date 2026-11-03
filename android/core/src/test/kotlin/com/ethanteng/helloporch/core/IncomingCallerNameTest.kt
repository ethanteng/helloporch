package com.ethanteng.helloporch.core

import com.ethanteng.helloporch.core.ModelFixtures.decoded
import com.ethanteng.helloporch.core.ModelFixtures.noPhotos
import com.ethanteng.helloporch.core.ModelFixtures.person
import com.ethanteng.helloporch.core.ModelFixtures.uuid
import com.ethanteng.helloporch.core.ModelFixtures.withStore
import com.ethanteng.helloporch.core.NativeCall.Mode.VIDEO
import com.ethanteng.helloporch.core.NativeCall.Mode.VOICE
import kotlin.test.Test
import kotlin.test.assertEquals

class IncomingCallerNameTest {
    private val caller = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
    private val bedside = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"
    private val invitation = "cccccccc-cccc-4ccc-8ccc-cccccccccccc"

    private fun snapshot(role: String = "bedside", includeCaller: Boolean = true) = ModelFixtures.snapshot(
        people = if (includeCaller) listOf(person(caller, "Ethan", invitationID = invitation, dropIns = true)) else emptyList(),
        me = bedside, role = role, dropInEnabled = true)

    private fun call(kind: String = "call", mode: String = "video", recipient: String? = null): FamilyCallRecord = decoded(mapOf("id" to "test-call",
        "from" to caller, "to" to (recipient ?: bedside), "mode" to mode, "kind" to kind, "state" to "pending", "createdAt" to 1, "expiresAt" to 90, "callerName" to "Ethan"))

    @Test fun savedRenameOverridesOriginalInviteNameForVoiceVideoCallsAndDropIns() = withStore { settings, store ->
        val state = snapshot()
        val slots = CallSlots()
        slots.setContact(CallContact("David", NativeCall("paired", VIDEO), phoneNumber = "+14155550123", familyMemberID = caller), 1)
        slots.save(settings, store)
        val loaded = CallSlots.load(settings, store)
        loaded.reconcile(state, store.familyMembers)
        for (kind in listOf("call", "dropIn")) {
            for (mode in listOf("voice", "video")) {
                val incoming = call(kind, mode)
                assertEquals("David", loaded.incomingCallerName(incoming, state))
                assertEquals("Ethan", incoming.callerName, "The local label must not change the caller's server identity")
            }
        }
        assertEquals("+14155550123", loaded.contact(1)?.phoneNumber)
    }

    @Test fun acceptedInvitationUsesSavedNameBeforeAndAfterLinkReconciliation() {
        val state = snapshot(); val incoming = call()
        val slots = CallSlots()
        slots.setContact(CallContact("家駿", NativeCall("paired", VIDEO), familyMemberID = uuid(), invitationID = invitation), 1)
        assertEquals("家駿", slots.incomingCallerName(incoming, state))
        slots.reconcile(state, noPhotos.familyMembers)
        assertEquals(caller, slots.contact(1)?.familyMemberID)
        assertEquals("家駿", slots.incomingCallerName(incoming, state))
    }

    @Test fun missingRemovedAndUnrelatedSlotsFallBackWithoutMatchingByName() {
        val state = snapshot(); val incoming = call()
        val slots = CallSlots()
        assertEquals("Ethan", slots.incomingCallerName(incoming, state))
        slots.setContact(CallContact("David", NativeCall("other", VOICE), familyMemberID = uuid(), invitationID = uuid()), 1)
        assertEquals("Ethan", slots.incomingCallerName(incoming, state))
        slots.setContact(CallContact("David", NativeCall("paired", VOICE), familyMemberID = caller), 1)
        assertEquals("Ethan", slots.incomingCallerName(incoming, snapshot(includeCaller = false)))
        slots.setAction(KeypadAction.CALL_CONTROL, 1)
        assertEquals("Ethan", slots.incomingCallerName(incoming, state))
    }

    @Test fun bedsideAliasesDoNotLabelFamilyModeOrCallsToAnotherRecipient() {
        val slots = CallSlots()
        slots.setContact(CallContact("David", NativeCall("paired", VOICE), familyMemberID = caller), 1)
        assertEquals("Ethan", slots.incomingCallerName(call(), snapshot(role = "family")))
        assertEquals("Ethan", slots.incomingCallerName(call(recipient = caller), snapshot()))
    }

    @Test fun onlyTelephoneDropInsUseTheSavedPersonForTheirNumber() {
        val state = snapshot()
        val slots = CallSlots()
        slots.setContact(CallContact("David", NativeCall("paired", VOICE), phoneNumber = "+14155550200"), 1)
        fun phone(kind: String, number: String? = "+14155550200"): FamilyCallRecord = decoded(mapOf("id" to "phone-call", "from" to "sip:PA_test", "to" to bedside,
            "mode" to "voice", "kind" to kind, "state" to "pending", "createdAt" to 1, "expiresAt" to 46,
            "callerName" to if (kind == "dropIn") "Dave" else "+14155550200", "source" to "phone", "callerNumber" to number))
        assertEquals("David", slots.incomingCallerName(phone("dropIn"), state))
        assertEquals("+14155550200", slots.incomingCallerName(phone("call"), state), "An unverified number must not borrow a saved name")
        assertEquals("Dave", slots.incomingCallerName(phone("dropIn", "+14155550999"), state))
        assertEquals("Dave", slots.incomingCallerName(phone("dropIn", null), state))
    }
}
