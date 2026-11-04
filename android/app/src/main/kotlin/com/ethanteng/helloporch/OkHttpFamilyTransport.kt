package com.ethanteng.helloporch

import com.ethanteng.helloporch.core.FamilyTransport
import com.ethanteng.helloporch.core.TransportResponse
import java.io.IOException
import java.util.concurrent.TimeUnit
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import kotlinx.coroutines.suspendCancellableCoroutine
import okhttp3.Call
import okhttp3.Callback
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.Response

/** Porch's requests to its server. No cache and no cookies, like the iOS app's ephemeral session, and no `Origin`
 * header, which the server would reject. Cancelling the coroutine cancels the request. */
class OkHttpFamilyTransport(private val client: OkHttpClient = OkHttpClient.Builder().cache(null).build()) : FamilyTransport {
    override suspend fun post(url: String, headers: Map<String, String>, body: String, timeoutMillis: Long): TransportResponse {
        val request = Request.Builder().url(url).post(body.toRequestBody(json)).apply { headers.forEach { (name, value) -> header(name, value) } }.build()
        val call = client.newCall(request).apply { timeout().timeout(timeoutMillis, TimeUnit.MILLISECONDS) }
        return suspendCancellableCoroutine { continuation ->
            continuation.invokeOnCancellation { call.cancel() }
            call.enqueue(object : Callback {
                override fun onFailure(call: Call, e: IOException) { continuation.resumeWithException(e) }
                override fun onResponse(call: Call, response: Response) {
                    val result = try { response.use { TransportResponse(it.code, it.body.string()) } }
                        catch (e: IOException) { continuation.resumeWithException(e); return }
                    continuation.resume(result)
                }
            })
        }
    }

    private companion object { val json = "application/json".toMediaType() }
}
