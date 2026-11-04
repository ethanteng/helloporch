package com.ethanteng.helloporch.core

/**
 * The USB operations the Cell2Jack transport needs, as Android's `UsbDeviceConnection` has them: each returns the
 * number of bytes moved, or -1 when the transfer failed or timed out. The app wraps a connection to the Cell2Jack's
 * interface 0; tests use a fake on a virtual clock. [Cell2JackSession] makes one call at a time, from one coroutine.
 */
interface Cell2JackLink {
    /** The bulk IN endpoint's wMaxPacketSize. [Cell2JackSession] rejects 0 or more than 256, as the iPad driver does. */
    val packetSize: Int

    suspend fun controlTransfer(requestType: Int, request: Int, value: Int, index: Int, buffer: ByteArray?, length: Int, timeoutMs: Int): Int

    /** Reads up to `length` bytes from the first bulk IN endpoint. -1 when nothing arrived within `timeoutMs`. */
    suspend fun bulkIn(buffer: ByteArray, length: Int, timeoutMs: Int): Int

    /** Writes `length` bytes to the first bulk OUT endpoint. */
    suspend fun bulkOut(buffer: ByteArray, length: Int, timeoutMs: Int): Int

    /** Clears a halt (a stall) on the bulk IN endpoint, or on the OUT one: 0 when that worked, -1 when it didn't. */
    suspend fun clearHalt(input: Boolean): Int

    /** Releases the interface and closes the connection. */
    fun close()
}

/** Why the Cell2Jack couldn't be opened, or stopped. The message ends up in the keypad's status and diagnostics. */
class Cell2JackException(message: String) : Exception(message)
