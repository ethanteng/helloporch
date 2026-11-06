package com.ethanteng.helloporch.core

import java.net.URI

/** Where a call's media goes, as `joinCall` gives it. */
object LiveKitAddress {
    /**
     * A secure LiveKit address, as iOS requires (`wss`). An unencrypted one (`ws`) is allowed only on this device, for
     * a LiveKit server run on a computer for testing and reached through `adb reverse` (android/README.md). Porch's
     * server only ever hands out `wss` addresses.
     */
    fun isAllowed(url: String): Boolean {
        val uri = try { URI(url.trim()) } catch (_: Exception) { return false }
        val host = uri.host?.lowercase() ?: return false
        if (uri.rawUserInfo != null) return false
        return when (uri.scheme?.lowercase()) {
            "wss" -> true
            "ws" -> host in localHosts
            else -> false
        }
    }

    private val localHosts = setOf("localhost", "127.0.0.1", "[::1]")
}
