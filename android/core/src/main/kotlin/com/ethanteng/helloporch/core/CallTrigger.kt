package com.ethanteng.helloporch.core

/** A physical press produces at most one request, with a short cooldown shared
 * by keypad and touch input. The controller separately guards URL launches. */
class CallTrigger {
    private val heldKeys = mutableSetOf<Int>()
    private var lastLaunch: Double? = null

    /** True only for a key's first report while it's held. Callers check that the press is a keypad key first. */
    fun keyDown(keyCode: Int): Boolean = heldKeys.add(keyCode)

    fun keyUp(keyCode: Int) { heldKeys.remove(keyCode) }
    fun resetKeys() { heldKeys.clear() }

    /** `now` is in seconds, from a clock that only moves forward. */
    fun allowLaunch(now: Double): Boolean {
        val last = lastLaunch
        if (last != null && now - last < 2) return false
        lastLaunch = now
        return true
    }

    companion object {
        /** F24, which the Porch phone adapter types when the receiver goes back on the cradle
         * (phone-adapter/README.md). Android has no key code for F24, so this is its scan code, Linux's `KEY_F24`.
         * The adapter's other keys are keypad keys, read like any number pad's. */
        const val receiverHangUpScanCode = 194

        /** The keypad key for an Android key code (`KeyEvent.KEYCODE_*`). */
        fun slot(keyCode: Int): Int? = when (keyCode) {
            in 145..153 -> keyCode - 145 + 1 // number pad 1–9
            144 -> 0 // number pad 0
            155 -> CallSlots.star // number pad *
            in 8..16 -> keyCode - 8 + 1 // keyboard 1–9
            7 -> 0 // keyboard 0
            17 -> CallSlots.star // phone keypad *
            18 -> CallSlots.pound // phone keypad #
            else -> null
        }

        /** A keyboard types * and # with Shift, on whichever key its layout puts them, so those two
         * go by the typed characters. Digits go by the key itself, and never with Shift. */
        fun slot(keyCode: Int, characters: String, shift: Boolean): Int? = when (characters) {
            "*" -> CallSlots.star
            "#" -> CallSlots.pound
            else -> if (shift) null else slot(keyCode)
        }
    }
}

/** Decide on key release so a long press can decline without answering first. */
class IncomingCallKey {
    enum class Decision { ANSWER, DECLINE }

    private var pressedKey: Int? = null

    fun begin(key: Int, dropIn: Boolean): Decision? {
        if (pressedKey != null) return null
        if (dropIn) return Decision.DECLINE
        pressedKey = key
        return null
    }

    fun held(key: Int): Decision? {
        if (pressedKey != key) return null
        pressedKey = null
        return Decision.DECLINE
    }

    fun release(key: Int): Decision? {
        if (pressedKey != key) return null
        pressedKey = null
        return Decision.ANSWER
    }

    fun cancel() { pressedKey = null }
}
