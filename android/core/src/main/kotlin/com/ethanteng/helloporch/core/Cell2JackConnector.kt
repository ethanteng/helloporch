package com.ethanteng.helloporch.core

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.delay

/** How long to wait before connecting again: 1, 2, 4, 8, then every 15 seconds. */
class Cell2JackBackoff {
    private var nextDelay = 1

    fun next(): Int {
        val delay = nextDelay
        nextDelay = minOf(delay * 2, maximumSeconds)
        return delay
    }

    fun reset() { nextDelay = 1 }

    private companion object { const val maximumSeconds = 15 }
}

/**
 * Keeps the Cell2Jack connected for as long as [run] runs, which is while the phone keypad is wanted: it opens the
 * Cell2Jack, runs a [Cell2JackSession], and when that ends tries again after [Cell2JackBackoff]'s wait. The wait goes
 * back to a second once a connection has been healthy for 30 seconds. Cancelling [run] ends the session with /q.
 */
class Cell2JackConnector(
    /** Opens the Cell2Jack, or throws (a [Cell2JackException]) saying why it can't, such as that it isn't plugged in. */
    private val open: suspend () -> Cell2JackLink,
    private val diagnostics: Cell2JackDiagnostics,
    /** Milliseconds on a clock that only goes forward. */
    private val clock: () -> Long = ::monotonicMillis,
) {
    /** `onUpdate` is called on this coroutine. */
    suspend fun run(onUpdate: (Cell2JackUpdate) -> Unit): Nothing {
        val backoff = Cell2JackBackoff()
        while (true) {
            diagnostics.record("usbStartRequested")
            onUpdate(Cell2JackUpdate.Connecting)
            val startedAt = clock()
            val link = try {
                open()
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                val message = "Phone keypad unavailable: " + (e.message ?: e.javaClass.simpleName)
                diagnostics.record("usbStopped", "result" to message)
                onUpdate(Cell2JackUpdate.Finished(message))
                null
            }
            link?.let { Cell2JackSession(it, diagnostics, clock).run { update -> report(update, startedAt, backoff, onUpdate) } }
            val delaySeconds = backoff.next()
            diagnostics.record("usbRetryScheduled", "delaySeconds" to delaySeconds)
            onUpdate(Cell2JackUpdate.Retrying(delaySeconds))
            delay(delaySeconds * 1_000L)
        }
    }

    private fun report(update: Cell2JackUpdate, startedAt: Long, backoff: Cell2JackBackoff, onUpdate: (Cell2JackUpdate) -> Unit) {
        when (update) {
            Cell2JackUpdate.Ready -> diagnostics.record("usbReady")
            is Cell2JackUpdate.Health -> {
                // A briefly responsive but faulty adapter must not reset the backoff on every attempt.
                if (update.bytes > 0 && clock() - startedAt >= healthyMs) backoff.reset()
                diagnostics.record("usbHealth", "bytes" to update.bytes, "packets" to update.packets, "primaryDigits" to update.primaryDigits)
            }
            is Cell2JackUpdate.Finished -> diagnostics.record("usbStopped", "result" to update.message)
            Cell2JackUpdate.Connecting, is Cell2JackUpdate.Keys, is Cell2JackUpdate.Retrying -> {}
        }
        onUpdate(update)
    }

    private companion object { const val healthyMs = 30_000L }
}
