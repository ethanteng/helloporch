# Porch for Android: port plan

Status: in progress. First written 2026-10-22 against `8c5cd8f`, and revised 2026-11-02 against `eeabf43` to cover the bedside device and family devices together. Phase 0's server changes are merged (#111, #112); the spikes wait for devices. Phase 1 is merged (#113, #114): an Android phone joins a household from an invitation and shows as online. Phase 2 is merged (#116, #117) and checked in the emulator. On 2026-11-05 a real tablet (a MUISOO KB10) set up against the local server and passed the Cell2Jack key test, and the Cell2Jack now keeps working after the tablet restarts; see [first tablet](#first-tablet-muisoo-kb10). What's left of phase 2 is QR joining from a real phone, once a signed build is in assetlinks.json. Phase 3 is merged (#123, #124, #125, #130, #131 through #133, #134). On 2026-11-07 a Samsung Galaxy A17 on Android 16, joined to a household on the production server, rang with Porch closed and with the phone locked, answered over the lock screen and kept the call going while locked; phone fallback reached a real phone from the KB10 through the local server. Phase 4's first four parts are merged (#126, #127, #128, #129), and its last, the Porch keyboard and About, is in #136.

The goal is Android versions of **both** Porch devices, working with the existing iOS devices in any mix:

- **The bedside device.** An Android tablet that stays with Mom. It shows the clock and keypad, takes the Cell2Jack phone or a USB keypad, handles calls, messages and texts, and runs the in-app setup a family goes through.
- **Family devices.** Android phones, and Android tablets used as family devices. They cover calls, drop-in, messages, caregiver mode and invitations.

Both are one app with two modes, as on iOS, sharing the same calling server.

Why the bedside matters now: inviting other families waits on Apple's DriverKit approval for the Cell2Jack (requested 2026-10-18, still pending), and the Cell2Jack also needs an M-series iPad. An Android tablet talks to the Cell2Jack over USB with no driver and no approval. That makes an Android bedside a second route to new families, alongside the phone adapter.

Estimate: about **18–23 weeks** for one experienced Android developer working by hand, or about **4–6 weeks** at the pace this repo was built. At that pace, testing on real devices limits progress more than writing code does. The iOS app has grown by about a third since the first draft, from about 11,100 to 14,800 lines of Swift. See [estimates](#estimates).

## Device combinations

| Bedside | Family devices | Today | After this plan |
|---|---|---|---|
| iPad | iPhones | Works | Unchanged |
| iPad | Android phones | Android family get only regular phone calls | Full app |
| Android tablet | iPhones | Not possible | Full app |
| Android tablet | Android phones | Not possible | Full app |

- **Mixed families.** One household can have iPhones and Android phones together. One phone can be in up to four families on either platform.
- **The bedside is always a tablet.** iOS allows only an iPad (`canBeBedside`, [FamilyService.swift:18](../ios/Porch/FamilyService.swift)). Android allows only a device whose smallest width is at least 600 dp. Phones are family devices on both.
- **Cross-platform behavior to get right:**
  - Message media must play both ways ([phase 5](#phase-5-messages-voicemail-and-texts)).
  - Push must reach each device on its own platform ([phase 0](#phase-0-server-changes-and-two-spikes)).
  - Wording must fit whichever device the bedside is. Shared text and server errors say "iPad" today.
  - When the keypad backup is built, one format must serve both apps, so an Android tablet can replace an iPad and the other way round ([phase 6](#phase-6-three-way-calls-dedicated-tablet-and-household-lifecycle)).

## Decisions

These are recommendations. The ones that need Ethan's call are repeated under [open questions](#open-questions).

1. **Native Kotlin with Jetpack Compose.** Don't move iOS to a cross-platform framework; the iOS app is already tested on real devices and would have to be rewritten. Kotlin Multiplatform isn't worth it either: PorchCore is small and ports quickly.
2. **Same server, same API.** Android calls `POST /api/family` and the `/api/calls/*` endpoints exactly as iOS does. The server changes are small and come first, in [phase 0](#phase-0-server-changes-and-two-spikes):
   - push through Firebase Cloud Messaging (FCM);
   - a `platform` field on devices;
   - `assetlinks.json` for App Links;
   - device-neutral wording.
3. **One app with both modes.** Phones are family devices only. Tablets can be either, and start at the welcome screen like an iPad does.
4. **One build.** Android needs no driver or special entitlement for the Cell2Jack, so there is no family/Cell2Jack split like [the iOS build variants](../ios/BUILD-VARIANTS.md). USB host is declared optional (`required="false"`).
5. **Application ID `com.ethanteng.helloporch`**, the same as the iOS bundle ID.
6. **minSdk 29 (Android 10), targetSdk 36.** Google Play has required API 36 for new apps and updates since August 31, 2026. API 29 gives scoped storage, `PowerManager.getCurrentThermalStatus()` and Keystore keys that require an unlocked device, all without compatibility branches. Lower it only if a family phone needs it. The bedside tablet needs Android 15 or later (see [the bedside tablet](#the-bedside-tablet)).
7. **The bedside and family devices are built together.** Each phase builds its feature on both device types, so every milestone is a working Android household. Phase 0 tests the hardest part of each device: ringing a locked phone, and a tablet that stays on with the Cell2Jack attached.
8. **On Android, a call you place keeps going when you lock the phone.** On iOS, leaving Porch ends a call you placed ([NativeCallViewController.swift](../ios/Porch/NativeCallViewController.swift), the `didEnterBackground` observer), which is a known gap. Android needs a phone-call foreground service for incoming calls anyway, so outgoing calls can run in it too.
9. **The bedside tablet is a supported product, like the iPad.** Support one or two tested models. List them on the pilot page with the stand and hub, and document setup.
10. **The Cell2Jack connects straight to the tablet.** Android needs no driver and no phone adapter. If the adapter is proven on iPad, it can also work on Android as a USB keyboard, after the key checks in [spike B](#spike-b-the-bedside-tablet).

## The bedside tablet

Requirements for a model we support:

- **Software.** Android 15 or later, with Google Play, and a manufacturer promise of several more years of updates.
- **Screen and camera.** A 10–11 inch screen. The front camera must be on the long edge, so Mom faces it when the tablet sits on its stand in landscape.
- **USB.** USB-C that works as a USB host and charges at the same time, through a hub with power passthrough. Check this on each model: some tablets can't charge while acting as a host.
- **Sound.** Speakers loud enough for a hard-of-hearing listener, and echo cancellation that holds up on a video call. Phase 0 tests both.
- **Parts.** The same as for an iPad, minus the M-chip requirement: a stand, a hub, and either the Cell2Jack with a corded phone or a USB number pad.

[Spike B](#spike-b-the-bedside-tablet) picks the model or models.

## How the iOS pieces map

| iOS | Android |
|---|---|
| UIKit view controllers, split view on iPad | Compose screens and ViewModels, Navigation Compose, two panes at ≥ 600 dp |
| PorchCore Swift package | `:core` Kotlin/JVM module with ported tests |
| UserDefaults (`porch.*` keys) | DataStore, using the same key names |
| Keychain, AfterFirstUnlockThisDeviceOnly | AES-GCM blob in credential-encrypted storage, key in Android Keystore |
| Keychain, WhenUnlockedThisDeviceOnly | Keystore key with `setUnlockedDeviceRequired(true)` |
| LiveKit Swift SDK 2.17.0 | LiveKit Android SDK (`io.livekit:livekit-android`) |
| PushKit VoIP push | FCM high-priority data message |
| CallKit | Jetpack Core-Telecom (`androidx.core:core-telecom`), a `CallStyle` notification with a full-screen intent, and a `phoneCall` foreground service |
| UNUserNotification alerts | FCM notification on a `messages` channel |
| AVSpeechSynthesizer | `TextToSpeech` |
| NaturalLanguage, to read foreign words in a text with their own voice | ML Kit language identification (on device) |
| AVAudioPlayer / AVPlayer | Media3 ExoPlayer, which plays the generated WAV tones, `.m4a`, `.mov`, `.mp4` and `.mp3` |
| AVAudioRecorder | `MediaRecorder` (MPEG_4, AAC) |
| AVCaptureMovieFileOutput, UIImagePickerController video | CameraX `VideoCapture` with `Recorder` |
| Vision face rectangles | CameraX `ImageAnalysis` with ML Kit face detection (bundled model) |
| CoreImage QR code | ZXing core encoder |
| CNContactPickerViewController | `ACTION_PICK` on `ContactsContract` |
| CNContactViewController (Add to Contacts) | `ACTION_INSERT` contact intent |
| MFMessageComposeViewController with a vCard | `ACTION_SENDTO` SMS with a vCard through `FileProvider`, falling back to the share sheet |
| PHPicker / UIColorPicker | Photo Picker / a Compose palette with a hex field |
| PhoneNumberKit 5.0.9 | libphonenumber |
| SFSafariViewController | Custom Tabs |
| `isIdleTimerDisabled`, proximity monitoring | `FLAG_KEEP_SCREEN_ON`, `PROXIMITY_SCREEN_OFF_WAKE_LOCK` |
| `pressesBegan` HID keys, `GCKeyboard` | `onKeyEvent` / `dispatchKeyEvent`, `InputManager` |
| Guided Access | Home-app mode, optionally lock task mode |
| DriverKit Cell2Jack driver | `UsbManager` / `UsbDeviceConnection` in the app; no driver |
| Universal links and the `porch://` scheme | App Links (`autoVerify`) and an intent filter for `porch` |
| Share sheet | `ACTION_SEND` chooser |
| `beginBackgroundTask` for hang-up | Finish the request inside the call's foreground service |
| Settings → Acknowledgements | An in-app open-source licenses screen |

## Phase 0: server changes and two spikes

### Server

**Push through FCM alongside APNs.** Today the server sends pushes only through APNs ([push.ts](../lib/family/push.ts)). Line numbers below are as of `eeabf43`.

- **Registration type.** Add `platform?: "ios" | "android"` to `VoIPRegistration` (push.ts:4). A missing field means iOS, because stored households don't have it. `Member.voip` and `Member.alerts` ([household.ts:17](../lib/family/household.ts)) pick up the change automatically.
- **Registration validation.** `registerVoIP` and `registerAlerts` ([service.ts:486-494](../lib/family/service.ts)) must accept `{token, platform: "android"}`. FCM tokens aren't hex, so validate Android tokens separately, for example with `^[A-Za-z0-9_:-]{20,4096}$`. Require `environment` only for iOS. Android sends the same FCM token to both actions, once in each family the phone belongs to.
- **Sender.** Add to push.ts:
  - `fcmConfigured()`.
  - A cached service-account OAuth token, modeled on `apnsAuthorization()`.
  - `sendFCM()`, which posts to the FCM HTTP v1 `messages:send` endpoint.

  `sendVoIPPush` and `sendAlertPush` then pick APNs or FCM by platform. Add `FCM_PROJECT_ID`, `FCM_CLIENT_EMAIL` and `FCM_PRIVATE_KEY` to the calling project's Vercel production environment.
- **Call push.** A data-only message with `android.priority: "HIGH"` and TTL `expiresAt − now`. It carries the same fields as the APNs VoIP payload, as strings: `type: "call"`, `callID`, `recipientID`, `callerName`, `mode`, `expiresAt`. As on iOS, there is no cancel push; the device notices cancellation by polling.
- **Alert push.** A notification message on channel `messages`, with a 7-day TTL. Tag it per recipient, as iOS now uses `thread-id: porch-messages-<recipientID>` (push.ts:69). Put `messageID`, `recipientID` and `badge` in the data. FCM has no badge field, so launchers count notifications instead.
- **Gating.** `voipConfigured()` is global and APNs-only, and it gates call reachability at service.ts:75/77, 92, 130, 175, 366–368, 580, 671 and 752, and at [inbound.ts](../lib/family/inbound.ts):150, 159 and 180. Replace it with a per-registration check, so an Android device is reachable whenever FCM is configured, whatever the APNs setup.
- **Invalid tokens.** Treat FCM `UNREGISTERED` (404) and invalid-token errors as `invalidToken`. In the cleanup sites (service.ts:152–155, 373–376, 680–683 and inbound.ts:190–193), compare platform as well as token.
- **Health checks.** `lib/calls/health.ts:10-11` fails without APNs. So does the admin System page's Ready badge (`lib/admin/system.ts:11-13`). Report push readiness per platform there, and in the `pushConfigured` checks in `scripts/prepare-app-review.mjs` and `scripts/verify-calling-deployment.mjs`.
- **Tests.** Extend `tests/voip-push.test.mjs` with a fake FCM endpoint. Tests must never contact Google.

**Device platform.**
- Clients send `platform: "ios" | "android"` with `enrollBedside`, `claimInvite` and push registration.
- The server stores it on the member, with a missing value meaning iOS, and returns it on `people[]`.
- Each app can then name the bedside correctly ("Mom's iPad" or "Mom's tablet"), and the admin Porches page can show which devices a household uses.

**App Links.**
- Add `app/.well-known/assetlinks.json/route.ts` beside the Apple file, built in `lib/invite-links.ts`. It returns the package name and the SHA-256 fingerprints of the Play signing key, upload key and debug key.
- It must not redirect on `helloporch.store`.
- The app's intent filter verifies `/join` and `/setup`, and later `/bedside` when replacement links exist.

**Wording.** Clients show server error text verbatim, and several messages name the iPad:
- service.ts:462;
- screening.ts:94;
- speech.ts:105;
- numbers.ts:205, 214 and 284;
- the phone-fallback participant name `"Porch iPad"` (phone.ts:105).

Make these device-neutral, or word them from the bedside's platform. Do the same for the admin invitation text (`lib/admin/invitations.ts:15`).

**Invite landing pages.** `components/InviteLanding.tsx` tells everyone to install TestFlight and says the bedside is an iPad with an M chip. On Android, show the Play testing link instead, from an `NEXT_PUBLIC_PLAY_TESTING_URL` alongside `NEXT_PUBLIC_TESTFLIGHT_URL`, and describe a supported tablet.

**Owner steps (Ethan).** Create the Firebase project and a service account, and put the key in Vercel.

### Spike A: ring a locked Android phone

Build a throwaway app on a branch. It should:

1. Pair as a family member of a test household and register its FCM token.
2. On a call push, add an incoming call with Core-Telecom (`CallsManager.addCall`; the library has been stable since 1.0) and post a `CallStyle` notification with a full-screen intent.
3. On Answer, start the call's foreground service, call `acceptCall` and `joinCall`, and connect LiveKit audio. Confirm the microphone works when answering from the lock screen.
4. Keep polling every 5 s while answered. The server drops an accepted-call member after 35 s without a poll ([household.ts:128](../lib/family/household.ts)).

Call each test phone from a bedside, either the iPad or the candidate tablet from spike B, in each of these states:

- Porch open.
- Porch in the background.
- Swiped away.
- Screen off for 30+ minutes. To force Doze immediately, use `adb shell dumpsys deviceidle force-idle`.
- Battery saver on.
- After a reboot, without opening Porch.
- Force-stopped. This is expected to fail, like force-quit on iOS; document it.

Record the time from key press to ring.

Exit criteria: the phone rings in every state except force-stop, on a stock Pixel, on a Samsung phone and, where possible, on each family member's own phone.

### Spike B: the bedside tablet

On each candidate tablet:

1. **Cell2Jack over USB.**
   - Claim interface 0 and send the [init sequence](#cell2jack).
   - Send `/v` and `/d`, and read DTMF lines with the receiver lifted, including the off-hook and on-hook events.
   - Confirm 2 Mbaud works, and that "always open Porch for this device" is remembered after unplugging.
2. **Power.** The tablet charges through a hub while the Cell2Jack, and separately a USB number pad, is attached. Leave it running overnight.
3. **USB number pad.** Digits, `*` (`KEYCODE_NUMPAD_MULTIPLY`) and the keypad's Enter arrive.
4. **Phone adapter**, only if it's proven on iPad. Check that its keypad `#` (HID `0xCC`) and receiver-back F24 (HID `0x73`) reach Porch. Android has no `KEYCODE_F24`, so look for scan code 194 (Linux `KEY_F24`). If either doesn't arrive, the firmware can send different codes for Android.
5. **Always on.**
   - Porch runs as the home app, and the screen stays on for 24 hours.
   - An incoming call wakes the tablet and shows over the lock screen, from polling while Porch is in front and from FCM if it isn't.
   - Porch starts again after a reboot and after a power cut.
6. **Video call.** Check echo cancellation, speaker volume, and where the camera sits on the stand.

Exit criteria: at least one tablet model passes everything. That model becomes the one the pilot page lists.

#### First tablet: MUISOO KB10

Checked 2026-11-05 with the debug build and the local server, over wireless debugging (the Cell2Jack takes the only USB-C port).

- **Passed.**
  - Android 16 with a smallest width of 800 dp, so Porch offers bedside mode.
  - The Cell2Jack connects straight to the tablet: CH340 version `0x31`, 2 Mbaud, firmware `a06`. Porch heard 0–9, `*`, `#` and the receiver going back.
  - "Always open Porch" is remembered across unplugging, and Porch stops the Cell2Jack when it leaves the front and reconnects when it comes back.
  - After a restart, Android gives Porch the Cell2Jack again before the tablet unlocks, through a direct-boot-aware activity; see [Cell2Jack](#cell2jack).
  - With Porch as the home screen, a restart comes back to Porch's clock by itself, with the screen kept on and the system bars hidden.
- **Against it.**
  - It's an Android Go device (`ro.config.low_ram`, 2.8 GB). Check what Go limits once calls exist: full-screen intents, background work, and LiveKit video on 3 GB.
  - Its firmware clears the screen lock and restarts ("reboot for clean password") after a Volume Up/Down sequence and Power on the lock screen. That's fine for a bedside with no screen lock, but not for a family member's own tablet.
  - **Its audio service crashes during calls.** On 2026-11-05, `android.hardware.audio.service-aidl.aw` crashed six times in six minutes of test calls (a null pointer in `pcm_mmap_avail`, in the maker's `libtinyalsav2.so`), each time sound started or stopped: ringback, the ring tone ending on Answer, the microphone starting and a call ending. It restarts in about a second. Porch retries the microphone once, so calls connect, but sound can drop for that second. Unless a firmware update fixes it, this rules the KB10 out as the supported tablet.
- **Not checked yet.**
  - Charging: powering the Cell2Jack from its own port drained it from 95% to 92% in a few minutes. It needs the hub with power passthrough, and an overnight run.
  - Each connection gets no data after its first `/d` and connects on the second try, about 3 s later. Compare with the iPad's log before treating it as normal.

## Phase 1: foundations

### Project layout

```
android/
  settings.gradle.kts
  gradle/libs.versions.toml   version catalog; pin everything
  core/                        Kotlin/JVM: the PorchCore port and its tests
  app/                         the Android app, both modes
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
- ML Kit face detection and language identification
- ZXing core
- libphonenumber
- AndroidX Browser
- An open-source licenses plugin

### `:core`: port PorchCore

Port the tests alongside the code, from [PorchCoreTests](../ios/PorchCore/Tests/PorchCoreTests).

- **`FamilyModels.swift` → kotlinx.serialization DTOs.** Many snapshot fields are optional because older servers omit them. Give every optional field a default, and ignore unknown keys. Decode `call.expiresAt` as a `Long`: an answered call now reports `Number.MAX_SAFE_INTEGER`, since calls no longer have a length limit.
- **`CallSlots`, `CallContact`, `KeypadAction`.**
  - There are 12 keys: 1–9, then 0, then `*` (slot 10) and `#` (slot 11), laid out as 1 2 3 / 4 5 6 / 7 8 9 / `*` 0 `#`.
  - There are five actions: No action, Call a person, Answer/decline/hang up, Turn video off/on, Play/stop messages.
  - Defaults ([CallSlots.swift:48](../ios/PorchCore/Sources/PorchCore/CallSlots.swift)): 9 toggles video, 0 is call control, and every other key is an empty person key.
  - Validation: names up to 80 characters, at most 5 numbers, color `^[0-9A-F]{6}$`, E.164 `^\+[1-9][0-9]{6,14}$`. Any country is allowed; the server decides what Porch can call.
  - Skip the old slot and inline-photo migrations; Android starts fresh.
- **Keypad logic.** `CallTrigger` covers repeat suppression, the 2 s launch cooldown, and `IncomingCallKey` (hold 1 s to decline, release to answer). Also port `KeypadActionPreview`.
- **Bedside display.** `BedsideDisplay` covers scene, period, season and hemisphere. `BedsideAttendance` and `AttendanceTracker` cover what family see about someone at the bedside, and the seconds the bedside reports.
- **`BedsideLanguage`.**
  - Five languages, in an English-keyed dictionary that now includes the text-message strings.
  - Keep it in code, not in Android string resources. The bedside language is independent of the device locale, and caregiver and family screens stay in English.
  - Port the test that checks format arguments match across languages.
- **Calls.**
  - `CallPreferences` constants.
  - `CallInactivityTimer`, on `SystemClock.elapsedRealtime()`.
  - `CallTone`, which generates the tones as 16 kHz mono WAV.
  - `NativeCallServer`: https only, or http for localhost.
  - The call-history entry model (`callHistory`).
- **Numbers.**
  - `PorchNumber`: the area-code rule `^[2-9](?!11)[0-9]{2}$`, and display as "(510) 567-7039".
  - `PhoneNumberNormalization` on libphonenumber: reject extensions, and use the device region.
- **Messages and photos.** `MessageAutoplay` and `PresenceTrigger`; `MessageBadge`, which sums across families; and `ContactPhotoStore`, with SHA-256 IDs, path-traversal checks and pruning of unreferenced photos after 24 h.
- **Invitation parsing.** The same rules as `FamilyInvitation` and `PorchWebLinks` in [FamilyModels.swift](../ios/PorchCore/Sources/PorchCore/FamilyModels.swift):
  - `https://helloporch.store/join#code=<64 hex>` and `/setup#code=…`, opened as App Links.
  - `porch://pair?server=<origin>&code=<64 hex>` and `porch://activate?…`, for servers other than production: exactly two query items; no path, user, port or fragment.
- **Cell2Jack parser.** Port `Cell2JackDTMFParser.swift` and its tests, covering:
  - primary `DTMF` and secondary `Double DTMF` reports;
  - the embedded-record fallback;
  - the pulse digit after `Get PULSE`, which is ignored;
  - A–D, which are ignored;
  - the hang-up event, which `ON_HOOK` produces only after an `OFF_HOOK` or a key in the same session.

  The phone adapter's firmware ports the same parser; change all three together.
- **Shared contract fixtures.** Save real response JSON from the server tests to `tests/fixtures/`. Decode the fixtures in both the PorchCore and `:core` tests, so a server change that breaks either client fails CI.

### Server client, credentials and polling

- **`FamilyClient`.** One `POST {origin}/api/family` JSON request carries `{action, …}`.
  - Headers: `Authorization: Bearer <deviceID>.<secret>`, plus `X-Porch-Setup-Code` for caregiver actions.
  - Timeouts:
    - 12 s by default;
    - 25 s for `addPhoneGuest`;
    - 30 s for `speech`;
    - 40 s for `textMessage`;
    - 45 s for `assignPhoneNumber`.
  - Keep the body under 2,048 characters, and send `platform: "android"` where phase 0 adds it.
  - Send no `Origin` header; the server rejects cross-origin requests (service.ts:166).
  - Responses: decode `{error, errorCode}` and show `error` as it comes. A 401 means access was removed. A 404 on `endCall` counts as success.
  - Server URL: `BuildConfig.PORCH_SERVER_URL`, defaulting to `https://porch-calling-prototype.vercel.app`.
- **Device identity.**
  - The device ID is a lowercase UUID v4, and the secret is 32 random bytes as hex. The phone routes match `^Bearer [a-f0-9-]{36}\.[a-f0-9]{64}$`.
  - Cache the pending credential by SHA-256 of origin plus code, so a retried claim is idempotent.
- **Secure storage.**
  - Paired credentials live in credential-encrypted storage, which unlocks at first unlock, as on iOS.
  - The caregiver PIN, pending pairing, activation link and phone approvals use a Keystore key that requires an unlocked device.
  - Turn off Auto Backup (`allowBackup="false"`) so a restored phone can't clone a device identity.
  - Unlike the iOS Keychain, none of this survives uninstalling. A reinstall means pairing again, and a caregiver removes the old device.
- **`FamilyCoordinator`.**
  - Polls every 1 s while a call isn't ended, otherwise every 2 s on the bedside and 3 s on family devices, with one loop per family on a phone.
  - Every poll carries `available`, `launch` (a UUID per app launch) and an increasing `sequence`, so the server ignores an older poll that arrives late. The bedside also sends `attendedSeconds` while sharing is on.
  - No backoff. On error, keep the last state. `pause()` sends `available: false`.
  - `available` is true only when the current screen can take an incoming call. This matches `readyForIncoming` in [PorchContainerViewController.swift](../ios/Porch/PorchContainerViewController.swift).
  - Work after each snapshot:
    - Photo sync, verifying each photo's SHA-256.
    - Bedside slot reconcile.
    - Speech-clip prefetch.
    - Keypad-number report, retrying after 30 s, or 600 s after a 403 or 429.
- **Links.**
  - Handle App Links and `porch://` links from intents, and also accept a pasted link. Check on a device that the `#code=` fragment arrives in the intent's data.
  - If a call or caregiver screen is open, show "Finish what's open in Porch, then tap the link again."
- **Mode switch.** Unregister push for the old role, then restart the coordinator.
- **CI.** `.github/workflows/android-build.yml` runs on `android/**` changes: build, `:core` unit tests, Android lint.

Exit criteria: an Android phone opens a `/join` link, joins an existing household and shows as online on the bedside iPad.

## Phase 2: setup and joining

### Bedside tablet

Follow [BedsideSetup.swift](../ios/Porch/BedsideSetup.swift), one screen at a time:

1. **Welcome**, on a device with no pairing: **Set up Porch for someone** or **I'm joining my family**. On a phone, "Set up", and any setup link, explains that the bedside runs on the tablet that stays with them.
2. **Setup link**, unless Porch was opened by it.
3. **Name.**
4. **PIN, entered twice.** This calls `enrollBedside`. A cancelled link answers 410.
5. **Porch number.**
   - `phoneNumberOptions` suggests an area code from the server's view of the IP address, with nearby choices. It's US only; otherwise the caregiver types one.
   - One tap on "Get number" calls `assignPhoneNumber`.
   - `noNumbers`, or a 400, means pick another area code. `numberLimit`, or any other failure, lets them continue while the server keeps retrying.
   - The number step can't be skipped. A setup that stopped after the PIN resumes here.
6. **Microphone and camera,** with one Continue. The screen is skipped if both are already granted.
7. **How they'll call.**
   - **Corded phone.** Android has no driver step, no Settings switch, no ten-second replug and no M-chip requirement. Instead:
     1. Android asks once to let Porch use the Cell2Jack; choose "always".
     2. Porch connects in trial mode, then turns the Cell2Jack keypad on by itself once the phone answers.
     3. "Lift the receiver and press a key" shows the digit Porch heard, without acting on it.
     4. "Put the receiver back" confirms hang-up.

     Tips appear after 30 s: replug it, use tone dialing, and lift the receiver first.
   - **USB keypad.** `InputManager` notices any keyboard, and the screen shows the key Porch heard. Tips appear after 30 s, including Num Lock.
   - **Just the touchscreen**, which goes straight on.
   - **Do this later** and **Back** turn off a keypad this screen turned on. The same screens open again from **This tablet** in caregiver mode.
8. **Add your phone.**
   - Asks for the caregiver's name, then calls `createInvite` with caregiver access. Drop-in is approved for whatever the tablet can already use.
   - Shows a QR code of the `/join` link (ZXing, error correction M, on a white frame). It's replaced when it expires, and the screen shows "Your phone joined" when the invitation is used.
   - **Send the invitation instead** opens the share sheet.
   - The screen is skipped if a caregiver phone has already joined.
9. **Done.** Explains that unknown callers are blocked.

**The Cell2Jack transport** is built in this phase, because step 7 needs it; see [Cell2Jack](#cell2jack).

**Replacing Mom's Porch.** A setup link opened on a tablet that is already a bedside asks "Replace Mom's Porch?". Nothing changes until the new PIN step. Then:

1. Unregister the old household's pushes.
2. Enroll the new household.
3. Save the new credential and PIN.
4. Wipe the old household's keypad, photos, call, message, display and voice settings, and the unsent outbox.

Keep the Cell2Jack settings and any family pairings. If enrolling fails, register the old household's pushes again.

### Family phone

- **I'm joining my family.** Open a `/join` link, scan the bedside's QR code with the phone's camera (which opens the App Link), or paste the link.
- **Joining.** `claimInvite`, then add the family. A phone can be in up to four families. Only a previous pairing with the same household is left with `leaveHousehold` (ignore 401 or 404).
  - Route call pushes and message notifications by `recipientID`, the phone's member ID in that family ([ios/FAMILY-SETUP.md](../ios/FAMILY-SETUP.md#more-than-one-family)).
- **Porch number card.** Shows `porchNumber`, with **Add to Contacts** and **Share this number** (an SMS with a vCard).

Exit criteria:
- A fresh Android tablet goes from a `/setup` link to a working household with its own number, the Cell2Jack key test passing, and both an Android phone and an iPhone joined by QR code.
- An Android phone joins an iPad bedside the same way.

## Phase 3: calling

Built in five pull requests, each a working household:

1. **In-app calls.** The bedside and family phones call each other while Porch is open, with the shared call engine, the call screen, ringing with Answer and Decline, and the bedside's people screen and keypad keys. A call ends if Porch leaves the screen.
2. **Announcements, drop-ins and the receiver.** "Calling David.", receiving a drop-in, the Cell2Jack routing table, and silence hang-up. Android's text-to-speech writes each sentence to a file that Porch plays: on Android 16 the speech engine plays from its own app, in the background, which the system flags to be muted.
3. **Phone fallback and calls to the Porch number.** When Porch isn't answered within the fallback wait, the bedside calls the person's phone (`fallback`, then `/api/calls/phone`), and a key with only a phone number calls it straight away. Tried on the KB10 with a real phone through the local server's `--phone` mode ([README](README.md#phone-fallback)). Calls to the household's Porch number are answered and hung up as on iOS, but need a pass on the production server to try.
4. **The always-on bedside.** Home app, screen on, showing over the lock screen, and the dynamic clock.
5. **Ringing when Porch isn't open.** A call push (FCM) rings through a call notification, full screen on a locked phone, while a phone-call foreground service checks in on the call every second; Porch's own incoming screen takes over once Porch is on screen, and hands it back if Porch leaves. The power button silences it, as on a phone. A call in progress on a family phone goes on with the phone locked, its camera off until Porch is back ([decision 8](#decisions)). Core-Telecom isn't used yet: the notification and the service ring a locked phone without it. Add it if testing shows a need, such as Bluetooth answer buttons or another app's call arriving during a Porch call.

Calls can be tried locally with LiveKit's server in dev mode; see [android/README.md](README.md#calls).


### Shared call engine

- **LiveKit.** Connect with default options; iOS sets no custom room or connect options. Ignore events from a room that has been replaced. The call ends when no remote participants remain.
- **Ringback and tones.** Play the `CallTone` ringback locally, looping at volume 0.7. Never publish it to the room.
- **Call screen.**
  - Two video tiles: side by side in landscape, stacked in portrait. Someone with the camera off shows as a photo or name.
  - Self view at 30% of the short side, at most 200 dp, 4:3. The photo and name move to stay clear of it.
  - Mute, camera and end, with one control change at a time. A chime plays when the camera turns on.
- **Screen.** Keep it on during any call. Phones turn the screen off with the proximity sensor on voice calls.
- **Silence hang-up.** Off by default; 1–30 minutes, default 2. It uses LiveKit active-speaker events, and a phone participant on a Porch call counts as activity. Reset it on reconnect.
- **Audio.** Use LiveKit's Android audio handling: speaker by default, plus Bluetooth headsets. During a Telecom call, route through the call's endpoint API. iOS shows no route picker; keep it that way unless testing shows a need.

### Bedside tablet

- **Always on.**
  - Porch is the home app (an activity alias with the HOME category, enabled only in bedside mode), so it starts at boot. Android 15 blocks starting phone-call, camera or microphone foreground services from a boot broadcast, and a home app avoids that problem.
  - The screen stays on and the system bars are hidden.
  - Incoming calls turn the screen on and show over the lock screen (`setShowWhenLocked`, `setTurnScreenOn`).
  - The bedside registers for call pushes too, in case Porch isn't in front.
- **Default clock.** Weekday, time and date in the bedside locale. Sizes come from screen ratios, and AM/PM is shown at 25%. It refreshes on the minute, and on time or locale changes.
- **Dynamic clock.** Drawn on a Canvas: sky ramps, a sun or moon arc, 24 stars at night, hills and a seasonal tree. It crossfades over 1.5 s unless animations are off. Day runs 6–18 by default, with a hemisphere setting.
- **Contact grid.**
  - Two columns at width ≥ 600 dp, with photo cards and "Press X".
  - The button color is configurable, with black or white text chosen by WCAG contrast.
  - Pressing an empty key shows "No one is assigned to X" for 5 s.
- **Keypad keys.**
  - Digits come from `KEYCODE_NUMPAD_0`–`9` and `KEYCODE_0`–`9`.
  - `*` comes from `KEYCODE_STAR`, `KEYCODE_NUMPAD_MULTIPLY` or a typed `*`. `#` comes from `KEYCODE_POUND` or a typed `#`.
  - Ignore digits with Ctrl, Alt or Meta, and with Shift.
  - Ignore auto-repeat, so each press triggers one action.
- **Cell2Jack keys and receiver.**
  - Digits go only to screens that accept keys, through the same handling as keyboard keys.
  - Putting the receiver back follows [the iOS routing table](../ios/CELL2JACK-CALLS.md):
    - It ends a connected, fallback or system-owned call, cancels one that's still opening, skips the message screen after "didn't answer", and finishes a recording.
    - It's ignored while ringing, during a drop-in countdown, during message playback and on the clock.
    - It retries every 0.4 s, up to 6 times, while a screen is changing.
  - The **Hang up when the receiver is put back** setting is on by default.
- **Outgoing calls.**
  1. The bedside says "Calling David." (chime, then the cached natural clip or `TextToSpeech`, with a 15 s watchdog) while `startCall` is in flight.
  2. Ringback waits for the sentence to finish, and so does joining the call audio. On iOS, joining cut the speech off; check whether `MODE_IN_COMMUNICATION` does the same on Android, and keep the same order either way.
  3. The hang-up key stops the sentence and cancels a call that's still starting.
  - `waitSeconds` is 45 for a contact without a phone number, otherwise the fallback wait.
  - A 2 s cooldown applies between launches.
- **Phone fallback,** in the iOS order (`switchToPhone` in [NativeCallViewController.swift](../ios/Porch/NativeCallViewController.swift)):
  1. Abort if anyone has joined the Porch call.
  2. `fallback {callID}`. A 409 `answered` means Porch was answered.
  3. Record whether the microphone is muted.
  4. Switch to a new room and disconnect the old one. This releases the camera and keeps late Porch joins out of the phone call.
  5. Get the contact authorization.
  6. `prepare {localRingback: true}`.
  7. Store the control token before connecting, then connect.
  8. `start`, then wait up to 60 s for an answer.
  9. Watch `sip.callStatus`: `active` or `automation` means connected, `hangup` ends the call.
  10. On end, call `end` with one retry, even after a long call, since the server accepts an expired control token for `end`. If it can't be confirmed, show "Retry ending phone call".
  - A phone leg can end on its own after 24 hours.
- **Incoming on the bedside.**
  - Shown in the app when the bedside is ready, with Answer, Decline and a repeating 3 s ring.
  - With the call-control key, tap to answer and hold 1 s to decline.
  - Caregiver screens never auto-answer.
  - Inbound phone calls (`source: "phone"`) use the same `acceptCall` and `joinCall`.
- **Receiving a drop-in.**
  1. Play the 0.6 s chime.
  2. Play the cached natural clip, never waiting for a download, or use `TextToSpeech`.
  3. A 15 s watchdog stops the announcement from hanging.
  4. Count down 5 s, then accept. "Don't connect" cancels.
  - Any failure needs a manual Answer.
  - Decline if microphone or camera permission is missing.
  - The server enforces the 5 s gap after `announcedAt`.

### Family phone

- **Home screen.**
  - One card per family. The bedside person's card holds:
    - availability, and the attendance line from `bedsideAttendedAt` and `serverTime`, such as "Someone is at the iPad" or "at the tablet";
    - Audio call and Video call;
    - Drop in with audio and Drop in with video;
    - the Messages thread.
  - Drop-in buttons are enabled only when the bedside is online and not busy, drop-in is on, and the person has permission.
  - Banners: new messages; N texts or voicemails need your review (`heldMessages` + `heldTexts`); drop-in paused.
- **Outgoing call.**
  1. `startCall`.
  2. `joinCall`.
  3. Ask for microphone and, for video, camera permission.
  4. Connect.
  5. Turn the microphone on, and the camera too if "Start with my camera on" is set.

  The wait timer starts after connecting. An `offline` error code offers a voicemail; any other error never falls back. On `accepted`, start a 30 s "couldn't connect" timer.
- **Incoming calls.**
  - **Every call push posts a call notification before any network request,** even a stale or duplicate push, which is then ended at once. This mirrors iOS's PushKit rule, and it also stops FCM from demoting high-priority messages that show nothing.
  - **Validation.** The `recipientID` must be one of this phone's member IDs, the role must be the current mode, and `expiresAt` must be in the future. Dedupe by call ID against the last 32.
  - **While ringing.** Poll `{available: false, receivedCallID}` every 1 s.
    - End the call if it disappears or ends, or after 25 s without a successful poll.
    - At expiry, end it as unanswered without calling `endCall`.
  - **Answer.** The microphone must already be granted. Then `acceptCall`, `joinCall`, connect, and mark the call active. Poll every 5 s while answered.
  - **Camera.** It turns on only once the call screen is visible and the phone is unlocked, and only if "Start with my camera on" is set. It turns off when Porch leaves the foreground, and back on when you return unless you turned it off during the call.
  - **Foreground service.** Outgoing calls run in the same service ([decision 8](#decisions)).
- **Drop-in from a phone.** `startCall {kind: "dropIn"}` with the fixed 45 s wait. The bedside must be online.
- **Permissions:**
  - `RECORD_AUDIO` and `CAMERA`;
  - `POST_NOTIFICATIONS` (Android 13+);
  - `MANAGE_OWN_CALLS`;
  - the phone-call, microphone and camera foreground-service permissions;
  - `USE_FULL_SCREEN_INTENT` (on Android 14+, check `canUseFullScreenIntent()` and link to the setting if it's off);
  - `BLUETOOTH_CONNECT`.

**Milestone A:** an Android tablet and an Android phone call each other, and the iOS devices, both ways. That includes locked-phone ringing, drop-in, phone fallback and the Cell2Jack. The beta goes to Play's internal testing track.

## Phase 4: caregiver mode

Built in five pull requests:

1. **The tablet's caregiver mode.** The gear and PIN on the clock, the two panes, the household's name and number, and Calls, Display & voice, Privacy, Caregivers & PIN, and This tablet.
2. **People.** The keypad, the person page and the key editor, with invitations, and family members' photos downloaded to the tablet. The bedside's people screen lists only the people on keys, as iOS's does, in their button colors.
3. **Drop-in, call history and blocked numbers.** The Drop-in page with its switch, who can and can't drop in, and adding a phone number; Call history and Blocked numbers open from Calls.
4. **Caregiver mode on a family phone.** Caregiver mode on a caregiver's family card, the PIN, and the pages a phone can change, with what only the bedside can change listed apart. Pages read the household again as they open, since a phone's check-ins leave out caregiver details. Calls still ring while it's open, which closes it.
5. **The Porch keyboard, and About.** Every form's fields can use Porch keyboard, chosen under the form; About lists the open-source licenses, from caregiver mode and from a family phone's families.

The pages follow [CaregiverSettings.swift](../ios/Porch/CaregiverSettings.swift):

- **On the tablet:** People, Calls, Drop-in, Messages, Display & voice, Privacy, Caregivers & PIN, and This tablet. It uses two panes, with the list beside the page.
- **On a phone:** the same, minus Display & voice and This tablet, with rows marked "On the bedside" for settings only the tablet can change. The phone keeps the PIN in memory for 10 idle minutes and clears it when Porch goes to the background. The photo picker, share sheet and privacy policy are other apps' screens on Android, so opening them from caregiver mode doesn't count as leaving.
- **Entry.** A gear tap, or a 0.5 s hold, on the tablet. Then `caregiverStatus` and `verifyPIN`, with a PIN matching `^[0-9]{6}$`. The privacy policy (helloporch.store/privacy, in Custom Tabs) is reachable without the PIN.
- **Header.** The household name, which can be renamed, and the Porch number. A pending number opens the number screen.

Page contents:

- **People.** The keypad grid, plus Family on Porch with pending invitations and Cancel.
- **Person page** ([CaregiverPerson.swift](../ios/Porch/CaregiverPerson.swift)):
  - Name and photo override (`setMemberOverride`).
  - Key menu, to move a person or take them off the keypad.
  - Button color.
  - "Reach X": Porch app status, Invite, Choose from Family on Porch, Calls start as, and phone numbers. Up to 5 numbers, with Make primary. A changed primary moves its drop-in approval (`setPhoneDropIn {replacing}`).
  - Drop-in, both in their Porch app (audio and video) and by phone.
  - Caregiver switch.
  - Remove, as Take off keypad or Remove from Porch.
- **Key editor.** Five actions per key. Saving a number calls `contacts/authorize`. Cache the approval until 5 minutes before its 30-day expiry. Show refusals as they come, such as "Porch can't call phone numbers in X yet."
- **Contact import.** Android's picker returns the one phone number you tap, with no permission, and that's what the key editor uses for now. iOS also imports the contact's other numbers, which on Android needs `READ_CONTACTS`. See [open questions](#open-questions).
- **Calls.**
  - Ring before voicemail: 15–120 s in steps of 5, default 45 (`setRingSeconds`).
  - Block unknown callers.
  - Fallback wait: 5–120 s, default 20.
  - Leave a message when unanswered.
  - Silence hang-up.
- **Call history.** `callHistory` covers 90 days, at most 100 calls, grouped by day. Each entry shows direction, how the call went (`via`), outcome, including "ringing" and "ongoing", and whether it reached their phone.
- **Drop-in.** The master switch, plus approved people and phone numbers.
- **Messages.** Messages on or off, autoplay hours, the waiting queue, and review of held voicemails and texts (`caregiverMessageMedia`, `releaseMessage`, `removeMessage`, `caregiverTexts`, `releaseText`, `removeText`).
- **Display & voice.**
  - Clock style and bedside language (`setBedsideLanguage`).
  - Natural voices from the snapshot's `speech` field (`setSpeechVoice`), and built-in `TextToSpeech` voices for en-US, zh-TW, zh-CN, zh-HK and es-ES. Check which speech engines on the chosen tablet offer Cantonese and Taiwan Mandarin.
  - Test ringing, and test announcement.
- **Privacy.** **Show family when someone is at the tablet** (`setShareAttendance`), and on the tablet, **Check with the camera**.
- **Caregivers & PIN.** Change the PIN.
- **This tablet.** **Use the Cell2Jack phone keypad** and **Hang up when the receiver is put back**, plus Connect the phone or USB keypad again, and Use this tablet as a family device. Also **Make Porch the home screen** or **Stop using Porch as the home screen**, and **Tablet settings**, which opens Android's Settings: with Porch as the home screen and the system bars hidden, a caregiver otherwise has to know to swipe down twice from the top.
- **About.** Porch's version and the open-source licenses, gathered from the dependencies at build time by AboutLibraries (iOS lists its own in Settings, from Settings.bundle). A tap shows a license in a dialog, never a browser, which on a family phone would end caregiver mode. A family phone also has About Porch under its families, since not everyone with Porch is a caregiver.
- **Typing with a keypad attached.** Android hides the on-screen keyboard when a hardware keyboard is attached unless the user changes that setting, which is the same problem iPadOS has.
  - Port the Porch keyboard: number pad, phone pad with `+`, and text with a symbols layer, plus Paste, Next and Done. Built in `PorchKeyboard.kt`, with the layouts and editing in `:core` (`PorchKeyboardKeys.kt`).
  - Hide the system keyboard for fields that use it. While Porch keyboard is in use, `InterceptPlatformTextInput` keeps the system keyboard from opening.
  - As on iOS, the system keyboard is the default, and two buttons under a form with fields switch between it and Porch keyboard. With a keypad attached, the first is Keyboard help, which also names Android's setting for showing the on-screen keyboard with a physical one. Unlike iOS, where each form starts over with the system keyboard, the choice lasts while Porch runs, since a keypad stays attached from one form to the next.
  - The button color dialog's hex field still uses the system keyboard: its color swatches cover the usual choices.

## Phase 5: messages, voicemail and texts

### Media formats both platforms play

- **Audio.** `.m4a`, AAC-LC, 44.1 kHz mono, 64 kbps, sent as `audio/mp4`.
- **Video.** MP4 with H.264 and AAC at about 640×480 (CameraX SD quality), sent as `video/mp4`.
- **Avoid the system camera app;** it can return HEVC or 3GP. Check the output codecs on each test device.
- **Limits.** Up to 120 s; audio up to 10 MB and video up to 100 MB ([messages.ts:12](../lib/family/messages.ts)). Check them before `createMessage`.
- **Upload.** `createMessage`, then PUT with exactly the returned headers (600 s timeout), then `completeMessage`. If the upload already finished, a retry only calls `completeMessage`.
- **Playback check.** Android plays iOS `.mov` and `.m4a` and the server's `.mp3`. iOS plays Android `.mp4` and `.m4a`.

### Bedside tablet

- **Voicemail recorder after an unanswered call.**
  - It waits for any "Calling X." sentence to finish.
  - Then a chime, the prompt and a beep, and it records for up to 120 s.
  - Keep a recording only if it's at least 2 s long with sound above −40 dB.
  - An interruption, or putting the receiver back, sends what was recorded.
  - An outbox retries after min(900, 15·2^(n−1)) s and gives up after 2 days.
- **Waiting messages.**
  - Sync on each poll, download, then `messageDelivered`.
  - The player announces "Message from X. Sent Y.", then plays.
  - `messagePlayed` is sent at the end.
  - The stop key stops playback.
- **Texts** ([BedsideMessages.swift](../ios/Porch/BedsideMessages.swift)).
  - Getting them:
    - Each poll lists `texts[]`. For each one, call `textMessage {textID}`, with a 40 s timeout and a retry after 60 s.
    - A 503 during the first 10 minutes means translation isn't ready yet; retry.
  - Order: texts show after waiting messages, and count toward "Play N messages".
  - Display:
    - "Text from X", the sent time, and a large body, from 52 down to 30 by length.
    - A translation shows the original beneath it, with "Translated from Y".
  - Reading:
    1. Chime, then the announcement.
    2. The body, read with the natural clip (`speech {textID}`, waiting up to 8 s, at most 600 characters), otherwise with `TextToSpeech`. Words in another language use that language's voice, found with ML Kit language identification.
    3. Then the counts of pictures and attachments are read aloud.
  - Each text stays on screen for 8 s, then `textRead`.
  - Held texts from unknown numbers wait for a caregiver.
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
  - Any touch, key or phone-keypad press counts. Send the whole seconds since then as `attendedSeconds` with each poll, only while `shareAttendance` is true. While it's false, forget the last time.
  - With **Check with the camera** on, the same face detection looks for up to 5 s every 30 s on the idle clock. A face held for 1 s counts. A face seen during presence autoplay counts too, but only with that setting on.
  - Nothing is recorded or sent. Stop the camera before any call screen opens, and hold a receiver hang-up that lands while it's stopping for the next screen.
- **Held phone voicemail.** Auto-release it (`releaseKnownCaller`) for carrier-verified callers who are saved on the keypad.

### Family phone

- **One "Messages with Mom" thread per family** ([FamilyMessages.swift](../ios/Porch/FamilyMessages.swift)).
  - Oldest first, with day headings.
  - Received messages are tagged New, Played, or Not played yet.
  - Sent messages show uploading, queued, played, expired, removed, unsent or failed, with Unsend.
  - Video posters are a frame taken at 0.5 s.
- **Composer.** Beep, a 0.7 s pause, then record for up to 120 s. Discard anything under 1 s.
- **Alerts.**
  - Call `registerAlerts` with the FCM token in each family.
  - Notifications use the `messages` channel, tagged per family, and tapping one opens that family's thread.
  - The badge sums across families.
- **Profile.** A name, and a photo from the camera or library: JPEG, quality 0.82, longest side ≤ 768 px, ≤ 1,000,000 bytes, with a SHA-256 ID. Upload with `profilePhotoUpload`, then PUT, then `setProfile`.

**Milestone B:** both Android devices match their iOS counterparts in everything iOS ships today, except three-way calls.

## Phase 6: three-way calls, dedicated tablet and household lifecycle

- **Three-way calls** ([CallGuests.swift](../ios/Porch/CallGuests.swift)):
  - On a phone, show Add when the call is accepted, the bedside is in the room, and this device isn't itself a guest.
  - **Adding family:** `addPorchGuest` rings the other person. The guest's phone sees a synthesized call with `guest: true` and uses the same `acceptCall`, `joinCall` and `endCall` with that ID.
  - **Adding a phone number:** caregivers only. `addPhoneGuest` takes US and Canadian numbers, with a 25 s request timeout and a 75 s window to join. `removePhoneGuest` runs on hang-up.
  - **DTMF:** sent over LiveKit data. iOS uses `publishDtmf`, codes 0–9 with `*` = 10 and `#` = 11; check what the Android SDK offers for this.
  - **On the tablet:** two people share the screen.
- **Dedicated tablet.**
  - Optional lock task mode, with Porch as device owner. It's set once with `adb shell dpm set-device-owner` on a freshly reset tablet, and hides the status bar and app switching.
  - On the tablet, set no screen lock and turn battery optimization off for Porch, once each in Settings.
  - Keep the same local call and keypad logs as iOS. They're read over USB with `adb` on a visit, as `devicectl` reads Mom's iPad.
- **Household lifecycle.** The [onboarding plan](../ONBOARDING-PLAN.md) has items that aren't built on iOS or the server yet:
  - the keypad and settings backup;
  - **Delete this Porch**;
  - `/bedside` replacement links;
  - forgotten-PIN reset;
  - the setup checklist;
  - the daily check.

  Build each on Android in the same PR as iOS, or right after. The keypad backup must use one versioned format for both apps, with photos referenced by SHA-256, so a household can move between an iPad and an Android tablet. Android already saves contacts in the iOS shape, with an empty `address`. An iPad key whose contact calls only through an iOS-only method (a FaceTime-style address or a Shortcut) has no Porch call for Android, so importing one should leave that key empty and keep the rest of the keypad, not reject the whole backup.

**Milestone C:** an all-Android household, and every mixed household, matches an all-iOS one.

## Cell2Jack

Used by the bedside tablet from phase 2.

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
- **Lifecycle.**
  - Off by default for existing installs. Setup turns it on once the phone answers.
  - It runs only in bedside mode with Porch in the foreground. On pause, send `/q` and close the connection.
  - Reconnect after 1, 2, 4, 8, then 15 s. The delay resets after 30 s of a healthy connection.
  - **After a restart.** Android forgets the USB permission when the tablet restarts, and it looks for the app to open for a plugged-in Cell2Jack before the tablet is unlocked. So `USB_DEVICE_ATTACHED` goes to `Cell2JackAttachedActivity`, which is direct-boot-aware and runs in its own `:usb` process where `PorchApplication` starts nothing; opening it is what gives Porch the permission. Once the tablet is unlocked, it opens `MainActivity`. If Porch still can't use the Cell2Jack, the bedside asks once each time it's plugged in, when it comes to the front with the phone keypad on.
- **Status and diagnostics.** "Phone keypad ready" shows for 3 s. Diagnostics keep the last 200 actions and a 64 KiB raw tail.

## Phase 7: hardening and release

- **Device matrix.**
  - The supported bedside tablet model or models.
  - A Pixel phone and a Samsung phone.
  - Each Android family member's own phone.
  - Android 10, 14, 15 and 16.
  - Mixed households in every combination from the [device combinations](#device-combinations) table.
- **Acceptance checks.** Write `android/ACCEPTANCE.md` from the iOS checks in [FAMILY-SETUP.md](../ios/FAMILY-SETUP.md#verify), [INCOMING-CALLS.md](../ios/INCOMING-CALLS.md), and the device checks in [ONBOARDING-PLAN.md](../ONBOARDING-PLAN.md#device-checks-before-inviting-other-families). Add the spike A and spike B states and the [race tests](#race-tests).
- **Play Console.**
  - The Data safety form: camera, microphone, photos, phone numbers from picked contacts, device identifiers, push tokens, audio and video messages, texts, and speech.
  - Declarations for each foreground-service type, with demo videos.
  - The full-screen intent declaration, as a calling app.
  - Target API 36.
  - 16 KB page-size support for native libraries; check LiveKit's WebRTC build.
  - Play App Signing. Its key fingerprint goes into `assetlinks.json`.
- **Tracks.**
  - Internal testing has no review and allows up to 100 testers, which covers our own family.
  - Production on a personal developer account created after November 13, 2023 first needs a closed test with 12 testers for 14 days. An organization account doesn't.
- **Review access.** Reuse `createBedsideInvite {purpose: "appReview"}`. Adapt `scripts/prepare-app-review.mjs` to write Play's "App access" instructions.
- **Release workflow.** `.github/workflows/android-release.yml`: manual, verify-only by default, and it deploys the calling server first, like `testflight.yml`. The upload key goes in GitHub secrets.
- **Website.**
  - The pilot page lists the supported tablet, with its stand and hub, beside the iPad. It currently says there's no Android app (`app/(site)/pilot/PilotGuide.tsx:230`).
  - The privacy policy ([app/(site)/privacy/page.tsx](<../app/(site)/privacy/page.tsx>)): add Google/FCM as a processor next to Apple, say "tablet" where it says iPad, and add Android permission wording.
  - The invite landing pages get the Android branch from phase 0.
- **Docs.** `android/README.md` covers build, setting up a bedside tablet (home app, power, Cell2Jack), and the optional lock task mode. Link it from the main README and [FAMILY-SETUP.md](../ios/FAMILY-SETUP.md).

## Estimates

| Phase | By hand | At this repo's pace (calendar days) |
|---|---|---|
| 0. Server changes and two spikes | 2–2.5 weeks | 3–4 |
| 1. Foundations | 2 weeks | 2–3 |
| 2. Setup and joining, with the Cell2Jack transport | 2–2.5 weeks | 3–4 |
| 3. Calling on both devices | 4–5 weeks | 6–9 |
| 4. Caregiver mode | 2.5–3 weeks | 3–5 |
| 5. Messages, voicemail and texts | 2.5–3 weeks | 3–5 |
| 6. Three-way calls, dedicated tablet | 1.5–2 weeks | 2–3 |
| 7. Hardening and release | 2–3 weeks | 5–8 |
| **Total** | **about 18–23 weeks** | **about 4–6 weeks** |

Notes:

- The by-hand column assumes one developer who knows Android calling.
- The second column follows this repo's history: the first iOS app and server took about ten days.
- Device testing runs alongside every phase from phase 2 on. Phase 7 is mostly calendar time on real devices.
- Not included: the household-lifecycle items that aren't built on iOS yet. Each adds a little to its iOS PR. Play's 14-day closed test, if it applies, also comes on top.

## Race tests

Each of these is handled explicitly in the iOS code. Each needs an Android test, automated where possible, otherwise on a device.

**Phone fallback**
1. The fallback timer fires just as the callee answers. The remote-participant check and the server's `answered` conflict pick one winner.
2. A lost `startCall` response must never trigger phone fallback. Only `offline` counts.
3. The call is answered while fallback starts but media isn't ready: show "answered, but this device couldn't connect".
4. Mute carries across the room switch, and the camera is released before dialing.
5. `start` races `end`: the server checks again after dialing, deletes the room on error and returns 409 `cancelled`.
6. A phone call whose end can't be confirmed keeps its control token and offers "Retry ending phone call".

**Calls and polling**

7. Events from a replaced LiveKit room are ignored.
8. An older poll that arrives late can't overwrite newer availability (`launch` and `sequence`).
9. "Calling X." finishes before the call audio starts, and the hang-up key stops it.

**Incoming calls**

10. Every call push shows a call, even a malformed, stale or duplicate one, which is then ended. The last 32 call IDs prevent ringing twice.
11. The camera never starts behind the lock screen on a family phone. A quick background-and-return leaves it in the right state.

**Bedside**

12. The presence camera stops before any call, drop-in or voicemail screen. An incoming call that arrives during that wait is checked again afterwards.
13. A receiver hang-up that lands while a screen is changing retries, and one that lands while the camera stops is held for the next screen.
14. A drop-in never connects when speech fails or hangs. The server also requires 5 s after `announcedAt`.

**Setup and links**

15. A link opened during a call or on a caregiver screen asks to finish first.
16. Replacing the bedside registers the old household's pushes again if enrolling fails.

**Three-way calls**

17. A guest invitation stops ringing when the main call ends.
18. A phone guest that connects after its dial request timed out is removed, and dialing is blocked for 6 s after a server error.
19. Leaving a three-way call uses actual LiveKit occupancy, and the bedside is never left alone with only a phone.

## Risks

| Risk | Likelihood | What we do |
|---|---|---|
| Phones from some manufacturers don't ring when Porch is in the background | High | Spike A on real phones, OEM settings guidance, regular-phone fallback for anyone left |
| No affordable tablet charges while the Cell2Jack is attached | Medium | Spike B tests charging through a hub before we pick a model |
| Echo or quiet audio on the bedside tablet | Medium | Spike B, and support only models that pass |
| Tablet models change quickly, or stop getting updates | Medium | Pick models with long update promises; re-run spike B on each new Android version |
| FCM demotes high-priority messages that show nothing | Medium | Every call push shows a call notification |
| A device records in a format iOS can't play | Medium | Fixed CameraX/MediaRecorder settings, a codec check per device, a cross-platform playback test |
| Play rejects the foreground-service or full-screen-intent declarations | Medium | Prepare the declarations and demo videos early; the app's core function is calling |
| Wording says "iPad" in a household with an Android tablet, or the reverse | Medium | The `platform` field, and device-neutral server text |
| The on-screen keyboard is hidden while the keypad is attached | Medium | Porch keyboard, as on iPadOS |
| No Cantonese or Taiwan Mandarin built-in voice on a device | Low | Natural voices come from the server; with no voice, a drop-in waits for a manual Answer |
| The two apps drift apart | Medium | Shared JSON fixtures in CI, and feature PRs that cover both apps |

## Open questions

1. **Family phones.** Which Android phones does the family actually use? This sets the device matrix.
2. **Bedside tablet.** Which model, or two, should we support? Should new families be offered an Android bedside before Apple approves the Cell2Jack driver?
3. **Play account.** Personal or organization? An organization account under the LLC avoids the 12-tester rule, but needs a D-U-N-S number.
4. **Outgoing calls.** Should calls you place keep going when the phone locks ([decision 8](#decisions))? This changes behavior from iOS. If yes, should iOS follow?
5. **Contacts.** Ask for `READ_CONTACTS` to import a contact's other numbers, or import only the number picked?
6. **Bedside lock-down.** Is the home-app mode enough, or should a supported tablet ship as device owner with lock task mode?
7. **Device platform.** Should the server record each device's platform, for wording and the admin page? It's recommended in phase 0.
8. **Phone adapter on Android.** Support it, or only the direct Cell2Jack connection, which needs no extra hardware?
9. **Firebase setup.** These are Ethan's steps: create the project and service account, and add their keys to Vercel.

## Keeping the two apps in step

- The server stays the single source of truth for behavior. Android adds no endpoints beyond FCM registration, the platform field and `assetlinks.json`.
- JSON fixtures shared between PorchCore and `:core` catch contract drift in CI.
- A feature PR covers both apps, or notes the Android follow-up, and updates the shared docs. That includes the remaining [onboarding plan](../ONBOARDING-PLAN.md) items.
