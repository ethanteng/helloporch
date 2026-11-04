package com.ethanteng.helloporch.core

import java.util.UUID
import java.util.concurrent.atomic.AtomicLong
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.delay
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonPrimitive

/** Numbers this launch's polls. Two can reach the server out of order, such as the one sent as Porch closes overtaking
 * the last one sent while it was open, and the server keeps the newest one's availability. One per app process. */
class PollOrder {
    val launch: String = UUID.randomUUID().toString().lowercase()
    private val sequence = AtomicLong(0)

    fun next(values: Map<String, JsonElement>): Map<String, JsonElement> =
        mapOf("launch" to JsonPrimitive(launch), "sequence" to JsonPrimitive(sequence.incrementAndGet())) + values
}

/** The households this device belongs to, and what it last heard from each. */
data class FamilyLinks(
    val links: List<Link> = emptyList(),
    /** The device ID of the family the screens are showing (see [PorchDevice.currentFamily]). */
    val currentID: String? = null,
) {
    /** One household this device belongs to, and what it last heard from it. The bedside has one; a family phone has
     * one for each family it joined, and checks in with all of them so any of them can reach it. */
    data class Link(
        val credential: FamilyCredential,
        val state: FamilySnapshot? = null,
        val error: String? = null,
        /** The server no longer recognizes this device (a caregiver removed it, or it left). */
        val accessRemoved: Boolean = false,
    )

    val current: Link? get() = links.firstOrNull { it.credential.deviceID == currentID } ?: links.firstOrNull()
    val state: FamilySnapshot? get() = current?.state
    val error: String? get() = current?.error
    val accessRemoved: Boolean get() = current?.accessRemoved ?: false
    val credential: FamilyCredential? get() = current?.credential

    fun link(credential: FamilyCredential): Link? = links.firstOrNull { it.credential.credential == credential.credential }
    /** What one family last said. A call keeps following its own family, whichever one the screens show. */
    fun state(credential: FamilyCredential): FamilySnapshot? = link(credential)?.state
}

/**
 * Keeps this device checked in with each of its households. Main thread only: `scope` runs the polling loops, so it
 * should use the main thread and last as long as the app. `afterChange` runs with every change, before [links] updates.
 */
class FamilyCoordinator(
    private val device: PorchDevice,
    private val scope: CoroutineScope,
    private val serviceFor: (FamilyCredential) -> FamilyService,
    val pollOrder: PollOrder,
    val canReceive: () -> Boolean,
    private val attendance: AttendanceTracker,
    private val caregiver: RemoteCaregiverSession = RemoteCaregiverSession.shared,
    private val afterChange: (FamilyLinks) -> Unit = {},
) {
    private class Link(val credential: FamilyCredential) {
        var state: FamilySnapshot? = null
        var error: String? = null
        var accessRemoved = false
        var job: Job? = null
        fun snapshot() = FamilyLinks.Link(credential, state, error, accessRemoved)
    }

    private var entries: List<Link> = emptyList()
    private var currentID: String? = null
    private val current: Link? get() = entries.firstOrNull { it.credential.deviceID == currentID } ?: entries.firstOrNull()
    private var generation = 0L
    private val published = MutableStateFlow(FamilyLinks())

    val links: StateFlow<FamilyLinks> = published.asStateFlow()
    val state: FamilySnapshot? get() = current?.state
    val error: String? get() = current?.error
    val accessRemoved: Boolean get() = current?.accessRemoved ?: false
    val credential: FamilyCredential? get() = current?.credential
    var isActive = false
        private set

    fun link(credential: FamilyCredential): FamilyLinks.Link? = entry(credential)?.snapshot()
    /** What one family last said. A call keeps following its own family, whichever one the screens show. */
    fun state(credential: FamilyCredential): FamilySnapshot? = entry(credential)?.state

    private fun entry(credential: FamilyCredential): Link? = entries.firstOrNull { it.credential.credential == credential.credential }

    fun start() {
        pause()
        isActive = true
        val credentials = if (device.experience == PorchExperience.FAMILY) device.families
            else listOfNotNull(device.credential(PorchExperience.BEDSIDE))
        currentID = device.credential(device.experience)?.deviceID
        entries = credentials.map(::Link)
        if (entries.isEmpty()) { changed(); return }
        generation += 1
        val generation = this.generation
        for (link in entries) link.job = scope.launch { poll(link, generation) }
    }

    private suspend fun poll(link: Link, generation: Long) {
        val credential = link.credential
        while (currentCoroutineContext().isActive) {
            if (!isActive || this.generation != generation) return
            try {
                val values = mutableMapOf<String, JsonElement>("available" to JsonPrimitive(canReceive()))
                // How long ago someone was at the bedside, so family can tell whether to call now. Never before this
                // launch's first poll says that's on. While a caregiver has it off, nothing is kept to report later.
                if (credential.role == PorchExperience.BEDSIDE && link.state?.shareAttendance == false) attendance.forget()
                else if (credential.role == PorchExperience.BEDSIDE && link.state?.shareAttendance == true) {
                    attendance.secondsSince?.let { values["attendedSeconds"] = JsonPrimitive(it) }
                }
                val result = serviceFor(credential).send("poll", pollOrder.next(values))
                if (this.generation != generation) return
                link.state = result.state; link.error = null; link.accessRemoved = false
                changed()
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (error: Exception) {
                currentCoroutineContext().ensureActive()
                link.error = error.message ?: error.toString()
                // A dropped connection isn't the family putting the phone back. Only a later successful
                // check-in clears the removal, so the card doesn't fill back in with calls that fail.
                if ((error as? FamilyServiceException)?.status == 401) link.accessRemoved = true
                changed()
            }
            val seconds = when {
                link.state?.call?.let { it.state != "ended" } == true -> 1
                credential.role == PorchExperience.FAMILY -> 3
                else -> 2
            }
            delay(seconds * 1000L)
        }
    }

    fun pause() {
        isActive = false; generation++
        for (link in entries) {
            link.job?.cancel(); link.job = null
            // Numbered now, after any poll still in flight.
            val values = pollOrder.next(mapOf("available" to JsonPrimitive(false)))
            val credential = link.credential
            scope.launch {
                try { serviceFor(credential).send("poll", values) } catch (cancelled: CancellationException) { throw cancelled } catch (_: Exception) {}
            }
        }
    }

    /** Shows a family phone's screens for one of its families. Caregiver mode was opened for the other one, so it ends. */
    fun select(credential: FamilyCredential) {
        if (credential.role != PorchExperience.FAMILY || credential.deviceID == current?.credential?.deviceID) return
        device.select(credential); currentID = credential.deviceID
        caregiver.end()
        changed()
    }

    /** Takes a family off this phone once it has left it, or the family removed it. The others keep ringing. */
    fun forget(credential: FamilyCredential) {
        device.removeFamily(credential)
        if (isActive) start()
        else {
            entry(credential)?.job?.cancel()
            entries = entries.filter { it.credential.credential != credential.credential }
            changed()
        }
    }

    /** Leaves a family on the server, then takes it off this phone. */
    suspend fun leave(credential: FamilyCredential) {
        try {
            serviceFor(credential).send("leaveHousehold")
        } catch (failure: FamilyServiceException) {
            // Already removed, or its household is gone: nothing is left to leave.
            if (failure.status !in listOf(401, 404)) throw failure
        }
        forget(credential)
    }

    /** A response's snapshot belongs to the family that knows this device by its member ID. */
    fun update(response: FamilyResponse) {
        val state = response.state ?: return
        val link = entries.firstOrNull { it.credential.deviceID == state.me.id } ?: return
        link.state = state; link.error = null
        changed()
    }

    private fun changed() {
        val links = FamilyLinks(entries.map(Link::snapshot), currentID)
        for (link in links.links) {
            val state = link.state ?: continue
            if (link.credential.role == PorchExperience.FAMILY) device.noteHousehold(state, link.credential)
        }
        afterChange(links)
        published.value = links
    }

    /** `family`: which of a family phone's families to call in; the one its screens show if not given. */
    suspend fun startCall(person: FamilyPerson, mode: NativeCall.Mode, dropIn: Boolean, family: FamilyCredential? = null): FamilyCallSession =
        startCall(person.id, person.name, mode, dropIn, family = family)

    suspend fun startCall(
        targetID: String?,
        name: String,
        mode: NativeCall.Mode,
        dropIn: Boolean,
        waitSeconds: Int = 45,
        family: FamilyCredential? = null,
    ): FamilyCallSession {
        val credential = family ?: credential ?: throw FamilyServiceException("Pair this device first.", 401)
        val values = mutableMapOf("mode" to PorchJson.encodeToJsonElement(NativeCall.Mode.serializer(), mode),
            "kind" to JsonPrimitive(if (dropIn) "dropIn" else "call"), "waitSeconds" to JsonPrimitive(waitSeconds))
        if (targetID != null) values["targetID"] = JsonPrimitive(targetID) else values["unlinked"] = JsonPrimitive(true)
        val service = serviceFor(credential)
        val result = service.send("startCall", values)
        update(result)
        val call = result.state?.call ?: throw FamilyServiceException("Couldn't start the call.", 503)
        // The server turns an ordinary call into a drop-in when this phone is approved for that drop-in and the bedside is open.
        val wait = when {
            credential.role != PorchExperience.FAMILY -> waitSeconds
            call.kind == "dropIn" -> CallPreferences.dropInWaitSeconds
            else -> result.state.ringSeconds ?: CallPreferences.defaultVoicemailSeconds
        }
        return FamilyCallSession(credential, call, name, service, waitSeconds = wait)
    }
}
