package com.ethanteng.helloporch

import android.content.Intent
import android.os.Bundle
import android.view.KeyEvent
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.staticCompositionLocalOf

/** Porch's one activity. An invitation or setup link that opens Porch arrives here, when it starts or while it's open. */
class MainActivity : ComponentActivity() {
    private val link = mutableStateOf<String?>(null)
    private val keys = KeyListener()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        // A link not yet handled survives the activity being recreated, such as when the phone turns.
        link.value = if (savedInstanceState == null) intent?.dataString else savedInstanceState.getString(linkKey)
        setContent {
            MaterialTheme {
                CompositionLocalProvider(LocalKeyListener provides keys) {
                    PorchRoot(application as PorchApplication, link.value, onLinkHandled = { link.value = null })
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        intent.dataString?.let { link.value = it }
    }

    override fun onSaveInstanceState(outState: Bundle) {
        super.onSaveInstanceState(outState)
        outState.putString(linkKey, link.value)
    }

    // A keypad's keys reach the screen listening for them once Compose has passed them up, as `pressesBegan` does on
    // iOS. Nothing on that screen takes typing, so digits always get here.
    override fun onKeyDown(keyCode: Int, event: KeyEvent): Boolean = keys.onKey?.invoke(event) == true || super.onKeyDown(keyCode, event)
    override fun onKeyUp(keyCode: Int, event: KeyEvent): Boolean = keys.onKey?.invoke(event) == true || super.onKeyUp(keyCode, event)

    private companion object { const val linkKey = "porch.link" }
}

/** Keys from a keypad or keyboard that Compose didn't use, for the one screen listening for them. It returns true for a
 * key it handled. */
class KeyListener { var onKey: ((KeyEvent) -> Boolean)? = null }

val LocalKeyListener = staticCompositionLocalOf { KeyListener() }
