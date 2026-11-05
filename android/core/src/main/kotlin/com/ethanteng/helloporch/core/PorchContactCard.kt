package com.ethanteng.helloporch.core

/** The bedside's Porch number as a contact, named so it's easy to find: to save on this phone, or to text to someone
 * with the number in the message too. `name` is who the Porch is for, such as "Mom". */
object PorchContactCard {
    fun contactName(name: String) = "$name's Porch"

    /** What the text says, so it still has the number when the card can't be attached. */
    fun note(name: String, number: String) =
        "Here's $name's Porch number: ${PorchNumber.display(number)}. Call it from any phone to talk with $name."

    /** A file name for the card. A slash would make it a path, and a line break would make it more than one name. */
    fun fileName(name: String) = buildString {
        for (ch in "${contactName(name)}.vcf") append(if (ch == '/' || ch.isISOControl() || ch == '\u2028' || ch == '\u2029') '-' else ch)
    }

    /** A vCard 3.0 for the number, with the CRLF line endings the format requires. */
    fun vCard(name: String, number: String): String {
        val full = escape(contactName(name))
        // The number is escaped too: it comes from the server, and a return in it would start another property.
        val tel = escape(number)
        return listOf("BEGIN:VCARD", "VERSION:3.0", "N:;$full;;;", "FN:$full", "TEL;TYPE=MAIN,VOICE:$tel", "END:VCARD")
            .joinToString("\r\n", postfix = "\r\n")
    }

    // vCard text values escape backslashes, commas, semicolons and line breaks. A bare return is a line break too.
    private fun escape(text: String) = text.replace("\\", "\\\\").replace(",", "\\,").replace(";", "\\;")
        .replace("\r\n", "\\n").replace("\n", "\\n").replace("\r", "\\n").replace("\u2028", "\\n").replace("\u2029", "\\n")
}
