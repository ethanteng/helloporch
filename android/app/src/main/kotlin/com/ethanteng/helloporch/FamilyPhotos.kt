package com.ethanteng.helloporch

import android.content.Context
import android.graphics.Bitmap
import android.graphics.ImageDecoder
import android.net.Uri
import android.os.SystemClock
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.setValue
import com.ethanteng.helloporch.core.CallSlots
import com.ethanteng.helloporch.core.ContactPhotoStore
import com.ethanteng.helloporch.core.FamilyCredential
import com.ethanteng.helloporch.core.FamilyServiceException
import com.ethanteng.helloporch.core.FamilySnapshot
import java.io.ByteArrayOutputStream
import java.util.concurrent.TimeUnit
import kotlin.math.roundToInt
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody

/**
 * Family members' photos from Porch, kept on the bedside under their content ID (the SHA-256 of the JPEG), as iOS's
 * FamilyPhotos keeps them: everyone's current photo, for the keypad, calls and caregiver mode. A family phone's own
 * photo comes with profiles. Main thread only, apart from the downloads and uploads.
 */
object FamilyPhotos {
    /** Goes up as each photo is saved, so screens that show photos read them again. */
    var saved by mutableIntStateOf(0)
        private set
    private val loading = mutableSetOf<String>()
    /** When a photo that couldn't be downloaded may be tried again, in elapsed milliseconds. */
    private val retryAfter = mutableMapOf<String, Long>()
    /** The photos kept at the last prune, and when it ran, in elapsed milliseconds. */
    private var kept: Set<String>? = null
    private var prunedAt = 0L
    private val client by lazy { OkHttpClient.Builder().callTimeout(60, TimeUnit.SECONDS).build() }
    private val uploads by lazy { OkHttpClient.Builder().callTimeout(120, TimeUnit.SECONDS).build() }

    /** A family member's photo, if this tablet has it. */
    fun data(app: PorchApplication, id: String?): ByteArray? = id?.let { app.photos.familyMembers.data(it) }

    /**
     * With every bedside snapshot: downloads the photos the bedside shows, and deletes ones it no longer needs a day
     * after they were saved. A key keeps its previous photo until the new one has downloaded, and a removed member's
     * photo until a caregiver edits that key, so those stay too.
     */
    fun sync(app: PorchApplication, state: FamilySnapshot, credential: FamilyCredential, slots: CallSlots) {
        val wanted = state.people.mapNotNull { person -> person.photoID?.let { it to person.id } }.toMap()
        for ((id, memberID) in wanted) load(app, id, mapOf("memberID" to JsonPrimitive(memberID)), credential)
        // A key keeps its previous photo, and a removed member's, until those IDs leave this set. A photo is deleted a
        // day after it was saved, which can be later than the check-in that dropped it, so pruning runs again hourly,
        // not on every check-in, which would read the folder on the main thread every two seconds.
        val keep = wanted.keys + slots.contacts.mapNotNull { it?.memberPhotoID }
        val now = SystemClock.elapsedRealtime()
        if (keep != kept || now - prunedAt >= 3_600_000) {
            kept = keep
            prunedAt = now
            app.photos.familyMembers.prune(keeping = keep)
        }
    }

    /** Starts downloading a photo unless it's already here, downloading, or failed in the last minute. */
    private fun load(app: PorchApplication, id: String, values: Map<String, JsonElement>, credential: FamilyCredential) {
        val store = app.photos.familyMembers
        if (store.contains(id) || id in loading || (retryAfter[id] ?: 0) > SystemClock.elapsedRealtime()) return
        loading += id
        app.scope.launch {
            try {
                val photo = app.service(credential).send("profilePhoto", values).photo
                    ?: throw FamilyServiceException("This photo isn't available.", 404)
                val data = withContext(Dispatchers.IO) {
                    client.newCall(Request.Builder().url(photo.url).build()).execute().use { http ->
                        val source = http.body.source()
                        // More than a photo can be is refused before it's read.
                        if (http.code != 200 || source.request(ContactPhotoStore.maximumBytes + 1)) null else source.buffer.readByteArray()
                    }
                }
                // The server can't see inside the photo, so the device that shows it checks it.
                if (data == null || ContactPhotoStore.id(data) != photo.id) throw FamilyServiceException("This photo couldn't be downloaded.", 502)
                withContext(Dispatchers.IO) { store.add(data) }
                saved++
                app.photoSaved()
            } catch (e: CancellationException) {
                throw e
            } catch (_: Exception) {
                retryAfter[id] = SystemClock.elapsedRealtime() + 60_000
            } finally {
                loading -= id
            }
        }
    }

    /**
     * Uploads a photo, such as a caregiver's choice for a family member (`overridePhotoUpload`), and gives the reference
     * `setMemberOverride` saves. The photo is kept here too, so it shows before the next check-in.
     */
    suspend fun upload(app: PorchApplication, data: ByteArray, action: String, values: Map<String, JsonElement>, credential: FamilyCredential,
        pin: String?): JsonObject {
        val created = app.service(credential).send(action, values + ("sizeBytes" to JsonPrimitive(data.size)), pin = pin)
        val target = created.upload
        val pathname = created.pathname
        if (target == null || pathname == null) throw FamilyServiceException("Couldn't upload the photo. Try again.", 503)
        val status = withContext(Dispatchers.IO) {
            val request = Request.Builder().url(target.url).method(target.method, data.toRequestBody())
            // Exactly the headers the server signed, Content-Type among them.
            target.headers.forEach { (name, value) -> request.header(name, value) }
            uploads.newCall(request.build()).execute().use { it.code }
        }
        if (status !in 200..299) throw FamilyServiceException("The photo didn't upload. Check the connection and try again.", status, "upload")
        withContext(Dispatchers.IO) { app.photos.familyMembers.add(data) }
        saved++
        return JsonObject(mapOf("id" to JsonPrimitive(ContactPhotoStore.id(data)), "pathname" to JsonPrimitive(pathname)))
    }

    /**
     * A chosen photo as Porch keeps them, for keys and profiles alike: upright, its longest side at most 768 pixels, and
     * a JPEG under 1 MB. Null when it can't be opened.
     */
    suspend fun prepared(context: Context, uri: Uri): ByteArray? = withContext(Dispatchers.IO) {
        try {
            // ImageDecoder turns the photo upright, as its camera saved it.
            val bitmap = ImageDecoder.decodeBitmap(ImageDecoder.createSource(context.contentResolver, uri)) { decoder, info, _ ->
                decoder.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
                val longest = maxOf(info.size.width, info.size.height)
                if (longest > LONGEST_SIDE) {
                    val scale = LONGEST_SIDE.toFloat() / longest
                    decoder.setTargetSize((info.size.width * scale).roundToInt().coerceAtLeast(1), (info.size.height * scale).roundToInt().coerceAtLeast(1))
                }
            }
            var quality = 82
            while (quality >= 40) {
                val jpeg = ByteArrayOutputStream()
                bitmap.compress(Bitmap.CompressFormat.JPEG, quality, jpeg)
                if (jpeg.size() <= ContactPhotoStore.maximumBytes) return@withContext jpeg.toByteArray()
                quality -= 10
            }
            null
        } catch (e: CancellationException) {
            throw e
        } catch (_: Exception) {
            null
        }
    }

    private const val LONGEST_SIDE = 768
}
