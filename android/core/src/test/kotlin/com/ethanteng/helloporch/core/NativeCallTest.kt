package com.ethanteng.helloporch.core

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlinx.serialization.json.Json

class NativeCallTest {
    @Test fun roomNamesRejectURLsAndInvalidNames() {
        for (room in listOf("", " ", "family/other", "a?x=1", "a#b", "a b", "家人", "-room", "a".repeat(65))) {
            assertFailsWith<ValidationException>(room) { NativeCall.of(room, NativeCall.Mode.VOICE) }
        }
        assertEquals("family-room", NativeCall.of(" Family-Room ", NativeCall.Mode.VIDEO).room)
    }

    @Test fun savedRoomsAreCheckedAgainWhenRead() {
        assertEquals(NativeCall("room", NativeCall.Mode.VIDEO), Json.decodeFromString<NativeCall>("""{"room":"room","mode":"video"}"""))
        for (json in listOf("""{"room":"../room","mode":"voice"}""", """{"room":"room","mode":"invalid"}""")) {
            assertFailsWith<IllegalArgumentException>(json) { Json.decodeFromString<NativeCall>(json) }
        }
    }

    @Test fun serverAllowsHTTPSAndLocalhostOnly() {
        val code = "prototype-code-for-test"
        val server = NativeCallServer(" https://porch.example.com/ ", code)
        assertEquals("https://porch.example.com/api/calls/token", server.tokenURL)
        assertEquals("http://localhost:3000", NativeCallServer("http://localhost:3000", code).baseURL)
        for (url in listOf("http://porch.example.com", "https://a:b@porch.example.com", "https://porch.example.com/path", "https://porch.example.com?code=secret",
            "https://porch.example.com#room", "wss://porch.example.com", "porch.example.com")) {
            assertFailsWith<ValidationException>(url) { NativeCallServer(url, code) }
        }
        for (invalid in listOf("short", "code with spaces in it", "abcdefghijklmnop\r\nAuthorization: bad", "a".repeat(257))) {
            assertFailsWith<ValidationException> { NativeCallServer("https://porch.example.com", invalid) }
        }
    }
}
