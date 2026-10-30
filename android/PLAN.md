# Porch for Android: port plan

Status: plan only, written 2026-10-22 against commit `8c5cd8f`. Nothing here is built yet.

The goal is an Android app with the same features as the iOS app: bedside mode and family mode in one app, using the same calling server, so Android and iOS devices can share a household.

Estimate: about **14–18 weeks** for one experienced Android developer working by hand, or about **3–5 weeks** at the pace this repo was built. At that pace, testing on real devices limits progress more than writing code does. See [estimates](#estimates).

## Decisions

These are recommendations. The ones that need Ethan's call are repeated under [open questions](#open-questions).

1. **Native Kotlin with Jetpack Compose.** Don't move iOS to a cross-platform framework; the iOS app is already tested on real devices and would have to be rewritten. Kotlin Multiplatform isn't worth it either: PorchCore is about 1,600 lines of Swift and ports quickly.
2. **Same server, same API.** Android calls `POST /api/family` and the `/api/calls/*` endpoints exactly as iOS does. The one server change is push delivery through Firebase Cloud Messaging (FCM), in [phase 0](#phase-0-server-push-and-an-incoming-call-spike).
3. **One app with both modes,** as on iOS. Phones default to family mode. Tablets (smallest width ≥ 600 dp) default to bedside mode.
4. **One build.** Android needs no driver or special entitlement for Cell2Jack, so there is no family/Cell2Jack split like [the iOS build variants](../ios/BUILD-VARIANTS.md). USB host is declared optional (`required="false"`).
5. **Application ID `com.ethanteng.helloporch`**, the same as the iOS bundle ID.
6. **minSdk 29 (Android 10), targetSdk 36.** Google Play has required API 36 for new apps and updates since August 31, 2026. API 29 gives scoped storage, `PowerManager.getCurrentThermalStatus()` and Keystore keys that require an unlocked device, all without compatibility branches. Lower it only if a family phone needs it.
7. **Family features first.** Mom's bedside iPad already works. Android family phones therefore deliver value soonest, and they test the riskiest part early: ringing a locked phone. The bedside comes after.
8. **On Android, a call you place keeps going when you lock the phone.** On iOS, leaving Porch ends a call you placed ([NativeCallViewController.swift:412](../ios/Porch/NativeCallViewController.swift)), which is a known gap. Android needs a phone-call foreground service for incoming calls anyway, so outgoing calls can run in it too.

## How the iOS pieces map

| iOS | Android |
|---|---|
| UIKit view controllers | Compose screens and ViewModels, Navigation Compose |
| PorchCore Swift package | `:core` Kotlin/JVM module with ported tests |
| UserDefaults (`porch.*` keys) | DataStore, using the same key names |
| Keychain, AfterFirstUnlockThisDeviceOnly | AES-GCM blob in credential-encrypted storage, key in Android Keystore |
| Keychain, WhenUnlockedThisDeviceOnly | Keystore key with `setUnlockedDeviceRequired(true)` |
| LiveKit Swift SDK 2.17.0 | LiveKit Android SDK (`io.livekit:livekit-android`) |
| PushKit VoIP push | FCM high-priority data message |
| CallKit | Jetpack Core-Telecom (`androidx.core:core-telecom`), a `CallStyle` notification with a full-screen intent, and a `phoneCall` foreground service |
| UNUserNotification alerts | FCM notification on a `messages` channel |
| AVSpeechSynthesizer | `TextToSpeech` |
| AVAudioPlayer / AVPlayer | Media3 ExoPlayer, which plays the generated WAV tones, `.m4a`, `.mov`, `.mp4` and `.mp3` |
| AVAudioRecorder | `MediaRecorder` (MPEG_4, AAC) |
| AVCaptureMovieFileOutput, UIImagePickerController video | CameraX `VideoCapture` with `Recorder` |
| Vision face rectangles | CameraX `ImageAnalysis` with ML Kit face detection (bundled model) |
| CNContactPickerViewController | `ACTION_PICK` on `ContactsContract` |
| PHPicker / UIColorPicker | Photo Picker / a Compose palette with a hex field |
| PhoneNumberKit 5.0.9 | libphonenumber |
| SFSafariViewController | Custom Tabs |
| `isIdleTimerDisabled` | `FLAG_KEEP_SCREEN_ON` |
| `pressesBegan` HID keys | `onKeyEvent` / `dispatchKeyEvent` |
| Guided Access | Home-app mode, optionally lock task mode ([phase 6](#phase-6-cell2jack-and-dedicated-tablet-mode)) |
| DriverKit Cell2Jack driver | `UsbManager` / `UsbDeviceConnection` in the app; no driver |
| `porch://` URL scheme | Intent filter for scheme `porch`, hosts `pair` and `activate` |
| Share sheet | `ACTION_SEND` chooser |
| `beginBackgroundTask` for hang-up | Finish the request inside the call's foreground service |

## Phase 0: server push and an incoming-call spike

### Server: add FCM alongside APNs

Today the server sends pushes only through APNs ([push.ts](../lib/family/push.ts)). Changes:

- **Registration type.** Add `platform?: "ios" | "android"` to `VoIPRegistration` (push.ts:4). A missing field means iOS, because stored households don't have it. `Member.voip` and `Member.alerts` ([household.ts:15](../lib/family/household.ts)) pick up the change automatically.
- **Registration validation.** `registerVoIP` and `registerAlerts` ([service.ts:423-431](../lib/family/service.ts)) must accept `{token, platform: "android"}`. FCM tokens aren't hex, so validate Android tokens separately, for example with `^[A-Za-z0-9_:-]{20,4096}$`. Require `environment` only for iOS. Android sends the same FCM token to both actions.
- **Sender.** Add to push.ts:
  - `fcmConfigured()`.
  - A cached service-account OAuth token, modeled on `apnsAuthorization()`.
  - `sendFCM()`, which posts to the FCM HTTP v1 `messages:send` endpoint.

  `sendVoIPPush` and `sendAlertPush` then pick APNs or FCM by platform. Add `FCM_PROJECT_ID`, `FCM_CLIENT_EMAIL` and `FCM_PRIVATE_KEY` to the calling project's Vercel production environment.
- **Call push.** A data-only message with `android.priority: "HIGH"` and TTL `expiresAt − now`. It carries the same fields as the APNs VoIP payload, as strings: `type: "call"`, `callID`, `recipientID`, `callerName`, `mode`, `expiresAt`. As on iOS, there is no cancel push; the device notices cancellation by polling. A later optimization could add a normal-priority cancel message, which Android allows.
- **Alert push.** A notification message on channel `messages`, tagged with the `messageID`, with a 7-day TTL. Put `messageID` and `badge` in the data, since FCM has no badge field and launchers count notifications instead.
- **Gating.** `voipConfigured()` is global and gates call reachability throughout: service.ts:71, 85, 114, 159, 313–315, 511, 591, 663 and [inbound.ts](../lib/family/inbound.ts):149, 155, 172. Replace it with a per-registration check, so an Android device is reachable whenever FCM is configured, whatever the APNs setup.
- **Invalid tokens.** Treat FCM `UNREGISTERED` (404) and invalid-token errors as `invalidToken`. In the four cleanup sites (service.ts:136–139, 320–323, 600–603 and inbound.ts:182–185), compare platform as well as token.
- **Health checks.** `health.ts:10-11` fails without APNs. Report `pushConfigured` per platform, and update the `pushConfigured` checks in `scripts/prepare-app-review.mjs` and `scripts/verify-calling-deployment.mjs` to match.
- **Wording.** Clients show server error text verbatim, and some of it names the iPad: screening.ts:94 and speech.ts:101. The phone-fallback participant is also named `"Porch iPad"` (phone.ts:100). Make these device-neutral.
- **Tests.** Extend `tests/voip-push.test.mjs` with a fake FCM endpoint. Tests must never contact Google.
- **Owner steps (Ethan).** Create the Firebase project and a service account, and put the key in Vercel.

### Spike: ring a locked Android phone

Build a throwaway app on a branch. It should:

1. Pair as a family member of a test household and register its FCM token.
2. On a call push, add an incoming call with Core-Telecom (`CallsManager.addCall`; the library has been stable since 1.0) and post a `CallStyle` notification with a full-screen intent.
3. On Answer, start the call's foreground service, call `acceptCall` and `joinCall`, and connect LiveKit audio. Confirm the microphone works when answering from the lock screen.
4. Keep polling every 5 s while answered. The server drops an accepted-call member after 35 s without a poll ([household.ts:97](../lib/family/household.ts)).

Call each test phone from the bedside iPad in each of these states:

- Porch open.
- Porch in the background.
- Swiped away.
- Screen off for 30+ minutes. To force Doze immediately, use `adb shell dumpsys deviceidle force-idle`.
- Battery saver on.
- After a reboot, without opening Porch.
- Force-stopped. This is expected to fail, like force-quit on iOS; document it.

Record the time from key press to ring.

Exit criteria: the phone rings in every state except force-stop, on a stock Pixel, on a Samsung phone and, where possible, on each family member's own phone. If a phone can't be made reliable, decide then: give OEM battery-settings guidance, or keep that person on regular-phone fallback, which already works.

Also in phase 0, run a LiveKit video call on the candidate bedside tablet. Check echo cancellation, speaker volume and where the front camera sits in landscape.

## Phase 1: foundations

### Project layout

```
android/
  settings.gradle.kts
  gradle/libs.versions.toml   version catalog; pin everything
  core/                        Kotlin/JVM: the PorchCore port and its tests
  app/                         the Android app
```

Libraries, at the latest stable versions when work starts:

- Compose and Navigation
- kotlinx.serialization
- OkHttp
- DataStore
- LiveKit Android
- Core-Telecom
- Firebase Messaging
- CameraX
- Media3
- ML Kit face detection
- libphonenumber
- AndroidX Browser

### `:core`: port PorchCore

Port the tests alongside the code. Sources are in [PorchCoreTests](../ios/PorchCore/Tests/PorchCoreTests): `PorchCoreTests.swift` (651 lines) plus eight smaller files.

- **`FamilyModels.swift` → kotlinx.serialization DTOs.** Many snapshot fields are optional because older servers omit them. Give every optional field a default, and ignore unknown keys.
- **`CallSlots`, `CallContact`, `KeypadAction`.**
  - There are 12 keys: 1–9, then 0, then `*` (slot 10) and `#` (slot 11).
  - Defaults: 1–8 are person keys, 9 toggles video, 0 is call control, and `*` and `#` are empty person keys ([CallSlots.swift:36](../ios/PorchCore/Sources/PorchCore/CallSlots.swift)).
  - Validation: names up to 80 characters, at most 5 numbers, color `^[0-9A-F]{6}$`, E.164 `^\+[1-9][0-9]{6,14}$`.
  - Skip the v1→v2 slot and inline-photo migrations; Android starts fresh.
- **Keypad logic.** `CallTrigger` covers repeat suppression, the 2 s launch cooldown, and `IncomingCallKey`: hold 1 s to decline, release to answer. Also port `KeypadActionPreview`.
- **Bedside display.** `BedsideDisplay` covers scene, period, season and hemisphere.
- **`BedsideLanguage`.**
  - Five languages, about 100 strings each, in an English-keyed dictionary.
  - Keep it in code, not in Android string resources. The bedside language is independent of the device locale, and caregiver and family screens stay in English.
  - Port the test that checks format arguments match across languages.
- **Calls.**
  - `CallPreferences` constants.
  - `CallInactivityTimer`, on `SystemClock.elapsedRealtime()`.
  - `CallTone`, which generates the tones as 16 kHz mono WAV.
  - `NativeCallServer`: https only, or http for localhost.
- **Messages and photos.**
  - `MessageAutoplay` and `PresenceTrigger`.
  - `BedsideAttendance` and `AttendanceTracker`: what family see about someone at the bedside, and the seconds the bedside reports.
  - `ContactPhotoStore`: SHA-256 IDs, path-traversal checks, prune unreferenced photos after 24 h.
- **Phone numbers.** `PhoneNumberNormalization` on libphonenumber: reject extensions, and use the device region.
- **Invitation parsing.** The same rules as `FamilyInvitation` and `PorchWebLinks` in [FamilyModels.swift](../ios/PorchCore/Sources/PorchCore/FamilyModels.swift):
  - `porch://pair?server=<origin>&code=<64 hex>` and `porch://activate?…`: exactly two query items; no path, user, port or fragment.
  - Web links for the app's own server, `https://helloporch.store/join#code=<64 hex>` and `/setup#code=…`, opened as Android App Links. That needs an `assetlinks.json` beside the Apple file in `app/.well-known/`.
- **Shared contract fixtures.** Save real response JSON from the server tests to `tests/fixtures/`. Decode the fixtures in both the PorchCore and `:core` tests, so a server change that breaks either client fails CI.

### Server client, credentials and polling

- **`FamilyClient`.** One `POST {origin}/api/family` JSON request carries `{action, …}`.
  - Headers: `Authorization: Bearer <deviceID>.<secret>`, plus `X-Porch-Setup-Code` for caregiver actions.
  - Timeouts: 12 s by default, 25 s for `addPhoneGuest`, 30 s for `speech`.
  - Keep the body under 2,048 characters.
  - Send no `Origin` header; the server rejects cross-origin requests (service.ts:150).
  - Responses: decode `{error, errorCode}` and show `error` as it comes. A 401 means access was removed. A 404 on `endCall` counts as success.
  - Server URL: `BuildConfig.PORCH_SERVER_URL`, defaulting to `https://porch-calling-prototype.vercel.app`.
- **Device identity.**
  - The device ID is a lowercase UUID v4, and the secret is 32 random bytes as hex. The phone routes match `^Bearer [a-f0-9-]{36}\.[a-f0-9]{64}$`.
  - Cache the pending credential by SHA-256 of origin plus code, so a retried claim is idempotent.
- **Secure storage.**
  - The paired credential (`porch.family.<role>`) lives in credential-encrypted storage, which unlocks at first unlock, as on iOS.
  - The caregiver PIN, pending pairing, activation link and phone approvals use a Keystore key that requires an unlocked device.
  - Turn off Auto Backup (`allowBackup="false"`) so a restored phone can't clone a device identity.
  - Unlike the iOS Keychain, none of this survives uninstalling. A reinstall means pairing again, and a caregiver revokes the old device.
- **`FamilyCoordinator`.**
  - Polls `poll {available}` every 1 s while a call isn't ended, otherwise every 2 s on the bedside and 3 s on family devices.
  - No backoff. On error, keep the last state. `pause()` sends `available: false`.
  - `available` is true only when the current screen can take an incoming call. This matches `readyForIncoming` ([PorchContainerViewController.swift:18](../ios/Porch/PorchContainerViewController.swift)).
  - Work after each snapshot:
    - Photo sync, verifying each photo's SHA-256.
    - Bedside slot reconcile.
    - Speech-clip prefetch.
    - Keypad-number report, retrying after 30 s, or 600 s after a 403 or 429.
- **Links and pairing.**
  - Handle `porch://pair` and `porch://activate` from intents, and also accept a pasted link.
  - Family pairing: `claimInvite`, then add the family to the ones the phone is in (up to four, as on iOS). Only a previous pairing with the same household is left with `leaveHousehold` (ignore 401 or 404). Save, then start polling every family. Route VoIP pushes and message notifications by `recipientID`, the phone's member ID in that family ([ios/FAMILY-SETUP.md](../ios/FAMILY-SETUP.md#more-than-one-family)).
  - Bedside: activation link, then `enrollBedside` with name and PIN. Refuse if the device is already enrolled.
- **Mode switch.** Unregister push for the old role, then restart the coordinator.
- **CI.** `.github/workflows/android-build.yml` runs on `android/**` changes: build, `:core` unit tests, Android lint.

Exit criteria: an Android phone joins an existing household from an invitation and shows as online on the bedside iPad, and an Android tablet enrolls from an activation link and sets a PIN.

## Phase 2: family calling

### Home screen

- For each person, show availability and four buttons: Audio call, Video call, Drop in with audio, Drop in with video.
- Under the bedside, show `BedsideAttendance.text` from `bedsideAttendedAt` and `serverTime`: "Someone is at the iPad", or how long ago someone was.
- Drop-in buttons are enabled only when the bedside is online and not busy, drop-in is on, and the person has permission.
- Also show message entry points and the held-voicemail, new-message and drop-in-paused banners.

### Outgoing call

1. `startCall`.
2. `joinCall`. The URL must be `wss`.
3. Ask for microphone and, for video, camera permission.
4. Connect LiveKit with default options; iOS sets no custom room or connect options.
5. Turn the microphone on, and the camera too for a video call when "Start with my camera on" is set.

- **Ringback.** Play the `CallTone` ringback locally, looping at volume 0.7. Never publish it to the room.
- **Wait timer.** It starts after connecting: 30 s if the callee already accepted, otherwise the session's wait.
- **Errors.** An `offline` error code offers a voicemail. Any other error never falls back, because a lost response may still have created a call.
- **On `accepted`.** Cancel the wait and start a 30 s "couldn't connect" timer.
- **Room events.** Ignore events from a room that has been replaced. The call ends when no remote participants remain.
- **Call screen.** Two video tiles: side by side in landscape, stacked in portrait. Someone with the camera off shows as a photo or name. Controls are mute, camera and end, with one control change at a time. A chime plays when the camera turns on.

### Incoming calls (from the spike, hardened)

- **Every call push posts a call notification before any network request,** even a stale or duplicate push, which is then ended at once. This mirrors iOS's PushKit rule, and it also stops FCM from demoting high-priority messages that show nothing.
- **Validation.** Check that the recipient is this device ID, the role is the current mode, and `expiresAt` is in the future. Dedupe by call ID against the last 32 IDs.
- **While ringing.** Poll `{available: false, receivedCallID}` every 1 s; `receivedCallID` tells the server the push arrived.
  - End the call if it disappears or ends, or after 25 s without a successful poll.
  - At expiry, end it as unanswered. On a family device, don't call `endCall` then; the caller's own timer decides what happens next.
- **Answer.** The microphone must already be granted, since there's no permission prompt from the background. Then `acceptCall`, `joinCall`, connect, and mark the call active. Poll every 5 s while answered.
- **Camera on a family phone.** It turns on only once the call screen is visible and the phone is unlocked, and only if "Start with my camera on" is set. It turns off when Porch leaves the foreground, and back on when you return unless you turned it off during the call. Serialize camera changes.
- **Foreground service.** Outgoing calls run in the same service ([decision 8](#decisions)).
- **Audio.** Use LiveKit's Android audio handling: speaker by default, plus Bluetooth headsets. During a Telecom call, route through the call's endpoint API. iOS shows no route picker; keep it that way unless testing shows a need.

### Drop-in, three-way calls and silence hang-up

- **Drop-in from a family phone.** `startCall {kind: "dropIn"}` with the fixed 45 s wait. The bedside must be online; there's no push for drop-ins.
- **Three-way calls** ([CallGuests.swift](../ios/Porch/CallGuests.swift)):
  - Show Add when the call is accepted, the bedside is in the room, and this device isn't itself a guest.
  - **Adding family:** `addPorchGuest` rings the other person. The guest's phone sees a synthesized call with `guest: true` and uses the same `acceptCall`, `joinCall` and `endCall` with that ID.
  - **Adding a phone number:** caregivers only. `addPhoneGuest` takes North American numbers only, with a 25 s request timeout and a 75 s window to join. `removePhoneGuest` runs on hang-up.
  - **DTMF:** sent over LiveKit data. iOS uses `publishDtmf`, codes 0–9 with `*` = 10 and `#` = 11; check what the Android SDK offers for this.
- **Silence hang-up.** Off by default; 15–1,800 s, default 120.
  - It uses LiveKit active-speaker events. A phone participant on a Porch call counts as activity, since a bank's hold music can be silent.
  - Reset it on reconnect.
- **Settings.** "Start with my camera on".

### Permissions

- `RECORD_AUDIO` and `CAMERA`.
- `POST_NOTIFICATIONS` (Android 13+).
- `MANAGE_OWN_CALLS`.
- The phone-call, microphone and camera foreground-service permissions.
- `USE_FULL_SCREEN_INTENT`. On Android 14+, check `canUseFullScreenIntent()` and link to the setting if it's off.
- `BLUETOOTH_CONNECT`.

**Milestone A:** an Android family beta on Play's internal testing track. It covers calls both ways with Mom's iPad, ringing while locked, drop-in, and three-way calls.

## Phase 3: family messages, profiles and remote caregiver

- **Recording formats iOS can play:**
  - Audio: `.m4a`, AAC-LC, 44.1 kHz mono, 64 kbps, sent as `audio/mp4`.
  - Video: MP4 with H.264 and AAC at about 640×480 (CameraX SD quality), sent as `video/mp4`.
  - Don't use the system camera app; it can return HEVC or 3GP. Check the output codecs on each test device.
  - Limits: up to 120 s; audio up to 10 MB, video up to 100 MB ([messages.ts:12](../lib/family/messages.ts)). Check them before `createMessage`.
- **Upload.** `createMessage`, then PUT with exactly the returned headers (600 s timeout), then `completeMessage`. If the upload already finished, a retry only calls `completeMessage`.
- **Composer.**
  - Beep, a 0.7 s pause, then record for up to 120 s. Discard anything under 1 s.
  - The sent list offers Unsend.
  - The received list plays messages with Media3, then sends `receivedMessagePlayed`.
  - Video posters are a frame taken at 0.5 s.
- **Alerts.** `registerAlerts` with the FCM token. Notifications go on the `messages` channel, and tapping one opens received messages.
- **Profile.** A name, and a photo from the camera or library: JPEG, quality 0.82, longest side ≤ 768 px, ≤ 1,000,000 bytes, with a SHA-256 ID. Upload with `profilePhotoUpload`, then PUT, then `setProfile`.
- **Remote caregiver.**
  - The PIN stays in memory for 10 idle minutes and is cleared when Porch goes to the background.
  - Admin screens:
    - People, permissions and drop-in.
    - Phone drop-in.
    - Call screening.
    - Messages and held-voicemail review.
    - Invites, sent with the share sheet using the iOS text.
    - Change PIN.
  - Build these here; bedside caregiver mode reuses them in phase 4.
- **Cross-platform media check.** Android must play iOS `.mov` and `.m4a` and the server's `.mp3`. iOS must play Android `.mp4` and `.m4a`.

**Milestone B:** the Android family app is complete.

## Phase 4: bedside shell and caregiver mode

- **Default clock.**
  - Weekday, time and date in the bedside locale.
  - Sizes come from screen ratios, and AM/PM is shown at 25%.
  - It refreshes on the minute, and on time or locale changes.
- **Dynamic clock.**
  - Drawn on a Canvas: sky ramps, a sun or moon arc, 24 stars at night, hills and a seasonal tree.
  - It crossfades over 1.5 s unless animations are off.
  - Day runs 6–18 by default, with a hemisphere setting.
- **Screen.** Keep it on and hide the system bars.
- **Contact grid.**
  - Two columns at width ≥ 600 dp, with photo cards.
  - The button color is configurable, with black or white text chosen by WCAG contrast.
  - Each card shows "Press X".
- **Keypad keys.**
  - Digits come from `KEYCODE_NUMPAD_0`–`9` and `KEYCODE_0`–`9`.
  - `*` comes from `KEYCODE_STAR`, `KEYCODE_NUMPAD_MULTIPLY` or a typed `*`. `#` comes from `KEYCODE_POUND` or a typed `#` (Shift+3).
  - Ignore digits with Ctrl, Alt or Meta, and with Shift.
  - Ignore auto-repeat, so each press triggers one action.
  - Status hints clear after 5 s.
- **Caregiver entry.**
  - A gear tap, or a 0.5 s hold, opens the PIN screen. The PIN must match `^[0-9]{6}$`.
  - It uses `caregiverStatus`, `verifyPIN` and `initializeCaregiverPIN`. First enrollment asks for a name, an activation link and a PIN.
  - The privacy policy (helloporch.store/privacy, in Custom Tabs) is reachable without the PIN.
- **Key editor.**
  - Four actions per key, and a link to a family member.
  - Contact import, a primary number plus other numbers (5 at most), and Make primary.
  - Photo comes from the Photo Picker; color from a palette plus a hex field.
  - Saving a number calls `contacts/authorize`. Cache the approval until 5 minutes before its 30-day expiry, then optionally call `setPhoneDropIn`.
- **Contact import.** Android's picker returns the one phone number you tap, with no permission. iOS also imports the contact's other numbers, which on Android needs `READ_CONTACTS`. See [open questions](#open-questions).
- **Call preferences.**
  - Fallback wait: 5–120 s in steps of 5.
  - Leave a message when unanswered.
  - Ring before voicemail: 15–120 s, saved with `setRingSeconds`.
  - Test ringing, and test announcement.
- **Bedside display, language and voice.**
  - Language is saved with `setBedsideLanguage`.
  - Natural voices come from the snapshot's `speech` field and are chosen with `setSpeechVoice`.
  - Built-in `TextToSpeech` voices are offered per language: en-US, zh-TW, zh-CN, zh-HK and es-ES. Check which speech engines on the chosen tablet offer Cantonese and Taiwan Mandarin.
- **Advanced.** Silence hang-up, and the Cell2Jack switch (phase 6).
- **Typing with a keypad attached.** Android hides the on-screen keyboard when a hardware keyboard is attached unless the user changes that setting, which is the same problem iPadOS has.
  - Port the Porch keyboard: number pad, phone pad with `+`, and text with a symbols layer, plus Paste, Next and Done.
  - Hide the system keyboard for fields that use it.

## Phase 5: bedside calls and messages

### Outgoing calls and phone fallback

- **Outgoing.**
  - `waitSeconds` is 45 for a contact without a phone number, otherwise the fallback wait.
  - A 2 s cooldown applies between launches.
  - The hang-up key cancels a call that's still starting.
- **Phone fallback,** in the iOS order ([NativeCallViewController.swift:868](../ios/Porch/NativeCallViewController.swift)):
  1. Abort if anyone has joined the Porch call.
  2. `fallback {callID}`. A 409 `answered` means Porch was answered.
  3. Record whether the microphone is muted.
  4. Switch to a new room and disconnect the old one. This releases the camera and keeps late Porch joins out of the phone call.
  5. Get the contact authorization.
  6. `prepare {localRingback: true}`.
  7. Store the control token before connecting, then connect.
  8. `start`, then wait up to 60 s for an answer.
  9. Watch `sip.callStatus`: `active` or `automation` means connected, `hangup` ends the call.
  10. On end, call `end` with one retry. If it can't be confirmed, show "Retry ending phone call". Finish the hang-up request even if Porch goes to the background.

### Incoming calls and drop-in

- **Incoming on the bedside.**
  - Shown in the app when the bedside is ready, with Answer, Decline and a repeating 3 s ring.
  - With the call-control key, tap to answer and hold 1 s to decline.
  - Caregiver screens never auto-answer.
  - Inbound phone calls (`source: "phone"`) use the same `acceptCall` and `joinCall`.
  - The bedside also registers for call pushes, as on iOS.
- **Receiving a drop-in.**
  1. Play the 0.6 s chime.
  2. Play the natural-voice clip if it's already cached; never wait for a download. Otherwise use `TextToSpeech`.
  3. A 15 s watchdog stops the announcement from hanging.
  4. Count down 5 s, then accept.
  - "Don't connect" cancels.
  - Any failure needs a manual Answer.
  - Decline if microphone or camera permission is missing.
  - The server enforces the 5 s gap after `announcedAt`.

### Messages

- **Voicemail recorder after an unanswered call.**
  - Conditions are in NativeCallViewController.swift:696.
  - Chime, prompt, beep, then record for up to 120 s.
  - Keep a recording only if it's at least 2 s long with sound above −40 dB.
  - An interruption sends what was recorded.
  - An outbox retries after min(900, 15·2^(n−1)) s and gives up after 2 days.
- **Waiting messages.**
  - Sync on each poll, download, then `messageDelivered`.
  - The player announces "Message from X. Sent Y.", then plays.
  - `messagePlayed` is sent at the end.
  - The stop key stops playback.
- **Presence autoplay.**
  - CameraX image analysis at about 3 frames per second at 640×480, with ML Kit face detection.
  - It triggers when the tallest face is ≥ 0.12 of the frame height for 2 s, allowing gaps of up to 1 s.
  - It runs only when all of these hold:
    - The clock is idle with messages waiting.
    - It's within the allowed hours (8–21 by default).
    - Porch is visible and the bedside isn't busy.
    - Thermal status is below severe.
  - It announces, then plays. "Not now" snoozes for 30 minutes per set of messages.
- **Someone at the bedside.**
  - Any touch, key or phone-keypad press counts. Send the whole seconds since then as `attendedSeconds` with each poll, only while the bedside snapshot's `shareAttendance` is true. While it's false, forget the last time.
  - Caregiver mode shows **Privacy → Show family when someone is at the iPad** (`setShareAttendance`), on the tablet and on phones.
  - If the caregiver turns on **Check with the camera** (a setting on the tablet), the same face detection looks for up to 5 s every 30 s on the idle clock. A face held for 1 s counts.
  - A face seen while presence autoplay is watching counts too, but only with that setting on.
  - Nothing is recorded or sent. Stop the camera before any call screen opens.
- **Held phone voicemail.** Auto-release it (`releaseKnownCaller`) for carrier-verified callers who are saved on the keypad.

## Phase 6: Cell2Jack and dedicated-tablet mode

### Cell2Jack

- **Matching.** Match VID `0x1A86` and PID `0x7523` (CH340) with `device_filter.xml` and the USB-attached intent, so Android offers to always open Porch for the device. Generic CH340 adapters share this ID, as they do on iOS.
- **Claiming.** Claim interface 0, detaching the kernel's serial driver. Use the first bulk IN and bulk OUT endpoints, and reject a packet size of 0 or over 256.
- **Init.** Write our own transport rather than relying on usb-serial-for-android, so we send exactly what the verified iPad driver sends ([PorchCell2JackDriver.cpp](../ios/Cell2JackDriver/PorchCell2JackDriver.cpp), [Cell2JackProtocol.h](../ios/Cell2JackDriver/Cell2JackProtocol.h)). Each control transfer has a 500 ms timeout.

  | Step | Request type | bRequest | wValue | wIndex | Length |
  |---|---|---|---|---|---|
  | Read chip version | `0xC0` | `0x5F` | 0 | 0 | 2 (reject versions below `0x30`) |
  | Serial init | `0x40` | `0xA1` | 0 | 0 | 0 |
  | 2 Mbaud | `0x40` | `0x9A` | `0x1312` | `0xFD03`, or `0xFD83` if version > `0x27` | 0 |
  | 8N1, RX and TX on | `0x40` | `0x9A` | `0x2518` | `0x00C3` | 0 |
  | Flow control off | `0x40` | `0x9A` | `0x2727` | 0 | 0 |
  | DTR and RTS off | `0x40` | `0xA4` | `0xFFFF` | 0 | 0 |

- **Protocol.**
  1. Send `/v`, then read up to 6 × 500 ms until a newline.
  2. Wait 500 ms, then send `/d`.
  3. Poll bulk IN with a 250 ms timeout.
  4. Send `/q` to stop.
  - If no bytes arrive within 2 s of starting, send `/q` and start again, up to 3 tries.
  - Clear a stalled endpoint once and retry the transfer once.
- **Parser.** Port `Cell2JackDTMFParser.swift` and its tests:
  - Primary `DTMF` versus secondary `Double DTMF` reports.
  - The embedded-record fallback.
  - The rule that ignores the pulse digit after `Get PULSE`.
  - A–D are ignored.
- **Lifecycle.**
  - Off by default, and it runs only in bedside mode with Porch in the foreground.
  - On pause, send `/q` and close the connection.
  - Reconnect after 1, 2, 4, 8, then 15 s. The delay resets after 30 s of a healthy connection.
- **Routing.** Digits go only to screens that accept keys, through the same handling as keyboard keys.
- **Status and diagnostics.** "Phone keypad ready" shows for 3 s. Diagnostics keep the last 200 actions and a 64 KiB raw tail.
- **Power.** Confirm the tablet charges while Cell2Jack is attached, for example through a USB-C hub with power passthrough. The bedside runs plugged in.

### Dedicated-tablet mode (new on Android)

The iPad needs Porch to stay open and unlocked, plus Guided Access. Android can do better:

- **Porch as the home app.** On the bedside, make Porch the home app: an activity alias with the HOME category, enabled only in bedside mode. It then starts at boot. Android 15 blocks starting phone-call, camera or microphone foreground services from a boot broadcast, and a home app avoids that problem.
- **Lock task mode (optional).** Porch can be the device owner, set once with `adb shell dpm set-device-owner` on a freshly reset tablet. This hides the status bar and app switching.
- **Waking for calls.** Incoming calls turn the screen on and show over the lock screen (`setShowWhenLocked`, `setTurnScreenOn`).
- **Tablet settings.** No screen lock, and battery optimization off for Porch, both set once in Settings.

**Milestone C:** the Android bedside matches the iPad.

## Phase 7: hardening and release

- **Device matrix.**
  - The chosen bedside tablet.
  - A Pixel phone and a Samsung phone.
  - Each Android family member's own phone.
  - Android 10, 14, 15 and 16.
- **Acceptance checks.** Write `android/ACCEPTANCE.md` from the iOS checks in [FAMILY-SETUP.md](../ios/FAMILY-SETUP.md#verify) and [INCOMING-CALLS.md](../ios/INCOMING-CALLS.md). Add the phase 0 background states and the [race tests](#race-tests-carried-over-from-ios).
- **Play Console.**
  - The Data safety form: camera, microphone, photos, phone numbers from picked contacts, device identifiers, push tokens, audio and video messages, and speech.
  - Declarations for each foreground-service type, with demo videos.
  - The full-screen intent declaration, as a calling app.
  - Target API 36.
  - 16 KB page-size support for native libraries; check LiveKit's WebRTC build.
  - Play App Signing.
- **Tracks.**
  - Internal testing has no review and allows up to 100 testers, which covers family.
  - Production on a personal developer account created after November 13, 2023 first needs a closed test with 12 testers for 14 days. An organization account doesn't.
- **Review access.** Reuse `createBedsideInvite {purpose: "appReview"}`. Adapt `scripts/prepare-app-review.mjs` to write Play's "App access" instructions.
- **Release workflow.** `.github/workflows/android-release.yml`: manual, verify-only by default, and it deploys the calling server first, like `testflight.yml`. The upload key goes in GitHub secrets.
- **Website.**
  - The privacy policy ([app/(site)/privacy/page.tsx](<../app/(site)/privacy/page.tsx>)): add Google/FCM as a processor next to Apple (line 36), say "tablet" or "device" where it says iPad, and add Android permission wording.
  - The pilot page says there's no Android app (app/(site)/pilot/page.tsx:281).
- **Docs.** `android/README.md` covering build, installing on the bedside tablet and dedicated-tablet setup. Link it from the main README.

## Estimates

| Phase | By hand | At this repo's pace (calendar days) |
|---|---|---|
| 0. Server push and incoming-call spike | 1.5–2 weeks | 2–3 |
| 1. Foundations | 2 weeks | 2–3 |
| 2. Family calling | 2–3 weeks | 3–5 |
| 3. Family messages, profiles, remote caregiver | 2 weeks | 2–4 |
| 4. Bedside shell and caregiver mode | 2–2.5 weeks | 3–5 |
| 5. Bedside calls and messages | 2–2.5 weeks | 3–5 |
| 6. Cell2Jack and dedicated-tablet mode | 1 week | 1–2 |
| 7. Hardening and release | 2–3 weeks | 5–8 |
| **Total** | **about 14–18 weeks** | **about 3–5 weeks** |

Notes:

- The by-hand column assumes one developer who knows Android calling.
- The second column follows this repo's history: the iOS app and server took about ten days.
- Device testing runs alongside every phase from phase 2 on. Phase 7 is mostly calendar time on real devices.
- Play's 14-day closed test, if it applies, comes on top.

## Race tests carried over from iOS

Each of these is handled explicitly in the iOS code. Each needs an Android test, automated where possible, otherwise on a device.

**Phone fallback**
1. The fallback timer fires just as the callee answers. The remote-participant check and the server's `answered` conflict pick one winner.
2. A lost `startCall` response must never trigger phone fallback. Only `offline` counts.
3. The call is answered while fallback starts but media isn't ready: show "answered, but this device couldn't connect".
4. Mute carries across the room switch, and the camera is released before dialing.
5. `start` races `end`: the server checks again after dialing, deletes the room on error and returns 409 `cancelled`.
6. A phone call whose end can't be confirmed keeps its control token and offers "Retry ending phone call".

**Room events**

7. Events from a replaced LiveKit room are ignored.

**Incoming calls**

8. Every call push shows a call, even a malformed, stale or duplicate one, which is then ended. The last 32 call IDs prevent ringing twice.
9. The camera never starts behind the lock screen on a family phone. A quick background-and-return leaves it in the right state.

**Bedside camera**

10. The bedside's presence camera stops before any call, drop-in or voicemail screen. An incoming call that arrives during that wait is checked again afterwards.

**Drop-in**

11. A drop-in never connects when speech fails or hangs. The server also requires 5 s after `announcedAt`.

**Three-way calls**

12. A guest invitation stops ringing when the main call ends.
13. A phone guest that connects after its dial request timed out is removed, and dialing is blocked for 6 s after a server error.
14. Leaving a three-way call uses actual LiveKit occupancy, and the bedside is never left alone with only a phone.

## Risks

| Risk | Likelihood | What we do |
|---|---|---|
| Phones from some manufacturers don't ring when Porch is in the background | High | Phase 0 spike on real phones, OEM settings guidance, regular-phone fallback for anyone left |
| FCM demotes high-priority messages that show nothing | Medium | Every call push shows a call notification |
| Echo or quiet audio on the bedside tablet | Medium | Test in phase 0, pick one tablet model |
| A device records in a format iOS can't play | Medium | Fixed CameraX/MediaRecorder settings, codec check per device, cross-platform playback test |
| Play rejects the foreground-service or full-screen-intent declarations | Medium | Prepare the declarations and demo video early; the app's core function is calling |
| The on-screen keyboard is hidden while the keypad is attached | Medium | Porch keyboard, as on iPadOS |
| No Cantonese or Taiwan Mandarin built-in voice on a device | Low | Natural voices come from the server; with no voice, a drop-in waits for a manual Answer |
| The two apps drift apart | Medium | Shared JSON fixtures in CI, and feature PRs that note the Android follow-up |

## Open questions

1. **Family phones.** Which Android phones does the family actually use? This sets the device matrix.
2. **Bedside tablet.** Will any household use an Android tablet as the bedside? If so, which model? It needs Android 15+, USB-C host and charging at the same time, and a front camera that's centered in landscape.
3. **Play account.** Personal or organization? An organization account under the LLC avoids the 12-tester rule, but needs a D-U-N-S number.
4. **Outgoing calls.** Should calls you place keep going when the phone locks ([decision 8](#decisions))? This changes behavior from iOS.
5. **Contacts.** Ask for `READ_CONTACTS` to import a contact's other numbers, or import only the number picked?
6. **Bedside lock-down.** Is the home-app mode enough, or should Porch be device owner with lock task mode?
7. **Firebase setup.** These are Ethan's steps: create the project and service account, and add their keys to Vercel.

## Keeping the two apps in step

- The server stays the single source of truth for behavior. Android adds no new endpoints beyond FCM registration.
- JSON fixtures shared between PorchCore and `:core` catch contract drift in CI.
- A feature PR either covers both apps or notes the Android follow-up, and updates the shared docs.
