package com.ethanteng.helloporch.core

/** What the rows of caregiver mode's person page say, as iOS's PersonViewController words them. */
object PersonRows {
    /** How someone on a key is on Porch, and what the Porch app row says for it. Someone not on Porch is offered an invite. */
    enum class PorchApp(val value: String) {
        CONNECTED("Connected"), INVITE_SENT("Invite sent"), INVITE_EXPIRED("Invite expired"), NOT_ON_PORCH("Invite")
    }

    /** A key's family member is connected. Otherwise its invitation is waiting while it's still open, and has expired (or
     * was cancelled) once it isn't. */
    fun porchApp(member: Boolean, invitationID: String?, open: List<PendingFamilyInvitation>?): PorchApp = when {
        member -> PorchApp.CONNECTED
        invitationID == null -> PorchApp.NOT_ON_PORCH
        open.orEmpty().any { it.id == invitationID } -> PorchApp.INVITE_SENT
        else -> PorchApp.INVITE_EXPIRED
    }

    /**
     * The Drop-in row: `Paused` while drop-ins are paused for everyone, otherwise what's on, such as `Audio and video ·
     * Phone`, or `Off`. `app` is a family member's Porch app approval, and `phone` whether their key's number is approved.
     */
    fun dropIn(paused: Boolean, app: DropInPermissions?, phone: Boolean): String {
        if (paused) return "Paused"
        val porch = app?.let {
            when {
                it.audio && it.video -> "Audio and video"
                it.audio -> "Audio"
                it.video -> "Video"
                else -> null
            }
        }
        return listOfNotNull(porch, "Phone".takeIf { phone }).joinToString(" · ").ifEmpty { "Off" }
    }
}
