# Porch for iPhone and iPad

Porch is one app with a quiet bedside clock and a family calling mode. Bedside mode supports ten configurable keypad slots, in-app audio/video calls and regular-phone fallback. Both modes support ordinary CallKit incoming calls while locked/backgrounded, including telephone calls to the bedside iPad, with APNs VoIP delivery configured as described in [incoming-call setup](INCOMING-CALLS.md). Family devices can also initiate approved foreground audio/video drop-in.

Start with the [family setup guide](FAMILY-SETUP.md). Family recipients join using a private invitation; no server address, shared calling code or room name is entered in the app.

## Caregiver setup

Tap the gear, or hold it for half a second. The first caregiver entry asks you to choose and confirm your own six-digit PIN. An already-paired iPad needs no preset PIN; an older installation can use its saved connection during migration. A completely new bedside device uses a private, one-use activation link from the server operator before enrollment. The PIN is specific to that bedside household and verified by the server; five wrong guesses lock that household for 15 minutes.

In **Family & drop-in**, edit the bedside display name (default **Your loved one**), invite family devices and approve audio/video drop-in separately. The PIN can be changed there. The native keyboard is the default, but iPadOS can hide it when a physical keypad is connected. Disconnect the keypad during setup to use native input, or choose **Porch keyboard** to type with the keypad connected. **Keyboard help** explains this limitation without relying on a system bar that may be missing. See [typing in caregiver settings](FAMILY-SETUP.md#typing-in-caregiver-settings).

Choose a keypad slot to edit a person's name, import a phone number from Contacts, choose voice/video and link their paired Porch app. Under **Photo & button color**, add or change a photo from the photo library and choose any button color, or restore the default color. Text automatically switches between black and white for contrast. Photos appear as large images on contact buttons, incoming calls and voice/waiting screens, with a smaller photo beside the name during video. Photos are stored as local image files; keypad settings contain only their identifiers so polling and keypad actions never decode image bytes. Earlier inline photos migrate automatically. Photos and colors stay on this device and survive pairing updates. Optionally enable phone fallback. Everything calls through Porch; no calling-method or manual-room configuration is shown. Old FaceTime/Shortcut contact records remain readable so names/key assignments survive, but must be edited into a Porch contact before calling.

The saved slot name is also used for that person's incoming calls, spoken drop-in announcements and active call screen on the bedside device. Existing renames take effect without inviting or pairing again. Porch matches the linked device/invitation identity; callers without a matching slot use their caregiver-assigned invitation name.

Porch attempts the paired app first. A person without a linked app gets a confirmed unavailable result before phone fallback. A family app that is open or registered for VoIP delivery can ring for the wait set in **Call preferences** (20 seconds by default). Answering Porch atomically cancels phone fallback. Phone numbers use E.164; saving approves the destination without placing a telephone call. Failed approval preserves the original contact.

## Dedicated bedside use

Keep Porch open and the iPad unlocked. The display stays awake in bedside mode. Any digit 0–9 can be configured to call a person. Initially 1–8 are person slots, 9 toggles video, and 0 answers/declines/hangs up. The large **Call someone** button also starts a call. Tap the call-control key to answer or hang up, hold one second to decline, and tap it during a drop-in countdown to stop the connection. Unassigned person keys show a brief hint. An audio call keeps the camera off. Drop-in announces its caller, waits five seconds and offers **Don't connect** before answering. Caregiver screens do not auto-answer.

Keep the bedside iPad open and unlocked. Ordinary incoming family calls use CallKit, and answered incoming audio can continue while the iPhone is locked or backgrounded. On a family phone, an answered video call turns the camera on once Porch is open, never behind the lock screen, unless **Call settings → Start with my camera on** is off; on the bedside, video starts after tapping **Camera on**. Backgrounding turns the camera off, and returning turns it back on unless it was turned off during the call. Outgoing calls and bedside/drop-in sessions still require Porch to stay open. Configure APNs and updated provisioning before relying on background ringing; see [setup and acceptance checks](INCOMING-CALLS.md). Ordinary USB/Bluetooth keyboard input cannot wake Porch behind another app or the lock screen. Use iPad brightness and Guided Access as appropriate, keeping Touch and Software Keyboards enabled for setup.

## Build and verify

Open `ios/Porch.xcodeproj` with Xcode 26 or newer, choose the Porch scheme and an iPhone/iPad running iOS/iPadOS 15+. The LiveKit Swift SDK is pinned to 2.17.0 and PhoneNumberKit to 5.0.9.

```sh
swift test --package-path ios/PorchCore
xcodebuild -project ios/Porch.xcodeproj -scheme Porch \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- build
```

Simulator Keychain access needs Xcode's simulated signing entitlements. Release/device archives use the configured distribution profile. Automated tests cover room/role authorization, enrollment and PIN isolation, name updates, contact normalization, keypad handling, caregiver focus/keyboard, first-entry PIN fields, first-tap gear opening and small-phone layouts. CI runs UIKit checks on both device families. See the [physical-device acceptance checks](FAMILY-SETUP.md#verify) before wider use.

For visual Debug previews, use `--preview-phone-setup`, `--preview-caregiver`, `--preview-pin-setup`, or `--preview-family-settings`. Combine the person editor preview with `--preview-system-keyboard` to focus a native input field, `--preview-hardware-keyboard` to show the keypad guidance, or `--preview-touch-keyboard` to inspect the optional Porch keyboard. Add `--preview-keyboard-help` with the hardware-keyboard flag to inspect the help alert. The hardware flag changes guidance only; it does not emulate iPadOS hardware-keyboard suppression. Use `--preview-language zh-Hans`, `--preview-language yue-Hant`, or `--preview-language es` for Simplified Chinese, Cantonese, or Spanish bedside previews (`--preview-chinese` still selects Traditional Chinese) and `--preview-incoming-video` for a static incoming-call fixture that never auto-answers. Combine `--preview-six --preview-people --preview-photos` to inspect large photo cards with sample colors. Combine `--preview-contact --preview-photos` with `--preview-incoming-call` or `--preview-outgoing-call` for static call screens that never connect a call. Previews don't place calls or save contacts.

## TestFlight

App: **Porch Family Calling**, App Store Connect ID **6822602923**. Bundle ID: **com.ethanteng.helloporch**. Apple team: **7U9T57JPF7**.

**iPhone and iPad build** runs the core and caregiver keyboard/focus tests and compiles the simulator and iPad release app without signing credentials. **Upload Porch to TestFlight** is manually dispatched, and tests, archives, signs, validates, and uploads the app. It defaults to **verification only**: it signs and verifies the archive/export and runs App Store validation without uploading or deploying the calling server. The default **family** variant uses `PorchFamily`, excluding the Cell2Jack driver while retaining all other features. The **cell2jack** variant uses `Porch` and requires Apple-approved driver distribution permissions. See [build variants](BUILD-VARIANTS.md) for development and family testing. Clear **verify_only** explicitly when uploading is intended. It does not publish to the App Store or invite testers.

Configure these encrypted GitHub secrets in the `testflight` environment or repository:

| Secret | Value |
| --- | --- |
| `ASC_KEY_ID` | App Store Connect team API key ID |
| `ASC_ISSUER_ID` | API issuer UUID |
| `ASC_PRIVATE_KEY` | Downloaded `.p8` file contents; Developer role is sufficient for binary upload |
| `IOS_DISTRIBUTION_P12` | Base64-encoded Apple Distribution certificate and private key, exported as `.p12` |
| `IOS_DISTRIBUTION_PASSWORD` | Password protecting the `.p12` |
| `IOS_APPSTORE_PROFILE` | Base64-encoded App Store profile with production push; DriverKit Communicates with Drivers is required only for the Cell2Jack variant |
| `IOS_DRIVER_APPSTORE_PROFILE` | Required only for `variant=cell2jack`: base64-encoded iPadOS App Store profile for `com.ethanteng.helloporch.usbdriver`, with Apple-approved DriverKit and USB transport grants for Cell2Jack, authorizing the same distribution certificate |

Set variables `APPLE_TEAM_ID=7U9T57JPF7` and `IOS_BUNDLE_ID=com.ethanteng.helloporch`.

Enable **Push Notifications** for the app ID in Apple Developer and regenerate the distribution profile with `aps-environment=production`; the upload script checks this. Create the certificate/profile in Apple Developer and the upload key in App Store Connect → Users and Access → Integrations. Team API keys apply across every app on the team; use the lowest required role. Keep credentials out of Git; signing files are ignored.

Run the workflow on the desired branch with **variant=family** and **verify_only** checked first. Family builds need no driver profile and must contain neither a driver nor DriverKit signature entitlements. For **variant=cell2jack**, the app and driver retain their separate project bundle IDs and provisioning profiles; do not pass a global `PRODUCT_BUNDLE_IDENTIFIER`. The script checks the actual archive and exported IPA signatures, embedded profiles, signer certificates, build numbers, and restricted USB entitlements before App Store validation. A successful compilation or development archive is insufficient. Only after verification succeeds should an upload run use **verify_only=false**. Build numbers use the workflow run number and attempt. After upload, wait for Apple processing and assign the build to an internal group. External testing requires beta test information and Apple's beta review.

Alternatively, in Xcode select the **PorchFamily** scheme for family TestFlight (or **Porch** for approved Cell2Jack distribution), select **Any iOS Device**, Product → Archive, and Distribute App → App Store Connect, using automatic signing with your team. This avoids storing signing credentials on GitHub.

## Privacy

See [server and privacy](FAMILY-SETUP.md#server-and-privacy) for shared storage and media handling. Contact slots stay local; selected fallback numbers reach the server for scoped approval and reach the telephone provider only when dialing. The Contacts picker exposes only the selected contact property, not the full address book. Keychain protects device credentials, the caregiver PIN and phone approvals. No recording, advertising, tracking or analytics is configured. Review App Store privacy disclosures for the server, LiveKit and telephone-provider data handling.

Caregiver settings also offer **Bedside display → Default / Dynamic**. Both retain the large current date and time; Dynamic adds day/night and season cues using a configurable daily schedule and hemisphere. Invitations created from a person show pending acceptance and link automatically when accepted. See the [family setup guide](FAMILY-SETUP.md) for details.

Under **Bedside display → Bedside language**, choose **English**, **繁體中文**, **简体中文**, **廣東話**, or **Español**, then tap **Save**. The clock, contact picker and call screens use the selected language. Spoken drop-in announcements use English, Taiwan Mandarin, mainland Mandarin, Cantonese, or Spanish respectively. Caregiver/family screens remain English and contact names are preserved. Contact cards use large wrapping names and keypad numbers without phone icons. **Call preferences → Test ringing / Test video announcement** checks local sound, output and media volume without placing a call. Incoming ringing repeats; drop-ins finish the spoken warning before their five-second countdown, and require manual acceptance if the announcement fails.

On the same screen, **Announcement voice** lists matching voices available on this iPad, with a **Preview announcement** button. Each language keeps its own voice selection after **Save**. English/Spanish allow regional accents; the Chinese choices retain Taiwan Mandarin, mainland Mandarin or Cantonese. Novelty voices are hidden on iOS 17+. Download more voices in the iPad's Accessibility speech settings. A removed voice falls back to the language's system default; unavailable speech still requires manual acceptance. See the [setup and voice acceptance checks](FAMILY-SETUP.md#verify).

Under **Caregiver mode → Advanced**, turn on **End calls after silence**, enter the number of seconds, then tap **Save**. It is off by default; when enabled the default is 120 seconds, adjustable from 15 to 1800 seconds. It applies to connected Porch calls and phone fallback on this device. Audio activity from either side, including a voicemail greeting or a spoken message, restarts the interval. Dialing and reconnection do not count. On timeout Porch uses the normal hang-up path, including ending the telephone leg, and returns to the clock. This uses LiveKit's speaker activity events without recording or transcribing audio. A recipient hanging up also ends phone fallback automatically.

## Cell2Jack and backup keypads

The normal **Porch** scheme now includes optional [Cell2Jack phone keypad support](CELL2JACK-CALLS.md). It starts **off**, under caregiver mode → **Advanced**. Standard USB/Bluetooth keyboards and numeric keypads keep their existing input path and need no Cell2Jack switch or driver. Touchscreen controls remain available alongside either input. On the bedside screen, the Phone keypad ready confirmation appears beneath Call someone for three seconds, then hides while input stays active.

Cell2Jack requires an M-series iPad with iPadOS 16 or later and its driver enabled in Porch's app settings. The universal app keeps its existing iOS 15 minimum for ordinary keyboard/touch operation; USB driver communication is gated and IOKit is weak-linked. DriverKit distribution approval is still needed before distributing the driver through TestFlight or the App Store.

The earlier [USB version/keypad test](CELL2JACK-POC.md), [no-call Preview](KEYPAD-PREVIEW.md), and `PorchCell2JackCalls` scheme remain as historical development fixtures. Build and install **Porch** for the integrated app.

Cell2Jack distribution verification on 2026-10-18 regenerated the previously invalid
Porch App Store profile. The app profile includes production push and driver
communication, but the generated driver App Store profile contains neither
`com.apple.developer.driverkit` nor `com.apple.developer.driverkit.transport.usb`.
The signed archive attempt was rejected by Xcode for those missing entitlements.
Apple DriverKit distribution authorization, a regenerated driver profile, and
`IOS_DRIVER_APPSTORE_PROFILE` are still required. No Cell2Jack TestFlight upload
has been validated. See [distribution evidence](CELL2JACK-CALLS.md#distribution-verification-2026-10-18).
