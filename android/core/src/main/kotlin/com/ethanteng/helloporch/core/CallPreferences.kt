package com.ethanteng.helloporch.core

/** Device-wide caregiver preferences. Silence disconnection is opt-in. */
object CallPreferences {
    val fallbackRange = 5..120
    const val defaultFallbackSeconds = 20
    /** How long calls to the bedside ring before voicemail. The household keeps it on the server. */
    val voicemailRange = 15..120
    const val defaultVoicemailSeconds = 45
    /** Drop-ins don't follow it: the announcement and countdown, or a manual answer, need this long. */
    const val dropInWaitSeconds = 45
    val silenceRange = 15..1800
    const val defaultSilenceSeconds = 120
    private const val silenceEnabledKey = "porch.disconnectAfterSilence"
    private const val silenceSecondsKey = "porch.silenceSeconds"
    private const val fallbackKey = "porch.phoneFallbackSeconds"
    private const val cameraKey = "porch.startVideoWithCamera"
    private const val leaveMessageKey = "porch.leaveMessageWhenUnanswered"

    fun disconnectAfterSilence(settings: PorchSettings): Boolean = settings.getBoolean(silenceEnabledKey) ?: false

    fun silenceSeconds(settings: PorchSettings): Int = settings.getInt(silenceSecondsKey)?.takeIf { it in silenceRange } ?: defaultSilenceSeconds

    fun saveSilence(enabled: Boolean, seconds: Int, settings: PorchSettings) {
        settings.putBoolean(silenceEnabledKey, enabled)
        settings.putInt(silenceSecondsKey, seconds.coerceIn(silenceRange))
    }

    /** Where a minute stepper lands, given the timeout it was showing. A whole number of minutes
     * follows the stepper. A leftover number of seconds moves one minute from that leftover:
     * up to the next minute, or down to the minute below it (and at least one minute). */
    fun silenceSeconds(minutes: Int, current: Int): Int {
        if (current % 60 == 0) return minutes * 60
        val floorMinutes = current / 60
        return if (minutes > floorMinutes) (floorMinutes + 1) * 60 else maxOf(60, floorMinutes * 60)
    }

    fun fallbackSeconds(settings: PorchSettings): Int = settings.getInt(fallbackKey)?.takeIf { it in fallbackRange } ?: defaultFallbackSeconds

    fun saveFallbackSeconds(seconds: Int, settings: PorchSettings) {
        settings.putInt(fallbackKey, seconds.coerceIn(fallbackRange))
    }

    /** Whether a family phone turns its camera on when a video call connects. On unless turned off. */
    fun startVideoWithCamera(settings: PorchSettings): Boolean = settings.getBoolean(cameraKey) ?: true

    /** Whether a video call on this device starts with its camera on. The bedside always does, whether it placed,
     * answered or was dropped in on; a family phone follows its own setting. */
    fun startVideoWithCamera(role: PorchExperience, settings: PorchSettings): Boolean =
        role == PorchExperience.BEDSIDE || startVideoWithCamera(settings)

    fun saveStartVideoWithCamera(enabled: Boolean, settings: PorchSettings) {
        settings.putBoolean(cameraKey, enabled)
    }

    /** Whether the bedside records a message when a Porch call isn't answered. On unless turned off.
     * Calls that ring through to a regular phone use that phone's own voicemail instead. */
    fun leaveMessageWhenUnanswered(settings: PorchSettings): Boolean = settings.getBoolean(leaveMessageKey) ?: true

    fun saveLeaveMessageWhenUnanswered(enabled: Boolean, settings: PorchSettings) {
        settings.putBoolean(leaveMessageKey, enabled)
    }

    /** Puts every call setting back to its default, such as when this device becomes someone else's bedside. */
    fun forget(settings: PorchSettings) {
        for (key in listOf(silenceEnabledKey, silenceSecondsKey, fallbackKey, cameraKey, leaveMessageKey)) settings.remove(key)
    }

    /** Bedside messages, like family ones, can be up to two minutes long. */
    const val messageSeconds: Double = 120.0
}
