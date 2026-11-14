package com.ethanteng.helloporch.core

/** A license's text as About shows it, as iOS's `Acknowledgement.reflowed` does. */
object LicenseText {
    /**
     * The text with its hard line breaks taken out, so it wraps to the screen. Most licenses are broken at about 80
     * columns: those lines join up within a paragraph, while a short line, such as a title or a copyright, keeps its own.
     */
    fun reflowed(text: String): String {
        val paragraphs = mutableListOf<String>()
        val current = StringBuilder()
        var joinNext = false
        for (raw in text.replace("\r\n", "\n").split("\n")) {
            val line = raw.trim()
            if (line.isEmpty()) {
                if (current.isNotEmpty()) { paragraphs += current.toString(); current.clear() }
                continue
            }
            if (current.isNotEmpty()) current.append(if (joinNext) " " else "\n")
            current.append(line)
            joinNext = line.length >= 55
        }
        if (current.isNotEmpty()) paragraphs += current.toString()
        return paragraphs.joinToString("\n\n")
    }
}
