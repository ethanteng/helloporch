package com.ethanteng.helloporch

import android.Manifest
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.SystemClock
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import com.ethanteng.helloporch.core.CallContact
import com.ethanteng.helloporch.core.CallPreferences
import com.ethanteng.helloporch.core.CallSlots
import com.ethanteng.helloporch.core.CallTrigger
import com.ethanteng.helloporch.core.FamilyCallRecord
import com.ethanteng.helloporch.core.FamilyCallSession
import com.ethanteng.helloporch.core.FamilyCredential
import com.ethanteng.helloporch.core.FamilyLinks
import com.ethanteng.helloporch.core.FamilyPerson
import com.ethanteng.helloporch.core.FamilyServiceException
import com.ethanteng.helloporch.core.KeypadAction
import com.ethanteng.helloporch.core.NativeCall
import com.ethanteng.helloporch.core.PorchExperience
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * The call this device is ringing for or on, and calls it starts: what iOS's PorchContainerViewController and clock
 * screen do for calls. [PorchRoot] shows [incoming] or [active] over everything else. Main thread only.
 */
class CallCenter(private val app: PorchApplication) {
    var incoming by mutableStateOf<IncomingCall?>(null); private set
    var active by mutableStateOf<PorchCall?>(null); private set
    /** The bedside is starting a call: the key was pressed and the server hasn't answered yet. */
    var opening by mutableStateOf(false); private set
    /** Why a call couldn't start, for the screen that started it. */
    var error by mutableStateOf<String?>(null)
    /** Porch was opened for a call, from its notification, and shows over the lock screen until that call is up. */
    var openedForCall by mutableStateOf(false); private set
    private var openedGeneration = 0
    /** A short note on the bedside's clock, such as "No one is assigned to 3", for 5 seconds. */
    var notice by mutableStateOf<String?>(null)

    /** The bedside's ringing call, so a later snapshot of the same call doesn't ring again. */
    private var incomingID: String? = null
    /** Calls a family phone already rang for, newest last. */
    private val rang = ArrayDeque<String>()
    private val trigger = CallTrigger()
    private var cancelOpening = false
    /** Who the bedside is calling, said while that call starts. */
    private var announcement: OutgoingAnnouncement? = null
    private var noticeGeneration = 0

    /** Whether a call screen is showing, so nothing else may ring or open. */
    val busy: Boolean get() = incoming != null || active != null || opening

    /** Already ringing for this call, or on it. A push for it must not be ended as a missed call. */
    fun owns(callID: String) = incoming?.call?.id?.equals(callID, ignoreCase = true) == true || active?.owns(callID) == true

    /** A call in progress on a family phone, which goes on while Porch isn't in front (decision 8 in android/PLAN.md). */
    val continuing: Boolean get() = active?.role == PorchExperience.FAMILY

    /** Porch opened from a call's notification. It shows over the lock screen until the call rings here or is up, or
     * for 10 seconds if it ended meanwhile. */
    fun openForCall() {
        openedForCall = true
        val generation = ++openedGeneration
        app.scope.launch {
            delay(10_000)
            if (openedGeneration == generation) openedForCall = false
        }
    }

    /**
     * What Porch's call service shows, which keeps Porch running for a call while it isn't in front: a call in
     * progress on a family phone, a call ringing through a notification, or Porch's own incoming screen on a family
     * phone, quietly, so it can go on ringing through a notification without the service starting from the background.
     */
    fun updateService() {
        val call = active
        val ringing = incoming
        val system = app.systemCalls.notification
        when {
            call != null && call.role == PorchExperience.FAMILY -> {
                NotificationManagerCompat.from(app).cancel(CallNotifications.INCOMING)
                // Android 11 and later need the microphone named for it to keep recording with the phone locked.
                CallService.show(app, CallNotifications.ONGOING, CallNotifications.ongoing(app, call.name), serviceTypes(withMicrophone = true))
            }
            system != null -> {
                // The service may already be showing the in-progress notification. A new foreground id leaves the old one.
                NotificationManagerCompat.from(app).cancel(CallNotifications.ONGOING)
                CallService.show(app, CallNotifications.INCOMING, system, ServiceInfo.FOREGROUND_SERVICE_TYPE_PHONE_CALL)
            }
            ringing != null && ringing.familyPhone -> {
                NotificationManagerCompat.from(app).cancel(CallNotifications.ONGOING)
                CallService.show(app, CallNotifications.INCOMING,
                    CallNotifications.incoming(app, ringing.call.id, ringing.name, ringing.video, ringing.call.expiresAt, quiet = true),
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_PHONE_CALL)
            }
            else -> CallService.stop(app)
        }
    }

    /** Answer was tapped on a family phone. Accept can still be in flight when the screen locks, and Android 14 will not
     * add the microphone to a call's service from the background, so name it now while Porch is in front. */
    fun noteAnswering() {
        val ringing = incoming?.takeIf { it.familyPhone } ?: return
        NotificationManagerCompat.from(app).cancel(CallNotifications.ONGOING)
        CallService.show(app, CallNotifications.INCOMING,
            CallNotifications.incoming(app, ringing.call.id, ringing.name, ringing.video, ringing.call.expiresAt, quiet = true),
            serviceTypes(withMicrophone = true))
    }

    /** Android 11 and later keep the microphone only while the call's service names it. */
    private fun serviceTypes(withMicrophone: Boolean): Int {
        val microphone = withMicrophone && Build.VERSION.SDK_INT >= 30 &&
            ContextCompat.checkSelfPermission(app, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED
        return if (microphone) ServiceInfo.FOREGROUND_SERVICE_TYPE_PHONE_CALL or ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
            else ServiceInfo.FOREGROUND_SERVICE_TYPE_PHONE_CALL
    }

    /** Each snapshot, from the coordinator: rings for a call to this device, as iOS's familyChanged does. */
    fun noteLinks(links: FamilyLinks) {
        if (app.device.experience == PorchExperience.FAMILY) {
            for (link in links.links) {
                val state = link.state ?: continue
                val call = state.call ?: continue
                if (call.state != "pending" || call.to != state.me.id || call.kind != "call") continue
                // A call ringing through a notification while Porch was closed shows here once Porch is on screen.
                if (call.id in rang && !app.systemCalls.isRinging(call.id)) continue
                if (busy || !app.onScreen || !app.screenReady) continue
                rang.addLast(call.id)
                while (rang.size > 32) rang.removeFirst()
                ring(call, link.credential, name = call.callerName, photo = null, contact = null)
            }
            return
        }
        val credential = links.credential ?: return
        val state = links.state ?: return
        val call = state.call
        if (call == null || call.state != "pending" || call.to != state.me.id) {
            if (call == null || call.state == "ended") incomingID = null
            return
        }
        if (incomingID == call.id || busy || !app.onScreen || !app.screenReady) return
        incomingID = call.id
        val slots = slots()
        val contact = slots.incomingContact(call, state)
        // Someone without a keypad number still shows the photo Porch has for them.
        val photo = contact?.photoData ?: if (call.source != "phone") state.people.firstOrNull { it.id == call.from }?.photoID?.let { app.photos.familyMembers.data(it) } else null
        ring(call, credential, name = contact?.name ?: call.callerName, photo = photo, contact = contact)
    }

    private fun ring(call: FamilyCallRecord, credential: FamilyCredential, name: String, photo: ByteArray?, contact: CallContact?) {
        val ringing = IncomingCall(app, call, credential, name, photo, contact,
            onAnswered = { session -> show(session, name, photo) },
            onClosed = { if (incoming === it) { incoming = null; updateService() } })
        incoming = ringing
        openedForCall = false
        // Porch's own screen takes over from the notification, which rang while Porch was closed.
        app.systemCalls.handOver(call.id)
        updateService()
        ringing.start()
        if (app.systemCalls.takeAnswer(call.id)) ringing.answer()
    }

    /** A family phone calls the bedside person. */
    fun call(person: FamilyPerson, mode: NativeCall.Mode, family: FamilyCredential) {
        // A call ringing through a notification is not [busy] until its screen is up. Starting this one would take that
        // call's service, and a failed start would leave its in-progress notification behind.
        if (busy || app.systemCalls.notification != null) return
        opening = true
        error = null
        // Still in front: the call's service names the microphone now, as for Answer (noteAnswering). The call then goes
        // on if the phone locks before the server answers, since Android won't add it from the background (decision 8).
        CallService.show(app, CallNotifications.ONGOING, CallNotifications.ongoing(app, person.name), serviceTypes(withMicrophone = true))
        app.scope.launch {
            try {
                val session = app.coordinator.startCall(person, mode, dropIn = false, family = family)
                show(session, person.name, person.photoID?.let { app.photos.familyMembers.data(it) })
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                error = (e as? FamilyServiceException)?.takeIf { it.code == "offline" }?.let { "${person.name} isn't available on Porch right now." }
                    ?: e.message ?: "Couldn't start the call."
            } finally {
                opening = false
                // It didn't start: nothing is left for the service to show.
                if (active == null) updateService()
            }
        }
    }

    /** The bedside presses a key, or taps a person: calls whoever is on that key, as iOS's call(slot:) does. */
    fun bedsideKey(digit: Int) {
        // While a call is still starting, the clock stays up but is no longer ready for a new one. The call-control
        // key cancels it, as the Cell2Jack does on iOS; the receiver does too, through [cancelPendingCall].
        if (opening) {
            if (slots().action(digit) == KeypadAction.CALL_CONTROL) cancelPendingCall()
            return
        }
        if (busy || !app.screenReady) return
        val slots = slots()
        val action = slots.action(digit)
        if (action == KeypadAction.MESSAGES) return
        if (action == KeypadAction.CALL_CONTROL || action == KeypadAction.TOGGLE_VIDEO) {
            note(text(if (action == KeypadAction.CALL_CONTROL) "Use this key to answer or end a call."
                else "Use this key to turn your camera off or on during a video call."))
            return
        }
        val contact = slots.contact(digit) ?: run {
            note(text("No one is assigned to %@.\nPlease choose another number.", CallSlots.symbol(digit)))
            return
        }
        call(contact)
    }

    private fun call(contact: CallContact) =
        startBedsideCall(contact.familyMemberID, contact.name, contact.nativeCall.mode, contact.photoData, contact)

    private fun startBedsideCall(memberID: String?, name: String, mode: NativeCall.Mode, photo: ByteArray?, contact: CallContact?) {
        if (app.device.credential(PorchExperience.BEDSIDE) == null || opening) {
            error = text("Check People and Drop-in in caregiver mode, then try again.")
            return
        }
        if (!trigger.allowLaunch(SystemClock.elapsedRealtime() / 1_000.0)) return
        cancelOpening = false
        app.cell2jack.record("callStartRequested", "digitSource" to "shared touch/keyboard/USB handler")
        opening = true
        // Said while the call is set up, so whoever pressed the key hears straight away who they're calling.
        val announcement = OutgoingAnnouncement(app, name)
        this.announcement = announcement
        app.scope.launch {
            try {
                // Someone with a phone number rings on Porch for the fallback wait, then on their phone (PorchCall).
                val wait = if (contact?.phoneNumber == null) 45 else CallPreferences.fallbackSeconds(app.settings)
                val session = app.coordinator.startCall(memberID, name, mode, dropIn = false, waitSeconds = wait)
                if (cancelOpening || !app.onScreen) {
                    announcement.stop()
                    session.end()
                    app.cell2jack.record("pendingCallCancelled")
                    return@launch
                }
                app.cell2jack.record("callSessionCreated")
                show(session.copy(peerContact = contact), name, photo, announcement, contact)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                if (cancelOpening) { announcement.stop(); return@launch }
                app.cell2jack.record("callStartFailed", "error" to e.message)
                // Their Porch app can't ring, or they have no Porch app, so their phone can. Only a confirmed "offline":
                // a lost answer may still have started a Porch call.
                if (contact?.phoneNumber != null && (e as? FamilyServiceException)?.code == "offline" && app.onScreen && active == null) {
                    val call = PorchCall(app, null, name, photo, announcement, contact, phoneOnly = true, onClosed = ::closed)
                    active = call
                    call.start()
                    return@launch
                }
                announcement.stop()
                error = text("Couldn't call %@", name) + "\n\n" + BedsideText.error(app, e.message ?: "Couldn't start the call.")
            } finally {
                opening = false
                this@CallCenter.announcement = null
            }
        }
    }

    /** The call-control key or the receiver while a bedside call is still starting: it doesn't open. As on iOS, the
     * bedside stays opening until that request is answered and the call ended, so no new call can start meanwhile and
     * pick the cancelled one back up. */
    fun cancelPendingCall(): String {
        if (!opening) return "no call"
        cancelOpening = true
        announcement?.stop()
        note(text("Ending call…"))
        return "cancel pending call requested"
    }

    /**
     * Porch left the screen. A family phone's ringing goes on through a notification, and its call in progress goes on
     * with the camera off (decision 8 in android/PLAN.md). The bedside's calls end, as on iOS.
     */
    fun leftScreen() {
        incoming?.leftScreen()
        active?.let { if (continuing) it.leftForeground() else it.endCall() }
        // A family call still being placed goes on with the phone locked, as one already up does. The bedside's ends.
        if (!opening || app.device.experience != PorchExperience.FAMILY) cancelPendingCall()
        // A push announced a call Porch's screen hadn't shown yet.
        app.systemCalls.leftScreen()
    }

    /** Porch is back on screen: a call in progress turns its camera back on if Porch turned it off, and a call whose
     * notification's Answer opened Porch, already showing here, is answered. */
    fun cameOnScreen() {
        active?.returnedToForeground()
        incoming?.let { if (app.systemCalls.takeAnswer(it.call.id)) it.answer() }
    }

    private fun show(session: FamilyCallSession, name: String, photo: ByteArray?, announcement: OutgoingAnnouncement? = null,
        contact: CallContact? = null) {
        val call = PorchCall(app, session, name, photo, announcement, contact, onClosed = ::closed)
        active = call
        openedForCall = false
        updateService()
        // Answered or placed just as Porch left the screen, which stopped its check-ins: a family phone's call needs them.
        if (!app.onScreen && continuing) app.coordinator.start()
        call.start()
    }

    private fun closed(call: PorchCall) {
        if (active !== call) return
        active = null
        updateService()
        // It went on while Porch wasn't in front. Now Porch stops checking in, as it does when it closes.
        if (!app.onScreen) app.coordinator.pause()
    }

    private fun note(text: String) {
        notice = text
        val generation = ++noticeGeneration
        app.scope.launch {
            delay(5_000)
            if (noticeGeneration == generation) notice = null
        }
    }

    private fun slots(): CallSlots = try { CallSlots.load(app.settings, app.photos) } catch (_: Exception) { CallSlots() }
    private fun text(english: String, vararg arguments: Any?) = BedsideText.string(app, english, *arguments)
}
