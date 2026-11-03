package com.ethanteng.helloporch.core

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith

class CallContactTest {
    @Test fun phoneFallbackRequiresAnInternationalNumberWithoutExtensions() {
        assertEquals("+442079460123", CallContact.normalizedPhoneNumber("+44 20 7946 0123"))
        for (phone in listOf("4155550123", "", " ", "+01415550123", "+1911", "+14155550123 ext 2", "+14155550123#2", "++14155550123", "tel:+14155550123",
            "+１２３４５６７８９０", "+1234567890123456")) {
            assertFailsWith<ValidationException>(phone) { CallContact.normalizedPhoneNumber(phone) }
        }
    }

    @Test fun appearanceValidationIsBounded() {
        val call = NativeCall("test", NativeCall.Mode.VOICE)
        for (color in listOf("#FFFFFF", "FFF", "ZZZZZZ", "12345678")) {
            assertFailsWith<ValidationException>(color) { CallContact("David", call, buttonColorHex = color) }
        }
        assertFailsWith<ValidationException> { CallContact("David", call, photoData = ByteArray(0)) }
        assertFailsWith<ValidationException> { CallContact("David", call, photoData = ByteArray(1_000_001)) }
    }
}
