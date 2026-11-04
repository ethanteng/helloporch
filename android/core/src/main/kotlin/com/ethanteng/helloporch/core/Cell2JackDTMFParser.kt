package com.ethanteng.helloporch.core

data class Cell2JackDigitEvent(val kind: Kind, val digit: String, val line: String, val embeddedInLine: Boolean = false) {
    // HANG_UP carries no digit: the receiver went back on the cradle.
    enum class Kind(val rawValue: String) { DIGIT("digit"), DOUBLE_REPORT("doubleReport"), PULSE("pulse"), HANG_UP("hangUp") }
}

/** Byte-oriented framing preserves fragmented lines and never combines an
 * overlong/binary line's suffix with the next line to invent a keypad event. */
class Cell2JackDTMFParser {
    private val line = ByteArray(maximumLine)
    private var length = 0
    private var dropping = false
    // Cell2Jack reports a digit counted from hook pulses as an ordinary DTMF
    // record right after "Get PULSE". A brief line break when the handset is
    // lifted counts as one pulse, so the record that follows is a phantom 1,
    // not a key press. A hook change clears a pulse that never produced one.
    private var pulseDigitPending = false
    // Cell2Jack also reports ON_HOOK as it starts up with the receiver already
    // down. Only a pickup or key press seen in this session makes ON_HOOK a
    // hang-up; keys work only off the cradle.
    private var handsetLifted = false

    fun resetPartialLine() { length = 0; dropping = false }

    fun append(bytes: ByteArray): List<Cell2JackDigitEvent> {
        val events = mutableListOf<Cell2JackDigitEvent>()
        for (byte in bytes) {
            if (byte == '\n'.code.toByte() || byte == '\r'.code.toByte()) {
                if (!dropping && length > 0) events += parse(line.copyOf(length))
                resetPartialLine()
            } else if (!dropping) {
                if (length == maximumLine) { length = 0; dropping = true }
                else line[length++] = byte
            }
        }
        return events
    }

    private fun parse(bytes: ByteArray): List<Cell2JackDigitEvent> {
        if (bytes.any { it < 0 }) return emptyList()
        val text = String(bytes, Charsets.US_ASCII)
        if ("ON_HOOK" in text || "OFF_HOOK" in text) pulseDigitPending = false
        if ("Get PULSE" in text) pulseDigitPending = true
        val events = mutableListOf<Cell2JackDigitEvent>()
        val primary = pattern.find(text)
        val match = primary ?: embeddedPattern.find(text)
        if (match != null) {
            var kind = if (match.groupValues[1] == "DTMF") Cell2JackDigitEvent.Kind.DIGIT else Cell2JackDigitEvent.Kind.DOUBLE_REPORT
            if (kind == Cell2JackDigitEvent.Kind.DIGIT && pulseDigitPending) { kind = Cell2JackDigitEvent.Kind.PULSE; pulseDigitPending = false }
            events += Cell2JackDigitEvent(kind, match.groupValues[2], text, embeddedInLine = primary == null)
            handsetLifted = true
        }
        // A hang-up joined to a key's line came after the key.
        if ("OFF_HOOK" in text) handsetLifted = true
        else if (hangUpPattern.containsMatchIn(text)) {
            if (handsetLifted) events += Cell2JackDigitEvent(Cell2JackDigitEvent.Kind.HANG_UP, "", text)
            handsetLifted = false
        }
        return events
    }

    private companion object {
        const val maximumLine = 4096
        val hangUpPattern = Regex("""(?:^|[^A-Z_])ON_HOOK(?:[^A-Z_]|$)""")
        val pattern = Regex("""^[ \t]*(DTMF|RX Double DTMF|Double DTMF)[ \t]+([0-9*#ABCD])(?=[ \t:]|$)""")
        // The full keypad capture contains " Cal DTMF 1 :0 20: 2": firmware
        // capture joined a status fragment to a genuine event. Recover only the
        // observed numeric record shape, not arbitrary mentions of a digit.
        val embeddedPattern = Regex("""(?:^|[ \t])(RX Double DTMF|Double DTMF|DTMF)[ \t]+([0-9*#ABCD])[ \t]*:[0-9]+[ \t]+[0-9]+[ \t]*:[ \t]*[0-9]+[ \t]*$""")
    }
}
