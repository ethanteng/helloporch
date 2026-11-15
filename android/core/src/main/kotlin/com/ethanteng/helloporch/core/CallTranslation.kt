package com.ethanteng.helloporch.core

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonPrimitive

/**
 * What the call translator (`translator/` in the repository, a LiveKit agent) sends the people on a call, on the
 * [topic] data topic, as iOS's CallTranslationMessage reads it. Each side hears the translator on its own track
 * ([trackName]): the bedside on `porch-translation-bedside`, family on `porch-translation-family`.
 */
sealed interface CallTranslationMessage {
    /** Something someone said. Family receive every line; the bedside only lines said to it, as they're said. */
    data class Line(val line: CallTranslationLine) : CallTranslationMessage
    /** Translation started, changed language or stopped. */
    data class State(val on: Boolean, val language: String) : CallTranslationMessage
    /** The translator started or stopped speaking to this side, so the app can lower the other voices under it. */
    data class Speaking(val on: Boolean) : CallTranslationMessage

    companion object {
        const val topic = "porch-translation"
        /** The attribute the translator sets on itself. */
        const val attribute = "porch.translator"
        fun trackName(bedside: Boolean) = if (bedside) "porch-translation-bedside" else "porch-translation-family"

        fun decode(data: ByteArray): CallTranslationMessage? = runCatching {
            val text = data.decodeToString()
            val fields = PorchJson.parseToJsonElement(text) as? JsonObject ?: return@runCatching null
            val on = fields["on"]?.jsonPrimitive?.booleanOrNull
            when (fields["type"]?.jsonPrimitive?.contentOrNull) {
                "line" -> Line(PorchJson.decodeFromString(CallTranslationLine.serializer(), text))
                "state" -> {
                    val language = fields["language"]?.jsonPrimitive?.contentOrNull
                    if (on == null || language == null) null else State(on, language)
                }
                "speaking" -> on?.let(::Speaking)
                else -> null
            }
        }.getOrNull()
    }
}

/** One thing someone said on a translated call. [said] is what the translator said to the other side, in [language];
 * null when it was already in their language. [speaker] is their LiveKit identity, and [side] "bedside" or "family". */
@Serializable
data class CallTranslationLine(
    val id: String,
    val speaker: String,
    val name: String,
    val side: String,
    val heard: String,
    val said: String? = null,
    val language: String,
    val at: Long,
) {
    val fromBedside get() = side == "bedside"
}
