package com.ethanteng.helloporch.core

import com.ethanteng.helloporch.core.ModelFixtures.parsed
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** Texts to the Porch number reach the bedside's snapshot without their words; the bedside fetches each one to show it. */
class FamilyTextTest {
    private fun snapshot(extra: Map<String, Any?>) = ModelFixtures.snapshot(extra = extra)

    @Test fun theBedsideSeesWaitingAndHeldTextsAndOlderServersSendNone() {
        val state = snapshot(mapOf("texts" to listOf(
            mapOf("id" to "t1", "from" to "+14155550123", "sentAt" to 100, "held" to false, "delivered" to true),
            mapOf("id" to "t2", "from" to "72975", "sentAt" to 200, "pictures" to 2, "attachments" to 1, "held" to true, "delivered" to false),
        )))
        assertEquals(listOf("t1", "t2"), state.texts?.map { it.id })
        assertEquals(listOf(false, true), state.texts?.map { it.held })
        assertEquals(2, state.texts?.last()?.pictures)
        assertEquals(1, state.texts?.last()?.attachments)
        assertNull(state.texts?.first()?.attachments)
        assertNull(state.texts?.first()?.body, "the words aren't in the snapshot")
        assertNull(snapshot(emptyMap()).texts)
        assertEquals(3, snapshot(mapOf("heldTexts" to 3)).heldTexts)
    }

    @Test fun aFetchedTextKeepsItsWordsTranslationAndLanguage() {
        val text = parsed<ReceivedText>("""{"id":"t1","from":"+14155550123","sentAt":100,"body":"I land at 6","language":"zh-Hant","text":"我六點到","translated":true,"sourceLanguage":"en"}""")
        assertEquals(listOf("I land at 6", "我六點到", "zh-Hant", "en"), listOf(text.body, text.text, text.language, text.sourceLanguage))
        assertTrue(text.translated)
        assertNull(text.pictures)
        assertEquals(text, parsed<ReceivedText>(PorchJson.encodeToString(ReceivedText.serializer(), text)), "the bedside keeps it as it came")
        val untranslated = parsed<ReceivedText>("""{"id":"t2","from":"72975","sentAt":1,"body":"","pictures":1,"language":"en","text":"","translated":false}""")
        assertNull(untranslated.sourceLanguage)
        assertEquals(1, untranslated.pictures)
    }

    @Test fun caregiverReviewCarriesTheWordsAndWhatTheBedsideShows() {
        val text = parsed<List<FamilyText>>("""[{"id":"t1","from":"+14155550123","sentAt":100,"held":true,"delivered":false,"body":"Hola mamá","translation":"Hi Mom","sourceLanguage":"es"}]""").first()
        assertEquals(listOf("Hola mamá", "Hi Mom", "es"), listOf(text.body, text.translation, text.sourceLanguage))
        val admin = parsed<FamilyAdminState>("""{"householdName":"Pat","dropInEnabled":false,"people":[],"texts":[{"id":"t1","from":"+14155550123","sentAt":100,"held":true,"delivered":false}]}""")
        assertEquals(true, admin.texts?.first()?.held)
    }
}
