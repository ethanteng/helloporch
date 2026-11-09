package com.ethanteng.helloporch.core

import java.time.Instant
import java.time.ZoneId
import kotlinx.serialization.Serializable

/** Playing waiting messages when someone sits in front of the bedside iPad. Kept on this iPad,
 * on until a caregiver turns it off, and limited to waking hours. */
@Serializable
data class MessageAutoplay(
    val enabled: Boolean = true,
    /** Local hours, start inclusive and end exclusive: 8 and 21 mean 8:00 AM until 9:00 PM. */
    val startHour: Int = 8,
    val endHour: Int = 21,
) {
    /** Within the hours. A start after the end wraps past midnight. */
    fun allows(date: Instant, zone: ZoneId = ZoneId.systemDefault()): Boolean {
        if (!enabled || startHour == endHour) return enabled
        val hour = date.atZone(zone).hour
        return if (startHour < endHour) hour in startHour until endHour else hour >= startHour || hour < endHour
    }

    fun save(settings: PorchSettings) {
        val valid = copy(startHour = startHour.coerceIn(0, 23), endHour = endHour.coerceIn(0, 23))
        settings.putString(key, PorchJson.encodeToString(serializer(), valid))
    }

    companion object {
        val hourRange = 0..23
        /** After Not now or Stop, the camera waits this long before trying again. */
        const val snoozeSeconds: Double = 30 * 60.0
        private const val key = "porch.messageAutoplay.v1"

        fun load(settings: PorchSettings): MessageAutoplay {
            val saved = settings.getString(key)?.let {
                try { PorchJson.decodeFromString(serializer(), it) } catch (_: IllegalArgumentException) { null }
            }
            return saved?.takeIf { it.startHour in hourRange && it.endHour in hourRange } ?: MessageAutoplay()
        }

        /** After Stop: messages that were already waiting when playback started and still are.
         * A message that arrived during playback is left out, so it can start on its own. */
        fun deferredMessageIDs(startedWith: List<String>, stillReady: List<String>): Set<String> {
            val started = startedWith.toSet()
            return stillReady.filter { it in started }.toSet()
        }

        /** The counts the notice may say, for natural voices to have ready: what's ready (downloaded and not played),
         * which is below the inbox's `total` while a message is still downloading or was played here before the server
         * drops it, then `total`. */
        fun noticeCounts(total: Int, ready: Int): List<Int> =
            (if (total > 1 && ready in 1 until total) listOf(ready) else emptyList()) + (if (total > 0) listOf(total) else emptyList())
    }
}

/** After Not now or Stop: the messages that were waiting, left alone `until` (seconds on any steady clock) unless a new
 * one arrives, as iOS's clock keeps it. */
data class AutoplaySnooze(val until: Double, val ids: Set<String>) {
    /** Whether it still holds back `waiting` at `now`. */
    fun holds(waiting: List<String>, now: Double): Boolean = now < until && ids.containsAll(waiting)

    companion object {
        /** From `now`, for what's `waiting`, or null when nothing is. */
        fun of(waiting: Collection<String>, now: Double): AutoplaySnooze? =
            if (waiting.isEmpty()) null else AutoplaySnooze(now + MessageAutoplay.snoozeSeconds, waiting.toSet())
    }
}

/** Decides from face detections that someone is sitting in front of the iPad: a face large enough
 * to be close by, seen steadily for a couple of seconds. Someone walking past or across the room
 * doesn't count. It fires once, then needs a reset. */
class PresenceTrigger(
    /** Face height as a fraction of the frame. About 0.12 is a face roughly an arm's length or two away. */
    val minimumFaceHeight: Double = 0.12,
    val requiredSeconds: Double = 2.0,
    /** A short miss (a blink, a turned head) doesn't restart the count. */
    val allowedGap: Double = 1.0,
) {
    private var since: Double? = null
    private var lastSeen: Double? = null
    private var fired = false

    /** One analyzed frame: the height of the largest face found, or null for none. Returns true
     * the first time someone has been present long enough. */
    fun observe(faceHeight: Double?, time: Double): Boolean {
        if (fired) return false
        val last = lastSeen
        if (faceHeight != null && faceHeight >= minimumFaceHeight) {
            if (last != null && time - last > allowedGap) since = null
            val start = since ?: time
            since = start
            lastSeen = time
            if (time - start >= requiredSeconds) { fired = true; return true }
        } else if (last != null && time - last > allowedGap) {
            since = null; lastSeen = null
        }
        return false
    }

    fun reset() { since = null; lastSeen = null; fired = false }
}
