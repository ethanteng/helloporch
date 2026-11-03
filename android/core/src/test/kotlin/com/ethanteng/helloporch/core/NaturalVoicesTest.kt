package com.ethanteng.helloporch.core

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull

/** The bedside's snapshot lists the natural voices a caregiver can choose for each language,
 * and the family's choice, where null means the device's built-in voice. */
class NaturalVoicesTest {
    private fun snapshot(speech: Any?, bedsideLanguage: String? = null) =
        ModelFixtures.snapshot(extra = mapOf("speech" to speech, "bedsideLanguage" to bedsideLanguage))

    @Test fun eachLanguageHasItsVoicesAndTheFamilysChoice() {
        val voices = listOf(mapOf("id" to "suk-yee", "name" to "Suk Yee", "detail" to "Direct, warm narrator · female"),
            mapOf("id" to "lucky", "name" to "Lucky Chan", "detail" to "Warm and calm · male"))
        val state = snapshot(mapOf("languages" to mapOf(
            "yue-Hant" to mapOf("selected" to "lucky", "defaultVoice" to "suk-yee", "voices" to voices),
            "es" to mapOf("selected" to null, "defaultVoice" to "eva", "voices" to listOf(mapOf("id" to "eva", "name" to "Eva Dorado", "detail" to "Warm and soft · female"))),
        )))
        val speech = assertNotNull(state.speech)
        val cantonese = assertNotNull(speech.choices(BedsideLanguage.CANTONESE))
        assertEquals("lucky", cantonese.selected)
        assertEquals("suk-yee", cantonese.defaultVoice)
        assertEquals(listOf("Suk Yee", "Lucky Chan"), cantonese.voices.map { it.name })
        assertNull(assertNotNull(speech.choices(BedsideLanguage.SPANISH)).selected, "null is the built-in voice")
        assertNull(speech.choices(BedsideLanguage.ENGLISH), "a language the server doesn't list has no natural voices")
    }

    @Test fun olderServersSendNoVoices() {
        assertNull(snapshot(null).speech)
    }

    /** Phone voicemail greets callers in the bedside language, which only the bedside knows until it reports it. */
    @Test fun savingReportsTheBedsideLanguageOnlyWhenTheServerHasAnother() {
        val english = snapshot(null, bedsideLanguage = "en")
        assertEquals(BedsideLanguage.CANTONESE, english.languageToReport(BedsideLanguage.CANTONESE))
        assertNull(english.languageToReport(BedsideLanguage.ENGLISH), "already known")
        assertNull(snapshot(null).languageToReport(BedsideLanguage.SPANISH), "older servers can't keep it")
    }
}
