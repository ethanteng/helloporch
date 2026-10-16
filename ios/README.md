# Porch for iPad

Native iPad prototype: configure up to **six people**, each using an in-app **Porch voice/video call**, a named Apple Shortcut, or a direct FaceTime contact. Press their number (**1–6**) on a connected keypad to start the call. The large numbered buttons on screen do the same thing. The Next.js website and LiveKit token endpoint live at the repository root.

## LiveKit voice and video calls

Follow the root [calling setup](../README.md#native-voice-and-video-calling-prototype) to configure the server. The LiveKit Swift SDK is pinned to 2.17.0 through Swift Package Manager; Xcode downloads it and its WebRTC dependency on first build.

In **Your people → Native calling server**, save your Porch server address (an HTTPS origin, without a path) and its prototype access code. The address is kept in UserDefaults, and the access code in this device's Keychain. LiveKit API credentials are never entered in the app. `http://localhost:3000` is supported for simulator testing with a locally running Next.js server; a real iPad needs an HTTPS server it can reach.

Choose a keypad slot, select **Porch**, enter the person's name and a shared room name such as `family-david`, then choose **Voice** or **Video**. Saving never starts a call. After Done, pressing that number opens the native call screen. The other person joins the same room/mode from another iPad or the server's `/call` browser page. They join manually; this prototype does not notify or ring another device. Each new room is configured for two participants. Use unique room names per contact and coordinate testing to avoid mixing calls.

- Voice requests microphone access only. The server grants microphone publication only, and voice/video rooms are separate.
- Video requests microphone and camera access, shows the remote video and a local preview, and provides camera on/off. Camera denial explains how to grant permission or change the contact to Voice.
- Both modes provide mute/unmute and a large End call button. End disconnects and releases media before returning to your people. If nobody joins within 90 seconds and no phone fallback is configured, Porch returns automatically. When the remote person leaves, Porch also ends the call.
- Network interruptions show a reconnecting state; a final disconnect returns to your people. An initial failure leaves an explanation and a Back to your people button.
- The app ends its call on entering the background or locking the iPad. CallKit, PushKit, incoming calls, and background audio are not implemented.
- Native calls do not leave Porch, so the FaceTime-specific Guided Access block does not apply. Verify permissions, controls, and recovery in Guided Access on the actual iPad before use.
- The shared code is for trusted prototype testers. It grants access to all prototype rooms. Family/device authentication and per-person authorization are still required for a public product. There is no recording or application-level end-to-end encryption configuration.

## Porch first, then their phone

For a Porch contact, enable **Call their phone if Porch isn't answered** and enter their international phone number. This is a fallback, never a direct telephone shortcut: Porch tries the shared room first for 20 seconds, then switches to a voice-only telephone call if nobody joins. An initial connection failure before anyone joins also starts fallback. An answered Porch call never falls through to phone after hangup. FaceTime/Shortcut contacts keep their existing behavior.

The server needs an outbound SIP trunk and a separate `PORCH_CONTACT_SETUP_CODE`. Enter that caregiver code once in **Native calling server**. Saving a phone contact then approves its number automatically; no Vercel update is needed per contact. Follow the root [phone fallback setup](../README.md#porch-first-then-phone-fallback). Phone numbers are normalized (for example, `+1 (415) 555-0123` → `+14155550123`) and stored locally with the contact. Saving a phone contact sends its number to the Porch server for approval, without contacting the telephone provider or placing a call. A failed approval leaves the previous contact unchanged. The approval and caregiver code are stored in Keychain. Approval renews automatically when needed before fallback; phone calls still require internet. The number reaches the telephone provider only when dialing. Older builds can keep using the legacy server destination list during migration.

Fallback disconnects the Porch room to release its camera and joins an isolated room with microphone-only credentials. Camera controls stay hidden and an existing mute setting is preserved. Late Porch joiners cannot enter the phone call. A dial tone plays while the telephone is being dialed; **Phone call connected** requires LiveKit's SIP `active`/`automation` status, not merely the presence of a SIP participant.

End Call and backgrounding disconnect the iPad and request deletion of the phone room to hang up the other end. If cleanup cannot be confirmed, the app offers **Retry ending phone call**. Calls are bounded to 45 seconds ringing and 15 minutes total on the server; network loss or force termination can prevent immediate cleanup. App notifications, answering-machine detection, and incoming regular phone calls aren't implemented.

For a visual-only setup preview, launch a Debug build with `--preview-phone-setup`. This shows a fictional contact and never saves it or places a call.

## Run on an iPad

1. Install Xcode 26 or newer and open `ios/Porch.xcodeproj`.
2. Select the **Porch** scheme and your connected iPad (iPadOS 15 or later).
3. In Signing & Capabilities, sign in to your Apple developer team. The project uses `com.ethanteng.helloporch` and team `7U9T57JPF7`.
4. In Apple’s **Shortcuts** app on the iPad, create a shortcut such as **Call David**. Add the native **FaceTime** action and choose a fixed recipient, without **Ask Each Time**. Run it once and grant any requested permissions.
5. Run Porch. Tap **Choose people**, select a number in **Your people**, choose **Shortcut** or **FaceTime**, enter that person’s details, and tap Save. Repeat for up to six people, then tap Done. Existing installations move the saved person to **key 1**, preserving the calling method; keys 2–6 start empty.
6. With Porch visible and the iPad unlocked, press that person’s keypad number (**1–6**). Top-row **1–6** work too. Modified key combinations don't initiate calls.

Shortcuts and FaceTime must be installed; FaceTime must be enabled and signed in. The shortcut controls the actual recipient; Porch’s display name is only a label. Shortcut names must match exactly and must be updated in Porch after renaming. For direct calling, select **FaceTime** in setup and choose or enter the person’s FaceTime address. A USB-C iPad can use a standard USB HID keypad; a USB-A keypad needs an adapter. Test the exact keypad and charging hub together.

Only configured people appear on the call screen. Unassigned keys do not call anyone or open setup. The buttons use two columns in portrait, three in landscape, and one with accessibility text sizes; scrolling keeps every person reachable.

To add, edit, or remove a person, hold **Hold here to set up** for two seconds, then choose their number in **Your people**. Removing a person leaves that number empty and never renumbers the others. The two-second hold prevents accidental edits; it isn't authentication. VoiceOver offers an **Open contact setup** custom action. Choosing or saving a contact never initiates a call. Save returns to the six-slot list; Done returns to the call screen.

## FaceTime limits

- Shortcut mode opens Apple’s documented `shortcuts://run-shortcut?name=…` URL with the name encoded as one query value. The shortcut must already be installed on that iPad. Porch does not create or inspect shortcuts.
- A native FaceTime action in Shortcuts can avoid the direct FaceTime confirmation on the tested iPad. The complete Porch → Shortcuts → FaceTime flow still needs testing on the intended device, including first-run permissions. Porch cannot suppress system prompts or bypass the lock screen.
- Direct mode still uses `facetime://` and may show a confirmation. Porch does not embed or control FaceTime.
- URL-open success only means the URL was handed off. It cannot confirm that a named shortcut exists or ran, or that a call is ringing or connected. A missing or renamed shortcut reports its error in Shortcuts. Porch can't detect the end of a FaceTime call or force a return. Use the app switcher/system Back to Porch control when needed.
- Keypad input is handled while Porch is in the foreground, not as a systemwide hotkey.
- Guided Access prevents switching to Shortcuts or FaceTime. Porch shows an explanation when it is enabled.
- Held-key repeats are suppressed; keypad and touch launches share a two-second cooldown.

## TestFlight

App: **Porch Family Calling**, App Store Connect ID **6822602923**. Bundle ID: **com.ethanteng.helloporch**. Apple team: **7U9T57JPF7**.

**iPad build** runs the core tests and compiles the simulator and iPad release app without signing credentials. **Upload iPad to TestFlight** is manually dispatched, and tests, archives, signs, validates, and uploads the app. It does not publish to the App Store or invite testers.

Configure these encrypted GitHub secrets in the `testflight` environment or repository:

| Secret | Value |
| --- | --- |
| `ASC_KEY_ID` | App Store Connect team API key ID |
| `ASC_ISSUER_ID` | API issuer UUID |
| `ASC_PRIVATE_KEY` | Downloaded `.p8` file contents; Developer role is sufficient for binary upload |
| `IOS_DISTRIBUTION_P12` | Base64-encoded Apple Distribution certificate and private key, exported as `.p12` |
| `IOS_DISTRIBUTION_PASSWORD` | Password protecting the `.p12` |
| `IOS_APPSTORE_PROFILE` | Base64-encoded App Store distribution profile for this bundle ID and certificate |

Set variables `APPLE_TEAM_ID=7U9T57JPF7` and `IOS_BUNDLE_ID=com.ethanteng.helloporch`.

Create the certificate/profile in Apple Developer and the upload key in App Store Connect → Users and Access → Integrations. Team API keys apply across every app on the team; use the lowest required role. Keep credentials out of Git; signing files are ignored.

Run the workflow on the desired branch. Build numbers use the workflow run number and attempt. After upload, wait for Apple processing and assign the build to an internal group. External testing requires beta test information and Apple's beta review.

Alternatively, in Xcode select **Any iOS Device**, Product → Archive, and Distribute App → App Store Connect, using automatic signing with your team. This avoids storing signing credentials on GitHub.

## Verification

```sh
swift test --package-path ios/PorchCore
xcodebuild -project ios/Porch.xcodeproj -scheme Porch \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

Tests cover keypad and top-row routing for all six numbers, six-slot persistence with both calling methods, empty and out-of-range slots, clearing without renumbering, migration of existing FaceTime/shortcut contacts into key 1, malformed saved data, shortcut URL encoding (including Unicode and query syntax), contact validation, held-key suppression, and the cooldown shared across people and touch input. CI compiles both device and simulator builds. A real iPad is required to verify an actual FaceTime call through Shortcuts.

Device checks: configure all six people with mixed calling methods, press each key and its matching button, clear a middle slot without changing other key assignments, relaunch and verify all six settings, run the shortcut directly, run it from Porch using both keypad and touch, first-run permissions, missing/renamed shortcut, Shortcuts uninstalled, successful call, cancellation, no answer, offline use, FaceTime disabled, held/repeated keys, return to Porch, relaunch persistence, rotation, large text, and the intended keypad/charging setup.

## Privacy

For each configured slot, the display name and either native room/mode, shortcut name, or selected FaceTime address are saved locally in UserDefaults. The native server address is also local; the calling access code, caregiver setup code, and signed phone approvals are stored in Keychain. Saving a phone contact sends its number to the server to obtain an approval; contact names remain local until a call is prepared. For native calls, Porch sends the room, mode, and a generic “Porch iPad” participant name to its token endpoint, then LiveKit handles audio/video transport and connection metadata. No call recording is configured. Review LiveKit's data handling and update App Store privacy disclosures before distributing this version. The privacy manifest declares local preferences and elapsed-time measurement for cooldown; LiveKit includes its own manifest.

In Shortcut mode, only the shortcut name is passed to Shortcuts; the recipient is configured there. In direct FaceTime mode, the Contacts picker gives access only to the selection, without full address-book permission, and the selected address is passed to FaceTime. FaceTime handles media and permissions for those calls. Porch has no advertising, tracking, or analytics integration.

References: [run a shortcut by URL](https://support.apple.com/guide/shortcuts/run-a-shortcut-from-a-url-apd624386f42/ios), [keyboard input](https://developer.apple.com/documentation/uikit/handling-key-presses-made-on-a-physical-keyboard), [FaceTime URLs](https://developer.apple.com/library/archive/featuredarticles/iPhoneURLScheme_Reference/FacetimeLinks/FacetimeLinks.html), [Contacts picker](https://developer.apple.com/documentation/contactsui/cncontactpickerviewcontroller), [TestFlight](https://developer.apple.com/testflight/).
