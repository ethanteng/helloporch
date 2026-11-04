package com.ethanteng.helloporch.core

import com.ethanteng.helloporch.core.FakeTransport.Companion.failure
import com.ethanteng.helloporch.core.FakeTransport.Companion.fixture
import com.ethanteng.helloporch.core.FakeTransport.Companion.ok
import java.io.IOException
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertIs
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.job
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonPrimitive

@OptIn(ExperimentalCoroutinesApi::class)
class FamilyServiceTest {
    private val family = TestFamilies.family(1)

    @Test fun postsTheActionAndItsValuesWithTheDevicesCredential() = runTest {
        val transport = FakeTransport { ok(mapOf("pushReady" to true)) }
        val response = FamilyService(family, transport).send("registerVoIP", mapOf("token" to JsonPrimitive("abc"), "sandbox" to JsonNull))
        assertEquals(true, response.pushReady)
        val request = transport.requests.single()
        assertEquals("https://porch.example/api/family", request.url)
        assertEquals(mapOf("Content-Type" to "application/json", "Authorization" to "Bearer ${family.credential}"), request.headers)
        assertEquals(ModelFixtures.json(mapOf("action" to "registerVoIP", "token" to "abc", "sandbox" to null)), request.body)
        assertEquals(12_000, request.timeoutMillis)
    }

    /** Caregiver actions carry the PIN. Claiming an invitation has no credential yet. Nothing sends an Origin header,
     * which the server would turn away. */
    @Test fun headersFollowWhatTheRequestCarries() = runTest {
        val transport = FakeTransport()
        FamilyService(family, transport).send("setDropIn", pin = "123456")
        FamilyService(TestFamilies.origin, null, transport).send("claimInvite")
        FamilyService("${TestFamilies.origin}/", null, transport).send("claimInvite")
        val (caregiver, claim, slash) = transport.requests
        assertEquals("123456", caregiver.headers["X-Porch-Setup-Code"])
        assertEquals("Bearer ${family.credential}", caregiver.headers["Authorization"])
        assertEquals(mapOf("Content-Type" to "application/json"), claim.headers)
        assertEquals("https://porch.example/api/family", slash.url)
        assertTrue(transport.requests.none { request -> request.headers.keys.any { it.equals("Origin", ignoreCase = true) } })
    }

    @Test fun valuesCantChangeTheAction() = runTest {
        val transport = FakeTransport()
        FamilyService(family, transport).send("poll", mapOf("action" to JsonPrimitive("leaveHousehold")))
        assertEquals("poll", transport.requests.single().action)
    }

    /** These wait on another service: a phone line, a voice, a translation, a number to buy. */
    @Test fun slowActionsWaitLonger() = runTest {
        assertEquals(mapOf("addPhoneGuest" to 25L, "speech" to 30L, "textMessage" to 40L, "assignPhoneNumber" to 45L, "poll" to 12L, "startCall" to 12L),
            listOf("addPhoneGuest", "speech", "textMessage", "assignPhoneNumber", "poll", "startCall").associateWith(FamilyService::timeoutFor))
        val transport = FakeTransport()
        val service = FamilyService(family, transport)
        service.send("textMessage")
        service.send("assignPhoneNumber", pin = "123456")
        service.send("poll", timeoutSeconds = 5)
        assertEquals(listOf(40_000L, 45_000L, 5_000L), transport.requests.map { it.timeoutMillis })
    }

    @Test fun readsTheServersOwnResponses() = runTest {
        val response = FamilyService(family, FakeTransport { fixture("family-poll") }).send("poll")
        assertEquals("Mom", response.state?.householdName)
        assertEquals(true, response.state?.me?.caregiver)
        val admin = FamilyService(family, FakeTransport { fixture("caregiver-admin") }).send("verifyPIN", pin = "123456")
        assertEquals(listOf("Ethan", "Lee"), admin.admin?.people?.map { it.name })
    }

    /** The server's message is shown as it comes. Without one, Porch says it couldn't reach the server. */
    @Test fun aRefusalCarriesTheServersMessageStatusAndCode() = runTest {
        suspend fun refusal(response: TransportResponse) =
            assertFailsWith<FamilyServiceException> { FamilyService(family, FakeTransport { response }).send("startCall") }

        val busy = refusal(TransportResponse(409, fixture("error-busy").body))
        assertEquals("Another call is already in progress.", busy.message)
        assertEquals(409, busy.status); assertNull(busy.code)
        val noNumbers = refusal(failure(400, "No numbers in that area code.", "noNumbers"))
        assertEquals("No numbers in that area code.", noNumbers.message); assertEquals("noNumbers", noNumbers.code)
        val gateway = refusal(TransportResponse(502, "<html>Bad gateway</html>"))
        assertEquals(FamilyService.unreachable, gateway.message); assertEquals(502, gateway.status)
        // As on iOS, a code means nothing without the message it goes with.
        val codeOnly = refusal(failure(400, errorCode = "noNumbers"))
        assertEquals(FamilyService.unreachable, codeOnly.message); assertNull(codeOnly.code)
    }

    @Test fun aRemovedDeviceIs401() = runTest {
        val removed = assertFailsWith<FamilyServiceException> {
            FamilyService(family, FakeTransport { failure(401, "This device was removed.") }).send("poll")
        }
        assertEquals(401, removed.status); assertEquals("This device was removed.", removed.message)
    }

    @Test fun aServerThatCantBeReachedIsStatus0() = runTest {
        val offline = assertFailsWith<FamilyServiceException> {
            FamilyService(family, FakeTransport { throw IOException("Unable to resolve host") }).send("poll")
        }
        assertEquals(0, offline.status); assertEquals(FamilyService.unreachable, offline.message)
    }

    /** Such as a hotel's sign-in page in place of Porch's answer. */
    @Test fun anAnswerItCantReadIsLikeNoAnswer() = runTest {
        val unreadable = assertFailsWith<FamilyServiceException> {
            FamilyService(family, FakeTransport { TransportResponse(200, "<html>Sign in to the Wi-Fi</html>") }).send("poll")
        }
        assertEquals(FamilyService.unreachable, unreadable.message); assertEquals(200, unreadable.status)
    }

    @Test fun cancellingARequestCancelsItRatherThanFailingIt() = runTest {
        var caught: Throwable? = null
        val job = launch {
            try { FamilyService(family, FakeTransport { awaitCancellation() }).send("poll") } catch (error: Throwable) { caught = error; throw error }
        }
        runCurrent()
        job.cancel(); job.join()
        assertIs<CancellationException>(caught)

        val stopped = assertFailsWith<CancellationException> {
            FamilyService(family, FakeTransport { throw CancellationException("stopped") }).send("poll")
        }
        assertEquals("stopped", stopped.message)

        // OkHttp reports a cancelled call as an IOException.
        caught = null
        val cutOff = launch {
            try {
                FamilyService(family, FakeTransport { currentCoroutineContext().job.cancel(); throw IOException("Canceled") }).send("poll")
            } catch (error: Throwable) { caught = error; throw error }
        }
        cutOff.join()
        assertIs<CancellationException>(caught)
    }
}

class PollOrderTest {
    /** The server keeps the availability of the newest poll from this launch, so one that arrives late can't undo it. */
    @Test fun eachPollIsNumberedWithinItsLaunch() {
        val order = PollOrder()
        assertTrue(Regex("^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$").matches(order.launch))
        val first = order.next(mapOf("available" to JsonPrimitive(true)))
        val second = order.next(mapOf("available" to JsonPrimitive(false), "attendedSeconds" to JsonPrimitive(30)))
        assertEquals(mapOf("launch" to JsonPrimitive(order.launch), "sequence" to JsonPrimitive(1L), "available" to JsonPrimitive(true)), first)
        assertEquals(2L, second.getValue("sequence").jsonPrimitive.content.toLong())
        assertEquals(JsonPrimitive(30), second["attendedSeconds"])
        assertFalse(PollOrder().launch == order.launch, "each launch has its own ID")
    }

    @Test fun pollsFromSeveralThreadsNeverShareANumber() {
        val order = PollOrder()
        val pool = Executors.newFixedThreadPool(8)
        val numbers = (1..4000).map { pool.submit<Long> { order.next(emptyMap()).getValue("sequence").jsonPrimitive.content.toLong() } }.map { it.get() }
        pool.shutdown(); pool.awaitTermination(5, TimeUnit.SECONDS)
        assertEquals((1L..4000L).toSet(), numbers.toSet())
    }
}
