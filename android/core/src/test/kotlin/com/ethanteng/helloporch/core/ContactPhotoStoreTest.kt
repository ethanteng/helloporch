package com.ethanteng.helloporch.core

import com.ethanteng.helloporch.core.ModelFixtures.withStore
import java.io.File
import java.time.Clock
import java.time.Duration
import java.time.Instant
import java.time.ZoneOffset
import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertFails
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class ContactPhotoStoreTest {
    @Test fun twelveLargePhotosKeepSettingsSmallAndLoadWithoutOpeningImages() = withStore { settings, store ->
        val slots = CallSlots()
        val call = NativeCall("test", NativeCall.Mode.VIDEO)
        for ((index, digit) in CallSlots.digits.withIndex()) {
            slots.setContact(CallContact("Person $digit", call, buttonColorHex = "FFCC00", photoData = ByteArray(900_000) { index.toByte() }), digit)
        }
        slots.save(settings, store)
        val encoded = assertNotNull(settings.getString("porch.slots.v2"))
        assertTrue(encoded.length < 10_000, "Frequent polling/keypad reads must only decode metadata")
        assertFalse(encoded.contains("photoData"))
        val restored = CallSlots.load(settings, store)
        assertEquals(slots, restored, "Inline and file-backed contacts compare by stable photo identity")
        assertEquals(CallSlots.count, store.directory.listFiles()?.size)
        assertEquals(900_000, restored.contact(1)?.photoData?.size)

        val moved = File(store.directory.path + ".unavailable")
        assertTrue(store.directory.renameTo(moved))
        // Files unavailable: metadata and validation still work, photos load
        // lazily and fall back to the name when a screen asks for an image.
        repeat(10) {
            val reloaded = CallSlots.load(settings, store)
            assertEquals(slots, reloaded)
            for (digit in CallSlots.digits) reloaded.setContact(reloaded.contact(digit), digit)
            assertEquals(slots, reloaded)
            assertNull(reloaded.contact(1)?.photoData)
        }
    }

    @Test fun photoWriteFailureDoesNotReplaceSavedSettings() = withStore { settings, store ->
        CallSlots().save(settings, store)
        val original = settings.getString("porch.slots.v2")
        val originalSymbols = settings.getString("porch.slots.v2.symbols")
        // A file in place of the directory simulates an unwritable store.
        store.directory.writeBytes(byteArrayOf(1))
        val changed = CallSlots()
        changed.setContact(CallContact("David", NativeCall("test", NativeCall.Mode.VOICE), photoData = byteArrayOf(1, 2, 3)), 1)
        assertFails { changed.save(settings, store) }
        assertEquals(original, settings.getString("porch.slots.v2"))
        assertEquals(originalSymbols, settings.getString("porch.slots.v2.symbols"))
    }

    @Test fun failedStarPhotoDoesNotCommitDigitEditsInTheSameSave() = withStore { settings, store ->
        CallSlots().save(settings, store)
        val original = settings.getString("porch.slots.v2")
        val originalSymbols = settings.getString("porch.slots.v2.symbols")
        store.directory.writeBytes(byteArrayOf(1))
        val changed = CallSlots()
        changed.setContact(CallContact("David", NativeCall("test", NativeCall.Mode.VOICE)), 1)
        changed.setContact(CallContact("Mei", NativeCall("star", NativeCall.Mode.VOICE), photoData = byteArrayOf(1, 2, 3)), CallSlots.star)
        assertFails { changed.save(settings, store) }
        assertEquals(original, settings.getString("porch.slots.v2"), "A photo failure on * must not commit the other keys")
        assertEquals(originalSymbols, settings.getString("porch.slots.v2.symbols"))
    }

    @Test fun invalidReferencesCannotReadOutsidePhotoDirectory() = withStore { _, store ->
        for (id in listOf("../private", "a".repeat(63), "z".repeat(64))) {
            assertNull(store.data(id))
            assertFailsWith<ValidationException>(id) { ContactPhoto(id, store) }
        }
    }

    @Test fun pruningRetainsReferencedAndRecentlyReplacedPhotos() = withStore { _, store ->
        val active = ContactPhoto(byteArrayOf(1))
        val orphan = ContactPhoto(byteArrayOf(2))
        val recent = ContactPhoto(byteArrayOf(3))
        for (photo in listOf(active, orphan, recent)) photo.persist(store)
        for (photo in listOf(active, orphan)) {
            assertTrue(File(store.directory, "${photo.id}.jpg").setLastModified(System.currentTimeMillis() - 172_800_000))
        }
        store.prune(keeping = setOf(active.id))
        assertNotNull(store.data(active.id)); assertNotNull(store.data(recent.id))
        assertNull(store.data(orphan.id))
    }

    @Test fun pruningGoesByTheStoresClock() = withStore { _, store ->
        val photo = byteArrayOf(4)
        store.add(photo)
        val tomorrow = ContactPhotoStore(store.directory, Clock.fixed(Instant.now().plus(Duration.ofHours(23)), ZoneOffset.UTC))
        tomorrow.prune(keeping = emptySet())
        assertContentEquals(photo, store.data(ContactPhotoStore.id(photo)), "a day hasn't passed")
        val later = ContactPhotoStore(store.directory, Clock.fixed(Instant.now().plus(Duration.ofHours(25)), ZoneOffset.UTC))
        later.prune(keeping = emptySet())
        assertNull(store.data(ContactPhotoStore.id(photo)))
    }
}
