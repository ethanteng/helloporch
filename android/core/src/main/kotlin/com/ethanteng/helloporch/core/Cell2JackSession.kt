package com.ethanteng.helloporch.core

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.delay
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.withContext

/** What the Cell2Jack transport reports, from its coroutine. */
sealed interface Cell2JackUpdate {
    /** Opening the Cell2Jack: the first time, or again after the last connection ended. */
    data object Connecting : Cell2JackUpdate
    /** The first log bytes arrived: the phone is plugged in and the Cell2Jack is answering. */
    data object Ready : Cell2JackUpdate
    /** The keypad events in one read, and when it arrived on the session's clock. */
    data class Keys(val events: List<Cell2JackDigitEvent>, val receivedAt: Long) : Cell2JackUpdate
    /** Every five seconds. The counts are the session's so far. */
    data class Health(val bytes: Long, val packets: Int, val primaryDigits: Int) : Cell2JackUpdate
    /** The connection ended. The message says why, and whether /q went out. */
    data class Finished(val message: String) : Cell2JackUpdate
    /** The next try is in this many seconds. */
    data class Retrying(val delaySeconds: Int) : Cell2JackUpdate
}

/**
 * One connection to the Cell2Jack, from the CH340's init to /q: what the verified iPad driver
 * (ios/Cell2JackDriver/PorchCell2JackDriver.cpp) and the iOS keypad's transport do together, sent byte for byte the
 * same. Continuous foreground input. Bounded parser, action history and 64 KiB raw diagnostic tail; no time cutoff
 * that would remove hang-up during a call.
 *
 * 1. Init: the chip version (versions below 0x30 are rejected), serial init, 2 Mbaud, 8N1, flow control off, DTR and
 *    RTS off. Each control transfer has 500 ms.
 * 2. /v, then up to six 500 ms reads until a newline.
 * 3. 500 ms, then /d, and the logs are read 250 ms at a time and parsed.
 * 4. With no bytes within 2 s of /d, /q and start again from the init, up to three tries.
 * 5. /q when it ends, however it ends, once /v has been answered.
 */
class Cell2JackSession(
    private val link: Cell2JackLink,
    private val diagnostics: Cell2JackDiagnostics,
    /** Milliseconds on a clock that only goes forward. */
    private val clock: () -> Long = ::monotonicMillis,
) {
    // The driver's stages (PorchC2JStage), for saying which step failed.
    private enum class Stage(val label: String) {
        CHIP_VERSION("chip version"), INITIALIZE("serial init"), BAUD("baud"), LINE_CONTROL("line control"),
        MODEM_CONTROL("modem control"), WRITE("/v"), READ("reply to /v"), LOG_ENABLE("/d"), LOG_READ("log read"),
        LOG_STOP("/q"),
    }

    private val parser = Cell2JackDTMFParser()
    private val buffer = ByteArray(Cell2JackProtocol.maxReply)
    private var packetSize = 0
    /** /v was answered, so /q is owed, even if /d didn't go out. */
    private var logging = false
    private var attempts = 0
    private var attemptTime = 0L
    private var ready = false
    private var totalBytes = 0L
    private var packets = 0
    private var primaryDigits = 0
    private var lastHealth = 0L

    /**
     * Runs until the connection fails or the coroutine is cancelled. Either way it then sends /q if that's owed, closes
     * the link and reports [Cell2JackUpdate.Finished], last. `onUpdate` is called on this coroutine.
     */
    suspend fun run(onUpdate: (Cell2JackUpdate) -> Unit) {
        var started = false
        var message = "Phone keypad stopped"
        try {
            packetSize = link.packetSize
            if (packetSize <= 0 || packetSize > Cell2JackProtocol.maxReply) throw Cell2JackException("Unsupported USB packet size $packetSize")
            begin()
            started = true
            lastHealth = clock() - healthIntervalMs
            while (true) {
                poll(onUpdate)
                // Our transport has no USB receive loop of its own, so start draining as soon as /d completes and keep
                // reading promptly during bursts, a millisecond apart as the iPad's timer does. Idle reads still wait
                // up to 250 ms each.
                delay(1)
            }
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            message = (if (started) "Phone keypad stopped: " else "Phone keypad unavailable: ") + (e.message ?: e.javaClass.simpleName)
        } finally {
            withContext(NonCancellable) {
                var cleanup = ""
                if (logging) {
                    logging = false
                    cleanup = if (write('q')) " · /q sent" else " · /q unconfirmed; unplug Cell2Jack if logging persists"
                }
                try { link.close() } catch (_: Exception) { /* Closing is the last step either way. */ }
                onUpdate(Cell2JackUpdate.Finished(message + cleanup))
            }
        }
    }

    private suspend fun begin() {
        // Stopped before a try begins: nothing has gone to the Cell2Jack for it, so nothing needs undoing.
        currentCoroutineContext().ensureActive()
        attempts += 1
        parser.resetPartialLine()
        readVersion()
        // Retain ownership even on a partial write, so the end can attempt /q.
        logging = true
        delay(logsDelayMs) // observed logger sequencing: /v, read, 500 ms, /d
        if (!write('d')) throw failed(Stage.LOG_ENABLE)
        attemptTime = clock()
    }

    /** The CH340's init, /v and its reply: ReadVersion in the driver. */
    private suspend fun readVersion() {
        // CH34x USB register protocol, separate from the Cell2Jack serial protocol.
        // Only volatile serial configuration is changed; no device firmware writes.
        val version = ByteArray(2)
        control(Stage.CHIP_VERSION, 0xC0, 0x5F, 0, 0, version)
        val chipVersion = version[0].toInt() and 0xFF
        diagnostics.record("usbChipVersion", "attempt" to attempts, "chipVersion" to "0x%02x".format(chipVersion))
        // Older variants need different line-control sequencing, not implemented.
        if (chipVersion < Cell2JackProtocol.minimumChipVersion) throw Cell2JackException("CH340 version 0x%02x isn't supported".format(chipVersion))
        control(Stage.INITIALIZE, 0x40, 0xA1, 0, 0)
        control(Stage.BAUD, 0x40, 0x9A, 0x1312, Cell2JackProtocol.baudRegister(chipVersion))
        control(Stage.LINE_CONTROL, 0x40, 0x9A, 0x2518, 0xC3) // 8N1 RX/TX
        // Disable hardware flow control. Keep DTR and RTS inactive, as in test-04.
        control(Stage.MODEM_CONTROL, 0x40, 0x9A, 0x2727, 0)
        control(Stage.MODEM_CONTROL, 0x40, 0xA4, 0xFFFF, 0)
        if (!write('v')) throw failed(Stage.WRITE)
        // Bounded receive window; preserve fragmentation and partial timeout data.
        val reply = ByteArray(Cell2JackProtocol.maxReply)
        var count = 0
        for (attempt in 0 until versionReads) {
            if (count >= reply.size) break
            val received = read(Stage.READ, versionReadTimeoutMs)
            val kept = minOf(received, reply.size - count)
            buffer.copyInto(reply, count, 0, kept)
            count += kept
            if ((0 until count).any { reply[it] == newline }) break
        }
        if (count == 0) throw failed(Stage.READ, "no reply")
        val result = Cell2JackVersionResult(reply.copyOf(count))
        diagnostics.record("usbVersion", "version" to result.version, "reply" to result.displayText)
    }

    private suspend fun poll(onUpdate: (Cell2JackUpdate) -> Unit) {
        val count = read(Stage.LOG_READ, pollTimeoutMs)
        if (count > 0) {
            val bytes = buffer.copyOf(count)
            totalBytes += count
            packets += 1
            diagnostics.appendRaw(bytes)
            if (!ready) { ready = true; onUpdate(Cell2JackUpdate.Ready) }
            val events = parser.append(bytes)
            primaryDigits += events.count { it.kind == Cell2JackDigitEvent.Kind.DIGIT }
            if (events.isNotEmpty()) onUpdate(Cell2JackUpdate.Keys(events, clock()))
        } else if (!ready && clock() - attemptTime >= noLogsRestartMs) {
            if (attempts >= maxAttempts) throw Cell2JackException("No device logs after three attempts. Unplug the Cell2Jack and plug it back in.")
            diagnostics.record("usbRestart", "attempt" to attempts + 1, "command" to "/q")
            // As EndLogs does, this gives up the session even when /q doesn't go out.
            logging = false
            if (!write('q')) throw failed(Stage.LOG_STOP)
            begin()
        }
        val now = clock()
        if (now - lastHealth >= healthIntervalMs) {
            lastHealth = now
            onUpdate(Cell2JackUpdate.Health(totalBytes, packets, primaryDigits))
        }
    }

    private suspend fun control(stage: Stage, requestType: Int, request: Int, value: Int, index: Int, data: ByteArray? = null) {
        val length = data?.size ?: 0
        if (link.controlTransfer(requestType, request, value, index, data, length, controlTimeoutMs) != length) throw failed(stage)
    }

    /** One read of up to a packet into [buffer]. 0 when nothing arrived: an idle read is normal while waiting for
     * physical keys. */
    private suspend fun read(stage: Stage, timeoutMs: Int): Int =
        when (val result = recoveringStall(input = true, timeoutMs) { link.bulkIn(buffer, packetSize, timeoutMs) }) {
            is Transfer.Moved -> if (result.count > packetSize) throw failed(stage, "overrun") else result.count
            Transfer.TimedOut -> 0
            Transfer.Failed, Transfer.Stalled -> throw failed(stage)
        }

    /** Writes `/` and the command. Only the fixed commands: version, start logs, stop logs. No caller-supplied serial
     * bytes, bootloader operations or flash writes. */
    private suspend fun write(command: Char): Boolean {
        val bytes = byteArrayOf('/'.code.toByte(), command.code.toByte())
        return try {
            recoveringStall(input = false, writeTimeoutMs) { link.bulkOut(bytes, bytes.size, writeTimeoutMs) } == Transfer.Moved(bytes.size)
        } catch (e: CancellationException) {
            throw e
        } catch (_: Exception) {
            false
        }
    }

    private sealed interface Transfer {
        data class Moved(val count: Int) : Transfer
        data object TimedOut : Transfer
        data object Stalled : Transfer
        data object Failed : Transfer
    }

    /**
     * At most one CLEAR_FEATURE(ENDPOINT_HALT) and one retry per transfer, as Cell2JackUSBRecovery.h allows. Android
     * reports a stall, an unplugged Cell2Jack and a read with nothing to read all as -1, so a transfer that gave up
     * before half its timeout counts as stalled, and one that waited it out timed out. An unplugged Cell2Jack then
     * fails to clear. A -1 carries no partial count either, so a partly received record is lost rather than delivered;
     * the commands are two bytes, one packet, so there's no partial write that a retry could replay.
     */
    private suspend fun recoveringStall(input: Boolean, timeoutMs: Int, transfer: suspend () -> Int): Transfer {
        val first = attempt(timeoutMs, transfer)
        if (first != Transfer.Stalled) return first
        val cleared = link.clearHalt(input)
        diagnostics.record("usbStall", "endpoint" to if (input) "in" else "out", "cleared" to (cleared >= 0))
        if (cleared < 0) return Transfer.Failed
        // A second stall is surfaced to the reconnect loop, never spun on.
        val second = attempt(timeoutMs, transfer)
        return if (second == Transfer.Stalled) Transfer.Failed else second
    }

    private suspend fun attempt(timeoutMs: Int, transfer: suspend () -> Int): Transfer {
        val started = clock()
        val count = transfer()
        return when {
            count >= 0 -> Transfer.Moved(count)
            clock() - started >= timeoutMs / 2 -> Transfer.TimedOut
            else -> Transfer.Stalled
        }
    }

    private fun failed(stage: Stage, detail: String? = null) =
        Cell2JackException("USB stage ${stage.label} failed" + (detail?.let { ": $it" } ?: ""))

    private companion object {
        const val controlTimeoutMs = 500
        const val writeTimeoutMs = 500
        const val versionReadTimeoutMs = 500
        const val versionReads = 6
        const val logsDelayMs = 500L
        const val pollTimeoutMs = 250
        const val noLogsRestartMs = 2_000L
        const val maxAttempts = 3
        const val healthIntervalMs = 5_000L
        const val newline = '\n'.code.toByte()
    }
}

/** Milliseconds since some fixed point, never going back. */
internal fun monotonicMillis(): Long = System.nanoTime() / 1_000_000
