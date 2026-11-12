package com.ethanteng.helloporch.core

import com.ethanteng.helloporch.core.ModelFixtures.noPhotos
import com.ethanteng.helloporch.core.ModelFixtures.withStore
import com.ethanteng.helloporch.core.NativeCall.Mode.VIDEO
import com.ethanteng.helloporch.core.NativeCall.Mode.VOICE
import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertNotEquals
import kotlin.test.assertNull

/** A key waiting for someone takes up the invitation sent for them from anywhere, so no caregiver has to link it by hand. */
class KeysFollowInvitationsTest {
    private val now = 1_800_000_000L
    private val lisaInvite = "11111111-1111-4111-8111-111111111111"
    private val lisa = "22222222-2222-4222-8222-222222222222"

    private fun snapshot(invitations: List<Any?> = emptyList(), people: List<Any?> = emptyList(), role: String = "bedside") =
        ModelFixtures.snapshot(people, role = role, householdName = "Mom", extra = mapOf("invitations" to invitations, "serverTime" to now))
    private fun invitation(id: String, name: String) = mapOf("id" to id, "name" to name, "expiresAt" to now + 3600)
    private fun member(id: String, invitation: String, invited: String, name: String = invited, joinedAt: Long?, photoID: String? = null) =
        ModelFixtures.person(id, name, invitationID = invitation, photoID = photoID, dropIns = true) + mapOf("invitedName" to invited, "joinedAt" to joinedAt)
    private fun phoneKey(name: String, room: String = "lisa") =
        CallContact(name, NativeCall(room, VIDEO), phoneNumber = "+14155550123", buttonColorHex = "FFCC00", photoData = byteArrayOf(1, 2, 3))
    private fun CallSlots.reconcile(state: FamilySnapshot) = reconcile(state, noPhotos)

    @Test fun phoneKeyFollowsAnInvitationSentElsewhereThenLinksWhenTheyJoin() {
        val slots = CallSlots()
        slots.setContact(phoneKey("Lisa"), 2)
        slots.reconcile(snapshot(invitations = listOf(invitation(lisaInvite, " lisa "))))
        val invited = slots.contact(2)!!
        assertEquals(lisaInvite, invited.invitationID)
        assertNull(invited.familyMemberID)
        assertEquals("lisa", invited.name, "Until they join, the key goes by the invitation's name")
        assertEquals("+14155550123", invited.phoneNumber); assertEquals("lisa", invited.nativeCall.room)
        assertEquals("FFCC00", invited.buttonColorHex); assertContentEquals(byteArrayOf(1, 2, 3), invited.customPhotoData)

        // She joins and chooses her own name, which the key then shows.
        slots.reconcile(snapshot(people = listOf(member(lisa, lisaInvite, invited = "lisa", name = "Lisa Chen", joinedAt = now - 60))))
        assertEquals(lisa, slots.contact(2)?.familyMemberID)
        assertEquals("Lisa Chen", slots.contact(2)?.name)
        assertEquals("+14155550123", slots.contact(2)?.phoneNumber, "Porch still calls her phone when the app isn't answered")
    }

    @Test fun keyTakesUpAnInvitationAcceptedWhileTheBedsideWasOfflineForADay() {
        for ((joinedAt, linked) in listOf(now - 3600 to true, now - CallSlots.joinedRecentlySeconds to false, null to false)) {
            val slots = CallSlots()
            slots.setContact(phoneKey("Lisa"), 2)
            slots.reconcile(snapshot(people = listOf(member(lisa, lisaInvite, invited = "LISA", name = "Lisa Chen", joinedAt = joinedAt))))
            assertEquals(if (linked) lisa else null, slots.contact(2)?.familyMemberID, "joinedAt $joinedAt")
            assertEquals(if (linked) "Lisa Chen" else "Lisa", slots.contact(2)?.name)
        }
    }

    @Test fun keysWhoseInvitationRanOutOrWhosePersonLeftFollowANewOne() {
        val expired = "33333333-3333-4333-8333-333333333333"
        val gone = "44444444-4444-4444-8444-444444444444"
        val dadInvite = "66666666-6666-4666-8666-666666666666"
        val slots = CallSlots()
        slots.setContact(CallContact("", NativeCall("a", VOICE), invitationID = expired, memberName = "Lisa"), 2)
        slots.setContact(CallContact("", NativeCall("b", VOICE), familyMemberID = gone, invitationID = expired.replace('3', '5'), memberName = "Dad"), 3)
        slots.reconcile(snapshot(invitations = listOf(invitation(lisaInvite, "Lisa"), invitation(dadInvite, "Dad"))))
        assertEquals(lisaInvite, slots.contact(2)?.invitationID)
        assertEquals(dadInvite, slots.contact(3)?.invitationID)
        assertEquals("b", slots.contact(3)?.nativeCall?.room)
    }

    @Test fun onlyTheCaregiversNameForTheInvitationCounts() {
        val slots = CallSlots()
        slots.setContact(phoneKey("Lisa"), 2)
        // Someone invited as Ethan who calls herself Lisa doesn't get Lisa's key.
        slots.reconcile(snapshot(people = listOf(member(lisa, lisaInvite, invited = "Ethan", name = "Lisa", joinedAt = now - 60))))
        assertNull(slots.contact(2)?.invitationID)
        assertNull(slots.contact(2)?.familyMemberID)
        assertEquals("Lisa", slots.contact(2)?.name)
    }

    @Test fun ambiguousNamesAreLeftToTheCaregiver() {
        val other = "77777777-7777-4777-8777-777777777777"
        // Two keys named Lisa, one of them already linked: an invitation for "Lisa" could be for either.
        val twoKeys = CallSlots()
        twoKeys.setContact(phoneKey("Lisa"), 2)
        twoKeys.setContact(CallContact("Lisa", NativeCall("other", VOICE), familyMemberID = other), 3)
        twoKeys.reconcile(snapshot(invitations = listOf(invitation(lisaInvite, "Lisa")),
            people = listOf(member(other, "88888888-8888-4888-8888-888888888888", invited = "Lisa", joinedAt = now - 60))))
        assertNull(twoKeys.contact(2)?.invitationID)
        // Two invitations named Lisa.
        val oneKey = CallSlots()
        oneKey.setContact(phoneKey("Lisa"), 2)
        oneKey.reconcile(snapshot(invitations = listOf(invitation(lisaInvite, "Lisa"), invitation(other, "lisa"))))
        assertNull(oneKey.contact(2)?.invitationID)
    }

    @Test fun keysAlreadyWaitingOrLinkedKeepTheirOwnInvitation() {
        val own = "99999999-9999-4999-8999-999999999999"
        val slots = CallSlots()
        slots.setContact(CallContact("", NativeCall("own", VOICE), invitationID = own, memberName = "Lisa"), 2)
        slots.setContact(phoneKey("Sam", room = "sam"), 3)
        slots.reconcile(snapshot(invitations = listOf(invitation(own, "Lisa"), invitation(lisaInvite, "Lisa"))))
        assertEquals(own, slots.contact(2)?.invitationID, "A key's own open invitation stays")
        assertNull(slots.contact(3)?.invitationID)
        slots.reconcile(snapshot(invitations = listOf(invitation(own, "Sam"))))
        assertNull(slots.contact(3)?.invitationID, "An invitation already on a key stays there")
    }

    @Test fun familyPhonesLeaveTheKeypadAlone() {
        val slots = CallSlots()
        slots.setContact(phoneKey("Lisa"), 2)
        slots.reconcile(snapshot(invitations = listOf(invitation(lisaInvite, "Lisa")), role = "family"))
        assertNull(slots.contact(2)?.invitationID)
    }

    /** Hand-linking a key drops the previous person's photo. Following an invitation has to do the same, or the key
     * shows someone who left while it waits for the new person. */
    @Test fun aKeyThatFollowsSomeoneNewDropsThePreviousPersonsPhoto() = withStore { _, store ->
        val photo = "dad's photo".toByteArray()
        val keypad = "keypad photo".toByteArray()
        store.familyMembers.add(photo)
        val gone = "44444444-4444-4444-8444-444444444444"
        val expired = "33333333-3333-4333-8333-333333333333"
        val dadInvite = "66666666-6666-4666-8666-666666666666"
        val slots = CallSlots()
        slots.setContact(CallContact("", NativeCall("dad", VOICE), familyMemberID = gone, invitationID = expired, memberName = "Dad", photoData = keypad), 3)
        slots.reconcile(snapshot(people = listOf(member(gone, expired, invited = "Dad", joinedAt = now - 60, photoID = ContactPhotoStore.id(photo)))), store.familyMembers)
        assertEquals(ContactPhotoStore.id(photo), slots.contact(3)?.memberPhotoID)
        assertContentEquals(keypad, slots.contact(3)?.customPhotoData)

        slots.reconcile(snapshot(invitations = listOf(invitation(dadInvite, "Dad"))), store.familyMembers)
        val followed = slots.contact(3)!!
        assertEquals(dadInvite, followed.invitationID)
        assertNull(followed.familyMemberID)
        assertNull(followed.memberPhotoID, "The previous person's photo must not stay on a key that picked up someone else")
        assertContentEquals(keypad, followed.customPhotoData, "The caregiver's own photo of the key stays")
    }

    @Test fun anInvitationSentAgainStillLinksWhoeverJoins() {
        val again = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
        // The key took up the first invitation, and the caregiver sent another for Lisa. She joins with the second.
        val followed = CallSlots()
        followed.setContact(phoneKey("Lisa"), 2)
        followed.reconcile(snapshot(invitations = listOf(invitation(lisaInvite, "Lisa"))))
        assertEquals(lisaInvite, followed.contact(2)?.invitationID)
        followed.reconcile(snapshot(invitations = listOf(invitation(lisaInvite, "Lisa"), invitation(again, "Lisa"))))
        assertEquals(lisaInvite, followed.contact(2)?.invitationID, "The key keeps its own invitation while both are open")
        followed.reconcile(snapshot(invitations = listOf(invitation(lisaInvite, "Lisa")),
            people = listOf(member(lisa, again, invited = "Lisa", joinedAt = now - 60))))
        assertEquals(lisa, followed.contact(2)?.familyMemberID)
        assertEquals(again, followed.contact(2)?.invitationID)
        // Two invitations for Lisa were open before the key was saved. It waits, then takes whichever she accepted.
        val waiting = CallSlots()
        waiting.setContact(phoneKey("Lisa"), 2)
        waiting.reconcile(snapshot(invitations = listOf(invitation(lisaInvite, "Lisa"), invitation(again, "Lisa"))))
        assertNull(waiting.contact(2)?.invitationID)
        waiting.reconcile(snapshot(invitations = listOf(invitation(again, "Lisa")),
            people = listOf(member(lisa, lisaInvite, invited = "Lisa", joinedAt = now - 60))))
        assertEquals(lisa, waiting.contact(2)?.familyMemberID)
        // Two people who joined as Lisa are left to the caregiver.
        val two = CallSlots()
        two.setContact(phoneKey("Lisa"), 2)
        two.reconcile(snapshot(people = listOf(member(lisa, lisaInvite, invited = "Lisa", joinedAt = now - 60),
            member("bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb", again, invited = "lisa", joinedAt = now - 30))))
        assertNull(two.contact(2)?.familyMemberID)
    }

    @Test fun namesMatchWithoutCaseAccentsOrExtraSpaces() {
        assertEquals(CallSlots.matchingName("lisa chen"), CallSlots.matchingName("  Lísa   Chen "))
        assertNotEquals(CallSlots.matchingName("Lisa"), CallSlots.matchingName("Lisa Chen"))
        assertEquals("家駿", CallSlots.matchingName("家駿"))
        // The same list as iOS's test, so a name matches on either bedside.
        for ((name, folded) in listOf("Straße" to "strasse", "STRASSE" to "strasse", "Lisa\u00A0Chen" to "lisa chen", "İsmail" to "ismail",
            "ﬁona" to "fiona", "Zoë\tO’Neil" to "zoe o’neil", "Ｌｉｓａ" to "ｌｉｓａ", "GROẞ" to "gross", "Işıl" to "isıl",
            "Søren" to "søren", "Łukasz" to "łukasz")) {
            assertEquals(folded, CallSlots.matchingName(name), name)
        }
    }
}
