package com.ethanteng.helloporch.core

/**
 * Porch's small on-device settings, under the same `porch.*` keys as the iOS app's UserDefaults. The app backs this
 * with SharedPreferences; tests and previews use [MemorySettings]. What iOS saves as JSON data is a JSON string here.
 */
interface PorchSettings {
    fun contains(key: String): Boolean
    fun getString(key: String): String?
    fun getBoolean(key: String): Boolean?
    fun getInt(key: String): Int?
    fun putString(key: String, value: String)
    fun putBoolean(key: String, value: Boolean)
    fun putInt(key: String, value: Int)
    fun remove(key: String)
}

/** Settings kept in memory only. A value of the wrong type reads as missing, as UserDefaults does. */
class MemorySettings : PorchSettings {
    private val values = mutableMapOf<String, Any>()
    override fun contains(key: String) = key in values
    override fun getString(key: String) = values[key] as? String
    override fun getBoolean(key: String) = values[key] as? Boolean
    override fun getInt(key: String) = values[key] as? Int
    override fun putString(key: String, value: String) { values[key] = value }
    override fun putBoolean(key: String, value: Boolean) { values[key] = value }
    override fun putInt(key: String, value: Int) { values[key] = value }
    override fun remove(key: String) { values.remove(key) }
}
