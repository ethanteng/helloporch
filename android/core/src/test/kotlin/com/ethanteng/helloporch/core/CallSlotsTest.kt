package com.ethanteng.helloporch.core

import com.ethanteng.helloporch.core.ModelFixtures.decoded
import com.ethanteng.helloporch.core.ModelFixtures.person
import com.ethanteng.helloporch.core.ModelFixtures.snapshot
import com.ethanteng.helloporch.core.ModelFixtures.uuid
import com.ethanteng.helloporch.core.ModelFixtures.withStore
import com.ethanteng.helloporch.core.NativeCall.Mode.VIDEO
import com.ethanteng.helloporch.core.NativeCall.Mode.VOICE
import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

class CallSlotsTest {
    /** Ten saved digits, the first as given and the rest empty person keys. */
    private fun savedKeypad(first: String) = (listOf(first) + List(9) { """{"action":"person"}""" }).joinToString(",", "[", "]")

    @Test fun keysAreTheDigitsThenStarAndPound() {
        assertEquals("1234567890*#", CallSlots.digits.joinToString("") { CallSlots.symbol(it) })
        for (digit in CallSlots.digits) assertEquals(digit, CallSlots.digit(CallSlots.symbol(digit)))
        for (symbol in listOf("10", "11", "A", "D", "", "١", "**", " 1")) assertNull(CallSlots.digit(symbol), symbol)
        val slots = CallSlots()
        assertEquals(KeypadAction.UNASSIGNED, slots.action(CallSlots.star)); assertNull(slots.contact(CallSlots.star))
        assertEquals(KeypadAction.UNASSIGNED, slots.action(CallSlots.pound)); assertNull(slots.contact(CallSlots.pound))
    }

    @Test fun starAndPoundSaveBesideTheTenDigitsSoEarlierBuildsCanStillReadThem() = withStore { settings, store ->
        val slots = CallSlots()
        slots.setContact(CallContact("David", NativeCall("david", VOICE)), 1)
        slots.save(settings, store)
        // As a build from before * and # saved it: ten slots and nothing beside them.
        settings.remove("porch.slots.v2.symbols")
        val loaded = CallSlots.load(settings, store)
        assertEquals(slots, loaded)
        loaded.setContact(CallContact("Mei", NativeCall("mei", VOICE)), CallSlots.star)
        loaded.setAction(KeypadAction.CALL_CONTROL, CallSlots.pound)
        loaded.save(settings, store)
        val saved = PorchJson.parseToJsonElement(assertNotNull(settings.getString("porch.slots.v2"))).jsonArray
        assertEquals(10, saved.size, "A build from before * and # reads exactly ten")
        val contacts = saved.mapNotNull { (it as? JsonObject)?.get("contact") as? JsonObject }
        assertEquals(listOf("\"\""), contacts.map { it["address"].toString() }, "iOS reads a contact only with its address, empty for a Porch contact")
        val reloaded = CallSlots.load(settings, store)
        assertEquals(loaded, reloaded)
        assertEquals("Mei", reloaded.contact(CallSlots.star)?.name)
        assertEquals(KeypadAction.CALL_CONTROL, reloaded.action(CallSlots.pound))
        assertEquals("David", reloaded.contact(1)?.name)
        settings.putString("porch.slots.v2.symbols", "[null]")
        assertFailsWith<ValidationException> { CallSlots.load(settings, store) }
    }

    @Test fun sixPeoplePersistAndRouteWithoutShiftingKeys() = withStore { settings, store ->
        val slots = CallSlots()
        for (number in 1..6) {
            val contact = if (number % 2 == 0) CallContact("Person $number", NativeCall("person-$number", VIDEO), phoneNumber = "+1415555000$number")
                else CallContact("Person $number", NativeCall("person-$number", VOICE))
            slots.setContact(contact, number)
        }
        slots.save(settings, store)
        assertEquals(slots, CallSlots.load(settings, store))
        for (number in 1..6) {
            val routedSlot = assertNotNull(CallTrigger.slot(145 + number - 1)) // number pad 1–6
            assertEquals("Person $number", slots.contact(routedSlot)?.name)
        }
        val sixth = slots.contact(6)
        slots.setContact(null, 2)
        slots.save(settings, store)
        val loaded = CallSlots.load(settings, store)
        assertEquals(12, loaded.contacts.size)
        assertNull(loaded.contact(2))
        assertEquals(NativeCall("person-3", VOICE), loaded.contact(3)?.nativeCall)
        assertEquals(sixth, loaded.contact(6))
        assertEquals("+14155550006", loaded.contact(6)?.phoneNumber)
    }

    @Test fun emptyAndOutOfRangeSlotsCannotResolveToAPerson() {
        val slots = CallSlots()
        val contact = CallContact("David", NativeCall("david", VOICE))
        slots.setContact(contact, 6)
        for (number in listOf(-1, 0, 1, 2, 3, 4, 5, 7, 8, 9, 10)) assertNull(slots.contact(number))
        for (number in listOf(-1, 12)) assertFailsWith<ValidationException> { slots.setContact(contact, number) }
        assertEquals(contact, slots.contact(6))
    }

    @Test fun nativeCallsPersistWithTheirRoomAndMode() = withStore { settings, store ->
        val slots = CallSlots()
        slots.setContact(CallContact("David", NativeCall.of(" Family-David ", VOICE)), 2)
        slots.setContact(CallContact("Maria", NativeCall("family-maria", VIDEO)), 6)
        slots.save(settings, store)
        val loaded = CallSlots.load(settings, store)
        assertEquals(slots, loaded)
        assertEquals("family-david", loaded.contact(2)?.nativeCall?.room)
        assertEquals(VOICE, loaded.contact(2)?.nativeCall?.mode)
        assertEquals(VIDEO, loaded.contact(6)?.nativeCall?.mode)
    }

    @Test fun malformedNativeSavedDataIsRevalidated() = withStore { settings, store ->
        for (contact in listOf("""{"name":"David","nativeCall":{"room":"../room","mode":"voice"}}""", """{"name":"David","nativeCall":{"room":"room","mode":"invalid"}}""")) {
            settings.putString("porch.slots.v2", savedKeypad("""{"action":"person","contact":$contact}"""))
            assertFailsWith<ValidationException>(contact) { CallSlots.load(settings, store) }
        }
    }

    @Test fun phoneFallbackRetainsPorchModeAndStableSlotAcrossRelaunch() = withStore { settings, store ->
        val slots = CallSlots()
        slots.setContact(CallContact("David", NativeCall("family-david", VIDEO), phoneNumber = " +1 (415) 555-0123 "), 4)
        slots.save(settings, store)
        val loaded = CallSlots.load(settings, store)
        assertEquals(VIDEO, loaded.contact(4)?.nativeCall?.mode)
        assertEquals("family-david", loaded.contact(4)?.nativeCall?.room)
        assertEquals("+14155550123", loaded.contact(4)?.phoneNumber)
        assertNull(loaded.contact(1))
        slots.setContact(CallContact("David", NativeCall("family-david", VIDEO)), 4)
        slots.save(settings, store)
        assertNull(CallSlots.load(settings, store).contact(4)?.phoneNumber)
    }

    @Test fun corruptPhoneFallbackCannotBypassValidation() = withStore { settings, store ->
        for (contact in listOf("""{"name":"David","address":"david@example.com","phoneNumber":"+14155550123"}""",
            """{"name":"David","address":"","phoneNumber":"4155550123","nativeCall":{"room":"family-david","mode":"voice"}}""")) {
            settings.putString("porch.slots.v2", savedKeypad("""{"action":"person","contact":$contact}"""))
            assertFailsWith<ValidationException>(contact) { CallSlots.load(settings, store) }
        }
    }

    @Test fun linkedContactSurvivesPersistenceWithoutChangingPhoneFallback() = withStore { settings, store ->
        val person = uuid().lowercase()
        val contact = CallContact("Ethan", NativeCall("paired", VIDEO), phoneNumber = "+14158676937", familyMemberID = person)
        val slots = CallSlots(); slots.setContact(contact, 3); slots.save(settings, store)
        val loaded = CallSlots.load(settings, store).contact(3)
        assertEquals(person, loaded?.familyMemberID); assertEquals("+14158676937", loaded?.phoneNumber)
        assertFailsWith<ValidationException> { CallContact("Ethan", NativeCall("paired", VOICE), familyMemberID = "a display name") }
    }

    @Test fun anyDigitCanBeAPersonOrControlAndChangesSurviveRelaunch() = withStore { settings, store ->
        val slots = CallSlots()
        val person = CallContact("Pat", NativeCall("pat", VIDEO))
        for (digit in CallSlots.digits) slots.setContact(person, digit)
        assertEquals(12, slots.contacts.filterNotNull().size)
        slots.setAction(KeypadAction.CALL_CONTROL, 4); slots.setAction(KeypadAction.TOGGLE_VIDEO, 7)
        slots.save(settings, store)
        val loaded = CallSlots.load(settings, store)
        assertEquals(4, loaded.digit(KeypadAction.CALL_CONTROL)); assertNull(loaded.contact(4))
        assertEquals(KeypadAction.TOGGLE_VIDEO, loaded.action(7)); assertEquals(person, loaded.contact(0))
    }

    @Test fun keysStartWithNoActionAndCanBeClearedAgain() = withStore { settings, store ->
        val slots = CallSlots()
        for (digit in CallSlots.digits) if (digit != 9 && digit != 0) assertEquals(KeypadAction.UNASSIGNED, slots.action(digit))
        slots.setContact(CallContact("Pat", NativeCall("pat", VIDEO)), 1); slots.setAction(KeypadAction.MESSAGES, 2)
        for (digit in listOf(1, 2, 9, 0)) slots.setAction(KeypadAction.UNASSIGNED, digit)
        for (digit in listOf(1, 2, 9, 0)) { assertEquals(KeypadAction.UNASSIGNED, slots.action(digit)); assertNull(slots.contact(digit)) }
        assertNull(slots.digit(KeypadAction.CALL_CONTROL))
        slots.save(settings, store)
        assertEquals(slots, CallSlots.load(settings, store))
        // A key with no action is saved as an empty person key, as on iOS.
        val saved = PorchJson.parseToJsonElement(assertNotNull(settings.getString("porch.slots.v2"))).jsonArray
        assertEquals(setOf("person"), saved.map { it.jsonObject["action"]?.jsonPrimitive?.content }.toSet())
    }

    @Test fun messagesKeySurvivesRelaunchAndBedsideQueueDecodes() = withStore { settings, store ->
        val slots = CallSlots()
        slots.setAction(KeypadAction.MESSAGES, 8); slots.save(settings, store)
        assertEquals(8, CallSlots.load(settings, store).digit(KeypadAction.MESSAGES))
        val state = snapshot(me = "bed", extra = mapOf("messagesEnabled" to true, "messages" to listOf(mapOf("id" to "m1", "from" to "f1", "fromName" to "Ethan",
            "kind" to "voicemail", "mode" to "video", "contentType" to "video/quicktime", "durationSeconds" to 42, "sentAt" to 1_800_000_000, "delivered" to false))))
        assertEquals("mov", state.messages?.first()?.fileExtension); assertEquals(true, state.messagesEnabled)
    }

    @Test fun phoneVoicemailNamesTheKeypadContactAndFormatsUnknownNumbers() {
        val slots = CallSlots()
        slots.setContact(CallContact("Aunt May", NativeCall("family-may", VOICE), phoneNumber = "+14158676937"), 2)
        assertEquals("Aunt May", slots.contact(phoneNumber = "+14158676937")?.name)
        assertNull(slots.contact(phoneNumber = "+14155550100")); assertNull(slots.contact(phoneNumber = null))
        assertEquals("(415) 867-6937", PhoneNumberNormalization.display("+14158676937", region = "US"))
        assertEquals("+44 20 7031 3000", PhoneNumberNormalization.display("+442070313000", region = "US"))
        val message = decoded<FamilyMessage>(mapOf("id" to "v1", "from" to "phone", "fromName" to "+14158676937", "kind" to "voicemail", "mode" to "audio",
            "contentType" to "audio/mpeg", "durationSeconds" to 12, "sentAt" to 1_800_000_000, "delivered" to false, "callerNumber" to "+14158676937",
            "callerVerified" to true, "held" to true))
        assertTrue(message.fromPhone); assertEquals(true, message.held); assertEquals(true, message.callerVerified); assertEquals("mp3", message.fileExtension)
    }

    @Test fun acceptingInvitationLinksOnlyMatchingContactAndKeepsFallback() = withStore { settings, store ->
        val invite = uuid(); val otherInvite = uuid(); val person = uuid()
        val contact = CallContact("Same name", NativeCall("person", VIDEO), phoneNumber = "+14158676937", invitationID = invite)
        val slots = CallSlots(); slots.setContact(contact, 8)
        slots.setContact(CallContact("Same name", NativeCall("other", VOICE), invitationID = otherInvite), 2)
        val state = snapshot(people = listOf(person(person, "Same name", invitationID = invite)), me = "bed")
        slots.reconcile(state, store.familyMembers)
        assertEquals(person, slots.contact(8)?.familyMemberID)
        assertEquals(contact.phoneNumber, slots.contact(8)?.phoneNumber)
        assertEquals(contact.nativeCall, slots.contact(8)?.nativeCall)
        assertNull(slots.contact(2)?.familyMemberID)
        slots.save(settings, store)
        assertEquals(slots, CallSlots.load(settings, store))
        slots.reconcile(snapshot(me = "bed"), store.familyMembers)
        assertNull(slots.contact(8)?.familyMemberID, "Revoked devices must not remain linked")
    }

    @Test fun photoAndColorSurviveSavingAndAcceptedInvitation() = withStore { settings, store ->
        val invitation = uuid(); val member = uuid()
        val photo = byteArrayOf(1, 2, 3, 4)
        var slots = CallSlots()
        slots.setContact(CallContact("David", NativeCall("david", VIDEO), phoneNumber = "+14155550123", invitationID = invitation,
            buttonColorHex = "fFcC00", photoData = photo), 3)
        slots.save(settings, store)
        slots = CallSlots.load(settings, store)
        val state = snapshot(people = listOf(person(member, "Original name", invitationID = invitation, dropIns = true)), me = "bedside", dropInEnabled = true)
        slots.reconcile(state, store.familyMembers)
        slots.save(settings, store)
        val loaded = CallSlots.load(settings, store)
        val saved = assertNotNull(loaded.contact(3))
        assertEquals("FFCC00", saved.buttonColorHex); assertContentEquals(photo, saved.photoData)
        assertEquals(member, saved.familyMemberID); assertEquals("+14155550123", saved.phoneNumber)
        for (kind in listOf("call", "dropIn")) {
            val incoming = decoded<FamilyCallRecord>(mapOf("id" to "call", "from" to member, "to" to "bedside", "mode" to "video", "kind" to kind, "state" to "pending",
                "createdAt" to 1, "expiresAt" to 90, "callerName" to "Original name"))
            assertEquals(saved, loaded.incomingContact(incoming, state))
        }
    }

    @Test fun forgettingTheKeypadAndCallSettingsLeavesWhatANewBedsideStartsWith() = withStore { settings, store ->
        val freshFallback = CallPreferences.fallbackSeconds(settings)
        val freshLeaveMessage = CallPreferences.leaveMessageWhenUnanswered(settings)
        val slots = CallSlots()
        slots.setContact(CallContact("David", NativeCall("david", VIDEO), photoData = byteArrayOf(1, 2, 3, 4)), CallSlots.star)
        slots.save(settings, store)
        CallPreferences.saveFallbackSeconds(freshFallback + 30, settings); CallPreferences.saveLeaveMessageWhenUnanswered(!freshLeaveMessage, settings)
        settings.putBoolean("porch.cell2jack.enabled", true)
        assertFalse(store.directory.listFiles().isNullOrEmpty())

        CallSlots.forget(settings, store); CallPreferences.forget(settings)
        assertFalse(CallSlots.isSaved(settings))
        assertNull(CallSlots.load(settings, store).contact(CallSlots.star))
        assertTrue(store.directory.listFiles().isNullOrEmpty(), "Its photos go too, however new")
        assertEquals(freshFallback, CallPreferences.fallbackSeconds(settings))
        assertEquals(freshLeaveMessage, CallPreferences.leaveMessageWhenUnanswered(settings))
        assertEquals(true, settings.getBoolean("porch.cell2jack.enabled"), "Not a keypad or call setting")
    }
}
