package com.ethanteng.helloporch.core

import java.net.URI
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith

class FamilyInvitationTest {
    @Test fun invitationCarriesOnlyItsServerAndOneTimeCode() {
        val origin = "https://porch.example"
        val code = "a".repeat(64)
        val url = FamilyInvitation.url(origin, code)
        val parsed = FamilyInvitation(url)
        assertEquals(origin, parsed.origin); assertEquals(code, parsed.code)
        for (raw in listOf("https://porch.example/pair?code=$code", "porch://pair?server=https://porch.example&code=short",
            "porch://pair?server=https://porch.example&code=$code&server=https://evil.example", "porch://pair?server=http://public.example&code=$code",
            "porch://pair?server=https://porch.example/path&code=$code", "porch://user@pair?server=https://porch.example&code=$code")) {
            assertFailsWith<ValidationException>(raw) { FamilyInvitation(raw) }
        }
    }

    @Test fun webInvitationsAreForTheAppsOwnServerAndKeepTheirCodeAfterTheHash() {
        val server = "https://porch.example"
        val code = "b".repeat(64)
        val link = FamilyInvitation.url(server, code, defaultOrigin = server)
        assertEquals("https://helloporch.store/join#code=$code", link)
        val parsed = FamilyInvitation(link, defaultOrigin = server)
        assertEquals(server, parsed.origin); assertEquals(code, parsed.code)
        // Another server keeps the porch:// form, which names it.
        assertEquals("porch", URI(FamilyInvitation.url("https://other.example", code, defaultOrigin = server)).scheme)
        // Without the app's own server, a web link can't be read.
        assertFailsWith<ValidationException> { FamilyInvitation(link) }
        assertEquals(code, FamilyInvitation("https://www.helloporch.store/join/#code=$code", defaultOrigin = server).code)
        for (raw in listOf("https://helloporch.store/join?code=$code", "https://helloporch.store/join#code=short", "https://evil.example/join#code=$code",
            "http://helloporch.store/join#code=$code", "https://helloporch.store/setup#code=$code", "https://helloporch.store/join#code=$code&server=https://evil.example",
            "https://helloporch.store:8443/join#code=$code", "https://user@helloporch.store/join#code=$code", "https://helloporch.store/join")) {
            assertFailsWith<ValidationException>(raw) { FamilyInvitation(raw, defaultOrigin = server) }
        }
        // A bedside's setup link is its own kind.
        val setup = "https://helloporch.store/setup#code=$code"
        assertEquals(server, BedsideInvitation(setup, defaultOrigin = server).origin)
        assertFailsWith<ValidationException> { BedsideInvitation(link, defaultOrigin = server) }
        assertFailsWith<ValidationException> { FamilyInvitation(setup, defaultOrigin = server) }
    }

    @Test fun activationLinksCannotBeConfusedWithFamilyInvitations() {
        val code = "a".repeat(64)
        val url = "porch://activate?server=https%3A%2F%2Fexample.com&code=$code"
        assertEquals("https://example.com", BedsideInvitation(url).origin)
        assertFailsWith<ValidationException> { FamilyInvitation(url) }
        assertFailsWith<ValidationException> { BedsideInvitation(FamilyInvitation.url("https://example.com", code)) }
        assertFailsWith<ValidationException> { BedsideInvitation("porch://activate?server=http%3A%2F%2Fexample.com&code=$code") }
    }

    @Test fun eachFamilyKnowsThisPhoneByItsOwnDeviceID() {
        val credential = FamilyCredential("https://porch.example", "0b3f1f4e-0000-4000-8000-000000000001.${"c".repeat(64)}", PorchExperience.FAMILY)
        assertEquals("0b3f1f4e-0000-4000-8000-000000000001", credential.deviceID)
        assertEquals("", FamilyCredential(credential.origin, "", PorchExperience.FAMILY).deviceID)
    }
}
