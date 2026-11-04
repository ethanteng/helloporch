package com.ethanteng.helloporch.core

import kotlinx.serialization.json.Json

/** How Porch reads and writes JSON: the server's responses and the settings it saves. Fields a newer server adds are
 * ignored, so an older app keeps working; every optional field has a default for an older server that omits it. */
val PorchJson = Json {
    ignoreUnknownKeys = true
    encodeDefaults = true
}
