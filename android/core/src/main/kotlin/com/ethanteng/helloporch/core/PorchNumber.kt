package com.ethanteng.helloporch.core

/** A household's own phone number, which anyone can call its Porch on. */
object PorchNumber {
    private val areaCodePattern = Regex("[2-9][0-9]{2}")

    /** "(510) 567-7039" for a US number in E.164, or the number as it came otherwise. */
    fun display(number: String): String {
        if (!number.startsWith("+1")) return number
        val digits = number.substring(2)
        if (digits.length != 10 || !digits.all { it in '0'..'9' }) return number
        return "(${digits.take(3)}) ${digits.substring(3, 6)}-${digits.takeLast(4)}"
    }

    /** A US area code Porch can look for numbers in: three digits, not starting with 0 or 1, and not a service code
     * such as 411. The server checks the same. */
    fun isAreaCode(text: String): Boolean = areaCodePattern.matches(text) && !text.endsWith("11")
}
