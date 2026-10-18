# Cell2Jack keypad in the real Porch app

Use the **PorchCell2JackCalls** scheme on
`feature/cell2jack-ipad-version-poc`. Build 11 installs as **Porch**, with the
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
interface depends only on digit events. The intended phone has a separate
handset/headset and base keypad; whether it emits digits with the handset
untouched requires a physical test. Previous successful captures used an
off-hook handset, so they do not establish on-hook hardware behavior.

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
that would disable hang-up during a longer call. It does not save an unbounded
raw log. Parser state is bounded and the local action trace retains only its
last 200 records in `Documents/cell2jack-call-actions.json`.

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

- Signed device build and deep signature verification passed. Build 11 installed
  in place on the physical M3 iPad. Saved assignment bytes match the pre-install
  copy. No contact data or credentials were imported from Preview.
- Six simulator routing tests passed: current-screen selection, unknown modal
  blocking, navigation, non-digit/hook rejection, repeated digits, fragmented
  USB/secondary report filtering, real call-screen hang-up using a remapped saved
  key without starting a connection, and clock status layout at four iPad sizes.
- The ordinary Porch simulator build passed. Preview's source/package safety
  boundary still passes. PorchCore was unchanged (68 tests passed at the prior
  preview milestone).
- Physical driver activation, untouched-handset input, and placing/ending an
  actual call remain pending the user-operated device check. Earlier Preview
  hardware results establish digit transport, not real call completion.

Build:

```sh
xcodebuild -project ios/Porch.xcodeproj -scheme PorchCell2JackCalls \
  -configuration Debug -destination 'generic/platform=iOS' \
  -derivedDataPath ios/build/Cell2JackCalls -allowProvisioningUpdates build
```

Simulator tests use the same scheme with a booted iPad destination and
`CODE_SIGNING_ALLOWED=NO`; the driver is excluded on the simulator.
