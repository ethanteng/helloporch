package com.ethanteng.helloporch.core

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

class FamilyNamesTest {
    /** Both sets of parents' bedsides are often "Mom". Until the phone names one, the family it joined later is numbered. */
    @Test fun familiesWithTheSameNameAreNumberedInTheOrderTheyJoined() {
        assertEquals(listOf("Mom", "Mom 2"), FamilyNames.distinct(listOf("Mom", "Mom")))
        assertEquals(listOf("Mom", "mom 2", "Mom 3"), FamilyNames.distinct(listOf("Mom", "mom", "Mom")), "names that differ only in case read the same")
        assertEquals(listOf("Mom", "Sarah's parents"), FamilyNames.distinct(listOf("Mom", "Sarah's parents")))
        assertEquals(listOf("Mom 2", "Mom", "Mom 3"), FamilyNames.distinct(listOf("Mom 2", "Mom", "Mom")), "a number never repeats a name already here")
        assertEquals(listOf(null, "Mom", null), FamilyNames.distinct(listOf(null, "Mom", null)))
    }

    /** Two sets of parents are often both "Mom" and "Dad". The name the phone gave a family wins, then the household's. */
    @Test fun aPhoneInSeveralFamiliesTellsThemApart() {
        assertEquals("Sarah's parents", FamilyNames.family(nickname = "Sarah's parents", householdName = "Mom"))
        assertEquals("Lee family", FamilyNames.family(nickname = "  ", householdName = " Lee family "))
        assertEquals("Lee family", FamilyNames.family(nickname = null, householdName = "Lee family"))
        assertNull(FamilyNames.family(nickname = null, householdName = null))
        assertEquals("Mom · Lee family", FamilyNames.caller("Mom", family = "Lee family"))
        assertEquals("Mom", FamilyNames.caller("Mom", family = "mom"), "a family named after the caller adds nothing")
        assertEquals("Mom", FamilyNames.caller("Mom", family = null))
        assertEquals("Mom", FamilyNames.caller("Mom", family = ""))
    }
}
