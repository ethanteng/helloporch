package com.ethanteng.helloporch.core

import java.text.BreakIterator

/** Which keys a field gets on Porch keyboard, as iOS picks them from a field's `keyboardType`. */
enum class PorchKeys { NUMBERS, PHONE, TEXT }

/** Porch keyboard's keys, laid out as iOS's CaregiverTouchKeyboard lays them out. */
object PorchKeyLayout {
    const val DELETE = "⌫"
    const val SPACE = "Space"
    const val PASTE = "Paste"
    const val NEXT = "Next"
    const val DONE = "Done"
    const val UPPERCASE = "ABC"
    const val LOWERCASE = "abc"
    const val SYMBOLS = "Symbols"
    const val LETTERS = "Letters"

    fun rows(keys: PorchKeys, symbols: Boolean): List<List<String>> = when {
        keys == PorchKeys.NUMBERS -> listOf(listOf("1", "2", "3", "4", "5"), listOf("6", "7", "8", "9", "0", DELETE))
        keys == PorchKeys.PHONE -> listOf(listOf("1", "2", "3", "4", "5", "6"), listOf("7", "8", "9", "0", "+", DELETE))
        symbols -> listOf("@#$%&*()-_+", "[]{}<>^~|\\", "/:;!?.,='\"`").map(::characters)
        else -> listOf("1234567890", "qwertyuiop", "asdfghjkl", "zxcvbnm").map(::characters)
    }

    /** The row under the keys. Text has its Space and Delete there. */
    fun controls(keys: PorchKeys, uppercase: Boolean, symbols: Boolean): List<String> =
        if (keys != PorchKeys.TEXT) listOf(PASTE, NEXT, DONE)
        else listOf(if (uppercase) LOWERCASE else UPPERCASE, if (symbols) LETTERS else SYMBOLS, SPACE, DELETE, PASTE, NEXT, DONE)

    /** What a key types, or null for a key that does something else. */
    fun typed(key: String, uppercase: Boolean): String? = when (key) {
        DELETE, PASTE, NEXT, DONE, UPPERCASE, LOWERCASE, SYMBOLS, LETTERS -> null
        SPACE -> " "
        else -> if (uppercase) key.uppercase() else key
    }

    /** A key's name as it shows: a letter in capitals while they're on. */
    fun title(key: String, uppercase: Boolean): String = if (key.length == 1 && uppercase) key.uppercase() else key

    private fun characters(row: String) = row.map(Char::toString)
}

/** A field's text and selection, edited as a keyboard does: typing replaces the selection, and Delete takes the selection
 * or the character before the cursor. `start` and `end` are a cursor when they're equal. */
data class TypedText(val text: String, val start: Int, val end: Int = start) {
    private val from get() = minOf(start, end).coerceIn(0, text.length)
    private val to get() = maxOf(start, end).coerceIn(0, text.length)

    fun insert(typed: String): TypedText {
        val at = from
        return TypedText(text.replaceRange(at, to, typed), at + typed.length)
    }

    fun deleteBackward(): TypedText {
        val at = from
        if (at != to) return TypedText(text.removeRange(at, to), at)
        if (at == 0) return TypedText(text, 0)
        // One character as a person sees it, such as an emoji, not half of one.
        val characters = BreakIterator.getCharacterInstance()
        characters.setText(text)
        val previous = characters.preceding(at).coerceAtLeast(0)
        return TypedText(text.removeRange(previous, at), previous)
    }
}
