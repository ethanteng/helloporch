package com.ethanteng.helloporch.core

import kotlinx.coroutines.delay

/**
 * A Cell2Jack on a test's virtual clock. It writes down every transfer, answers the chip-version request with
 * [chipVersion], answers /v with [versionReply] and /d with [logs], and plays whatever else the test queues on
 * [reads]. A read with nothing queued is idle: it waits out its timeout and returns -1, as Android's does.
 */
class FakeCell2JackLink(private val clock: () -> Long, override var packetSize: Int = 32, var chipVersion: Int = 0x31) : Cell2JackLink {
    sealed interface Read {
        class Bytes(val bytes: ByteArray) : Read
        /** -1 at once: what a stalled endpoint, or an unplugged Cell2Jack, returns. */
        data object Stall : Read
    }

    data class Control(val requestType: Int, val request: Int, val value: Int, val index: Int, val length: Int, val timeoutMs: Int)
    data class Write(val command: String, val time: Long, val timeoutMs: Int)

    var versionReply: List<Read> = listOf(Read.Bytes(" >>>>>>>>>>>>>> CJ Version = a06\r\n".toByteArray()))
    var logs: List<Read> = emptyList()
    val reads = ArrayDeque<Read>()
    val controls = mutableListOf<Control>()
    val writes = mutableListOf<Write>()
    val readTimeouts = mutableListOf<Int>()
    val clears = mutableListOf<String>()
    var stalledWrites = 0
    var clearResult = 0
    /** Every transfer fails at once, including clearing a halt: the Cell2Jack was pulled out. */
    var unplugged = false
    var closed = false

    val commands get() = writes.map { it.command }

    override suspend fun controlTransfer(requestType: Int, request: Int, value: Int, index: Int, buffer: ByteArray?, length: Int, timeoutMs: Int): Int {
        if (unplugged) return -1
        controls += Control(requestType, request, value, index, length, timeoutMs)
        if (request == 0x5F && buffer != null) { buffer[0] = chipVersion.toByte(); buffer[1] = 0 }
        return length
    }

    override suspend fun bulkOut(buffer: ByteArray, length: Int, timeoutMs: Int): Int {
        if (unplugged) return -1
        if (stalledWrites > 0) { stalledWrites -= 1; return -1 }
        val command = String(buffer, 0, length, Charsets.US_ASCII)
        writes += Write(command, clock(), timeoutMs)
        when (command) {
            "/v" -> reads.addAll(versionReply)
            "/d" -> reads.addAll(logs)
        }
        return length
    }

    override suspend fun bulkIn(buffer: ByteArray, length: Int, timeoutMs: Int): Int {
        readTimeouts += timeoutMs
        if (unplugged) return -1
        return when (val next = reads.removeFirstOrNull()) {
            null -> { delay(timeoutMs.toLong()); -1 }
            Read.Stall -> -1
            is Read.Bytes -> {
                val count = minOf(length, next.bytes.size)
                next.bytes.copyInto(buffer, 0, 0, count)
                // What doesn't fit in a packet comes in the next read.
                if (count < next.bytes.size) reads.addFirst(Read.Bytes(next.bytes.copyOfRange(count, next.bytes.size)))
                count
            }
        }
    }

    override suspend fun clearHalt(input: Boolean): Int {
        clears += if (input) "in" else "out"
        return if (unplugged) -1 else clearResult
    }

    override fun close() { closed = true }

    companion object {
        fun bytes(text: String) = Read.Bytes(text.toByteArray(Charsets.US_ASCII))
    }
}
