package com.ethanteng.helloporch

import android.content.Context
import androidx.core.content.edit
import com.ethanteng.helloporch.core.PorchSettings

/** Porch's settings in one SharedPreferences file, under the iOS app's `porch.*` keys. A value of the wrong type
 * reads as missing, as UserDefaults does. */
class SharedPreferencesSettings(context: Context) : PorchSettings {
    private val preferences = context.getSharedPreferences("porch", Context.MODE_PRIVATE)

    override fun contains(key: String) = preferences.contains(key)
    override fun getString(key: String) = preferences.all[key] as? String
    override fun getBoolean(key: String) = preferences.all[key] as? Boolean
    override fun getInt(key: String) = preferences.all[key] as? Int
    override fun putString(key: String, value: String) = preferences.edit { putString(key, value) }
    override fun putBoolean(key: String, value: Boolean) = preferences.edit { putBoolean(key, value) }
    override fun putInt(key: String, value: Int) = preferences.edit { putInt(key, value) }
    override fun remove(key: String) = preferences.edit { remove(key) }
}
