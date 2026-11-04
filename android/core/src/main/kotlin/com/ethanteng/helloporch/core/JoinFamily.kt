package com.ethanteng.helloporch.core

import kotlinx.coroutines.CancellationException
import kotlinx.serialization.json.JsonPrimitive

/** The family this phone just joined. When another family here has the same name, `sharedName` is that name and
 * `numberedName` is what the new one is called until the phone names it, such as "Mom" and "Mom 2". */
data class JoinedFamily(val credential: FamilyCredential, val sharedName: String? = null, val numberedName: String? = null)

/** Joins the family that sent `invitation`. Joining another family adds it: this phone stays in the ones it's already
 * in, such as the other set of parents. `nickname` is what this phone calls the new family. */
suspend fun joinFamily(
    invitation: FamilyInvitation,
    nickname: String?,
    device: PorchDevice,
    coordinator: FamilyCoordinator,
    serviceFor: (FamilyCredential) -> FamilyService,
    serviceAt: (origin: String) -> FamilyService,
): JoinedFamily {
    val pending = device.pending(PorchExperience.FAMILY, invitation.origin, invitation.code)
    // Reopening an invitation this phone already used returns the same identity, which doesn't add one.
    // Which family an invitation is from is known only once it's claimed, and claiming one for a fifth
    // family would use it up, so a new invitation from one of the four is turned away too.
    val families = device.families
    if (families.size >= FamilyNames.limit && families.none { it.deviceID == pending.deviceID }) {
        throw FamilyServiceException("This phone is in ${FamilyNames.limit} families, the most Porch allows. To join another, or to join one of these again with a new invitation, leave one in Settings first.", 409)
    }
    val registration = device.registration(pending) + mapOf("code" to JsonPrimitive(invitation.code), "platform" to JsonPrimitive("android"))
    val response = serviceAt(invitation.origin).send("claimInvite", registration)
    val token = response.credential ?: throw ValidationException(FamilyInvitation.invalid)
    val joined = FamilyCredential(invitation.origin, token, PorchExperience.FAMILY)
    // A pairing that hasn't checked in since this phone began remembering households doesn't say which
    // one it's in yet. Ask it once, so a new invitation from that family still replaces it.
    for (family in families) {
        if (family.deviceID == joined.deviceID || family.origin != joined.origin) continue
        if (coordinator.state(family) != null || device.householdID(family) != null) continue
        val values = coordinator.pollOrder.next(mapOf("available" to JsonPrimitive(coordinator.canReceive())))
        val state = try {
            serviceFor(family).send("poll", values).state
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (_: Exception) {
            null
        }
        if (state != null) device.noteHousehold(state, family)
    }
    // A new invitation from a family this phone is already in replaces its old pairing there, as it
    // always has. It leaves only once the family has accepted this phone again.
    val householdID = response.state?.householdID
    val replaced = families.filter {
        it.deviceID != joined.deviceID && it.origin == joined.origin && householdID != null &&
            (coordinator.state(it)?.householdID ?: device.householdID(it)) == householdID
    }
    for (previous in replaced) {
        // Keep the old pairing so Join can retry; reclaiming this invitation returns the same identity.
        val switchFailed = FamilyServiceException("Couldn't switch families. Check your internet and tap Join family again.", 503)
        try {
            serviceFor(previous).send("leaveHousehold")
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (failure: FamilyServiceException) {
            // Already removed, or its household is gone: nothing is left to leave.
            if (failure.status !in listOf(401, 404)) throw switchFailed
        } catch (_: Exception) {
            throw switchFailed
        }
    }
    device.save(joined)
    response.state?.let { device.noteHousehold(it, joined) }
    val kept = replaced.firstNotNullOfOrNull { device.nickname(it) }
    for (previous in replaced) device.removeFamily(previous)
    val name = nickname?.trim()
    if (!name.isNullOrEmpty()) device.setNickname(name, joined)
    else if (kept != null) device.setNickname(kept, joined)
    device.select(joined)
    coordinator.start()
    // Two sets of parents are often both "Mom". Left unnamed, the new one is numbered, so ask now, while
    // it's clear which one it is.
    val shared = device.unnumberedName(joined)
    val numbered = device.familyName(joined)
    if (shared != null && numbered != null && numbered != shared) return JoinedFamily(joined, shared, numbered)
    return JoinedFamily(joined)
}
