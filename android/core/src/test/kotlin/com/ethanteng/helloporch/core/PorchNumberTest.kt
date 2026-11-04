package com.ethanteng.helloporch.core

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class PorchNumberTest {
    @Test fun usNumbersReadTheWayPeopleWriteThemAndOthersAreLeftAlone() {
        assertEquals("(510) 567-7039", PorchNumber.display("+15105677039"))
        for (other in listOf("+447700900123", "+1510567703", "+1510567703x", "5105677039", "")) {
            assertEquals(other, PorchNumber.display(other))
        }
    }

    @Test fun areaCodesMatchWhatTheServerSearches() {
        for (good in listOf("510", "978", "212", "800")) assertTrue(PorchNumber.isAreaCode(good), good)
        for (bad in listOf("011", "123", "411", "911", "51", "5100", "51a", " 510", "٥١٠")) assertFalse(PorchNumber.isAreaCode(bad), bad)
    }
}
