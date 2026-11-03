package com.ethanteng.helloporch.core

/** Measures one continuous silent interval using a monotonic clock in milliseconds supplied by
 * the caller. Ringing, fallback setup and reconnection each clear the interval. */
class CallInactivityTimer(timeout: Double?, private val clock: () -> Long) {
    /** Seconds of silence before the call ends, or null for never. */
    val timeout: Double? = timeout?.takeIf { it.isFinite() && it > 0 }
    private var lastActivity: Long? = null

    fun reset() { lastActivity = null }

    fun update(connected: Boolean, speaking: Boolean): Boolean {
        val timeout = timeout
        if (timeout == null || !connected) { reset(); return false }
        val now = clock()
        val lastActivity = lastActivity
        if (lastActivity == null || now < lastActivity || speaking) {
            this.lastActivity = now
            return false
        }
        return now - lastActivity >= timeout * 1000
    }
}
