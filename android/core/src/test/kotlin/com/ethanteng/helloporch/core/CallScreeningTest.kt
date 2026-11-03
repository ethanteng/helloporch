package com.ethanteng.helloporch.core

import com.ethanteng.helloporch.core.ModelFixtures.decoded
import com.ethanteng.helloporch.core.ModelFixtures.noPhotos
import com.ethanteng.helloporch.core.NativeCall.Mode.VIDEO
import com.ethanteng.helloporch.core.NativeCall.Mode.VOICE
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertNull

class CallScreeningTest {
    private fun screening(keypad: List<String>?): CallScreening = decoded(mapOf("enabled" to true,
        "allowed" to listOf(mapOf("number" to "+14155550300", "allowedAt" to 1_800_000_000)),
        "blocked" to listOf(mapOf("number" to "+14155550999", "firstCallAt" to 1_800_000_000, "lastCallAt" to 1_800_000_060, "calls" to 2)),
        "keypadNumbers" to keypad))

    @Test fun keypadReportsEachSavedPhoneNumberOnceInOrder() {
        val slots = CallSlots()
        assertEquals(emptyList(), slots.phoneNumbers)
        slots.setContact(CallContact("David", NativeCall("david", VOICE), phoneNumber = "+14155550200"), 3)
        slots.setContact(CallContact("May", NativeCall("may", VIDEO), phoneNumber = "+14155550100"), 1)
        slots.setContact(CallContact("Dave", NativeCall("dave", VOICE), phoneNumber = "+14155550200"), 2)
        // Only Porch calls, no phone: nothing to let through.
        slots.setContact(CallContact("Sam", NativeCall("sam", VIDEO)), 4)
        assertEquals(listOf("+14155550100", "+14155550200"), slots.phoneNumbers)
        // A key turned into a control no longer lets its person ring.
        slots.setAction(KeypadAction.MESSAGES, 1)
        assertEquals(listOf("+14155550200"), slots.phoneNumbers)
    }

    @Test fun otherNumbersCallInButOnlyThePrimaryIsTheFallback() {
        val call = NativeCall("mom", VOICE)
        val mom = CallContact("Mom", call, phoneNumber = "+1 (415) 555-0100",
            otherPhoneNumbers = listOf(" +14155550101 ", "+14155550100", "+14155550101", "+1 415 555 0102"))
        // Normalized; repeats and the primary listed again are dropped.
        assertEquals("+14155550100", mom.phoneNumber)
        assertEquals(listOf("+14155550101", "+14155550102"), mom.otherPhoneNumbers)
        assertEquals(listOf("+14155550100", "+14155550101", "+14155550102"), mom.phoneNumbers)
        assertFailsWith<ValidationException>("Other numbers need a primary one") { CallContact("Mom", call, otherPhoneNumbers = listOf("+14155550101")) }
        assertFailsWith<ValidationException> { CallContact("Mom", call, phoneNumber = "+14155550100", otherPhoneNumbers = listOf("415-555")) }
        val five = (1..4).map { "+1415555010$it" }
        CallContact("Mom", call, phoneNumber = "+14155550100", otherPhoneNumbers = five)
        assertFailsWith<ValidationException> { CallContact("Mom", call, phoneNumber = "+14155550100", otherPhoneNumbers = five + "+14155550109") }
        // Saved and reloaded, and kept when the keypad revalidates the contact.
        val serializer = CallContactSerializer(noPhotos)
        val decoded = PorchJson.decodeFromString(serializer, PorchJson.encodeToString(serializer, mom))
        assertEquals(mom, decoded)
        val slots = CallSlots()
        slots.setContact(decoded, 1)
        assertEquals(listOf("+14155550101", "+14155550102"), slots.contact(1)?.otherPhoneNumbers)
        // Every number names a phone voicemail and can ring while unknown callers are blocked.
        assertEquals("Mom", slots.contact(phoneNumber = "+14155550102")?.name)
        assertNull(slots.contact(phoneNumber = "+14155550199"))
        assertEquals(listOf("+14155550100", "+14155550101", "+14155550102"), slots.phoneNumbers)
        // Older saved contacts have no other numbers.
        val older = PorchJson.decodeFromString(serializer,
            """{"name":"David","address":"","phoneNumber":"+14155550123","nativeCall":{"room":"family-david","mode":"voice"}}""")
        assertEquals(emptyList(), older.otherPhoneNumbers)
        assertFalse(PorchJson.encodeToString(serializer, older).contains("otherPhoneNumbers"))
    }

    @Test fun keypadIsReportedOnlyWhenTheServerCopyDiffers() {
        val slots = CallSlots()
        slots.setContact(CallContact("David", NativeCall("david", VOICE), phoneNumber = "+14155550200"), 1)
        assertNull(screening(listOf("+14155550200")).keypadNumbersToReport(slots))
        assertEquals(listOf("+14155550200"), screening(emptyList()).keypadNumbersToReport(slots))
        // Never reported yet: even an empty keypad is reported, so blocking can be turned on.
        assertEquals(emptyList(), screening(null).keypadNumbersToReport(CallSlots()))
        assertNull(screening(emptyList()).keypadNumbersToReport(CallSlots()))
    }

    @Test fun screeningDecodesForTheBedsideAndCaregiversAndIsOptionalForOlderServers() {
        val decoded = screening(listOf("+14155550200"))
        assertEquals(listOf(AllowedCaller("+14155550300", 1_800_000_000)), decoded.allowed)
        assertEquals(2, decoded.blocked.first().calls)
        val admin = mapOf("householdName" to "Pat", "dropInEnabled" to false, "people" to emptyList<Any>())
        assertNull(decoded<FamilyAdminState>(admin).callScreening)
        val unreported = mapOf("enabled" to false, "keypadNumbers" to null, "allowed" to emptyList<Any>(), "blocked" to emptyList<Any>())
        val state = decoded<FamilyAdminState>(admin + ("callScreening" to unreported))
        assertEquals(false, state.callScreening?.enabled)
        assertNull(state.callScreening?.keypadNumbers)
    }
}
