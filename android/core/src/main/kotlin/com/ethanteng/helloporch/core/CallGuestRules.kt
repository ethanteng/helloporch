package com.ethanteng.helloporch.core

/**
 * What a family phone offers and says while ringing family into a call with the bedside, as iOS's CallGuestControls
 * decides it. Anyone in the family on the call can ring in one more family member at a time, who joins with video.
 * Whoever was rung in can't add anyone.
 */
object CallGuestRules {
    /** The bedside on this phone's call, by member ID, which is also its LiveKit identity: the call's other end. A family
     * member who was rung in sees no bedside here, since their call is from whoever rang them. */
    fun bedsideID(call: FamilyCallRecord, myID: String): String? = when {
        call.guest == true -> null
        call.from == myID -> call.to
        call.to == myID -> call.from
        else -> null
    }

    /** Who Add someone offers: family whose Porch can ring now, unless someone is already being rung or is on. */
    fun ringable(family: List<FamilyRelative>, guest: FamilyPorchGuest?): List<FamilyRelative> =
        if (guest?.isActive == true) emptyList() else family.filter { it.canReceiveCalls }

    /** Whether Add someone shows: the call is answered, the bedside is still on it and in the room, this phone wasn't
     * rung in itself, and there's someone to ring or, for a caregiver, a phone number to dial. */
    fun showsAdd(call: FamilyCallRecord?, bedsideHere: Boolean, ringable: List<FamilyRelative>, canDial: Boolean = false): Boolean =
        call != null && call.state == "accepted" && call.bedsideLeft != true && call.guest != true && bedsideHere && (ringable.isNotEmpty() || canDial)

    /** The code LiveKit sends for a key on an added phone's keypad: 0 to 9, then 10 for * and 11 for #. */
    fun dtmfCode(key: Char): Int? = when (key) {
        in '0'..'9' -> key - '0'
        '*' -> 10
        '#' -> 11
        else -> null
    }

    /** What this phone says for a few seconds when it sees a ring it started change. */
    fun notice(guest: FamilyPorchGuest): String? = when (guest.state) {
        "joined" -> "${guest.name} joined the call."
        "declined" -> "${guest.name} declined."
        "missed" -> "${guest.name} didn't answer."
        "left" -> "${guest.name} left the call."
        "cancelled" -> "Stopped ringing ${guest.name}."
        else -> null
    }
}

/**
 * Follows a regular phone a caregiver added, such as a bank, by its leg in the call's room, as iOS's CallGuestControls
 * does: it's answered once LiveKit says its call is "active", and it's over once it leaves after joining, says
 * "hangup", or never joins within `joinSeconds`, say after a dial request timed out. The server keeps tracking it until
 * then, so this also catches a leg that arrives late.
 */
class PhoneGuestLeg(private val startedAt: Double, private val joinSeconds: Double = JOIN_SECONDS) {
    var seen = false
        private set
    var answered = false
        private set

    /** One look at the room at `now` (seconds): whether the leg is in it, and its `sip.callStatus`. True once it's over. */
    fun observe(present: Boolean, callStatus: String?, now: Double): Boolean {
        if (present) seen = true
        if (callStatus == "active") answered = true
        return (seen && !present) || callStatus == "hangup" || (!seen && now - startedAt >= joinSeconds)
    }

    companion object {
        const val JOIN_SECONDS = 75.0
    }
}
