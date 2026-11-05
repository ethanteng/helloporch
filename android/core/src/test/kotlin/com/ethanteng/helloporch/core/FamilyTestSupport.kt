package com.ethanteng.helloporch.core

import java.io.File
import java.time.Instant
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.TestScope
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

/** A Porch server for tests: it records every request and answers with `reply`, which can suspend or throw as a real
 * connection would. `now` stamps each request, such as with a test's virtual time. */
internal class FakeTransport(
    private val now: () -> Long = { 0 },
    var reply: suspend (Request) -> TransportResponse = { ok() },
) : FamilyTransport {
    data class Request(val url: String, val headers: Map<String, String>, val body: JsonObject, val timeoutMillis: Long, val time: Long) {
        val action: String get() = body.getValue("action").jsonPrimitive.content
        /** The device the request is from, by its credential. */
        val deviceID: String? get() = headers["Authorization"]?.removePrefix("Bearer ")?.substringBefore('.')
        operator fun get(key: String): JsonElement? = body[key]
    }

    val requests = mutableListOf<Request>()
    fun requests(action: String) = requests.filter { it.action == action }

    override suspend fun post(url: String, headers: Map<String, String>, body: String, timeoutMillis: Long): TransportResponse {
        val request = Request(url, headers, PorchJson.parseToJsonElement(body).jsonObject, timeoutMillis, now())
        requests += request
        return reply(request)
    }

    companion object {
        fun ok(body: Map<String, Any?> = emptyMap()) = TransportResponse(200, ModelFixtures.json(body).toString())
        fun failure(status: Int, error: String? = null, errorCode: String? = null) =
            TransportResponse(status, ModelFixtures.json(listOfNotNull(error?.let { "error" to it }, errorCode?.let { "errorCode" to it }).toMap()).toString())
        fun fixture(name: String) = TransportResponse(200, File(System.getProperty("porch.fixtures"), "$name.json").readText())
    }
}

internal object TestFamilies {
    const val origin = "https://porch.example"

    /** A device's credential as the server issues it: a lowercase UUID, a dot, and 64 hex digits. */
    fun credential(number: Int) = "%08d-0000-4000-8000-000000000000.%064x".format(number, number)
    fun family(number: Int, origin: String = this.origin) = FamilyCredential(origin, credential(number), PorchExperience.FAMILY)
    fun bedside(number: Int) = FamilyCredential(origin, credential(number), PorchExperience.BEDSIDE)

    fun snapshot(me: String, role: String = "family", householdID: String = "home", householdName: String = "Pat",
        call: Map<String, Any?>? = null, extra: Map<String, Any?> = emptyMap()): Map<String, Any?> =
        mapOf("householdID" to householdID, "householdName" to householdName, "dropInEnabled" to false,
            "me" to mapOf("id" to me, "name" to "Ethan", "role" to role, "permissions" to mapOf("audio" to false, "video" to false), "online" to true),
            "people" to emptyList<Any?>(), "busy" to false, "serverTime" to 1, "call" to call) + extra

    fun call(state: String = "accepted", kind: String = "call", from: String = "a", to: String = "b") =
        mapOf("id" to "call-1", "from" to from, "to" to to, "mode" to "video", "kind" to kind, "state" to state,
            "createdAt" to 1, "expiresAt" to 2, "callerName" to "Mom")

    fun state(snapshot: Map<String, Any?>): FamilySnapshot = ModelFixtures.decoded(snapshot)
}

/** A device, its server and its coordinator, on a test's virtual time. */
@OptIn(ExperimentalCoroutinesApi::class)
internal class FamilyHarness(scope: TestScope, canBeBedside: Boolean = false) {
    val settings = MemorySettings()
    val secrets = MemorySecretStore()
    val device = PorchDevice(settings, secrets, TestFamilies.origin, canBeBedside)
    val transport = FakeTransport(now = { scope.testScheduler.currentTime })
    val attendance = AttendanceTracker { Instant.ofEpochMilli(scope.testScheduler.currentTime) }
    val caregiver = RemoteCaregiverSession { Instant.ofEpochMilli(scope.testScheduler.currentTime) }
    var receiving = true
    val changes = mutableListOf<FamilyLinks>()
    /** More work after each change, as the app's own `afterChange` does. */
    var onChange: (FamilyLinks) -> Unit = {}
    val serviceFor: (FamilyCredential) -> FamilyService = { FamilyService(it, transport) }
    val serviceAt: (String) -> FamilyService = { FamilyService(it, null, transport) }
    val coordinator = FamilyCoordinator(device, scope.backgroundScope, serviceFor, PollOrder(), { receiving }, attendance, caregiver) { changes += it; onChange(it) }
}
