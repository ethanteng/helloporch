package com.ethanteng.helloporch.core

import java.time.Instant
import java.time.ZoneId
import kotlinx.serialization.KSerializer
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.descriptors.PrimitiveKind
import kotlinx.serialization.descriptors.PrimitiveSerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder

@Serializable
data class BedsidePreferences(
    val appearance: Appearance = Appearance.DEFAULT,
    val hemisphere: Hemisphere = Hemisphere.NORTHERN,
    val dayStart: Int = 6,
    val nightStart: Int = 18,
    @Serializable(with = LanguageOrEnglish::class) val language: BedsideLanguage = BedsideLanguage.ENGLISH,
    /** Voice identifiers are local to this device and remembered separately per language. */
    val announcementVoiceIdentifiers: Map<String, String> = emptyMap(),
) {
    @Serializable
    enum class Appearance { @SerialName("default") DEFAULT, @SerialName("dynamic") DYNAMIC }

    @Serializable
    enum class Hemisphere { @SerialName("northern") NORTHERN, @SerialName("southern") SOUTHERN }

    fun announcementVoiceIdentifier(language: BedsideLanguage): String? = announcementVoiceIdentifiers[language.code]

    fun withAnnouncementVoiceIdentifier(identifier: String?, language: BedsideLanguage): BedsidePreferences = copy(
        announcementVoiceIdentifiers = if (identifier == null) announcementVoiceIdentifiers - language.code
        else announcementVoiceIdentifiers + (language.code to identifier))

    fun save(settings: PorchSettings) {
        val valid = copy(dayStart = dayStart.coerceIn(0, 11), nightStart = nightStart.coerceIn(12, 23))
        settings.putString(key, PorchJson.encodeToString(serializer(), valid))
    }

    companion object {
        private const val key = "porch.bedsideDisplay.v1"

        fun load(settings: PorchSettings): BedsidePreferences {
            val saved = settings.getString(key)?.let {
                try { PorchJson.decodeFromString(serializer(), it) } catch (_: IllegalArgumentException) { null }
            }
            return saved?.takeIf { it.dayStart in 0..11 && it.nightStart in 12..23 } ?: BedsidePreferences()
        }
    }
}

/** A language this app doesn't know, such as one a newer version saved, reads as English. */
internal object LanguageOrEnglish : KSerializer<BedsideLanguage> {
    override val descriptor = PrimitiveSerialDescriptor("BedsideLanguageOrEnglish", PrimitiveKind.STRING)
    override fun serialize(encoder: Encoder, value: BedsideLanguage) = encoder.encodeString(value.code)
    override fun deserialize(decoder: Decoder) = BedsideLanguage.fromCode(decoder.decodeString()) ?: BedsideLanguage.ENGLISH
}

/** An orientation cue based on a caregiver's daily schedule, not an astronomical
 * sunrise forecast. It needs no location access and always uses the local date. */
class BedsideScene(date: Instant, preferences: BedsidePreferences, zone: ZoneId = ZoneId.systemDefault()) {
    enum class Season(val rawValue: String) { SPRING("Spring"), SUMMER("Summer"), FALL("Fall"), WINTER("Winter") }
    enum class Period(val rawValue: String) { MORNING("Morning"), AFTERNOON("Afternoon"), EVENING("Evening"), NIGHT("Night") }

    val season: Season
    val period: Period
    val isDay: Boolean
    val progress: Double
    val hour: Double

    init {
        val local = date.atZone(zone)
        hour = local.hour + local.minute / 60.0 + local.second / 3600.0
        val day = preferences.dayStart.toDouble()
        val night = preferences.nightStart.toDouble()
        isDay = hour >= day && hour < night
        progress = if (isDay) (hour - day) / (night - day)
        else (if (hour >= night) hour - night else hour + 24 - night) / (24 - night + day)
        period = if (isDay) (if (hour < 12) Period.MORNING else Period.AFTERNOON)
        else if (hour >= night && hour < minOf(22.0, night + 3)) Period.EVENING else Period.NIGHT
        val month = (local.monthValue - 1 + if (preferences.hemisphere == BedsidePreferences.Hemisphere.SOUTHERN) 6 else 0) % 12 + 1
        season = when (month) {
            in 3..5 -> Season.SPRING
            in 6..8 -> Season.SUMMER
            in 9..11 -> Season.FALL
            else -> Season.WINTER
        }
    }

    override fun equals(other: Any?) = other is BedsideScene && other.season == season && other.period == period &&
        other.isDay == isDay && other.progress == progress && other.hour == hour
    override fun hashCode() = listOf(season, period, isDay, progress, hour).hashCode()
    override fun toString() = "BedsideScene(season=$season, period=$period, isDay=$isDay, progress=$progress, hour=$hour)"
}
