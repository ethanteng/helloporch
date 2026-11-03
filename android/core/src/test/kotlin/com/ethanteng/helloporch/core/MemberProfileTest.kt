package com.ethanteng.helloporch.core

import com.ethanteng.helloporch.core.ModelFixtures.json
import com.ethanteng.helloporch.core.ModelFixtures.withStore
import com.ethanteng.helloporch.core.NativeCall.Mode.VIDEO
import com.ethanteng.helloporch.core.NativeCall.Mode.VOICE
import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

/** Keypad contacts for Porch family members go by the name and photo the member chose (or a caregiver
 * chose for everyone) unless the caregiver typed a name or chose a photo for that key. */
class MemberProfileTest {
    private val member = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
    private val invitation = "cccccccc-cccc-4ccc-8ccc-cccccccccccc"

    private fun snapshot(people: List<Any?>, invitations: List<Any?> = emptyList()) =
        ModelFixtures.snapshot(people, extra = mapOf("invitations" to invitations))

    private fun person(name: String, photoID: String? = null) = ModelFixtures.person(member, name, invitationID = invitation, photoID = photoID)

    private fun porchContact(name: String = "", photo: ByteArray? = null) =
        CallContact(name, NativeCall("paired", VIDEO), invitationID = invitation, memberName = "Ethan", photoData = photo)

    @Test fun unnamedContactFollowsTheInvitationThenTheMembersOwnNameAndPhoto() = withStore { settings, store ->
        val slots = CallSlots()
        slots.setContact(porchContact(), 1)
        assertEquals("Ethan", slots.contact(1)?.name)
        slots.reconcile(snapshot(emptyList(), listOf(mapOf("id" to invitation, "name" to "Ethan W", "expiresAt" to 9))), store.familyMembers)
        assertEquals("Ethan W", slots.contact(1)?.name, "the invitation's current name until it's accepted")

        val photo = "ethan's photo".toByteArray()
        val chosen = snapshot(listOf(person("Ethan T.", ContactPhotoStore.id(photo))))
        slots.reconcile(chosen, store.familyMembers)
        assertEquals("Ethan T.", slots.contact(1)?.name)
        assertEquals(member, slots.contact(1)?.familyMemberID)
        assertNull(slots.contact(1)?.photoData, "the photo shows once it has downloaded")
        store.familyMembers.add(photo)
        slots.reconcile(chosen, store.familyMembers)
        assertContentEquals(photo, slots.contact(1)?.photoData)
        assertNull(slots.contact(1)?.photoID, "the keypad's own photo stays empty")

        // Saved and reloaded, it still follows them, and saving never prunes their photo.
        slots.save(settings, store)
        val loaded = CallSlots.load(settings, store)
        assertEquals(slots, loaded)
        assertContentEquals(photo, loaded.contact(1)?.photoData)
        assertEquals("", loaded.contact(1)?.customName)

        // A replacement photo waits for its download; a removed one goes at once.
        val next = "a newer photo".toByteArray()
        loaded.reconcile(snapshot(listOf(person("Ethan T.", ContactPhotoStore.id(next)))), store.familyMembers)
        assertContentEquals(photo, loaded.contact(1)?.photoData)
        loaded.reconcile(snapshot(listOf(person("Ethan T."))), store.familyMembers)
        assertNull(loaded.contact(1)?.photoData)
        // Once they leave, the key keeps the name it last showed.
        loaded.reconcile(snapshot(emptyList()), store.familyMembers)
        assertEquals("Ethan T.", loaded.contact(1)?.name)
        assertNull(loaded.contact(1)?.familyMemberID)
    }

    /** An invitation created without a name keeps the name typed on the key, and that name gives way once they join. */
    @Test fun blankInvitationKeepsTheNameTypedForTheKeyUntilTheyJoin() = withStore { _, store ->
        val slots = CallSlots()
        slots.setContact(CallContact("", NativeCall("paired", VOICE), invitationID = invitation, memberName = "David"), 1)
        slots.reconcile(snapshot(emptyList(), listOf(mapOf("id" to invitation, "name" to "", "expiresAt" to 9))), store.familyMembers)
        assertEquals("David", slots.contact(1)?.name)
        assertEquals("", slots.contact(1)?.customName)
        slots.reconcile(snapshot(listOf(person("David Chen"))), store.familyMembers)
        assertEquals("David Chen", slots.contact(1)?.name)
        assertEquals("", slots.contact(1)?.customName)
    }

    @Test fun caregiversKeypadNameAndPhotoComeFirst() = withStore { _, store ->
        val theirs = "their photo".toByteArray()
        val keypad = "keypad photo".toByteArray()
        store.familyMembers.add(theirs)
        val slots = CallSlots()
        slots.setContact(porchContact(name = "Grandson", photo = keypad), 1)
        slots.reconcile(snapshot(listOf(person("Ethan T.", ContactPhotoStore.id(theirs)))), store.familyMembers)
        assertEquals("Grandson", slots.contact(1)?.name)
        assertContentEquals(keypad, slots.contact(1)?.photoData)
        assertEquals("Ethan T.", slots.contact(1)?.memberName)
        assertEquals(ContactPhotoStore.id(theirs), slots.contact(1)?.memberPhotoID)
    }

    @Test fun onlyPorchFamilyMembersCanGoWithoutAName() {
        val call = NativeCall("paired", VOICE)
        assertFailsWith<ValidationException> { CallContact(" ", call, phoneNumber = "+14155550123", memberName = "Ethan") }
        assertFailsWith<ValidationException> { CallContact("", call, invitationID = invitation) }
        assertEquals("Ethan", CallContact("", call, familyMemberID = member, memberName = " Ethan ").name)
    }

    @Test fun earlierSavedContactsKeepTheCaregiversName() = withStore { settings, store ->
        // Settings saved before members could choose their own names.
        val legacy = CallSlots.digits.map { digit ->
            if (digit == 1) mapOf("action" to "person", "contact" to mapOf("name" to "David", "address" to "", "nativeCall" to mapOf("room" to "paired", "mode" to "video"),
                "invitationID" to invitation))
            else mapOf("action" to if (digit == 0) "callControl" else if (digit == 9) "toggleVideo" else "person")
        }
        settings.putString("porch.slots.v2", json(legacy).toString())
        val slots = CallSlots.load(settings, store)
        slots.reconcile(snapshot(listOf(person("Ethan T."))), store.familyMembers)
        assertEquals("David", slots.contact(1)?.name)
        assertEquals("David", slots.contact(1)?.customName)
        // Anything reading new settings still finds a name for everyone.
        slots.setContact(porchContact(), 2)
        slots.save(settings, store)
        val saved = PorchJson.parseToJsonElement(assertNotNull(settings.getString("porch.slots.v2"))).jsonArray
        assertEquals("Ethan", saved[1].jsonObject["contact"]?.jsonObject?.get("name")?.jsonPrimitive?.content)
    }

    /** Caregiver settings change one detail of a key at a time, such as its color, and nothing else on it. */
    @Test fun updatingOneDetailKeepsTheRestOfTheKeyIncludingTheMembersPhoto() = withStore { _, store ->
        val photo = "ethan's photo".toByteArray()
        store.familyMembers.add(photo)
        val slots = CallSlots()
        slots.setContact(CallContact("Grandpa Joe", NativeCall("paired", VOICE), phoneNumber = "+14155550123", otherPhoneNumbers = listOf("+14155550199"),
            invitationID = invitation, memberName = "Ethan", buttonColorHex = "FFCC00"), 1)
        slots.reconcile(snapshot(listOf(person("Ethan", ContactPhotoStore.id(photo)))), store.familyMembers)
        val original = assertNotNull(slots.contact(1))
        assertContentEquals(photo, original.photoData)

        val video = original.updating(mode = VIDEO)
        assertEquals(VIDEO, video.nativeCall.mode)
        assertEquals("paired", video.nativeCall.room)
        assertEquals("Grandpa Joe", video.customName)
        assertEquals(listOf("+14155550123", "+14155550199"), video.phoneNumbers)
        assertEquals(member, video.familyMemberID)
        assertEquals("FFCC00", video.buttonColorHex)
        assertContentEquals(photo, video.photoData, "the member's photo stays on the key")

        // One name per family member: an empty name makes the key go by theirs.
        assertEquals("Ethan", original.updating(name = "").name)
        assertNull(original.updating(buttonColorHex = null).buttonColorHex)
        assertEquals("00AA00", original.updating(buttonColorHex = "00aa00").buttonColorHex)

        val own = "a key photo".toByteArray()
        val withPhoto = original.updatingPhoto(own)
        assertContentEquals(own, withPhoto.customPhotoData)
        assertContentEquals(own, withPhoto.photoData, "a key's own photo comes first")
        val cleared = withPhoto.updatingPhoto(null)
        assertNull(cleared.customPhotoData)
        assertContentEquals(photo, cleared.photoData, "back to the member's photo")
        assertFailsWith<ValidationException>("someone who isn't on Porch needs a name") {
            CallContact("David", NativeCall("phone", VOICE), phoneNumber = "+14155550123").updating(name = "")
        }
    }
}
