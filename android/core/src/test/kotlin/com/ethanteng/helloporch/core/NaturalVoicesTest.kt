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

    private val hope = mapOf("id" to "hope", "name" to "Hope", "detail" to "Natural, clear and calm · female")
    private val linda = mapOf("id" to "lindaVoice000000001", "name" to "Linda", "detail" to "Family voice", "family" to true, "memberID" to "linda")
    private val tom = mapOf("id" to "tomVoice00000000001", "name" to "Tom", "detail" to "Family voice", "family" to true, "memberID" to "tom")

    /** Caregivers' own voices come after the listed ones, each saying whose it is. */
    @Test fun familyVoicesSayWhoseTheyAre() {
        val choices = assertNotNull(snapshot(mapOf("languages" to mapOf(
            "en" to mapOf("selected" to "lindaVoice000000001", "defaultVoice" to "hope", "voices" to listOf(hope, linda, tom)),
        ))).speech?.choices(BedsideLanguage.ENGLISH))
        assertEquals(listOf("Hope"), choices.listed.map { it.name })
        assertEquals(listOf("Linda", "Tom"), choices.family.map { it.name })
        assertEquals(listOf(false, true, true), choices.voices.map { it.isFamily })
        assertEquals("lindaVoice000000001", choices.yours("linda")?.id)
        assertEquals(listOf("Tom"), choices.others("linda").map { it.name })
        assertNull(choices.yours("sam"), "someone who hasn't recorded")
        assertEquals(listOf("Linda", "Tom"), choices.others("sam").map { it.name })
        assertNull(choices.yours(null))
    }

    /** Servers from before family voices send neither field, and every voice is a listed one. */
    @Test fun voicesWithoutFamilyFieldsAreListedVoices() {
        val voice = ModelFixtures.decoded<NaturalVoices.Voice>(hope)
        assertNull(voice.family); assertNull(voice.memberID); assertEquals(false, voice.isFamily)
        val choices = ModelFixtures.decoded<NaturalVoices.Choices>(mapOf("defaultVoice" to "hope", "voices" to listOf(hope)))
        assertEquals(listOf("Hope"), choices.listed.map { it.name }); assertEquals(emptyList(), choices.family)
    }

    /** Caregiver mode on a phone gets the voices with the PIN, with the language they're for. */
    @Test fun theCaregiverStateCarriesTheVoicesAndTheBedsideLanguage() {
        val admin = ModelFixtures.decoded<FamilyAdminState>(mapOf("householdName" to "Rose", "dropInEnabled" to true, "people" to emptyList<Any>(),
            "bedsideLanguage" to "yue-Hant", "speech" to mapOf("languages" to mapOf(
                "yue-Hant" to mapOf("selected" to null, "defaultVoice" to "suk-yee", "voices" to listOf(linda))))))
        assertEquals("yue-Hant", admin.bedsideLanguage)
        assertEquals(BedsideLanguage.CANTONESE, admin.language)
        val cantonese = assertNotNull(admin.announcementVoices)
        assertNull(cantonese.selected, "the built-in voice")
        assertEquals("linda", cantonese.yours("linda")?.memberID)
    }

    /** Older servers, and ones without voices, send neither. */
    @Test fun aCaregiverStateWithoutVoices() {
        val admin = ModelFixtures.parsed<FamilyAdminState>("""{"householdName":"Rose","dropInEnabled":true,"people":[]}""")
        assertNull(admin.speech); assertNull(admin.bedsideLanguage); assertNull(admin.announcementVoices)
        assertEquals(BedsideLanguage.ENGLISH, admin.language)
        assertEquals(BedsideLanguage.ENGLISH, ModelFixtures.parsed<FamilyAdminState>(
            """{"householdName":"Rose","dropInEnabled":true,"people":[],"bedsideLanguage":"xx"}""").language, "a language this app doesn't know")
    }

    /** Phone voicemail greets callers in the bedside language, which only the bedside knows until it reports it. */
    @Test fun savingReportsTheBedsideLanguageOnlyWhenTheServerHasAnother() {
        val english = snapshot(null, bedsideLanguage = "en")
        assertEquals(BedsideLanguage.CANTONESE, english.languageToReport(BedsideLanguage.CANTONESE))
        assertNull(english.languageToReport(BedsideLanguage.ENGLISH), "already known")
        assertNull(snapshot(null).languageToReport(BedsideLanguage.SPANISH), "older servers can't keep it")
    }
}
