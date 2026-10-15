# Porch for iPad

Native iPad prototype: save a named Apple Shortcut (or a direct FaceTime contact), then press **1** on a connected keypad to start the call. The large on-screen button does the same thing. The Next.js landing page remains at the repository root.

## Run on an iPad

1. Install Xcode 26 or newer and open `ios/Porch.xcodeproj`.
2. Select the **Porch** scheme and your connected iPad (iPadOS 15 or later).
3. In Signing & Capabilities, sign in to your Apple developer team. The project uses `com.ethanteng.helloporch` and team `7U9T57JPF7`.
4. In Apple’s **Shortcuts** app on the iPad, create a shortcut such as **Call David**. Add the native **FaceTime** action and choose a fixed recipient, without **Ask Each Time**. Run it once and grant any requested permissions.
5. Run Porch. Tap **Choose a contact**, select **Shortcut**, enter the display name and the shortcut’s exact name, and tap Save. Existing installations keep their saved direct FaceTime contact; hold setup and select **Shortcut** to switch.
6. With Porch visible and the iPad unlocked, press keypad **1**. Top-row **1** works too. Modified key combinations don't initiate calls.

Shortcuts and FaceTime must be installed; FaceTime must be enabled and signed in. The shortcut controls the actual recipient; Porch’s display name is only a label. Shortcut names must match exactly and must be updated in Porch after renaming. For direct calling, select **FaceTime** in setup and choose or enter the person’s FaceTime address. A USB-C iPad can use a standard USB HID keypad; a USB-A keypad needs an adapter. Test the exact keypad and charging hub together.

To change the contact, hold **Hold here to set up** for two seconds. This prevents accidental taps; it isn't authentication. VoiceOver offers an **Open contact setup** custom action. Choosing a contact never initiates a call.

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

Tests cover shortcut URL encoding (including Unicode and query syntax), required shortcut names, migration of existing saved contacts, number normalization, malformed/multiple recipients, persistence, held-key suppression, and cooldown. CI compiles both device and simulator builds. A real iPad is required to verify an actual FaceTime call through Shortcuts.

Device checks: run the shortcut directly, run it from Porch using both keypad and touch, first-run permissions, missing/renamed shortcut, Shortcuts uninstalled, successful call, cancellation, no answer, offline use, FaceTime disabled, held/repeated keys, return to Porch, relaunch persistence, rotation, large text, and the intended keypad/charging setup.

## Privacy

The display name and either a shortcut name or selected FaceTime address are saved locally in UserDefaults. In Shortcut mode, only the shortcut name is passed to Shortcuts; the recipient is configured there. In direct mode, the Contacts picker gives access only to the selection, without full address-book permission, and the selected address is passed to FaceTime. FaceTime handles camera/microphone access and calling. Porch has no backend, third-party SDK, tracking, or analytics. Its privacy manifest declares local preferences and elapsed-time measurement for cooldown.

References: [run a shortcut by URL](https://support.apple.com/guide/shortcuts/run-a-shortcut-from-a-url-apd624386f42/ios), [keyboard input](https://developer.apple.com/documentation/uikit/handling-key-presses-made-on-a-physical-keyboard), [FaceTime URLs](https://developer.apple.com/library/archive/featuredarticles/iPhoneURLScheme_Reference/FacetimeLinks/FacetimeLinks.html), [Contacts picker](https://developer.apple.com/documentation/contactsui/cncontactpickerviewcontroller), [TestFlight](https://developer.apple.com/testflight/).
