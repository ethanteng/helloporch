package com.ethanteng.helloporch.core

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class AddSomeoneDraftTest {
    private val memberID = "11111111-2222-4333-8444-555555555555"
    private val memberInvitation = "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee"
    private val newInvitation = "99999999-8888-4777-8666-555555555555"
    private val tom = FamilyPerson(id = memberID, name = "Tom Reyes", role = PorchExperience.FAMILY, permissions = DropInPermissions(audio = true, video = false),
        online = false, invitationID = memberInvitation)

    @Test fun firstFreeKeyFollowsTheKeypadsLayout() {
        val slots = CallSlots()
        assertEquals(1, AddSomeoneDraft.firstFreeKey(slots))
        for (digit in 1..8) slots.setContact(CallContact("Person $digit", NativeCall("room-$digit", NativeCall.Mode.VOICE)), digit)
        // 9 starts as Video on / off and 0 as Answer / hang up, so * and # come before them.
        assertEquals(CallSlots.star, AddSomeoneDraft.firstFreeKey(slots))
        slots.setAction(KeypadAction.MESSAGES, CallSlots.star)
        assertEquals(CallSlots.pound, AddSomeoneDraft.firstFreeKey(slots))
        slots.setAction(KeypadAction.MESSAGES, CallSlots.pound)
        assertNull(AddSomeoneDraft.firstFreeKey(slots), "A full keypad has no key to offer")
        slots.setContact(null, 4)
        assertEquals(4, AddSomeoneDraft.firstFreeKey(slots))
        assertEquals(listOf("1", "2", "3", "4", "5", "6", "7", "8", "9", "*", "0", "#"), AddSomeoneDraft.keypadOrder.map(CallSlots::symbol))
    }

    @Test fun porchAppRowSaysWhatTheInvitationApproves() {
        val draft = AddSomeoneDraft(key = 5, name = "Linda Park", viaApp = true)
        assertEquals("Drop-in on", draft.porchAppValue)
        assertEquals("Audio drop-in", draft.copy(dropInVideo = false).porchAppValue)
        assertEquals("Video drop-in", draft.copy(dropInAudio = false).porchAppValue)
        assertEquals("Drop-in off", draft.copy(dropInAudio = false, dropInVideo = false).porchAppValue)
        assertEquals("Connected", draft.choosing(tom).porchAppValue)
    }

    @Test fun phoneRowShowsTheNumberPorchCallsAndHowManyMore() {
        val draft = AddSomeoneDraft(key = 5, name = "Linda")
        assertNull(draft.phoneValue("US"))
        val one = draft.reaching("(415) 867-6937", "US")
        assertEquals("(415) 867-6937", one.phoneValue("US"))
        assertEquals("(415) 867-6937 +1", one.copy(numbers = PhoneNumberList.adding(one.numbers, "+44 20 7031 3000", "US")).phoneValue("US"))
    }

    @Test fun stepTwoReplacesTheNumberPorchCallsAndKeepsTheOthers() {
        val draft = AddSomeoneDraft(key = 5, name = "Linda", numbers = listOf("+14158676937", "+442070313000"))
        val changed = draft.reaching("+1 415 555 2671", "US")
        assertEquals(listOf("+14155552671", "+442070313000"), changed.numbers)
        assertTrue(changed.viaPhone)
        // Typing one of their other numbers makes it the one Porch calls, once.
        assertEquals(listOf("+442070313000"), draft.reaching("+44 20 7031 3000", "US").numbers)
        val bad = assertFailsWith<ValidationException> { draft.reaching("415 555", "US") }
        assertEquals("Check this number. For other countries, start with +.", bad.message)
    }

    @Test fun addingNumbersRefusesBadRepeatedAndTooMany() {
        var numbers = listOf("+14158676937")
        assertEquals("Check this number. For other countries, start with +.",
            assertFailsWith<ValidationException> { PhoneNumberList.adding(numbers, "911", "US") }.message)
        assertEquals("That number is already saved for them.", assertFailsWith<ValidationException> { PhoneNumberList.adding(numbers, "415-867-6937", "US") }.message)
        for (number in listOf("+14155552671", "+14155552672", "+14155552673", "+14155552674")) numbers = PhoneNumberList.adding(numbers, number, "US")
        assertEquals("+14155552674", numbers.last(), "A typed number goes after the others")
        assertEquals(CallContact.maximumPhoneNumbers, numbers.size)
        assertEquals("Save up to 5 phone numbers for one person.",
            assertFailsWith<ValidationException> { PhoneNumberList.adding(numbers, "+14155552675", "US") }.message)
        val moved = PhoneNumberList.makingPrimary(numbers, "+14155552673")
        assertEquals("+14155552673", moved.first())
        assertEquals(numbers.toSet(), moved.toSet())
        assertEquals(numbers, PhoneNumberList.makingPrimary(numbers, "+14155550000"), "A number that isn't theirs changes nothing")
    }

    @Test fun aPickedNumberBecomesTheOnePorchCalls() {
        val numbers = listOf("+14158676937", "+14155552671")
        assertEquals(listOf("+442070313000", "+14158676937", "+14155552671"), PhoneNumberList.picking(numbers, "+44 20 7031 3000", "US"))
        // One already saved moves to the front instead of repeating, even when the list is full.
        assertEquals(listOf("+14155552671", "+14158676937"), PhoneNumberList.picking(numbers, "(415) 555-2671", "US"))
        val full = numbers + listOf("+14155552672", "+14155552673", "+14155552674")
        assertEquals("+14155552674", PhoneNumberList.picking(full, "415 555 2674", "US").first())
        assertEquals("Save up to 5 phone numbers for one person.",
            assertFailsWith<ValidationException> { PhoneNumberList.picking(full, "+14155552675", "US") }.message)
        assertEquals("Check this number. For other countries, start with +.",
            assertFailsWith<ValidationException> { PhoneNumberList.picking(numbers, "555", "US") }.message)
        assertEquals(listOf("+14158676937"), PhoneNumberList.picking(emptyList(), "4158676937", "US"))
    }

    @Test fun onlySomeoneOnPorchCanBeLeftWithoutANumber() {
        val call = NativeCall("contact-1a2b3c4d", NativeCall.Mode.VOICE)
        val byPhone = CallContact("Linda Park", call, phoneNumber = "+14158676937")
        assertEquals("Add a number so Porch can reach Linda.", PhoneNumberList.missing(emptyList(), byPhone))
        assertNull(PhoneNumberList.missing(listOf("+14155552671"), byPhone))
        val invited = CallContact("", call, phoneNumber = "+14158676937", invitationID = newInvitation, memberName = "Linda Park")
        assertNull(PhoneNumberList.missing(emptyList(), invited))
        val onPorch = CallContact("", call, familyMemberID = memberID, memberName = "Tom Reyes")
        assertNull(PhoneNumberList.missing(emptyList(), onPorch))
    }

    @Test fun choosingAFamilyMemberUsesTheirPorchNameAndApp() {
        val picked = AddSomeoneDraft(key = 5, tile = 5, name = "David", numbers = listOf("+14158676937"), viaPhone = true).choosing(tom)
        assertEquals("Tom Reyes", picked.name)
        assertEquals("Tom", picked.firstName)
        assertTrue(picked.viaApp && picked.member && !picked.inviting)
        assertFalse(picked.viaPhone)
        assertEquals(emptyList(), picked.numbers)
        assertTrue(picked.fromKeyTile)
        val again = picked.someoneNew("Linda Park")
        assertFalse(again.member)
        assertTrue(again.inviting)
    }

    @Test fun keyForSomeoneOnlyByPhoneKeepsTheirNameAndPhoto() {
        val photo = byteArrayOf(1, 2, 3)
        val draft = AddSomeoneDraft(key = 5, name = " Linda Park ", numbers = listOf("+14158676937", "+442070313000"), viaPhone = true, video = false,
            colorHex = "1565C0")
        assertTrue(draft.reachable)
        val contact = draft.contact(null, "contact-1a2b3c4d", photo)
        assertEquals("Linda Park", contact.customName)
        assertNull(contact.memberName)
        assertNull(contact.invitationID)
        assertEquals("+14158676937", contact.phoneNumber)
        assertEquals(listOf("+442070313000"), contact.otherPhoneNumbers)
        assertEquals(NativeCall("contact-1a2b3c4d", NativeCall.Mode.VOICE), contact.nativeCall)
        assertEquals("1565C0", contact.buttonColorHex)
        assertTrue(photo.contentEquals(contact.customPhotoData))
    }

    @Test fun keyForSomeoneInvitedGoesByTheInvitation() {
        val draft = AddSomeoneDraft(key = 5, name = "Linda Park", viaApp = true)
        val contact = draft.contact(newInvitation, "contact-1a2b3c4d", byteArrayOf(1))
        assertEquals("", contact.customName)
        assertEquals("Linda Park", contact.memberName)
        assertEquals("Linda Park", contact.name)
        assertEquals(newInvitation, contact.invitationID)
        assertNull(contact.familyMemberID)
        assertEquals(NativeCall.Mode.VIDEO, contact.nativeCall.mode)
    }

    @Test fun keyForAFamilyMemberUsesTheirPorchPhoto() {
        val draft = AddSomeoneDraft(key = 5).choosing(tom)
        // An invitation made earlier for someone new doesn't follow the caregiver to a family member.
        val contact = draft.copy(invitationID = newInvitation).contact(null, "contact-1a2b3c4d", byteArrayOf(1))
        assertEquals("", contact.customName)
        assertEquals("Tom Reyes", contact.memberName)
        assertEquals(memberID, contact.familyMemberID)
        assertEquals(memberInvitation, contact.invitationID)
        assertNull(contact.customPhotoData)
    }

    @Test fun anInvitationIsReusedOnlyForTheSameNameAndDropIn() {
        val made = AddSomeoneDraft(key = 5, name = "Linda Park", viaApp = true, dropInAudio = true, dropInVideo = false,
            invitationID = newInvitation, link = "https://helloporch.store/join#code=abc",
            invitationName = "Linda Park", invitationAudio = true, invitationVideo = false)
        assertEquals(newInvitation, made.reusableInvitation())
        assertEquals(newInvitation, made.copy(name = " Linda Park ").reusableInvitation(), "Spaces around the name don't make another invitation")
        assertNull(made.copy(name = "David").reusableInvitation(), "A different person needs their own invitation")
        assertNull(made.copy(dropInVideo = true).reusableInvitation(), "Drop-in is part of the invitation")
        assertNull(made.copy(viaApp = false).reusableInvitation(), "Phone only doesn't keep the invitation")
        assertNull(made.choosing(tom).reusableInvitation(), "Someone already on Porch isn't invited again")
        assertNull(made.copy(invitationName = null).reusableInvitation())
        // Coming back from a family member to the same new person can still use the invitation already made.
        assertEquals(newInvitation, made.choosing(tom).someoneNew("Linda Park").reusableInvitation())
    }

    @Test fun someoneMustBeReachable() {
        val draft = AddSomeoneDraft(key = 5, name = "Linda")
        assertFalse(draft.reachable)
        assertTrue(draft.copy(viaApp = true).reachable)
        assertTrue(draft.copy(numbers = listOf("+14158676937")).reachable)
        assertTrue(draft.choosing(tom).reachable)
    }
}
