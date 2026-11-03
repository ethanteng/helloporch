package com.ethanteng.helloporch.core

import com.google.i18n.phonenumbers.NumberParseException
import com.google.i18n.phonenumbers.PhoneNumberUtil
import com.google.i18n.phonenumbers.PhoneNumberUtil.PhoneNumberFormat

/** `region` is the device's, as an ISO 3166 country code such as "US". */
object PhoneNumberNormalization {
    private val utility = PhoneNumberUtil.getInstance()

    /** Parse national numbers using an explicit region; preserve international country codes.
     * Extensions cannot be sent to the SIP destination field and are never silently dropped. */
    fun e164(value: String, region: String): String {
        val number = try { utility.parse(value, region.uppercase()) } catch (_: NumberParseException) { throw ValidationException(ContactError.invalidPhoneNumber) }
        // Like PhoneNumberKit's parse, a number that fits none of its country's patterns isn't one.
        if (number.extension.isNotEmpty() || !utility.isValidNumber(number)) throw ValidationException(ContactError.invalidPhoneNumber)
        return CallContact.normalizedPhoneNumber(utility.format(number, PhoneNumberFormat.E164))
    }

    /** A caller's number for people to read: national format at home, international otherwise. */
    fun display(e164: String, region: String): String {
        val number = try { utility.parse(e164, region.uppercase()) } catch (_: NumberParseException) { return e164 }
        val home = utility.getRegionCodeForNumber(number) == region.uppercase()
        return utility.format(number, if (home) PhoneNumberFormat.NATIONAL else PhoneNumberFormat.INTERNATIONAL)
    }
}
