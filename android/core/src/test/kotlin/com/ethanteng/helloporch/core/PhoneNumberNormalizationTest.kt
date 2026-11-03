package com.ethanteng.helloporch.core

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith

class PhoneNumberNormalizationTest {
    @Test fun contactsNumbersBecomeE164UsingTheirRegion() {
        for (input in listOf("(415) 867-6937", "4158676937", "1 (415) 867-6937", "+1 415 867 6937")) {
            assertEquals("+14158676937", PhoneNumberNormalization.e164(input, region = "US"), input)
        }
        assertEquals("+442070313000", PhoneNumberNormalization.e164("020 7031 3000", region = "GB"))
        assertEquals("+442070313000", PhoneNumberNormalization.e164("+44 20 7031 3000", region = "US"))
        for (invalid in listOf("911", "not a number", "+1 415 867 6937 ext 42")) {
            assertFailsWith<ValidationException>(invalid) { PhoneNumberNormalization.e164(invalid, region = "US") }
        }
    }
}
