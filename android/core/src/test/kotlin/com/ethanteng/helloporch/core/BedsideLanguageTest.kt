package com.ethanteng.helloporch.core

import java.time.ZoneOffset
import java.time.ZonedDateTime
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import kotlin.math.abs
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

class BedsideLanguageTest {
    @Test fun olderDisplaySettingsKeepTheirScheduleAndDefaultToEnglish() {
        val saved = PorchJson.decodeFromString<BedsidePreferences>("""{"appearance":"dynamic","hemisphere":"southern","dayStart":7,"nightStart":21}""")
        assertEquals(BedsidePreferences.Appearance.DYNAMIC, saved.appearance); assertEquals(BedsidePreferences.Hemisphere.SOUTHERN, saved.hemisphere)
        assertEquals(7, saved.dayStart); assertEquals(21, saved.nightStart); assertEquals(BedsideLanguage.ENGLISH, saved.language)
        assertTrue(saved.announcementVoiceIdentifiers.isEmpty())
        for (language in BedsideLanguage.entries) {
            val localized = saved.copy(language = language)
            assertEquals(localized, PorchJson.decodeFromString<BedsidePreferences>(PorchJson.encodeToString(localized)))
        }
        val future = """{"appearance":"dynamic","dayStart":7,"nightStart":21,"language":"future"}"""
        assertEquals(BedsideLanguage.ENGLISH, PorchJson.decodeFromString<BedsidePreferences>(future).language)
    }

    @Test fun announcementVoiceChoicesSurviveLanguageChangesAndRelaunch() {
        val settings = MemorySettings()
        var preferences = BedsidePreferences(dayStart = 7, nightStart = 21, hemisphere = BedsidePreferences.Hemisphere.SOUTHERN)
        for (language in BedsideLanguage.entries) {
            assertNull(preferences.announcementVoiceIdentifier(language))
            preferences = preferences.withAnnouncementVoiceIdentifier("voice-${language.code}", language)
        }
        preferences = preferences.copy(language = BedsideLanguage.CANTONESE)
        preferences.save(settings)
        var loaded = BedsidePreferences.load(settings)
        assertEquals(preferences, loaded)
        loaded = loaded.copy(language = BedsideLanguage.SPANISH).withAnnouncementVoiceIdentifier(null, BedsideLanguage.SPANISH)
        loaded.save(settings)
        val reopened = BedsidePreferences.load(settings)
        assertNull(reopened.announcementVoiceIdentifier(BedsideLanguage.SPANISH))
        for (language in BedsideLanguage.entries.filter { it != BedsideLanguage.SPANISH }) {
            assertEquals("voice-${language.code}", reopened.announcementVoiceIdentifier(language))
        }
        assertEquals(7, reopened.dayStart); assertEquals(21, reopened.nightStart)
        assertEquals(BedsidePreferences.Hemisphere.SOUTHERN, reopened.hemisphere)
    }

    @Test fun voiceMatchingAllowsRegionalAccentsButKeepsChineseDialectsSeparate() {
        val cases = listOf(
            "en-US" to BedsideLanguage.ENGLISH, "en-GB" to BedsideLanguage.ENGLISH, "en_AU" to BedsideLanguage.ENGLISH,
            "es-ES" to BedsideLanguage.SPANISH, "es-MX" to BedsideLanguage.SPANISH, "es-US" to BedsideLanguage.SPANISH,
            "zh-TW" to BedsideLanguage.TRADITIONAL_CHINESE, "zh-Hant-TW" to BedsideLanguage.TRADITIONAL_CHINESE, "cmn-TW" to BedsideLanguage.TRADITIONAL_CHINESE,
            "zh-CN" to BedsideLanguage.SIMPLIFIED_CHINESE, "zh-Hans-CN" to BedsideLanguage.SIMPLIFIED_CHINESE, "cmn-CN" to BedsideLanguage.SIMPLIFIED_CHINESE,
            "zh-HK" to BedsideLanguage.CANTONESE, "zh-Hant-HK" to BedsideLanguage.CANTONESE, "yue-HK" to BedsideLanguage.CANTONESE, "yue-Hant-HK" to BedsideLanguage.CANTONESE,
        )
        for ((tag, expected) in cases) {
            for (language in BedsideLanguage.entries) {
                assertEquals(language == expected, language.supportsSpeechVoice(tag), "$tag / $language")
            }
        }
        for (unsupported in listOf("fr-FR", "zh", "zh-SG", "enochian", "", "yue-CN")) {
            assertFalse(BedsideLanguage.entries.any { it.supportsSpeechVoice(unsupported) }, unsupported)
        }
    }

    @Test fun everyLanguageCoversAllBedsideStringsAndPreservesFormatArguments() {
        val keys = BedsideLanguage.TRADITIONAL_CHINESE.translations.keys
        val placeholders = Regex("%[@d]")
        fun arguments(text: String) = placeholders.findAll(text).map { it.value }.toList()
        for (language in BedsideLanguage.entries.filter { it != BedsideLanguage.ENGLISH }) {
            assertEquals(keys, language.translations.keys, language.code)
            for (key in keys) {
                val text = language.text(key)
                assertFalse(text.isEmpty(), "$language: $key")
                assertNotEquals(key, text, "$language: $key")
                assertEquals(arguments(key), arguments(text), "$language: $key")
            }
            assertTrue(language.format("Call %@, key %@", "María 陳", "#").contains("María 陳"))
            assertTrue(language.format("Call %@, key %@", "María 陳", "#").contains("#"))
        }
    }

    @Test fun newLanguagesUseDistinctTranslationsAndAnnouncementVoices() {
        assertEquals("挂断", BedsideLanguage.SIMPLIFIED_CHINESE.text("End call"))
        assertEquals("收線", BedsideLanguage.CANTONESE.text("End call"))
        assertEquals("Colgar", BedsideLanguage.SPANISH.text("End call"))
        assertEquals("zh-CN", BedsideLanguage.SIMPLIFIED_CHINESE.speechLanguage)
        assertEquals("zh-HK", BedsideLanguage.CANTONESE.speechLanguage)
        assertEquals("es-ES", BedsideLanguage.SPANISH.speechLanguage)
        assertEquals("陳先生想同您視像通話，五秒後接通。", BedsideLanguage.CANTONESE.format("%@ is dropping in with video. Connecting in five seconds.", "陳先生"))
        assertEquals("视频自动接听\n5 秒后接通…", BedsideLanguage.SIMPLIFIED_CHINESE.format("Video drop-in\nConnecting in %d…", 5))
        assertEquals("Pulse # para contestar. Mantenga pulsado # para rechazar.", BedsideLanguage.SPANISH.format("Tap %@ to answer. Hold %@ to decline.", "#", "#"))
        assertEquals("End call", BedsideLanguage.ENGLISH.text("End call"))
        assertEquals("打緊畀陳先生。", BedsideLanguage.CANTONESE.format("Calling %@.", "陳先生"))
        assertEquals("Calling David.", BedsideLanguage.ENGLISH.format("Calling %@.", "David"))
    }

    @Test fun newLanguageDatesKeepTheLocalDateAndWeekday() {
        val zone = ZoneOffset.ofHours(-7)
        val date = ZonedDateTime.of(2026, 10, 16, 23, 35, 0, 0, zone).toInstant()
        for (language in listOf(BedsideLanguage.SIMPLIFIED_CHINESE, BedsideLanguage.CANTONESE, BedsideLanguage.SPANISH)) {
            val weekday = DateTimeFormatter.ofPattern("EEEE", language.locale).withZone(zone)
            assertEquals(if (language == BedsideLanguage.SPANISH) "viernes" else "星期五", weekday.format(date))
            val text = DateTimeFormatter.ofLocalizedDate(FormatStyle.LONG).withLocale(language.locale).withZone(zone).format(date)
            assertTrue(text.contains("2026")); assertTrue(text.contains("16"))
            assertTrue(text.contains(if (language == BedsideLanguage.SPANISH) "octubre" else "10月"), text)
        }
    }

    @Test fun traditionalChineseCoversOrientationAndCallActions() {
        val language = BedsideLanguage.TRADITIONAL_CHINESE
        for (key in listOf("Morning", "Afternoon", "Evening", "Night", "Spring", "Summer", "Fall", "Winter", "Call someone", "Who would you like to call?", "Answer video call", "Don't connect", "End call", "Back to clock")) {
            assertNotEquals(key, language.text(key))
        }
        assertEquals("打給家人，按 8", language.format("Call %@, key %@", "家人", "8"))
        assertEquals("視訊自動接聽\n5 秒後接通…", language.format("Video drop-in\nConnecting in %d…", 5))
        assertEquals("zh-TW", language.speechLanguage, "Use Mandarin, not a Cantonese voice")
        assertTrue(language.format("%@ is dropping in with video. Connecting in five seconds.", "家人").contains("視訊"))
    }

    @Test fun traditionalChineseDateKeepsTheLocalDateAndWeekday() {
        val zone = ZoneOffset.ofHours(-7)
        val date = ZonedDateTime.of(2026, 10, 16, 19, 35, 0, 0, zone).toInstant()
        val locale = BedsideLanguage.TRADITIONAL_CHINESE.locale
        assertEquals("星期五", DateTimeFormatter.ofPattern("EEEE", locale).withZone(zone).format(date))
        val text = DateTimeFormatter.ofLocalizedDate(FormatStyle.LONG).withLocale(locale).withZone(zone).format(date)
        assertTrue(text.contains("2026年")); assertTrue(text.contains("10月")); assertTrue(text.contains("16日"))
    }

    @Test fun callCuesAreValidAudiblePCMWithFadesAndRingbackSilence() {
        for (tone in CallTone.entries) {
            val data = tone.wave()
            assertEquals("RIFF", String(data, 0, 4, Charsets.US_ASCII))
            assertEquals("WAVE", String(data, 8, 4, Charsets.US_ASCII))
            assertEquals(44 + (tone.duration * 16_000).toInt() * 2, data.size)
            val samples = (44 until data.size step 2).map { ((data[it].toInt() and 0xFF) or (data[it + 1].toInt() shl 8)).toShort().toInt() }
            assertEquals(0, samples.first()); assertTrue(abs(samples.last()) < 250)
            assertTrue(samples.maxOf { abs(it) } > 10_000); assertTrue(samples.maxOf { abs(it) } < 30_000)
            if (tone == CallTone.RINGBACK) assertTrue(samples.drop(32_000).all { it == 0 })
        }
        assertTrue(CallTone.INCOMING.loops); assertTrue(CallTone.RINGBACK.loops)
        assertFalse(CallTone.CONNECTED.loops); assertFalse(CallTone.ANNOUNCEMENT.loops)
    }

    /** Caregiver settings say which language each Chinese choice speaks. */
    @Test fun choiceLabelsNameTheSpokenLanguage() {
        assertEquals(listOf("English", "繁體中文 · Mandarin", "简体中文 · Mandarin", "廣東話 · Cantonese", "Español"), BedsideLanguage.entries.map { it.choiceLabel })
    }
}
