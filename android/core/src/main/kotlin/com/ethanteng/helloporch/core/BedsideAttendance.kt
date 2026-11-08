package com.ethanteng.helloporch.core

import java.time.Duration
import java.time.Instant

/** Whether someone is at the bedside, so family can tell whether a call now is likely to be answered. The bedside
 * notices someone when a key is pressed or the screen is touched and, if a caregiver turns it on, when its camera sees
 * a face close by. It can't tell who: an aide or a visitor counts too. Family only learn when, never how. */
object BedsideAttendance {
    /** Noticed this recently counts as there now. The camera looks every `lookInterval`, so someone sitting still stays
     * "at the tablet" between looks, and a look or two that misses a turned head doesn't change that. */
    const val presentSeconds: Double = 90.0
    /** After this long, family see nothing rather than a stale time. */
    const val shownSeconds: Double = 7 * 86400.0
    /** The camera looks for a face this often, for up to `lookSeconds`, and stops as soon as it sees one. */
    const val lookInterval: Double = 30.0
    const val lookSeconds: Double = 5.0

    /** What family see under the bedside's name, from server times. `device` is what they call the bedside: "iPad", or
     * "tablet" for an Android one. Null before anyone has been noticed, or once it's been a week. It never says no one
     * is there: the camera can't see in the dark or across the room, and someone in bed can still hear a call ring. */
    fun text(attendedAt: Double?, now: Double, device: String): String? {
        if (attendedAt == null) return null
        if (isPresent(attendedAt, now)) return "Someone is at the $device"
        val age = now - attendedAt
        if (age >= shownSeconds) return null
        return "Someone was at the $device ${ago(age)}"
    }

    /** Noticed recently enough to count as there now. A server time a little behind the bedside's report still is. */
    fun isPresent(attendedAt: Double?, now: Double): Boolean {
        if (attendedAt == null) return false
        return now - attendedAt < presentSeconds
    }

    internal fun ago(seconds: Double): String {
        val minutes = (seconds / 60).toInt()
        if (minutes < 60) return if (minutes == 1) "1 minute ago" else "$minutes minutes ago"
        val hours = minutes / 60
        if (hours < 24) return if (hours == 1) "1 hour ago" else "$hours hours ago"
        val days = hours / 24
        return if (days == 1) "1 day ago" else "$days days ago"
    }

    // The camera's part is a caregiver's choice, kept on this bedside like starting messages when someone sits down.
    private const val cameraKey = "porch.attendanceCamera.v1"

    /** The camera also looks for someone, so family can see they're there. Off until a caregiver turns it on. */
    fun cameraEnabled(settings: PorchSettings): Boolean = settings.getBoolean(cameraKey) ?: false
    fun setCameraEnabled(enabled: Boolean, settings: PorchSettings) = settings.putBoolean(cameraKey, enabled)
}

/** When this bedside last noticed someone. Main thread only. Kept for this launch; the server keeps the newest it heard. */
class AttendanceTracker(private val clock: () -> Instant = { Instant.now() }) {
    private var noticedAt: Instant? = null

    fun noticed() { noticedAt = clock() }

    /** While a caregiver has sharing off, so turning it back on can't report someone who was there meanwhile. */
    fun forget() { noticedAt = null }

    /** Whole seconds since then, for the bedside's poll. Null until someone has been noticed, and null when the clock has
     * jumped back: reporting 0 would tell family someone just arrived. Seconds ago rather than a time, so a clock that
     * is merely wrong, but still running forward, doesn't matter. */
    val secondsSince: Int?
        get() {
            val noticedAt = noticedAt ?: return null
            val elapsed = Duration.between(noticedAt, clock())
            if (elapsed.isNegative) return null
            return elapsed.seconds.toInt()
        }

    companion object {
        val shared = AttendanceTracker()
    }
}
