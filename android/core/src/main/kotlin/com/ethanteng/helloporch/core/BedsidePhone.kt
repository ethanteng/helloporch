package com.ethanteng.helloporch.core

import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.util.Locale
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

/**
 * What the bedside's check-ins say about its desk phone (lib/family/bedside-phone.ts), so caregivers hear when it's been
 * out for a while. An Android tablet only ever has a Cell2Jack, plugged into its USB port, which Porch talks to itself.
 */
sealed class BedsidePhoneReport {
    /** No phone set up here: the phone keypad is off. The server forgets the phone. */
    data object NotSetUp : BedsidePhoneReport()

    /** The Cell2Jack, answering or not. */
    data class Cell2Jack(val connected: Boolean) : BedsidePhoneReport()

    /** The check-in's `phone`: null with no phone set up, else its kind and whether it's connected. */
    val json: JsonElement get() = when (this) {
        NotSetUp -> JsonNull
        is Cell2Jack -> JsonObject(mapOf("kind" to JsonPrimitive(BedsidePhone.CELL2JACK), "connected" to JsonPrimitive(connected)))
    }

    companion object {
        /**
         * What to report, or null when Porch can't tell, and the check-in leaves `phone` out so the server keeps the last
         * report: the Cell2Jack connection runs only while the bedside is in front. `setUp` is the phone keypad being on,
         * and `connected` the Cell2Jack answering, as This tablet's Connect the physical phone shows them.
         */
        fun of(inFront: Boolean, setUp: Boolean, connected: Boolean): BedsidePhoneReport? = when {
            !inFront -> null
            !setUp -> NotSetUp
            else -> Cell2Jack(connected)
        }
    }
}

/**
 * Family caregivers: the bedside's desk phone, once it's been out long enough that caregivers were told, until it's back.
 * `since` is when it went out, in server time. `kind` is how it's plugged in, so the steps to check match: "cell2jack", a
 * Cell2Jack the bedside talks to itself (USB on an Android tablet, Porch's driver on an iPad), or "adapter", the Porch
 * phone adapter on an iPad. Older servers don't send it.
 */
@Serializable
data class BedsidePhone(val since: Long, val kind: String) {
    /** What to check at the bedside, plug by plug. `bedsideDevice` is "tablet" for an Android one, "iPad" otherwise. */
    fun steps(bedsideDevice: String): List<String> = when {
        kind == ADAPTER -> listOf("Phone cord into the Cell2Jack", "Cell2Jack into the adapter", "Adapter into the hub by the iPad")
        bedsideDevice == ANDROID_DEVICE -> listOf("Phone cord into the Cell2Jack", "Cell2Jack into the hub by the tablet")
        else -> listOf("Phone cord into the Cell2Jack", "Cell2Jack into the iPad or its hub")
    }

    /** The setup guide's part on the desk phone, for the bedside's kind of device. */
    fun guideURL(bedsideDevice: String): String = if (bedsideDevice == ANDROID_DEVICE) ANDROID_GUIDE else IOS_GUIDE

    /** When it went out, by this phone's clock, as Every call says when it was turned on: "2:14 PM" today, otherwise
     * "Nov 23, 2:14 PM". */
    fun time(now: Instant, zone: ZoneId, locale: Locale = Locale.getDefault()): String {
        val at = Instant.ofEpochSecond(since).atZone(zone)
        val clock = DateTimeFormatter.ofLocalizedTime(FormatStyle.SHORT).withLocale(locale).format(at)
        if (at.toLocalDate() == now.atZone(zone).toLocalDate()) return clock
        return "${DateTimeFormatter.ofPattern("MMM d", locale).format(at)}, $clock"
    }

    /** What Share these steps sends, for someone at the bedside to follow. */
    fun shareText(name: String, bedsideDevice: String): String = buildString {
        append("$name’s phone isn’t connected to Porch. At $name’s $bedsideDevice, please check each plug:\n")
        steps(bedsideDevice).forEachIndexed { index, step -> append("${index + 1}. $step\n") }
        append("Step-by-step: ${guideURL(bedsideDevice)}")
    }

    companion object {
        const val CELL2JACK = "cell2jack"
        const val ADAPTER = "adapter"
        /** What `bedsideDevice` calls an Android bedside. */
        private const val ANDROID_DEVICE = "tablet"
        const val IOS_GUIDE = "https://helloporch.store/pilot/ios#phone"
        const val ANDROID_GUIDE = "https://helloporch.store/pilot/android#phone"

        /** Under the banner's title: "Since 2:14 PM". */
        fun since(time: String) = "Since $time"

        /** The banner as TalkBack reads it: "Rose’s phone isn’t connected. Since 2:14 PM". */
        fun notConnectedDescription(name: String, time: String) = "$name’s phone isn’t connected. ${since(time)}"

        /** The sheet's status while it's still out: "Not connected · since 2:14 PM". */
        fun notConnected(time: String) = "Not connected · since $time"

        /** The sheet's title: "Reconnect Rose’s phone". */
        fun reconnect(name: String) = "Reconnect $name’s phone"

        /** Above the steps: "At Rose’s tablet, check each plug:". */
        fun checkEachPlug(name: String, bedsideDevice: String) = "At $name’s $bedsideDevice, check each plug:"
    }
}
