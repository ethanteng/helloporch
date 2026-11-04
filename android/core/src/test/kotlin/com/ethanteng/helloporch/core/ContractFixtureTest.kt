package com.ethanteng.helloporch.core

import java.io.File
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

/** The server's own responses, saved by tests/contract-fixtures.test.mjs. PorchCore's tests decode the same files, so a
 * server change that breaks either app fails CI. */
class ContractFixtureTest {
    private fun fixture(name: String): JsonObject =
        PorchJson.parseToJsonElement(File(System.getProperty("porch.fixtures"), "$name.json").readText()).jsonObject
    private fun snapshot(name: String) = PorchJson.decodeFromJsonElement(FamilySnapshot.serializer(), fixture(name).getValue("state"))

    @Test fun everySavedSnapshotDecodes() {
        val bedside = snapshot("bedside-poll")
        assertEquals(PorchExperience.BEDSIDE, bedside.me.role)
        assertEquals(listOf("Ethan" to "ios", "Lee" to "android"), bedside.people.map { it.name to it.platform })
        assertEquals(listOf("Sam"), bedside.invitations?.map { it.name })
        val family = snapshot("family-poll")
        assertEquals(true, family.me.caregiver); assertNull(family.call)
        val ringing = snapshot("family-incoming-call")
        assertEquals("pending", ringing.call?.state); assertEquals("Mom", ringing.call?.callerName)
        // An answered call has no time limit: Number.MAX_SAFE_INTEGER, more than 32 bits.
        val answered = snapshot("family-answered-call")
        assertEquals("accepted", answered.call?.state); assertEquals(9007199254740991L, answered.call?.expiresAt)
    }

    @Test fun caregiverStateAndErrorsDecode() {
        val response = fixture("caregiver-admin")
        PorchJson.decodeFromJsonElement(FamilySnapshot.serializer(), response.getValue("state"))
        val admin = PorchJson.decodeFromJsonElement(FamilyAdminState.serializer(), response.getValue("admin"))
        assertEquals(listOf("Ethan", "Lee"), admin.people.map { it.name })
        assertEquals("Another call is already in progress.", fixture("error-busy").getValue("error").jsonPrimitive.content)
    }
}
