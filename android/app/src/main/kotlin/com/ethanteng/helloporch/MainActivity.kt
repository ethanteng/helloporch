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
        if (savedInstanceState == null) link.value = intent?.dataString
        setContent {
            MaterialTheme { PorchScreens(application as PorchApplication, link.value, onLinkHandled = { link.value = null }) }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        intent.dataString?.let { link.value = it }
    }
}
