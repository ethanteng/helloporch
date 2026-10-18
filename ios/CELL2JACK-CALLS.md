# Cell2Jack keypad in the real Porch app

Use the **PorchCell2JackCalls** scheme on
`feature/cell2jack-ipad-version-poc`. Build 14 installs as **Porch**, with the
real app identity `com.ethanteng.helloporch`. It replaces the installed Porch
binary in place, preserving its settings, contact photos, and keychain identity.
It uses the normal calling engine and live saved assignments, not Preview's
snapshot. This experiment can place real calls.

## Build boundary

The ordinary **Porch** scheme remains free of the USB extension and transport.
The experimental target compiles the regular app sources with
`PORCH_CELL2JACK_CALLS`, plus the verified bridge/parser and the new keypad owner.
Its separate entitlement file includes APNs and driver communication. It embeds
**PorchCell2JackCallsDriver**, the same driver implementation/build 6/ABI 2 under
`com.ethanteng.helloporch.usbdriver`. iPad installation requires exactly one
identifier component after the parent app prefix; the Preview driver's nested
identifier cannot be embedded in the real Porch app.

Debug signing succeeded using development profiles. Distribution approval is
still separate; this scheme does not archive. The regular app's release target
and entitlements are unchanged. Reinstalling an ordinary Porch build removes
this integration while retaining the app's data. Do not uninstall Porch as a
rollback: that can remove its saved data.

## Setup and use

- Turn off the driver in **Porch Preview** settings to avoid matching two copies
  of the same driver. Enable the driver in the real **Porch** app's settings,
  disconnect Cell2Jack for ten seconds, then reconnect it.
- In Porch caregiver mode → **Advanced**, turn on **Use Cell2Jack phone keypad**.
  This takes effect immediately, separately from the existing Save button for
  silence settings. It is off by default. For this authorized device test, the
  Debug launch argument `--enable-cell2jack-keypad` enabled it during installation.
- Return to the bedside clock and wait for **Phone keypad ready**. Input is
  ignored on caregiver/PIN screens and other unsupported screens.
- Press a saved person's key to call them. Press the configured call-control key
  (currently **0**) to end the call, including while it is ringing. During the
  short interval while the request is starting, that key marks the request for
  cancellation and ends a returned session before presenting it.
- The saved camera key works in an applicable video call. Incoming call-control
  input is treated as a tap to answer; during an automatic drop-in countdown it
  cancels the drop-in. Message/call-control keys can stop message playback.
- Keep Porch open. Leaving the foreground stops logs with `/q`, closes the user
  client, invalidates pending callbacks, and cancels a pending outgoing request.
  Returning reconnects when enabled. After a USB error/replug, use **Retry phone
  connection** in Advanced, or leave and reopen Porch. Touch call controls remain
  available when USB is disconnected.

Pickup and handset hang-up events are never routed to app actions. The app's
interface depends only on digit events. The current physical test uses an AT&T
210 with its handset off the cradle.
The handset was left in that position during the successful key and call tests.
This establishes operation without pickup/hang-up between calls; it does not
establish on-cradle digit output or behavior of the intended separate-headset
phone.

USB transports keypad input only. Call audio uses the existing iPad audio route.
This integration does not add a USB audio device or automatically route audio to
the phone. DTMF logs provide no trustworthy down/up duration, so hold-to-decline
is not synthesized. `*`, `#`, and A–D have no saved digit assignments and are
ignored. Secondary Double DTMF diagnostic reports do not trigger actions;
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
primary-digit counts; input gate failures report their reason.

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
xcodebuild -project ios/Porch.xcodeproj -scheme PorchCell2JackCalls \
  -configuration Debug -destination 'generic/platform=iOS' \
  -derivedDataPath ios/build/Cell2JackCalls -allowProvisioningUpdates build
```

Simulator tests use the same scheme with a booted iPad destination and
`CODE_SIGNING_ALLOWED=NO`; the driver is excluded on the simulator.

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
