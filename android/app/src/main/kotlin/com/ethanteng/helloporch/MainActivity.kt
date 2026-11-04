package com.ethanteng.helloporch

import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.mutableStateOf

/** Porch's one activity. An invitation link that opens Porch arrives here, when it starts or while it's open. */
class MainActivity : ComponentActivity() {
    private val link = mutableStateOf<String?>(null)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        // A link not yet handled survives the activity being recreated, such as when the phone turns.
        link.value = if (savedInstanceState == null) intent?.dataString else savedInstanceState.getString(linkKey)
        setContent {
            MaterialTheme { PorchScreens(application as PorchApplication, link.value, onLinkHandled = { link.value = null }) }
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

    private companion object { const val linkKey = "porch.link" }
}
