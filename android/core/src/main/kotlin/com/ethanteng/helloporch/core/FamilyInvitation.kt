package com.ethanteng.helloporch.core

import java.net.URI
import java.net.URLDecoder

/** Invitation links on Porch's website: https://helloporch.store/join#code=… for a family member and /setup#code=… for a
 * new bedside. They open Porch as App Links, or show how to get it, and keep the code after `#` so it never
 * reaches a server's logs. A web link names no server: it's for the one the app is built with (`defaultOrigin`), and an
 * invitation for any other server keeps the porch:// form. */
object PorchWebLinks {
    const val host = "helloporch.store"

    internal fun code(url: URI, path: String): String? {
        val host = url.host?.lowercase() ?: return null
        if (url.scheme != "https" || (host != this.host && host != "www.${this.host}")) return null
        if ((url.path != path && url.path != "$path/") || url.rawUserInfo != null || url.port != -1 || url.rawQuery != null) return null
        val items = queryItems(url.rawFragment ?: return null) ?: return null
        val code = items.singleOrNull()?.takeIf { it.first == "code" }?.second ?: return null
        return code.takeIf { codePattern.matches(it) }
    }

    internal fun sameServer(a: String, b: String): Boolean {
        val first = uri(a) ?: return false
        val second = uri(b) ?: return false
        return first.scheme?.lowercase() == second.scheme?.lowercase() && first.host?.lowercase() == second.host?.lowercase() &&
            first.port == second.port
    }
}

/** `defaultOrigin` is the server a web link means. Without it, only porch:// links are accepted. */
class FamilyInvitation(url: String, defaultOrigin: String? = null) {
    val origin: String
    val code: String

    init {
        val (origin, code) = invitation(url, "pair", "/join", defaultOrigin)
        this.origin = origin
        this.code = code
    }

    companion object {
        /** The link to share: a web link for the app's own server (`defaultOrigin`), which opens Porch or shows how to get it,
         * and porch:// for any other. */
        fun url(origin: String, code: String, defaultOrigin: String? = null): String {
            if (defaultOrigin != null && PorchWebLinks.sameServer(origin, defaultOrigin)) {
                return "https://${PorchWebLinks.host}/join#code=$code"
            }
            return "porch://pair?server=${queryValue(origin)}&code=${queryValue(code)}"
        }

        internal const val invalid = "Paste the complete Porch invitation link from your caregiver."
    }
}

class BedsideInvitation(url: String, defaultOrigin: String? = null) {
    val origin: String
    val code: String

    init {
        val (origin, code) = invitation(url, "activate", "/setup", defaultOrigin)
        this.origin = origin
        this.code = code
    }
}

private val codePattern = Regex("^[a-f0-9]{64}$")

/** An invitation's server origin and one-time code. A porch:// link names its server, which must be one Porch can use. */
private fun invitation(url: String, host: String, webPath: String, defaultOrigin: String?): Pair<String, String> {
    val parts = uri(url) ?: throw ValidationException(FamilyInvitation.invalid)
    if (parts.scheme?.lowercase() == "https") {
        val code = defaultOrigin?.let { PorchWebLinks.code(parts, webPath) } ?: throw ValidationException(FamilyInvitation.invalid)
        return NativeCallServer(defaultOrigin, "invitation-validation-only").baseURL to code
    }
    val valid = parts.scheme == "porch" && parts.host == host && parts.rawPath.isNullOrEmpty() &&
        parts.rawUserInfo == null && parts.port == -1 && parts.rawFragment == null
    val items = parts.rawQuery?.takeIf { valid }?.let(::queryItems)
    val server = items?.singleOrNull { it.first == "server" }?.second
    val code = items?.singleOrNull { it.first == "code" }?.second
    if (items?.size != 2 || server == null || code == null || !codePattern.matches(code)) throw ValidationException(FamilyInvitation.invalid)
    return NativeCallServer(server, "invitation-validation-only").baseURL to code
}

private fun uri(text: String): URI? = try { URI(text) } catch (_: Exception) { null }

/** A query's items as URLComponents reads them: split at each & and the first =, with percent escapes decoded and +
 * kept as it is. Null if an escape is malformed. */
private fun queryItems(query: String): List<Pair<String, String?>>? = query.split('&').map { item ->
    val separator = item.indexOf('=')
    val name = decoded(if (separator < 0) item else item.substring(0, separator)) ?: return null
    val value = if (separator < 0) null else decoded(item.substring(separator + 1)) ?: return null
    name to value
}

private fun decoded(text: String): String? =
    try { URLDecoder.decode(text.replace("+", "%2B"), Charsets.UTF_8) } catch (_: IllegalArgumentException) { null }

/** Percent-encodes everything a query value can't carry as it is, including & = + and #. */
private fun queryValue(text: String): String = buildString {
    for (byte in text.toByteArray(Charsets.UTF_8)) {
        val char = (byte.toInt() and 0xFF).toChar()
        if (char in 'A'..'Z' || char in 'a'..'z' || char in '0'..'9' || char in "-._~:/?@!$'()*,;") append(char)
        else append("%%%02X".format(byte.toInt() and 0xFF))
    }
}
