package com.ethanteng.helloporch.core

import kotlin.test.Test
import kotlin.test.assertEquals

class PorchContactCardTest {
    @Test fun theCardNamesThePorchAndCarriesItsNumber() {
        assertEquals("BEGIN:VCARD\r\nVERSION:3.0\r\nN:;Mom's Porch;;;\r\nFN:Mom's Porch\r\nTEL;TYPE=MAIN,VOICE:+15105550101\r\nEND:VCARD\r\n",
            PorchContactCard.vCard("Mom", "+15105550101"))
        assertEquals("Here's Mom's Porch number: (510) 555-0101. Call it from any phone to talk with Mom.",
            PorchContactCard.note("Mom", "+15105550101"))
        assertEquals("Mom's Porch.vcf", PorchContactCard.fileName("Mom"))
    }

    @Test fun namesCantBreakTheCardOrTheFileName() {
        val card = PorchContactCard.vCard("Grandma; Pop, and\nme\\", "+15105550101")
        assertEquals("FN:Grandma\\; Pop\\, and\\nme\\\\'s Porch", card.lines().first { it.startsWith("FN:") }.trimEnd('\r'))
        assertEquals(6, card.split("\r\n").filter { it.isNotEmpty() }.size, "one line per field")
        // A return in the name or the number would otherwise start a new property, such as another phone number.
        val injected = PorchContactCard.vCard("Mom\rTEL;TYPE=CELL:+19005551212", "+15105550101\r\nNOTE:nope")
        assertEquals(6, injected.split("\r\n").filter { it.isNotEmpty() }.size, "a return stays on its own line")
        assertEquals(emptyList(), injected.lines().filter { it.startsWith("NOTE:") || it.startsWith("TEL;TYPE=CELL") })
        assertEquals("Mom-Dad's Porch.vcf", PorchContactCard.fileName("Mom/Dad"))
        assertEquals("Mom-Dad's Porch.vcf", PorchContactCard.fileName("Mom\rDad"))
        assertEquals("Mom-Dad's Porch.vcf", PorchContactCard.fileName("Mom\nDad"))
    }
}
