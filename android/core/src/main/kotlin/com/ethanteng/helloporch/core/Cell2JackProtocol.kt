package com.ethanteng.helloporch.core

/**
 * The parts of the verified iPad driver's protocol (PorchCell2JackDriver.cpp and Cell2JackProtocol.h in
 * ios/Cell2JackDriver) that more than the session needs. [Cell2JackSession] sends the init sequence itself, line for
 * line as the driver does.
 */
object Cell2JackProtocol {
    /** The CH340 in the Cell2Jack. Generic CH340 adapters share this ID, as they do on iOS. */
    const val vendorID = 0x1A86
    const val productID = 0x7523

    /** PorchC2JMaxReply: the largest packet size accepted, and the most of the reply to /v that's kept. */
    const val maxReply = 256

    /** Older chips need different line-control sequencing, which isn't implemented. */
    const val minimumChipVersion = 0x30

    // Fixed 2 Mbaud: 48 MHz / (2^(12-3*3) * 3) = 2,000,000.
    // Registers 0x13/0x12 encode divisor (256-3), fact=0, prescaler=3.
    // Chip revisions >0x27 use bit 7 for short-packet delivery.
    fun baudRegister(chipVersion: Int): Int = 0xFD03 or (if (chipVersion > 0x27) 0x80 else 0)
}

/**
 * The Cell2Jack's reply to /v, kept as raw bytes. Only the observed CJ Version header is recognized, so unrelated
 * digits, debug lines and partial headers can't pass for a version. As Cell2JackVersionResult.swift does.
 */
class Cell2JackVersionResult(val bytes: ByteArray) {
    val version: String?
        get() {
            if (bytes.any { it < 0 }) return null
            return pattern.find(String(bytes, Charsets.US_ASCII))?.groupValues?.get(1)
        }

    /** The reply as text, with a carriage return and anything unprintable spelled out. */
    val displayText: String
        get() = bytes.joinToString("") { byte ->
            when (val code = byte.toInt() and 0xFF) {
                10 -> "\n"
                13 -> "\\r"
                in 32..126 -> code.toChar().toString()
                else -> "\\x%02x".format(code)
            }
        }

    val hex: String get() = bytes.joinToString(" ") { "%02x".format(it.toInt() and 0xFF) }

    private companion object {
        val pattern = Regex("""CJ Version\s*=\s*([A-Za-z0-9]{3})(?=\s|$)""")
    }
}

/** The Cell2Jack keypad's settings, under the iOS app's keys. */
object Cell2JackSettings {
    // The prototype's automatic test opt-in is deliberately not migrated.
    const val enabledKey = "porch.cell2jack.enabled"
    // On unless a caregiver turns it off, for someone who sets the receiver down right after pressing a key because
    // the sound comes from the tablet.
    const val receiverHangUpKey = "porch.cell2jack.receiverHangUp"

    /** Use Cell2Jack phone keypad. Off by default, including on an install from before the setting existed: setup
     * turns it on once the phone answers. */
    fun enabled(settings: PorchSettings): Boolean = settings.getBoolean(enabledKey) ?: false
    fun setEnabled(settings: PorchSettings, enabled: Boolean) = settings.putBoolean(enabledKey, enabled)

    /** Hang up when the receiver is put back. On by default. */
    fun receiverHangUp(settings: PorchSettings): Boolean = settings.getBoolean(receiverHangUpKey) ?: true
    fun setReceiverHangUp(settings: PorchSettings, enabled: Boolean) = settings.putBoolean(receiverHangUpKey, enabled)
}
