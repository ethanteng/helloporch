package com.ethanteng.helloporch.core

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

// What the Porch server sends (`lib/family/service.ts`). Times are whole seconds since 1970, as the server keeps them.

@Serializable
enum class PorchExperience { @SerialName("bedside") BEDSIDE, @SerialName("family") FAMILY }

@Serializable
data class DropInPermissions(val audio: Boolean, val video: Boolean)

/** A family member's name and photo, as they chose them or as a caregiver chose them for them. */
@Serializable
data class FamilyProfile(
    val name: String? = null,
    /** The SHA-256 of the photo's JPEG bytes. */
    val photoID: String? = null,
)

@Serializable
data class FamilyPerson(
    val id: String,
    /** What Porch shows: a caregiver's choice first, then the family member's own, then the invitation's name. */
    val name: String,
    /** The photo Porch shows (the SHA-256 of its JPEG), a caregiver's or the member's own. Older servers don't send it. */
    val photoID: String? = null,
    /** Caregiver screens and the member's own snapshot: the parts behind `name` and `photoID`. */
    val invitedName: String? = null,
    val profile: FamilyProfile? = null,
    val override: FamilyProfile? = null,
    val role: PorchExperience,
    /** "ios" or "android", so each app can name the other devices, such as "Mom's iPad" or "Mom's tablet". Servers from
     * before Android don't send it. */
    val platform: String = "ios",
    val permissions: DropInPermissions,
    val canReceiveCalls: Boolean? = null,
    val online: Boolean,
    val invitationID: String? = null,
    /** Family devices only: approved to open caregiver mode with the PIN. */
    val caregiver: Boolean? = null,
)

@Serializable
data class FamilyCallRecord(
    val id: String,
    val from: String,
    val to: String,
    val mode: NativeCall.Mode,
    val kind: String,
    val state: String,
    val createdAt: Long,
    val announcedAt: Long? = null,
    val acceptedAt: Long? = null,
    /** An answered call reports `Number.MAX_SAFE_INTEGER`: calls have no length limit. */
    val expiresAt: Long,
    val callerName: String,
    /** "phone" for a call to the household's telephone number. Telephone calls carry audio
     * only and require an explicit answer, unless the server marks a carrier-verified,
     * caregiver-approved number as a drop-in. */
    val source: String? = null,
    /** The caller's telephone number, when caller ID is available. Display information only. */
    val callerNumber: String? = null,
    val reason: String? = null,
    /** A regular phone a family caregiver added to this call, such as a bank. Older servers don't send it. */
    val phoneGuest: FamilyPhoneGuest? = null,
    /** Family devices: the bedside hung up while the call went on without it. */
    val bedsideLeft: Boolean? = null,
    /** The family member rung into this call, as the call's two ends see them. Older servers don't send it. */
    val porchGuest: FamilyPorchGuest? = null,
    /** This device was rung into someone else's call with the bedside: `from` rang it in, and `id` is its invitation. */
    val guest: Boolean? = null,
)

/** A family member rung into a call with the bedside, and how their invitation went. */
@Serializable
data class FamilyPorchGuest(
    val id: String,
    val memberID: String,
    val name: String,
    /** "ringing", "joined", "declined", "missed", "cancelled" (they lost access while it rang) or "left". */
    val state: String,
) {
    val isActive: Boolean get() = state == "ringing" || state == "joined"
}

/** Another family member on this Porch, who can be rung into a call with the bedside. */
@Serializable
data class FamilyRelative(
    val id: String,
    val name: String,
    /** Their Porch is open, or can ring while it's closed. */
    val canReceiveCalls: Boolean,
)

/** A regular phone on a Porch call. Its telephone leg joins the call's LiveKit room as `identity`. */
@Serializable
data class FamilyPhoneGuest(
    val id: String,
    /** What the person who added it called it, such as "Bank". The bedside sees this, never the number. */
    val label: String,
    val addedBy: String,
    /** Only the person who added it receives the number. */
    val number: String? = null,
) {
    val identity: String get() = "phone-guest-$id"
}

/** A telephone number the caregiver approved for audio drop-in by calling the household's number. */
@Serializable
data class PhoneDropInApproval(val number: String, val name: String)

/** A caller ID that tried to ring the bedside while unknown callers were blocked. */
@Serializable
data class BlockedCaller(val number: String, val firstCallAt: Long, val lastCallAt: Long, val calls: Int)

/** A number a caregiver allowed to ring the bedside although it isn't saved on the keypad. */
@Serializable
data class AllowedCaller(val number: String, val allowedAt: Long)

/** Who can ring the bedside from a regular phone. Calls are matched by caller ID, which can be faked. */
@Serializable
data class CallScreening(
    /** Only keypad contacts, approved phone drop-ins and allowed numbers ring; other numbers are listed in `blocked`. */
    val enabled: Boolean,
    /** The keypad's phone numbers as the server last heard them; null until the bedside first reports them. */
    val keypadNumbers: List<String>? = null,
    val allowed: List<AllowedCaller>,
    /** Newest first. Numbers saved or allowed since they called aren't listed. */
    val blocked: List<BlockedCaller>,
) {
    /** The keypad's numbers to report, or null when the server already has them. */
    fun keypadNumbersToReport(slots: CallSlots): List<String>? {
        val numbers = slots.phoneNumbers
        return if (keypadNumbers == numbers) null else numbers
    }
}

/** A message waiting on the bedside device (only the bedside's snapshot carries the queue). */
@Serializable
data class FamilyMessage(
    val id: String,
    val from: String,
    val fromName: String,
    /** "message" or "voicemail". */
    val kind: String,
    /** "audio" or "video". */
    val mode: String,
    val contentType: String,
    val durationSeconds: Int,
    val sentAt: Long,
    val delivered: Boolean,
    /** Voicemail from a regular phone call: the caller's number, when caller ID was shown. */
    val callerNumber: String? = null,
    /** The phone company verified the caller ID (STIR/SHAKEN full attestation). Caller ID alone is easy to fake. */
    val callerVerified: Boolean? = null,
    /** Phone voicemail waiting for a caregiver (or a matching keypad contact) before it plays. */
    val held: Boolean? = null,
) {
    val fromPhone: Boolean get() = from == "phone"
    val fileExtension: String
        get() = when (contentType) {
            "video/quicktime" -> "mov"
            "video/mp4" -> "mp4"
            "audio/mpeg" -> "mp3"
            else -> "m4a"
        }
}

/** A text message to the household's Porch number. The bedside shows and reads it after the waiting messages. */
@Serializable
data class FamilyText(
    val id: String,
    /** The sender's phone number in E.164, or a short code. Texts carry no carrier check, so it can be faked. */
    val from: String,
    val sentAt: Long,
    /** Pictures that came with it, and anything else, such as a contact card or a voice clip. Porch doesn't show them yet. */
    val pictures: Int? = null,
    val attachments: Int? = null,
    /** From a number the household doesn't know: it waits for a caregiver before the bedside shows it. */
    val held: Boolean,
    val delivered: Boolean,
    /** Caregiver review only (`caregiverTexts`): the words as sent, and what the bedside shows when it translated them. */
    val body: String? = null,
    val translation: String? = null,
    val sourceLanguage: String? = null,
)

/** A text as the bedside shows and reads it (`textMessage`). */
@Serializable
data class ReceivedText(
    val id: String,
    val from: String,
    val sentAt: Long,
    /** The words as sent. Empty for a text that was only pictures. */
    val body: String,
    val pictures: Int? = null,
    val attachments: Int? = null,
    /** The bedside language it was prepared in. One kept from before a language change is fetched again. */
    val language: String,
    /** What the bedside shows and reads: `body`, or `body` translated into `language`. */
    val text: String,
    val translated: Boolean,
    /** The language it was written in, as a BCP 47 tag, when Porch could tell. */
    val sourceLanguage: String? = null,
)

/** A message this device sent. States: uploading, queued, played, expired, removed, unsent, failed. */
@Serializable
data class SentMessage(
    val id: String,
    val kind: String,
    val mode: String,
    val durationSeconds: Int,
    val createdAt: Long,
    val state: String,
    val sentAt: Long? = null,
    val deliveredAt: Long? = null,
    val playedAt: Long? = null,
    val endedAt: Long? = null,
    /** The recording can still be played back (it's kept for 90 days after playback). */
    val replayable: Boolean? = null,
)

/** A message the bedside left for this family device after a missed call (family devices only).
 * States: queued (not played yet), played, expired (deleted after 90 days unplayed). */
@Serializable
data class ReceivedMessage(
    val id: String,
    val fromName: String,
    val kind: String,
    /** "audio" or "video", matching the call that wasn't answered. */
    val mode: String,
    val durationSeconds: Int,
    val sentAt: Long,
    val state: String,
    val playedAt: Long? = null,
    /** The recording is kept for 90 days after it was left, played or not. */
    val available: Boolean,
)

@Serializable
data class PendingFamilyInvitation(
    val id: String,
    /** The name the caregiver gave the invitation. Older servers don't send it. */
    val name: String? = null,
    val expiresAt: Long,
)

@Serializable
data class FamilySnapshot(
    val householdID: String,
    val householdName: String,
    val dropInEnabled: Boolean,
    val me: FamilyPerson,
    val people: List<FamilyPerson>,
    val invitations: List<PendingFamilyInvitation>? = null,
    val call: FamilyCallRecord? = null,
    val busy: Boolean,
    val serverTime: Long,
    val messagesEnabled: Boolean? = null,
    val messages: List<FamilyMessage>? = null,
    /** For approved caregivers: phone voicemails waiting for review. */
    val heldMessages: Int? = null,
    /** Bedside only: text messages on their way to the bedside, and held ones. Older servers don't send them. */
    val texts: List<FamilyText>? = null,
    /** For approved caregivers: texts from unknown numbers waiting for review. Older servers don't send it. */
    val heldTexts: Int? = null,
    /** Bedside only: numbers approved for telephone drop-in. */
    val phoneDropIns: List<PhoneDropInApproval>? = null,
    /** How long calls to the bedside ring before the caller is offered voicemail. Older servers don't send it. */
    val ringSeconds: Int? = null,
    /** Family devices: messages the bedside left for this device that haven't been played. */
    val newMessages: Int? = null,
    /** Bedside only: natural announcement voices. Older servers, and ones without a speech service, don't send them. */
    val speech: NaturalVoices? = null,
    /** Bedside only: the bedside language as the server last heard it; phone voicemail greets callers in it. Older servers don't send it. */
    val bedsideLanguage: String? = null,
    /** Bedside only: who can ring by phone. Older servers don't send it. */
    val callScreening: CallScreening? = null,
    /** Bedside only: family see when someone is at the bedside, unless a caregiver turned it off. The bedside reports it
     * only when this is true; older servers don't send it, and don't take reports. */
    val shareAttendance: Boolean? = null,
    /** Family caregivers: this phone can add a regular phone number to its calls with the bedside. */
    val canAddPhoneGuests: Boolean? = null,
    /** Family devices: the rest of the family on this Porch, who can be rung into a call. Older servers don't send it. */
    val family: List<FamilyRelative>? = null,
    /** Family devices: when someone was last noticed at the bedside, in server time (see `BedsideAttendance`).
     * Older servers don't send it, nor does one that hasn't heard of anyone there yet. */
    val bedsideAttendedAt: Long? = null,
    /** Everyone: the household's own phone number in E.164, which anyone can call it on. Older servers, and households
     * that don't have one yet, don't send it. */
    val porchNumber: String? = null,
    /** The bedside and caregivers: a Porch number that's still being set up. Gone once `porchNumber` is there. */
    val phoneSetup: PorchNumberSetup? = null,
) {
    /** The language to report after a caregiver saves `language`, or null when the server already has it or can't keep it. */
    fun languageToReport(language: BedsideLanguage): BedsideLanguage? {
        val known = bedsideLanguage ?: return null
        return if (known == language.code) null else language
    }
}

/** A Porch number that isn't ready yet: the area code asked for, and why the last try failed, if it did. With
 * `needsChoice`, that area code had no numbers, so Porch waits for a caregiver to choose another. */
@Serializable
data class PorchNumberSetup(val areaCode: String, val error: String? = null, val needsChoice: Boolean? = null)

/** The natural voices a caregiver can choose for each bedside language, and the household's choice. */
@Serializable
data class NaturalVoices(
    /** Keyed by `BedsideLanguage.code`. */
    val languages: Map<String, Choices>,
) {
    @Serializable
    data class Voice(
        val id: String,
        val name: String,
        /** How it sounds, such as "Steady, calm and grounded · female". */
        val detail: String,
    )

    @Serializable
    data class Choices(
        /** The household's voice for this language; null means the device's built-in voice. */
        val selected: String? = null,
        val defaultVoice: String,
        val voices: List<Voice>,
    )

    fun choices(language: BedsideLanguage): Choices? = languages[language.code]
}

/** Returned with caregiver actions after a PIN check. Lists every family device, which a
 * family device's own snapshot doesn't include. */
@Serializable
data class FamilyAdminState(
    val householdName: String,
    val dropInEnabled: Boolean,
    val people: List<FamilyPerson>,
    val messagesEnabled: Boolean? = null,
    /** Messages waiting on the bedside device, for caregiver review. */
    val messages: List<FamilyMessage>? = null,
    /** Texts waiting for the bedside, without their words. Older servers don't send them. */
    val texts: List<FamilyText>? = null,
    val phoneDropIns: List<PhoneDropInApproval>? = null,
    /** Unclaimed invitations, so a caregiver can see who hasn't joined yet and cancel one. */
    val invitations: List<PendingFamilyInvitation>? = null,
    /** Who can ring by phone. Older servers don't send it. */
    val callScreening: CallScreening? = null,
    /** Family see when someone is at the bedside. Older servers don't send it. */
    val shareAttendance: Boolean? = null,
)

/**
 * One call to or from the bedside, as caregivers see it in Call history (`callHistory`).
 * `direction` is the bedside's: "incoming" rang the bedside and "outgoing" was placed from it. `via` is "porch", or
 * "phone": someone calling the household's Porch number, or the bedside calling a regular phone, including phone
 * fallback. `name` and `number` are as Porch showed them then; a phone caller is named by caller ID, which can be faked.
 * `outcome` is "answered", "missed", "declined", "unavailable" (Porch couldn't reach their app), "dialed" (the bedside
 * called a regular phone; the server can't tell whether it was answered), "ringing" or "ongoing".
 */
@Serializable
data class CallHistoryEntry(
    val id: String,
    val direction: String,
    val via: String,
    val name: String,
    val memberID: String? = null,
    val number: String? = null,
    val mode: NativeCall.Mode,
    val dropIn: Boolean? = null,
    val startedAt: Long,
    val answeredAt: Long? = null,
    /** When the bedside's part ended. Calls from before the server recorded it have none. */
    val endedAt: Long? = null,
    val outcome: String,
    /** The bedside's unanswered Porch calls: whether the family phone showed the call. False means it never got
     * there, rather than that it rang and nobody heard. Older servers don't send it. */
    val reached: Boolean? = null,
) {
    val isIncoming: Boolean get() = direction == "incoming"
    /** A missed call to the bedside, which caregivers may want to follow up. */
    val isMissed: Boolean get() = isIncoming && outcome == "missed"
    /** What kind of call it was: "Incoming video call", "Audio drop-in", "Called their phone". */
    val kindText: String
        get() {
            if (via == "phone") return if (isIncoming) "Phone call" else "Called their phone"
            val media = if (mode == NativeCall.Mode.VIDEO) "video" else "audio"
            if (dropIn == true) return "${media.replaceFirstChar { it.uppercase() }} drop-in"
            return "${if (isIncoming) "Incoming" else "Outgoing"} $media call"
        }
    /** How it went, or null for a phone the bedside dialed: "Talked 12 min", "Missed", "No answer". */
    val outcomeText: String?
        get() = when (outcome) {
            "answered" -> {
                val answeredAt = answeredAt
                val endedAt = endedAt
                if (answeredAt == null || endedAt == null || endedAt < answeredAt) "Answered"
                else "Talked ${duration((endedAt - answeredAt).toDouble())}"
            }
            "missed" -> when {
                isIncoming -> "Missed"
                reached == true -> "No answer · Their phone showed the call"
                reached == false -> "No answer · Didn't reach their phone"
                else -> "No answer"
            }
            "declined" -> "Declined"
            "unavailable" -> "Couldn't reach their Porch"
            "ringing" -> "Ringing now"
            "ongoing" -> "On the call now"
            else -> null
        }

    companion object {
        /** "45 sec", "12 min", "1 hr 5 min". */
        fun duration(seconds: Double): String {
            // Halves round up, as Swift's `rounded()` does, rather than to even.
            val total = maxOf(0L, Math.round(seconds)).toInt()
            if (total < 60) return "$total sec"
            val minutes = (total + 30) / 60
            return when {
                minutes < 60 -> "$minutes min"
                minutes % 60 == 0 -> "${minutes / 60} hr"
                else -> "${minutes / 60} hr ${minutes % 60} min"
            }
        }
    }
}

@Serializable
data class FamilyCredential(val origin: String, val credential: String, val role: PorchExperience) {
    /** This device's ID in its household, which is also its member ID there. A phone in several families has a
     * different one in each, so calls and messages can say which family they're for. */
    val deviceID: String get() = credential.split('.').firstOrNull { it.isNotEmpty() } ?: ""
}

/** What a phone in more than one family shows to tell them apart, such as two sets of parents who are both "Mom" and
 * "Dad" on their own Porch. */
object FamilyNames {
    /** Each family can have several phones; a phone can be in up to this many families. */
    const val limit = 4

    /** What each of a phone's families is called, in the order it joined them, numbered where two would read the same:
     * two families that are both "Mom" are "Mom" and "Mom 2" until the phone names one. */
    fun distinct(names: List<String?>): List<String?> {
        val used = mutableSetOf<String>()
        return names.map { name ->
            if (name == null) return@map null
            var distinct: String = name
            var number = 1
            while (distinct.lowercase() in used) { number += 1; distinct = "$name $number" }
            used += distinct.lowercase()
            distinct
        }
    }

    /** The name this phone gave the family, or else the one its caregiver did. */
    fun family(nickname: String?, householdName: String?): String? =
        listOf(nickname, householdName).firstNotNullOfOrNull { it?.trim()?.ifEmpty { null } }

    /** Who's calling, with their family when the phone is in more than one: "Mom · Lee family". A family named after
     * the person calling adds nothing. */
    fun caller(name: String, family: String?): String {
        if (family.isNullOrEmpty() || family.equals(name, ignoreCase = true)) return name
        return "$name · $family"
    }
}
