package com.ethanteng.helloporch.core

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

class PorchKeyboardKeysTest {
    @Test
    fun numbersAndPhoneMatchIOS() {
        assertEquals(listOf(listOf("1", "2", "3", "4", "5"), listOf("6", "7", "8", "9", "0", "⌫")), PorchKeyLayout.rows(PorchKeys.NUMBERS, symbols = false))
        assertEquals(listOf(listOf("1", "2", "3", "4", "5", "6"), listOf("7", "8", "9", "0", "+", "⌫")), PorchKeyLayout.rows(PorchKeys.PHONE, symbols = true))
        assertEquals(listOf("Paste", "Next", "Done"), PorchKeyLayout.controls(PorchKeys.PHONE, uppercase = true, symbols = true))
    }

    @Test
    fun textHasLettersSymbolsAndControls() {
        val letters = PorchKeyLayout.rows(PorchKeys.TEXT, symbols = false)
        assertEquals(listOf(10, 10, 9, 7), letters.map { it.size })
        assertEquals("q", letters[1].first())
        val symbols = PorchKeyLayout.rows(PorchKeys.TEXT, symbols = true).flatten()
        for (symbol in listOf("@", "+", "\\", "\"", "`", "'")) assert(symbol in symbols) { "$symbol is missing" }
        assertEquals(listOf("ABC", "Symbols", "Space", "⌫", "Paste", "Next", "Done"), PorchKeyLayout.controls(PorchKeys.TEXT, uppercase = false, symbols = false))
        assertEquals(listOf("abc", "Letters", "Space", "⌫", "Paste", "Next", "Done"), PorchKeyLayout.controls(PorchKeys.TEXT, uppercase = true, symbols = true))
    }

    @Test
    fun keysTypeWhatTheyShow() {
        assertEquals("a", PorchKeyLayout.typed("a", uppercase = false))
        assertEquals("A", PorchKeyLayout.typed("a", uppercase = true))
        assertEquals("A", PorchKeyLayout.title("a", uppercase = true))
        assertEquals("Paste", PorchKeyLayout.title("Paste", uppercase = true))
        assertEquals("7", PorchKeyLayout.typed("7", uppercase = true))
        assertEquals(" ", PorchKeyLayout.typed("Space", uppercase = false))
        for (control in listOf("⌫", "Paste", "Next", "Done", "ABC", "abc", "Symbols", "Letters")) assertNull(PorchKeyLayout.typed(control, uppercase = false))
    }

    @Test
    fun typingGoesAtTheCursorOrOverTheSelection() {
        assertEquals(TypedText("4158", 4), TypedText("415", 3).insert("8"))
        assertEquals(TypedText("+1415", 1), TypedText("1415", 0).insert("+"))
        assertEquals(TypedText("Mom", 1), TypedText("om", 0).insert("M"))
        assertEquals(TypedText("David", 5), TypedText("Dad", 1, 3).insert("avid"))
        // A selection made from its end works the same.
        assertEquals(TypedText("Dx", 2), TypedText("Dad", 3, 1).insert("x"))
    }

    @Test
    fun deleteTakesTheSelectionOrOneCharacter() {
        assertEquals(TypedText("41", 2), TypedText("415", 3).deleteBackward())
        assertEquals(TypedText("45", 1), TypedText("415", 2).deleteBackward())
        assertEquals(TypedText("415", 0), TypedText("415", 0).deleteBackward())
        assertEquals(TypedText("4", 1), TypedText("415", 1, 3).deleteBackward())
        // An emoji is one character to a person, though it's two to Java.
        assertEquals(TypedText("Hi ", 3), TypedText("Hi 👋", 5).deleteBackward())
    }

    @Test
    fun aCursorPastTheEndIsKeptInside() {
        assertEquals(TypedText("ab", 2), TypedText("abc", 9).deleteBackward())
        assertEquals(TypedText("abcd", 4), TypedText("abc", 9).insert("d"))
    }
}
