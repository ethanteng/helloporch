package com.ethanteng.helloporch.core

import java.time.Instant
import java.time.ZoneId
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

/** A family phone's Do Not Disturb: Porch calls don't ring it, and your loved one can leave a message instead. On until
 * turned off, or every day for set hours, or both. Kept on this phone for all its families, each of which hears it with
 * every check-in (lib/family/do-not-disturb.ts), so the server can turn the bedside's calls away while the phone is
 * closed. Hours are whole hours on this phone's clock, as for the bedside's message hours. As on iOS. */
@Serializable
data class DoNotDisturb(
    val on: Boolean = false,
    val scheduled: Boolean = false,
    /** Start inclusive and end exclusive: 22 and 7 mean 10:00 PM until 7:00 AM. A start after the end runs past midnight,
     * and the same hour for both is all day. */
    val startHour: Int = 22,
    val endHour: Int = 7,
) {
    /** Whether Porch calls don't ring now. */
    fun applies(date: Instant, zone: ZoneId = ZoneId.systemDefault()): Boolean {
        if (on) return true
        if (!scheduled) return false
        if (startHour == endHour) return true
        val hour = date.atZone(zone).hour
        return if (startHour < endHour) hour in startHour until endHour else hour >= startHour || hour < endHour
    }

    /** What a family check-in says. Hours go with this phone's time zone, so a phone that travels keeps them on its own clock. */
    fun checkIn(zone: ZoneId = ZoneId.systemDefault()): JsonElement {
        val value = mutableMapOf<String, JsonElement>("on" to JsonPrimitive(on))
        if (scheduled) {
            value["hours"] = JsonObject(mapOf("start" to JsonPrimitive(startHour), "end" to JsonPrimitive(endHour)))
            value["timeZone"] = JsonPrimitive(zone.id)
        }
        return JsonObject(value)
    }

    fun save(settings: PorchSettings) {
        val valid = copy(startHour = startHour.coerceIn(0, 23), endHour = endHour.coerceIn(0, 23))
        settings.putString(key, PorchJson.encodeToString(serializer(), valid))
    }

    companion object {
        val hourRange = 0..23
        private const val key = "porch.doNotDisturb.v1"

        fun load(settings: PorchSettings): DoNotDisturb {
            val saved = settings.getString(key)?.let {
                try { PorchJson.decodeFromString(serializer(), it) } catch (_: IllegalArgumentException) { null }
            }
            return saved?.takeIf { it.startHour in hourRange && it.endHour in hourRange } ?: DoNotDisturb()
        }
    }
}
