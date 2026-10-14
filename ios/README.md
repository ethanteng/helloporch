# Porch for iPad

Native iPad prototype: save one FaceTime contact, then press **1** on a connected keypad to open a FaceTime video call to that person. The large on-screen button does the same thing. The Next.js landing page remains at the repository root.

## Run on an iPad

1. Install Xcode 26 or newer and open `ios/Porch.xcodeproj`.
2. Select the **Porch** scheme and your connected iPad (iPadOS 15 or later).
3. In Signing & Capabilities, sign in to your Apple developer team. The project uses `com.ethanteng.helloporch` and team `7U9T57JPF7`.
4. Run. Tap **Choose a contact**, select a phone number/email from Contacts or enter it manually, and tap Save.
5. With Porch visible and the iPad unlocked, press keypad **1**. Top-row **1** works too. Modified key combinations don't initiate calls.

FaceTime must be installed, enabled, and signed in. The saved address must be registered for FaceTime. A USB-C iPad can use a standard USB HID keypad; a USB-A keypad needs an adapter. Test the exact keypad and charging hub together.

To change the contact, hold **Hold here to set up** for two seconds. This prevents accidental taps; it isn't authentication. VoiceOver offers an **Open contact setup** custom action. Choosing a contact never initiates a call.

## FaceTime limits

- Porch uses the public `facetime://` URL scheme to hand the call to Apple's app. It does not embed or control FaceTime.
- Apple's archived documentation describes native launches without confirmation; current behavior needs verification on the intended iPad. Porch can't bypass Apple confirmations or the lock screen.
- URL-open success does not mean ringing or connection. Porch can't detect the end of a FaceTime call or force a return. Use the app switcher/system Back to Porch control when needed.
- Keypad input is handled while Porch is in the foreground, not as a systemwide hotkey.
- Guided Access prevents switching to FaceTime. Porch shows an explanation when it is enabled.
- Held-key repeats are suppressed; keypad and touch launches share a two-second cooldown.

## TestFlight

App: **Porch Family Calling**, App Store Connect ID **6822602923**. Bundle ID: **com.ethanteng.helloporch**. Apple team: **7U9T57JPF7**.

**iPad build** runs six core tests and compiles the simulator and iPad release app without signing credentials. **Upload iPad to TestFlight** is manually dispatched, and tests, archives, signs, validates, and uploads the app. It does not publish to the App Store or invite testers.

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

Tests cover number normalization, URL encoding, malformed/multiple recipients, persistence, held-key suppression, and cooldown. CI compiles both device and simulator builds. A real iPad is required to verify an actual FaceTime call.

Device checks: successful call, cancellation, no answer, offline use, FaceTime disabled, held/repeated keys, return to Porch, relaunch persistence, rotation, large text, and the intended keypad/charging setup.

## Privacy

The selected contact's name and address are saved locally in UserDefaults. The Contacts picker gives access only to the selection, without full address-book permission. The address is passed to FaceTime when a call is requested. FaceTime handles camera/microphone access and calling. Porch has no backend, third-party SDK, tracking, or analytics. Its privacy manifest declares local preferences and elapsed-time measurement for cooldown.

References: [keyboard input](https://developer.apple.com/documentation/uikit/handling-key-presses-made-on-a-physical-keyboard), [FaceTime URLs](https://developer.apple.com/library/archive/featuredarticles/iPhoneURLScheme_Reference/FacetimeLinks/FacetimeLinks.html), [Contacts picker](https://developer.apple.com/documentation/contactsui/cncontactpickerviewcontroller), [TestFlight](https://developer.apple.com/testflight/).
