package com.ethanteng.helloporch.core

import com.ethanteng.helloporch.core.FakeTransport.Companion.failure
import com.ethanteng.helloporch.core.FakeTransport.Companion.ok
import com.ethanteng.helloporch.core.TestFamilies.family
import java.security.MessageDigest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertNotEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

class PorchDeviceTest {
    /** Records how each secret was saved, which [MemorySecretStore] doesn't. */
    private class RecordingSecrets : SecretStore {
        private val store = MemorySecretStore()
        val access = mutableMapOf<String, SecretStore.Access>()
        override fun read(account: String) = store.read(account)
        override fun write(account: String, value: ByteArray?, access: SecretStore.Access) {
            store.write(account, value, access)
            this.access[account] = access
        }
    }

    private val settings = MemorySettings()
    private val secrets = RecordingSecrets()
    private fun device(canBeBedside: Boolean = false) = PorchDevice(settings, secrets, TestFamilies.origin, canBeBedside)

    @Test fun aTabletIsTheBedsideAndAPhoneIsFamilyUntilToldOtherwise() {
        assertEquals(PorchExperience.BEDSIDE, device(canBeBedside = true).experience)
        val phone = device()
        assertEquals(PorchExperience.FAMILY, phone.experience)
        phone.experience = PorchExperience.BEDSIDE
        assertEquals("bedside", settings.getString("porch.experience"))
        assertEquals(PorchExperience.BEDSIDE, device().experience)
        settings.putString("porch.experience", "kiosk")
        assertEquals(PorchExperience.FAMILY, device().experience, "a mode it doesn't know reads as the default")
    }

    @Test fun onlyADeviceWithNothingSetUpAsksWhichItIs() {
        assertTrue(device().needsWelcome)
        device().save(family(1))
        assertFalse(device().needsWelcome, "a pairing")
        device().removeFamily(family(1))
        assertTrue(device().needsWelcome)
        device().save(TestFamilies.bedside(2))
        assertFalse(device().needsWelcome, "a bedside pairing")
        secrets.write("porch.family.bedside", null)
        secrets.write("porch.contact-setup-code", "123456".encodeToByteArray())
        assertFalse(device().needsWelcome, "a caregiver PIN")
        secrets.write("porch.contact-setup-code", null)
        device().saveActivation("https://helloporch.store/setup#code=${"a".repeat(64)}")
        assertFalse(device().needsWelcome, "a setup link")
        device().saveActivation(null)
        assertTrue(device().needsWelcome)
        CallSlots().save(settings, ModelFixtures.noPhotos)
        assertFalse(device().needsWelcome, "a keypad")
        settings.remove("porch.slots.v2")
        device().experience = PorchExperience.FAMILY
        assertFalse(device().needsWelcome, "a mode it was told")
    }

    @Test fun aSetUpDeviceWritesDownItsMode() {
        device(canBeBedside = true).rememberExperience()
        assertNull(settings.getString("porch.experience"), "nothing is set up")
        device(canBeBedside = true).save(TestFamilies.bedside(1))
        device(canBeBedside = true).rememberExperience()
        assertEquals("bedside", settings.getString("porch.experience"))
        device(canBeBedside = true).experience = PorchExperience.FAMILY
        device(canBeBedside = true).rememberExperience()
        assertEquals("family", settings.getString("porch.experience"), "a mode already written down stays")
    }

    /** A phone's families stay in the order it joined them, and rejoining one keeps its place. Pairings can be read
     * after the first unlock, so a call can ring on a locked phone that just restarted. */
    @Test fun pairingsAreKeptInTheOrderTheyJoined() {
        val phone = device()
        phone.save(family(1)); phone.save(family(2)); phone.save(family(3))
        val renewed = FamilyCredential("https://other.example", family(2).credential, PorchExperience.FAMILY)
        phone.save(renewed)
        assertEquals(listOf(family(1), renewed, family(3)), device().families)
        assertEquals(SecretStore.Access.AFTER_FIRST_UNLOCK, secrets.access["porch.family.families"])
        assertNull(phone.credential(PorchExperience.BEDSIDE))

        phone.save(TestFamilies.bedside(9))
        assertEquals(TestFamilies.bedside(9), device().credential(PorchExperience.BEDSIDE))
        assertEquals(SecretStore.Access.AFTER_FIRST_UNLOCK, secrets.access["porch.family.bedside"])
        assertEquals(3, device().families.size, "the bedside pairing isn't a family")
        // The same shapes as the iOS Keychain items.
        val saved = PorchJson.parseToJsonElement(secrets.read("porch.family.bedside")!!.decodeToString()).jsonObject
        assertEquals(setOf("origin", "credential", "role"), saved.keys)
        assertEquals("bedside", saved.getValue("role").jsonPrimitive.content)
    }

    @Test fun pairingsItCantReadAreTreatedAsNone() {
        secrets.write("porch.family.families", "not json".encodeToByteArray())
        secrets.write("porch.family.bedside", "{}".encodeToByteArray())
        assertEquals(emptyList(), device().families)
        assertNull(device().credential(PorchExperience.BEDSIDE))
    }

    @Test fun theScreensShowTheChosenFamilyOrElseTheFirst() {
        val phone = device()
        assertNull(phone.currentFamily)
        phone.save(family(1)); phone.save(family(2))
        assertEquals(family(1), phone.currentFamily)
        phone.select(family(2))
        assertEquals(family(2), device().credential(PorchExperience.FAMILY))
        assertEquals(family(2).deviceID, settings.getString("porch.family.current"))
        phone.removeFamily(family(2))
        assertEquals(family(1), phone.currentFamily)
        assertEquals(family(1), phone.family(memberID = family(1).deviceID))
        assertNull(phone.family(memberID = family(2).deviceID))
        assertNull(phone.family(memberID = null))
    }

    @Test fun aNicknameIsTrimmedAndBlankRemovesIt() {
        val phone = device()
        phone.save(family(1))
        phone.setNickname("  Sarah's parents \n", family(1))
        assertEquals("Sarah's parents", phone.nickname(family(1)))
        assertEquals(ModelFixtures.json(mapOf(family(1).deviceID to "Sarah's parents")), PorchJson.parseToJsonElement(settings.getString("porch.family.nicknames")!!))
        phone.setNickname("x".repeat(79) + "👨‍👩‍👧" + "tail", family(1))
        assertEquals("x".repeat(79) + "👨‍👩‍👧", phone.nickname(family(1)), "80 characters as a person counts them")
        phone.setNickname("   ", family(1))
        assertNull(phone.nickname(family(1)))
        phone.setNickname("Mom", family(1)); phone.setNickname(null, family(1))
        assertNull(phone.nickname(family(1)))
    }

    /** Two sets of parents are often both "Mom". The family joined later is numbered until the phone names one. */
    @Test fun familiesAreNamedByNicknameOrHouseholdAndNumberedWhenTheyMatch() {
        val phone = device()
        phone.save(family(1)); phone.save(family(2)); phone.save(family(3))
        phone.noteHousehold(TestFamilies.state(TestFamilies.snapshot(family(1).deviceID, householdID = "a", householdName = "Mom")), family(1))
        phone.noteHousehold(TestFamilies.state(TestFamilies.snapshot(family(2).deviceID, householdID = "b", householdName = "mom")), family(2))
        assertEquals(listOf("Mom", "mom 2", null), phone.families.map(phone::familyName))
        assertEquals("mom", phone.unnumberedName(family(2)))
        phone.setNickname("Sarah's parents", family(2))
        assertEquals(listOf("Mom", "Sarah's parents", null), phone.families.map(phone::familyName))
        assertNull(phone.familyName(family(4)), "a family the phone isn't in, with nothing known about it")
    }

    @Test fun theHouseholdIsNotedUntilTheFamilyIsRemoved() {
        val phone = device()
        phone.save(family(1)); phone.save(family(2))
        assertNull(phone.householdID(family(1)))
        phone.noteHousehold(TestFamilies.state(TestFamilies.snapshot(family(1).deviceID, householdID = "home", householdName = "Lee family")), family(1))
        phone.setNickname("Grandma", family(1)); phone.setNickname("Dad", family(2))
        assertEquals("home", phone.householdID(family(1)))
        assertEquals(ModelFixtures.json(mapOf(family(1).deviceID to mapOf("id" to "home", "name" to "Lee family"))),
            PorchJson.parseToJsonElement(settings.getString("porch.family.households")!!))
        phone.removeFamily(family(1))
        assertEquals(listOf(family(2)), phone.families)
        assertNull(phone.householdID(family(1)))
        assertNull(phone.nickname(family(1)))
        assertEquals("Dad", phone.nickname(family(2)), "other families keep their names")
    }

    /** Claiming the same invitation again, such as after a dropped connection, must offer the same identity: the
     * server accepts a claim only once, from one device. */
    @Test fun aPendingIdentityIsKeptForItsServerAndInvitation() {
        val phone = device()
        val first = phone.pending(PorchExperience.FAMILY, TestFamilies.origin, "c".repeat(64))
        assertTrue(Regex("^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\\.[0-9a-f]{64}$").matches(first.credential))
        assertEquals(PorchExperience.FAMILY, first.role); assertEquals(TestFamilies.origin, first.origin)
        assertEquals(first, device().pending(PorchExperience.FAMILY, TestFamilies.origin, "c".repeat(64)))

        val scope = MessageDigest.getInstance("SHA-256").digest((TestFamilies.origin + "c".repeat(64)).encodeToByteArray()).joinToString("") { "%02x".format(it) }
        val saved = PorchJson.parseToJsonElement(secrets.read("porch.family.pending.family")!!.decodeToString()).jsonObject
        assertEquals(scope, saved.getValue("scope").jsonPrimitive.content)
        assertEquals(first, PorchJson.decodeFromJsonElement(FamilyCredential.serializer(), saved.getValue("profile")))
        assertEquals(SecretStore.Access.WHEN_UNLOCKED, secrets.access["porch.family.pending.family"])

        val bedside = phone.pending(PorchExperience.BEDSIDE, TestFamilies.origin, "c".repeat(64))
        assertNotEquals(first.deviceID, bedside.deviceID, "each role keeps its own")
        assertEquals(first, phone.pending(PorchExperience.FAMILY, TestFamilies.origin, "c".repeat(64)))
        val another = phone.pending(PorchExperience.FAMILY, TestFamilies.origin, "d".repeat(64))
        assertNotEquals(first.credential, another.credential, "a new invitation")
        assertNotEquals(another.credential, phone.pending(PorchExperience.FAMILY, "https://other.example", "d".repeat(64)).credential, "another server")
        assertNotEquals(first.credential, phone.pending(PorchExperience.FAMILY, TestFamilies.origin, "c".repeat(64)).credential,
            "only the latest invitation is kept")
    }

    @Test fun aRegistrationSplitsTheCredential() {
        val profile = family(5)
        assertEquals(mapOf("deviceID" to JsonPrimitive(profile.deviceID), "deviceSecret" to JsonPrimitive("%064x".format(5))), device().registration(profile))
    }

    @Test fun theSetupLinkIsKeptUntilCleared() {
        val tablet = device(canBeBedside = true)
        assertNull(tablet.bedsideActivation)
        tablet.saveActivation("https://helloporch.store/setup#code=${"a".repeat(64)}")
        assertEquals("https://helloporch.store/setup#code=${"a".repeat(64)}", device().bedsideActivation)
        assertEquals(SecretStore.Access.WHEN_UNLOCKED, secrets.access["porch.bedside.activation"])
        tablet.saveActivation(null)
        assertNull(tablet.bedsideActivation)
        assertEquals(0, secrets.read("porch.bedside.activation")?.size, "cleared as iOS clears it, by saving nothing")
    }

    /** Its old household stops ringing it. One that no longer knows it has nothing left to stop. */
    @Test fun leavingTheBedsideUnregistersItsAlerts() = runTest {
        val transport = FakeTransport()
        val tablet = device(canBeBedside = true)
        val bedside = TestFamilies.bedside(1)
        tablet.leaveBedside(bedside) { FamilyService(it, transport) }
        assertEquals(listOf("registerVoIP", "registerAlerts"), transport.requests.map { it.action })
        assertTrue(transport.requests.all { it["token"] == JsonNull && it.deviceID == bedside.deviceID })

        for (status in listOf(401, 403, 404, 410)) {
            transport.requests.clear()
            transport.reply = { failure(status, "Gone.") }
            tablet.leaveBedside(bedside) { FamilyService(it, transport) }
            assertEquals(listOf("registerVoIP"), transport.requests.map { it.action })
        }

        transport.reply = { if (it.action == "registerVoIP") ok() else failure(500, "Try again.") }
        val failed = assertFailsWith<FamilyServiceException> { tablet.leaveBedside(bedside) { FamilyService(it, transport) } }
        assertEquals(500, failed.status)
    }
}
