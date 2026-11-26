package com.ethanteng.helloporch.core

import com.ethanteng.helloporch.core.ModelFixtures.person
import com.ethanteng.helloporch.core.ModelFixtures.snapshot
import com.ethanteng.helloporch.core.ModelFixtures.uuid
import com.ethanteng.helloporch.core.ModelFixtures.withStore
import com.ethanteng.helloporch.core.NativeCall.Mode.VIDEO
import com.ethanteng.helloporch.core.NativeCall.Mode.VOICE
import java.time.Clock
import java.time.Duration
import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject

/** A key that rings Ethan and David at once, as iOS's GroupKeysTests check it. */
class GroupKeysTest {
    private val ethan = "11111111-1111-4111-8111-111111111111"
    private val david = "22222222-2222-4222-8222-222222222222"

    private fun kids(name: String = "", photo: ByteArray? = null) =
        CallGroup(name, listOf(ethan, david), listOf("Ethan", "David"), VIDEO, buttonColorHex = "1565c0", photoData = photo)

    private fun lisa() = CallContact("Lisa", NativeCall("lisa", VOICE))

    @Test fun aGroupGoesByItsPeoplesNamesUnlessTheCaregiverNamesIt() {
        assertEquals("Ethan & David", kids().name)
        assertEquals("Kids", kids(name = "  Kids ").name)
        assertEquals("1565C0", kids().buttonColorHex)
        val contact = kids(name = "Kids").callContact
        assertEquals("Kids", contact.name); assertEquals(VIDEO, contact.nativeCall.mode); assertNull(contact.phoneNumber)
        assertEquals("1565C0", contact.buttonColorHex)
        assertContentEquals(byteArrayOf(7, 8), kids(photo = byteArrayOf(7, 8)).callContact.photoData, "The call screen shows the key's photo")
        assertFailsWith<ValidationException> { CallGroup("", listOf(ethan, ethan), listOf("Ethan", "Ethan"), VOICE) }
        assertFailsWith<ValidationException> { CallGroup("", listOf(ethan, david, uuid()), listOf("a", "b", "c"), VOICE) }
        assertFailsWith<ValidationException> { CallGroup("", emptyList(), emptyList(), VOICE) }
        assertFailsWith<ValidationException> { CallGroup("", listOf("ethan"), listOf("Ethan"), VOICE) }
        assertFailsWith<ValidationException> { CallGroup("", listOf(ethan, david), listOf("Ethan"), VOICE) }
        assertFailsWith<ValidationException> { kids(name = "x".repeat(81)) }
        assertFailsWith<ValidationException> { CallGroup("", listOf(ethan), listOf("Ethan"), VOICE, buttonColorHex = "blue") }
    }

    @Test fun twoLongNamesAreCutToFitTheCallScreenRatherThanFailing() {
        val long = CallGroup("", listOf(ethan, david), listOf("E".repeat(40), "\uD83D\uDC4B\uD83C\uDFFD".repeat(40)), VOICE)
        assertEquals(83, long.name.characterCount())
        assertEquals(80, long.callContact.name.characterCount())
        assertTrue(long.callContact.name.endsWith("\uD83D\uDC4B\uD83C\uDFFD"), "Characters, not code units, are cut")
    }

    @Test fun aGroupKeyReplacesWhatWasOnItAndAnythingElseReplacesTheGroup() {
        val slots = CallSlots()
        slots.setContact(lisa(), 3)
        slots.setGroup(kids(), 3)
        assertEquals(KeypadAction.GROUP, slots.action(3))
        assertNull(slots.contact(3)); assertEquals("Ethan & David", slots.group(3)?.name)
        assertEquals(listOf(3), slots.allGroups.map { it.first }); assertEquals(3, slots.digit(KeypadAction.GROUP))
        slots.setAction(KeypadAction.GROUP, 3)
        assertEquals(KeypadAction.GROUP, slots.action(3), "Choosing the group again keeps it")
        assertFailsWith<ValidationException>("A group needs its people") { slots.setAction(KeypadAction.GROUP, 4) }
        slots.setAction(KeypadAction.MESSAGES, 3)
        assertEquals(KeypadAction.MESSAGES, slots.action(3)); assertNull(slots.group(3))
        slots.setGroup(kids(), 3)
        slots.setContact(lisa(), 3)
        assertEquals(KeypadAction.PERSON, slots.action(3)); assertNull(slots.group(3))
        slots.setGroup(kids(), 3)
        slots.setGroup(null, 3)
        assertEquals(KeypadAction.UNASSIGNED, slots.action(3))
        assertFailsWith<ValidationException> { slots.setGroup(kids(), 12) }
    }

    @Test fun aCopyKeepsItsGroupsApart() {
        val slots = CallSlots()
        slots.setGroup(kids(), 2)
        val copy = slots.copy()
        assertEquals(slots, copy)
        copy.setGroup(kids(name = "Kids"), 2)
        assertEquals("Ethan & David", slots.group(2)?.name, "Changing the copy leaves the original")
        assertFalse(slots == copy)
    }

    @Test fun groupsAreSavedBesideTheKeypadSoAnOlderBuildSeesAnEmptyKey() = withStore { settings, store ->
        val slots = CallSlots()
        slots.setContact(lisa(), 1)
        slots.setGroup(kids(name = "Kids", photo = ByteArray(2000) { 4 }), CallSlots.star)
        slots.save(settings, store)
        val symbols = PorchJson.parseToJsonElement(assertNotNull(settings.getString("porch.slots.v2.symbols"))).jsonArray
        assertEquals("\"person\"", symbols.first().jsonObject["action"].toString(), "An older build reads * as an empty key")
        assertNull(symbols.first().jsonObject["contact"])
        assertFalse(assertNotNull(settings.getString("porch.slots.v2")).contains("group"))
        val groups = assertNotNull(settings.getString("porch.slots.v2.groups"))
        assertTrue(groups.contains("\"*\"")); assertFalse(groups.contains("photoData"))
        val restored = CallSlots.load(settings, store)
        assertEquals(slots, restored)
        assertEquals("Kids", restored.group(CallSlots.star)?.name)
        assertEquals(2000, restored.group(CallSlots.star)?.photoData?.size, "Saving keeps the group's photo")
        assertEquals("Lisa", restored.contact(1)?.name)
        // Taking the group off clears what was saved for it.
        val cleared = restored.copy()
        cleared.setGroup(null, CallSlots.star)
        cleared.save(settings, store)
        assertNull(settings.getString("porch.slots.v2.groups"))
        assertNull(CallSlots.load(settings, store).group(CallSlots.star))
        CallSlots.forget(settings, store)
        assertNull(settings.getString("porch.slots.v2.groups"))
    }

    /** What iOS saves, so a keypad can move between an iPad and a tablet. */
    @Test fun groupsReadAsTheIPadSavesThem() = withStore { settings, store ->
        CallSlots().save(settings, store)
        settings.putString("porch.slots.v2.groups",
            """{"4":{"customName":"","memberIDs":["$ethan","$david"],"memberNames":["Ethan","David"],"mode":"voice","buttonColorHex":"00838F"}}""")
        val group = assertNotNull(CallSlots.load(settings, store).group(4))
        assertEquals("Ethan & David", group.name); assertEquals(VOICE, group.mode); assertEquals("00838F", group.buttonColorHex)
    }

    @Test fun aGroupOnAKeyThatIsSavedAsSomethingElseCannotBeRead() = withStore { settings, store ->
        val slots = CallSlots()
        slots.setContact(lisa(), 1)
        slots.save(settings, store)
        settings.putString("porch.slots.v2.groups",
            """{"1":{"customName":"","memberIDs":["$ethan","$david"],"memberNames":["Ethan","David"],"mode":"video"}}""")
        assertFailsWith<ValidationException> { CallSlots.load(settings, store) }
        // Nor can one Porch wouldn't take, or a key that isn't one.
        for (saved in listOf("""{"2":{"customName":"","memberIDs":[],"memberNames":[],"mode":"video"}}""",
            """{"A":{"customName":"","memberIDs":["$ethan"],"memberNames":["Ethan"],"mode":"video"}}""", "[]")) {
            settings.putString("porch.slots.v2.groups", saved)
            assertFailsWith<ValidationException>(saved) { CallSlots.load(settings, store) }
        }
        // A slot saved as a group, which Porch never saves.
        settings.remove("porch.slots.v2.groups")
        settings.putString("porch.slots.v2", (listOf("""{"action":"group"}""") + List(9) { """{"action":"person"}""" }).joinToString(",", "[", "]"))
        assertFailsWith<ValidationException> { CallSlots.load(settings, store) }
    }

    @Test fun groupsShowTheirPeoplesCurrentNames() {
        val slots = CallSlots()
        slots.setGroup(kids(), 2)
        slots.setGroup(kids(name = "Kids"), 4)
        slots.reconcile(snapshot(listOf(person(ethan, "Ethan T"), person(david, "Dave"))), ModelFixtures.noPhotos)
        assertEquals("Ethan T & Dave", slots.group(2)?.name)
        assertEquals("Kids", slots.group(4)?.name)
        assertEquals(listOf("Ethan T", "Dave"), slots.group(4)?.memberNames)
        // Someone no longer on Porch keeps the last name Porch showed.
        slots.reconcile(snapshot(listOf(person(ethan, "Ethan"))), ModelFixtures.noPhotos)
        assertEquals("Ethan & Dave", slots.group(2)?.name)
        assertEquals(listOf(ethan, david), slots.group(2)?.memberIDs)
    }

    @Test fun savingTheKeypadKeepsAGroupsPhoto() = withStore { settings, store ->
        val slots = CallSlots()
        slots.setGroup(kids(photo = byteArrayOf(1, 2, 3)), 5)
        slots.setContact(CallContact("Lisa", NativeCall("lisa", VOICE), photoData = byteArrayOf(9)), 6)
        slots.save(settings, store)
        val id = assertNotNull(slots.group(5)?.photoID)
        // Two days on, saving prunes every photo no key uses: Lisa's, once she's off the keypad, but not the group's.
        val later = ContactPhotoStore(store.directory, Clock.offset(Clock.systemUTC(), Duration.ofDays(2)))
        val loaded = CallSlots.load(settings, later)
        val lisa = assertNotNull(loaded.contact(6)?.photoID)
        loaded.setContact(null, 6)
        loaded.save(settings, later)
        assertTrue(store.contains(id)); assertFalse(store.contains(lisa))
        assertContentEquals(byteArrayOf(1, 2, 3), CallSlots.load(settings, store).group(5)?.photoData)
    }

    @Test fun updatingKeepsThePhotoUnlessReplaced() {
        val group = kids(photo = byteArrayOf(1))
        val renamed = group.updating(name = "Boys", mode = VOICE)
        assertEquals("Boys", renamed.name); assertEquals(VOICE, renamed.mode); assertContentEquals(byteArrayOf(1), renamed.photoData)
        assertNull(group.updatingPhoto(null).photoData)
        assertNull(group.updating(buttonColorHex = null).buttonColorHex)
        assertEquals("David", group.updating(memberIDs = listOf(david), memberNames = listOf("David")).name)
    }

    @Test fun thePreviewSaysWhoAGroupKeyWouldCall() {
        val slots = CallSlots()
        slots.setGroup(kids(name = "Kids"), 5)
        val result = KeypadActionPreview(slots).receive("5")
        assertEquals(KeypadActionPreview.Result.Kind.PERSON, result.kind); assertEquals("Would call Kids", result.title)
        assertEquals(KeypadAction.GROUP, result.action)
    }
}
