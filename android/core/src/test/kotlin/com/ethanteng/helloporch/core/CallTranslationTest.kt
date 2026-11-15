package com.ethanteng.helloporch.core

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull

class CallTranslationTest {
    @Test fun linesStatesAndSpeakingDecode() {
        val line = """{"type":"line","id":"3","speaker":"ethan","name":"Ethan","side":"family","heard":"The doctor said 你的血壓 is a little high","said":"醫生說你的血壓有點高","language":"zh-Hant","at":1800000000000}"""
        assertEquals(CallTranslationMessage.Line(CallTranslationLine("3", "ethan", "Ethan", "family", "The doctor said 你的血壓 is a little high",
            "醫生說你的血壓有點高", "zh-Hant", 1_800_000_000_000)), CallTranslationMessage.decode(line.encodeToByteArray()))
        val passedThrough = """{"type":"line","id":"4","speaker":"ethan","name":"Ethan","side":"family","heard":"你今天吃飯了沒有？","said":null,"language":"zh-Hant","at":1}"""
        val quiet = (CallTranslationMessage.decode(passedThrough.encodeToByteArray()) as CallTranslationMessage.Line).line
        assertNull(quiet.said); assertFalse(quiet.fromBedside)
        assertEquals(CallTranslationMessage.State(true, "yue-Hant"), CallTranslationMessage.decode("""{"type":"state","on":true,"language":"yue-Hant"}""".encodeToByteArray()))
        assertEquals(CallTranslationMessage.Speaking(false), CallTranslationMessage.decode("""{"type":"speaking","on":false}""".encodeToByteArray()))
    }

    @Test fun unknownOrBrokenMessagesAreIgnored() {
        assertNull(CallTranslationMessage.decode("""{"type":"dtmf","digit":"1"}""".encodeToByteArray()))
        assertNull(CallTranslationMessage.decode("""{"type":"state"}""".encodeToByteArray()))
        assertNull(CallTranslationMessage.decode("""{"type":"state","on":{"bad":true},"language":"en"}""".encodeToByteArray()))
        assertNull(CallTranslationMessage.decode("""{"type":{"bad":true}}""".encodeToByteArray()))
        assertNull(CallTranslationMessage.decode("not json".encodeToByteArray()))
        assertEquals("porch-translation-bedside", CallTranslationMessage.trackName(bedside = true))
        assertEquals("porch-translation-family", CallTranslationMessage.trackName(bedside = false))
    }

    @Test fun callsCarryTranslationWhenTheServerSendsIt() {
        val json = """{"id":"c1","from":"ethan","to":"mom","mode":"video","kind":"call","state":"accepted","createdAt":1,"expiresAt":9007199254740991,"callerName":"Ethan","translationAvailable":true,"translation":{"on":true,"language":"zh-Hant","by":"ethan","at":5}}"""
        val call = PorchJson.decodeFromString(FamilyCallRecord.serializer(), json)
        assertEquals(FamilyCallTranslation(true, "zh-Hant", "ethan", 5), call.translation)
        assertEquals(true, call.translationAvailable)
        val older = PorchJson.decodeFromString(FamilyCallRecord.serializer(),
            """{"id":"c1","from":"ethan","to":"mom","mode":"video","kind":"call","state":"accepted","createdAt":1,"expiresAt":2,"callerName":"Ethan"}""")
        assertNull(older.translation); assertNull(older.translationAvailable)
    }
}
