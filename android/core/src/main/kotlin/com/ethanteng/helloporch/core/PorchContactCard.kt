package com.ethanteng.helloporch.core

/** The bedside's Porch number as a contact, named so it's easy to find: to save on this phone, or to text to someone
 * with the number in the message too. `name` is who the Porch is for, such as "Mom". */
object PorchContactCard {
    fun contactName(name: String) = "$name's Porch"

    /** What the text says, so it still has the number when the card can't be attached. */
    fun note(name: String, number: String) =
        "Here's $name's Porch number: ${PorchNumber.display(number)}. Call it from any phone to talk with $name."

    /** A file name for the card. Slashes would make it a path. */
    fun fileName(name: String) = "${contactName(name)}.vcf".replace('/', '-')

    /** A vCard 3.0 for the number, with the CRLF line endings the format requires. */
    fun vCard(name: String, number: String): String {
        val full = escape(contactName(name))
        return listOf("BEGIN:VCARD", "VERSION:3.0", "N:;$full;;;", "FN:$full", "TEL;TYPE=MAIN,VOICE:$number", "END:VCARD")
            .joinToString("\r\n", postfix = "\r\n")
    }

    // vCard text values escape backslashes, commas, semicolons and line breaks.
    private fun escape(text: String) = text.replace("\\", "\\\\").replace(",", "\\,").replace(";", "\\;")
        .replace("\r\n", "\\n").replace("\n", "\\n")
}
