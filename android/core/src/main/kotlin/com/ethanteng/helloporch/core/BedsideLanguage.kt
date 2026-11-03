package com.ethanteng.helloporch.core

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/** The language the bedside speaks and shows, which is independent of the device's own language. `code` is the value
 * the server and the iOS app use. */
@Serializable
enum class BedsideLanguage(val code: String) {
    @SerialName("en") ENGLISH("en"),
    @SerialName("zh-Hant") TRADITIONAL_CHINESE("zh-Hant"),
    @SerialName("zh-Hans") SIMPLIFIED_CHINESE("zh-Hans"),
    @SerialName("yue-Hant") CANTONESE("yue-Hant"),
    @SerialName("es") SPANISH("es");

    companion object {
        fun fromCode(code: String?): BedsideLanguage? = entries.firstOrNull { it.code == code }
    }
}
