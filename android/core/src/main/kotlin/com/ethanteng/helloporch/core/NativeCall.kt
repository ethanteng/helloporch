package com.ethanteng.helloporch.core

import java.net.URI
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/** A Porch call room and whether it starts with video. Decoding saved data checks the room again. */
@Serializable
data class NativeCall(val room: String, val mode: Mode) {
    @Serializable
    enum class Mode { @SerialName("voice") VOICE, @SerialName("video") VIDEO }

    init {
        if (!roomPattern.matches(room)) throw ValidationException(
            "Use a room name with 1–64 lowercase letters, numbers, or hyphens, starting with a letter or number.")
    }

    companion object {
        private val roomPattern = Regex("^[a-z0-9][a-z0-9-]{0,63}$")
        /** A room as someone typed it, trimmed and in lowercase. */
        fun of(room: String, mode: Mode) = NativeCall(room.trim().lowercase(), mode)
    }
}

/** A Porch server: HTTPS, or HTTP on this computer for testing, with no path, query, fragment or login. */
class NativeCallServer(url: String, accessCode: String) {
    /** The server's origin, such as `https://porch-calling-prototype.vercel.app`, with no trailing slash. */
    val baseURL: String
    val accessCode: String
    val tokenURL: String get() = "$baseURL/api/calls/token"

    init {
        val uri = try { URI(url.trim()) } catch (_: Exception) { null }
        val host = uri?.host
        val valid = uri != null && !host.isNullOrEmpty() && uri.rawUserInfo == null && uri.rawQuery == null && uri.rawFragment == null &&
            (uri.rawPath.isNullOrEmpty() || uri.rawPath == "/") &&
            (uri.scheme == "https" || (uri.scheme == "http" && host in localHosts))
        if (!valid) throw ValidationException(
            "Enter your Porch server's HTTPS address, without a path, query, or login. HTTP localhost is allowed for simulator testing.")
        baseURL = "${uri.scheme}://${uri.rawAuthority}"
        val code = accessCode.trim()
        if (code.length !in 16..256 || code.any { it.code !in 0x21..0x7E }) throw ValidationException(
            "Enter the server's prototype access code: 16–256 characters with no spaces.")
        this.accessCode = code
    }

    override fun equals(other: Any?) = other is NativeCallServer && other.baseURL == baseURL && other.accessCode == accessCode
    override fun hashCode() = 31 * baseURL.hashCode() + accessCode.hashCode()

    private companion object {
        val localHosts = setOf("localhost", "127.0.0.1", "[::1]")
    }
}
