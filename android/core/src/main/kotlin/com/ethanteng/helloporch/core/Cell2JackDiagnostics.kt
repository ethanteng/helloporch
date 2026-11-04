package com.ethanteng.helloporch.core

import java.time.Instant
import java.time.temporal.ChronoUnit
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

/**
 * What the Cell2Jack keypad did, for working out a problem on a tablet in someone's room: the last 200 actions, as
 * the iOS app's cell2jack-call-actions.json keeps them, and the last 64 KiB the Cell2Jack sent (cell2jack-usb-tail.bin).
 * Bounded, with no time cutoff that would remove a hang-up during a call. Safe to use from any thread; `onChange` runs
 * after each record, on the thread that made it.
 */
class Cell2JackDiagnostics(private val now: () -> Instant = Instant::now, private val onChange: () -> Unit = {}) {
    private val records = ArrayList<JsonObject>()
    private val tail = ByteArray(tailLimit)
    private var tailStart = 0
    private var tailSize = 0
    private var tailChanged = false

    /** Adds an action, such as `record("digit", "symbol" to "5")`. Values are strings, numbers, booleans or null. */
    fun record(kind: String, vararg values: Pair<String, Any?>) {
        val fields = sortedMapOf<String, JsonElement>()
        for ((key, value) in values) fields[key] = element(value)
        fields["kind"] = JsonPrimitive(kind)
        fields["utc"] = JsonPrimitive(now().truncatedTo(ChronoUnit.SECONDS).toString())
        synchronized(this) {
            // Health repeats every five seconds and its counts are cumulative; keeping only the latest one stops it
            // pushing key and call history out of the 200 records.
            if (kind == "usbHealth" && records.lastOrNull()?.get("kind") == JsonPrimitive("usbHealth")) records.removeAt(records.lastIndex)
            records.add(JsonObject(fields))
            if (records.size > recordLimit) records.subList(0, records.size - recordLimit).clear()
        }
        onChange()
    }

    fun records(): List<JsonObject> = synchronized(this) { records.toList() }

    /** The records as a JSON array, for the diagnostics file. */
    fun json(): String = format.encodeToString(JsonArray.serializer(), JsonArray(records()))

    /** Keeps bytes the Cell2Jack sent, dropping the oldest past 64 KiB. */
    fun appendRaw(bytes: ByteArray) = synchronized(this) {
        for (byte in bytes) {
            tail[(tailStart + tailSize) % tailLimit] = byte
            if (tailSize < tailLimit) tailSize += 1 else tailStart = (tailStart + 1) % tailLimit
        }
        if (bytes.isNotEmpty()) tailChanged = true
    }

    fun rawTail(): ByteArray = synchronized(this) { ByteArray(tailSize) { tail[(tailStart + it) % tailLimit] } }

    /** The raw tail when bytes arrived since the last time this returned it, so saving it can skip a quiet one. */
    fun rawTailIfChanged(): ByteArray? = synchronized(this) {
        if (!tailChanged) return null
        tailChanged = false
        rawTail()
    }

    private fun element(value: Any?): JsonElement = when (value) {
        null -> JsonNull
        is String -> JsonPrimitive(value)
        is Number -> JsonPrimitive(value)
        is Boolean -> JsonPrimitive(value)
        else -> JsonPrimitive(value.toString())
    }

    companion object {
        const val recordLimit = 200
        const val tailLimit = 65_536
        private val format = Json { prettyPrint = true }
    }
}
