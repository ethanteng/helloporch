# Cell2Jack and backup keypads in Porch

Use the normal **Porch** scheme on `feature/cell2jack-ipad-version-poc`.
Build 17 installs as **Porch**, identity `com.ethanteng.helloporch`, preserving
contacts, photos, calling credentials, and ordinary keyboard/touch input.
The app's Cell2Jack option starts **off**, including on the iPad that previously
ran the automatically enabled experiment. It uses a new opt-in preference,
`porch.cell2jack.enabled`; the prototype's `porch.cell2jack.realCalls.enabled`
value and its Debug auto-enable launch argument do not activate the normal app.

## Build and input boundaries

The normal target compiles the tested owner, bridge and parser, embeds
**PorchCell2JackCallsDriver** (ABI 2), and includes driver communication
alongside its existing APNs entitlement. The driver identity remains
`com.ethanteng.helloporch.usbdriver`, preserving the verified installed driver.
The old experimental real-call target is a historical fixture, not required to
build the normal app. No experimental compilation flag gates the integration.
Preview still excludes the calling engine and this owner.

Standard USB/Bluetooth HID keypads still go through UIKit's `pressesBegan` /
`pressesEnded` and the existing `CallTrigger`, separately from Cell2Jack. Neither
Cell2Jack's switch, connection status, nor driver registration disables that
path. A hardware key held down retains repeat suppression; outgoing launch
cooldown is shared through the existing call handler. The current call screen
still accepts HID hang-up and camera keys. Touchscreen buttons retain their
existing handlers. Caregiver/PIN fields continue using normal keyboard input.
There is no input-device mode switch and the driver still matches only the
specific Cell2Jack USB interface, not HID keyboard interfaces.

The universal app retains device families 1 and 2 and minimum iOS 15. IOKit is
weak-linked, and the default USB transport is created only on an iPad with
OS 16 or later; the settings explain that an M-series chip is required. Other
platforms retain keyboard/touch operation. This OS/idiom check does not identify
individual chip models; an unsupported iPad or missing driver produces an
unavailable status instead of blocking the standard input paths.

Both normal Debug and unsigned Release builds passed. Signed development build
17 installed on the physical M3 iPad. Distribution remains subject to Apple's
[DriverKit entitlements](https://developer.apple.com/documentation/driverkit/requesting-entitlements-for-driverkit-development)
and provisioning approval. An unsigned Release build is not a TestFlight or
App Store signing validation. Apple's [iPadOS driver guide](https://developer.apple.com/documentation/driverkit/creating-drivers-for-ipados)
describes the driver packaging; [Apple DTS](https://developer.apple.com/forums/thread/793915)
explains that the same client app can run on iOS and iPadOS, while DriverKit
communication is an iPadOS facility.

## Setup and use

- Turn off the driver in **Porch Preview** settings to avoid matching two copies
  of the same driver. Enable the driver in the real **Porch** app's settings,
  disconnect Cell2Jack for ten seconds, then reconnect it.
- In Porch caregiver mode → **Advanced**, turn on **Use Cell2Jack phone keypad**.
  This takes effect immediately, separately from the existing Save button for
  silence settings. It is off by default. No launch argument automatically enables the normal app.
  To use it, explicitly turn on this switch; it persists until turned off again.
- Return to the bedside clock and wait for **Phone keypad ready** beneath **Call someone**. This confirmation
  disappears after three seconds; keypad input stays active. Input is
  ignored on caregiver/PIN screens and other unsupported screens.
- Informational clock messages (a key with no action, call/camera key hints, and
  no waiting messages) clear after five seconds. Each replacement gets its own
  five seconds; leaving the clock or backgrounding clears the message.
- Press a saved person's key to call them. Press the configured call-control key
  (currently **0**) to end the call, including while it is ringing. During the
  short interval while the request is starting, that key marks the request for
  cancellation and ends a returned session before presenting it.
- Putting the receiver back on the phone also ends the call, as the
  call-control key does, unless **Hang up when the receiver is put back** is off
  in Advanced. See [Hanging up the receiver](#hanging-up-the-receiver-2026-10-23).
- The saved camera key works in an applicable video call. Incoming call-control
  input is treated as a tap to answer; during an automatic drop-in countdown it
  cancels the drop-in. Message/call-control keys can stop message playback.
- Keep Porch open. Leaving the foreground stops logs with `/q`, closes the user
  client, invalidates pending callbacks, and cancels a pending outgoing request.
  Returning reconnects when enabled. Unexpected USB failures automatically retry
  after 1, 2, 4, 8, then 15 seconds while Porch is active in bedside mode.
  **Retry phone connection** in Advanced can retry immediately. Touch call
  controls remain available when USB is disconnected.

Picking up the receiver is never routed to an app action; putting it back is
(see below). The first physical tests used an AT&T 210 with its handset left
off the cradle during the successful key and call tests.

USB transports keypad input only. Call audio uses the existing iPad audio route.
This integration does not add a USB audio device or automatically route audio to
the phone. DTMF logs provide no trustworthy down/up duration, so hold-to-decline
is not synthesized. `*` and `#` act on whatever their keys are assigned, like
digits; both start with no action. A–D have no keys and are ignored. Secondary Double DTMF diagnostic reports do not trigger actions;
separate primary reports, including repeated digits, remain separate inputs.

## Lifecycle and diagnostics

`Cell2JackKeypadTransport` uses the established `/v` read → 500 ms → `/d`
sequence, two million baud, and the existing DriverKit bridge. It drains USB on
one serial queue; idle reads block for up to 250 ms. It retries initial silence
at most three times and closes on an error. There is no preview time/byte cutoff
that would disable hang-up during a longer call. Parser state is bounded and
the local action trace retains only its last 200
records in `Documents/cell2jack-call-actions.json`. Build 14 also retains a
64 KiB maximum raw USB tail in `Documents/cell2jack-usb-tail.bin`, written at
most once every five seconds during normal polling and on cleanup. Diagnostic
storage failure does not stop input. Health records report packet, byte, and
primary-digit counts; each replaces the previous health record so the five-second
reports cannot push key and call history out of the 200 records (before, the
trace covered only about 17 minutes). Input gate failures report their reason.

The owner reconnects after unexpected failures only after the previous USB
client has closed. Retries are cancelled when disabled, backgrounded, or leaving
bedside mode. Backoff resets after 30 seconds of a responsive session; stale
client completions cannot clear a replacement connection. Retry scheduling is
recorded as `usbRetryScheduled`, without displaying diagnostics on the clock.

The driver clears a stalled bulk endpoint with `ClearStall(true)` and retries
the transfer at most once. Partial reads are retained; partially written serial
commands are not replayed. Other failures return to the app for reconnection.
The embedded driver's build number is `$(CURRENT_PROJECT_VERSION)`.
`PorchCell2JackCallsDriver` follows `PORCH_BUILD_NUMBER`, the same number as
the Porch app (currently 24), newer than the bedside's installed build 23.
A command-line
`CURRENT_PROJECT_VERSION` still overrides both. Reconnect the USB
cable after installing an updated driver so iPadOS can start the new copy.

Protocol tests exercise bounded stall clearing and partial-transfer behavior.
`Cell2JackRoutingTests` also covers automatic retry, backoff, cancellation and
late callbacks; the iPad CI job runs this suite. Recovery support belongs to the
connection: an unavailable production platform never retries, while injected
connections can exercise recovery on both the iPhone and family targets.
The retry scheduler and monotonic clock are injectable so the backoff/reset tests
run deterministically without timing margins or a 30-second wait. These use injected failures;
physical unplug/replug and phone-key verification remain device checks.

Routing chooses the current visible receiver; an unknown modal blocks routing
instead of falling through to the clock. Transitioning screens and callbacks
more than one second old are ignored. A generation token prevents pre-pause
callbacks from acting after a foreground change. Existing contact launch
cooldown, call-in-progress, and ending guards remain in force. No phone digit
or hook input executes a URL or bypasses caregiver setup.

The trace distinguishes USB readiness, primary digits/raw lines and dispatch
outcomes, call start requested/session created, end requested, and local call
screen closure. A dispatch record alone does not prove that a peer answered or
that the remote call ended. Confirm those on both devices during the call test.
Trace files can contain phone-key activity and local error details; keep them
out of source control.

## Validation to date

- Signed device build and deep signature verification passed. Build 14 installed
  in place on the physical M3 iPad. Saved assignment bytes match the pre-install
  copy. No contact data or credentials were imported from Preview.
- Nine simulator routing tests passed: current-screen selection, unknown modal
  blocking, navigation, non-digit/hook rejection, repeated digits, fragmented
  USB/secondary report filtering, real call-screen hang-up using a remapped saved
  key without starting a connection, clock status layout at four iPad sizes,
  launch before activation, quick foreground return while the old client closes,
  disabled/family mode, and stale readiness
  callback rejection, plus USB dispatch to a full-screen receiver while its
  presenting clock view is detached from the window.
- The ordinary Porch simulator build passed. Preview's source/package safety
  boundary still passes. PorchCore was unchanged (68 tests passed at the prior
  preview milestone).
- Physical build 12 reached USB ready. The user pressed the unassigned key 3
  with the handset untouched and confirmed that Porch showed no person assigned.
  The user then started a call with 1, but 0 did nothing in build 12; on-screen
  End worked. Build 13 changed the full-screen gate, but another test had no
  accepted digits, with no raw capture available to establish its cause.
  Build 14 captured 3/5/0, then two successful 1 → answer → 0 call cycles. The
  user confirmed both ended on both devices without moving the handset or
  reconnecting USB.

Build:

```sh
xcodebuild -project ios/Porch.xcodeproj -scheme Porch \
  -configuration Debug -destination 'generic/platform=iOS' \
  -derivedDataPath ios/build/PorchIntegrated -allowProvisioningUpdates build
```

Simulator tests use the same scheme with a booted iPad destination and
normal automatic signing. Ad-hoc simulator app signing is needed for the
keychain tests; disabling signing causes those tests to fail independently of
Cell2Jack. The driver is not embedded into the simulator app.

## Build 12 startup correction

Build 11 could remain at “Phone keypad paused” without opening USB. On the
physical iPad, the build 12 scene activation trace recorded UIApplication state
1 (inactive) while UIWindowScene state was 0 (foreground active), with bedside
mode and the feature enabled. The scene callback arrived before the app-wide
state caught up. Build 12 follows explicit scene activation/resignation for
transport ownership and foreground cleanup; it still checks the active window
before routing digits. It recorded `usbStartRequested`, then `usbReady` three
seconds later. Eight simulator tests passed, including startup and rapid
stop/restart lifecycle tests with an injected transport (no USB or calls).

## Build 13 full-screen call input correction

Build 12 checked `root.view.window.windowScene` before dispatching a digit. A
full-screen call can remove its presenting clock/container view from the window,
so valid input was discarded before it could be recorded or sent to the call
screen. The physical trace showed call creation from 1, no dispatched 0, then
an on-screen end request and local closure. The user confirmed that 0 did nothing
and the touch End button worked.

Build 13 retains a weak reference to the owning UIWindowScene, assigned by the
scene delegate. Input checks that scene's activation state independently of the
presenter's view attachment. It records `rootViewAttached` for accepted digits
and records a scene-gate rejection instead of silently losing its evidence.
The new regression test sends USB 0 to a visible receiver while the clock view
has no window, then verifies the same input is blocked after scene resignation.
Nine simulator tests and the signed device build passed. Driver build 6 is
unchanged. The build 14 physical retest subsequently verified call teardown, including
`rootViewAttached: false` on the USB 0 dispatch.

## Build 14 physical call verification and bounded diagnostics

Build 14 adds the bounded raw tail, periodic receive counters, and explicit
rejection diagnostics. It changes no driver commands or calling actions. The
user pressed 3, 5, 0 on the AT&T 210 while off the cradle; all three appear in
both the raw USB tail and action trace, dispatched at the clock with the root
view attached.

The user then pressed 1, answered on the other device, and pressed 0. The trace
records USB 1 → call request/session creation → call-end request and USB 0 to the
call screen → local screen closure. The 0 event explicitly records the root
view detached from its window, verifying the full-screen gate correction. The
user confirmed the call ended on both devices. A second complete cycle also
worked without handset movement or USB reconnection. Nine simulator tests and
the signed build passed. This is a verified experimental build, not a claim of
unattended reliability, on-cradle detection, or distribution approval.

## Build 15 normal integration verification

The normal Porch scheme's full 62-test suite passed on both iPad and iPhone
simulators. The normal signed device build and unsigned Release build passed,
and the device signature verified. The app keeps its iOS 15 deployment target;
IOKit references are weak imports in the built binary. Preview's source/package
boundary still passed.

New coverage checks off-by-default behavior even with the old test preference
set, the immediate caregiver toggle, ordinary HID person selection and hang-up
with Cell2Jack off/ready/disconnected, repeat suppression, and touchscreen entry
to the person picker. The keypad-backup checks exercise UIKit handlers using
synthetic HID presses, not a physical USB connection. The user also physically verified the standard USB keypad on the M3 iPad
with Cell2Jack off: key 3 showed its empty-slot message, 1 placed a call,
0 ended it, and tapping Call someone opened the touch person picker. The
installed preferences confirm Cell2Jack is off and the saved slot bytes are
unchanged from the pre-install copy.

The broader setup tests also exposed secure PIN insertion clearing the previous
text after keyboard help restored focus. The touch keyboard now replaces its
current caret/selection explicitly for secure text and emits editing-change
notification. The existing PIN-preservation regression passes alongside normal
text selection, deletion, and native/hardware-keyboard setup tests.

## Build 16 bedside confirmation

The phone keypad status now sits directly below Call someone, outside the clock
stack. A ready confirmation hides after three seconds without changing USB
ownership or digit routing. Duplicate ready notifications do not restart the
timer; reconnecting gets a fresh confirmation. Build 17 restricts the bedside label to this ready confirmation; connection,
paused, stopped, and error details are not displayed in the app UI.
Switching the feature off hides the status immediately.
Layout checks cover four iPad portrait/landscape sizes. A timed regression checks
visibility before three seconds, dismissal afterwards, duplicate notifications,
reconnection, and disabling. All 63 iPad simulator cases passed. Xcode’s runner stalled during result
finalization after reporting all suites passed; it was terminated afterwards.
The signed
build installed on the M3 iPad, preserving the user's now-enabled Cell2Jack
preference and saved contacts. Build 15's physical backup-keypad and touchscreen
checks remain the latest hardware verification for those paths.

## PR verification and build 17

The automated code review of the integration reported no findings. The initial
GitHub simulator build rejected ad-hoc signing for its DriverKit dependency.
Simulator CI now uses `SimulatorCI.xcconfig`: app/test ad-hoc signing remains
enabled for real Keychain tests, while signing is disabled only for the
DriverKit SDK dependency, which is not embedded in Simulator. Device signing
settings are unchanged. The universal simulator build and all 63 cases on both
iPad and iPhone completed successfully locally with this configuration. Local
runs disabled test diagnostic collection to avoid earlier result-finalization
stalls. CI also runs the USB protocol/parser and no-call Preview boundary checks.

Build 17 hides all connection diagnostics on the bedside clock, including the
reported USB stage 10 stop message. The caregiver status label is also removed;
the toggle and Retry control remain. Diagnostics stay in local diagnostic files. The ready confirmation still appears below Call someone for
three seconds. The existing timed regression now also checks diagnostic
suppression and dismissing an active confirmation when the connection stops.

## Distribution verification 2026-10-18

Apple Developer showed the existing Porch TestFlight App Store profile as invalid
after adding the app capability. It was regenerated with the existing Apple
Distribution certificate. Its signed profile now grants production APNs and
`com.apple.developer.driverkit.communicates-with-drivers`, and has no device
list or development debugging permission. The encrypted GitHub app-profile
secret was updated.

A separate App Store profile, Porch Cell2Jack TestFlight, was generated for
`com.ethanteng.helloporch.usbdriver` with the same certificate. Its signed
entitlements contain **neither DriverKit nor USB transport authorization**.
An App Store profile existing in the portal does not establish permission to
distribute a DriverKit extension. Xcode's actual Release archive attempt rejected
this profile for both missing entitlements. The local Mac also lacks the Apple
Distribution private key; the existing distribution identity is stored in the
GitHub environment. No valid distribution archive/export or App Store validation
can be claimed yet. Development builds remain separately signed and functional.

The manual TestFlight workflow now defaults to verification only, without a server
deployment or upload. It requires independent app and driver profiles; checks
team, bundle IDs, expiration, App Store type, shared signing certificate, production
APNs, app driver communication, and the driver's approved hardware grant; and
checks the actual signatures and embedded profiles in both archive and exported
IPA before App Store validation. The driver signature must retain the exact USB
VID/PID restriction. A global product bundle ID override was removed because it
would also rename the driver. Nine provisioning regressions cover missing grants,
wildcard development permissions, incorrect devices/platforms/IDs/certificates,
and a valid restricted or vendor-level distribution grant. These checks are also
part of normal simulator CI.

With user authorization, a request was submitted on 2026-10-18 through [Apple's DriverKit entitlement form](https://developer.apple.com/contact/request/system-extension/)
requesting `com.apple.developer.driverkit` and USB transport covering vendor 6790
(`0x1A86`), product 29987 (`0x7523`). The request must disclose that Cell2Jack
is third-party hardware and the developer does not own the shared vendor ID.
Apple confirmed receipt; approval remains pending. After Apple grants the entitlements, regenerate the driver App Store profile,
configure `IOS_DRIVER_APPSTORE_PROFILE`, and run verification-only archive/export
and App Store validation with the GitHub-held signing identity. Upload only after
those checks pass. Apple's [entitlement instructions](https://developer.apple.com/documentation/driverkit/requesting-entitlements-for-driverkit-development)
describe the required approved entitlement group and distribution profile.

## Separate family TestFlight builds

The [build variants guide](BUILD-VARIANTS.md) describes `PorchFamily`, which shares
feature sources/resources but excludes Cell2Jack transport, its driver and settings,
and DriverKit signature entitlements. The TestFlight workflow defaults to this
family variant and needs only the app profile. The earlier distribution blocker
above applies to `variant=cell2jack`; it does not prevent family-only TestFlight
updates. Continue using the `Porch` development scheme on the bedside iPad.

## Picture phone pickup pulse 2026-10-22

The bedside now uses a big-button picture phone (photo keys, STORE, MEMORY,
REDIAL/P, FLASH, MUTE, SOS) instead of the AT&T 210. Its keys work only with the
handset off the cradle. That is the phone, not Porch: an analog phone's keypad is
powered by line current and joined to the line by the hook switch, and Cell2Jack
also enables tone detection only after it reports `OFF_HOOK`
(`MIC gain=45, dtmfis=1`). Nothing reaches USB from an on-cradle press.

The user reported that the first pickup after Cell2Jack had been disconnected
sometimes called the person on 1 without any key press, and reproduced it with
logging on. The raw USB tail shows:

```
L1L2 OFF_HOOK
H1H2L1L2 FLASH
.. Get PULSE 1 1
 Stop Playing Dialtone
 DTMF 1 :0 20: 2
```

Cell2Jack saw one brief line break right after pickup and counted it as a
pulse-dialed 1 (one pulse), then reported it as an ordinary DTMF record. A later
pickup with a real 0 press shows `OFF_HOOK`, `Stop Playing Audio`,
` DTMF 0 :0 20: 2`, with no FLASH or PULSE line, so the photo keys send tones.

The parser now classifies the DTMF record that follows `Get PULSE` as `pulse`,
which Porch, Preview and the test app never act on. An `ON_HOOK`/`OFF_HOOK` line
clears a pulse that produced no record, so it cannot swallow a later key press.
Porch records each one as `pulseDigitIgnored` with its raw line. Pulse (rotary)
dialing is therefore not an input; a phone with a tone/pulse switch must stay on
tone. Parser tests replay this capture at every split point, and a routing test
sends it through the owner to the clock, which receives only the 0.

## Hanging up the receiver 2026-10-23

The picture phone's keys work only with the receiver lifted, so every call from
the bedside starts with a pickup. Putting the receiver back now ends the call,
like a regular phone.

Someone who sets the receiver down right after pressing a person's key, because
the sound comes from the iPad, would end every call at once. **Caregiver mode →
Advanced → Hang up when the receiver is put back** turns this off. It starts on,
takes effect immediately, is stored as `porch.cell2jack.receiverHangUp`, and
leaves keys working. With it off, hang-ups are still recorded, with the outcome
`receiver hang-up off`.

Cell2Jack has no setting to silence its "phone not
connected" warning on pickup (none of its keypad codes or C2JUtility settings
covers it); pressing any key already stops it.

Cell2Jack reports a hang-up as a ` ON_HOOK ` line (`H1H2 ON_HOOK ` and similar),
followed by `Set ON-hook 121`, and a pickup as `L1L2 OFF_HOOK `. A brief break
shows as `FLASH`, never `ON_HOOK`. It also reports ` ON_HOOK ` while starting up
after being plugged back in, with the receiver already down. The parser
therefore reports a `hangUp` event only for an `ON_HOOK` that follows a pickup
or a key press in the same log session (keys only work off the cradle). If logs
start with the receiver already up, the first key press is enough.

Porch routes `hangUp` like a key, to the visible screen only, recording each as
`hangUp` with its outcome and raw line:

| Screen | Putting the receiver back |
| --- | --- |
| Outgoing, connected or phone-fallback call | Ends it, as the call-control key does |
| Answered system (CallKit) call | Ends it |
| Clock while a call request is starting | Cancels the request |
| Call screen already saying they didn't answer | Skips the message screen that would follow, as hanging up does on a phone |
| Leaving a message after no answer | Finishes it; before the beep nothing is sent |
| Incoming call still ringing, drop-in countdown, message playback, clock, people picker | Nothing |

Lifting and replacing the receiver while a call rings does not decline it.

A key pressed while a screen opens or closes is dropped and can be pressed
again, but a hang-up can't be repeated without lifting the receiver. So a
hang-up that finds a screen transitioning is tried again every 0.4 seconds,
up to six tries (about two seconds), and each try is recorded with its
`attempt`. That covers a screen animating in or out. Leaving Porch drops a
waiting retry, recorded as `dropped: session or foreground gate`.

Before a new screen appears, the clock first waits for the presence camera to
stop, which has no fixed length. A hang-up in that wait is held for that
screen and given to it once it has appeared, recorded as `heldHangUp`. Only
the screen that was waiting gets it; a later screen never does. The simulator's
presence camera stops at once, so unit tests can't open this wait; it needs a
check on the iPad with waiting messages and presence detection on.

Saved captures replay as expected: the pickup tests' two hang-ups and the
full-keypad test's final hang-up are found, and three plug-in starts produce
none.
