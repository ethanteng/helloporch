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
     * rung in itself, and there's someone to ring. */
    fun showsAdd(call: FamilyCallRecord?, bedsideHere: Boolean, ringable: List<FamilyRelative>): Boolean =
        call != null && call.state == "accepted" && call.bedsideLeft != true && call.guest != true && bedsideHere && ringable.isNotEmpty()

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
