package com.ethanteng.helloporch.core

/** One HTTPS POST to the Porch server. The app sends it with OkHttp, and tests answer it themselves. It throws an
 * [java.io.IOException] when the server can't be reached, and otherwise returns whatever status the server sent. */
fun interface FamilyTransport {
    suspend fun post(url: String, headers: Map<String, String>, body: String, timeoutMillis: Long): TransportResponse
}

data class TransportResponse(val status: Int, val body: String)
