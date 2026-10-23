# Incoming calls on a locked iPhone or bedside iPad

The ordinary Porch attempt now has its own delivery path:

1. The bedside device reserves the household's call in Redis.
2. The server sends an APNs **VoIP** push to that paired family device's PushKit token, even if foreground presence has expired.
3. iOS wakes/launches Porch. The app immediately reports the UUID and caller name to CallKit, before performing network work.
4. Porch validates the call against the authenticated server state. Answer atomically accepts the Porch call and cancels eligibility for regular-phone fallback. LiveKit joins after acceptance; CallKit activation controls its audio engine.
5. The existing bedside wait timer still owns regular-phone fallback if the person doesn't answer. Pushes that APNs rejects for an unreachable app return the existing `offline` result, allowing immediate fallback. An APNs acknowledgment means accepted for delivery, not that the phone actually rang. Authenticated background polls acknowledge the exact incoming call separately from foreground availability; this preserves an already-ringing call if the APNs acknowledgment is lost.

The server sends VoIP pushes for new, ordinary calls to either paired device role, including inbound telephone calls to the bedside iPad. Drop-in retains its foreground bedside announcement and five-second consent window. Cancellation, revocation and expiry travel through authenticated signaling, never a second VoIP push. The app checks state every second while ringing and every five seconds during an incoming call. If iOS ends the ringing execution window, CallKit ringing stops locally. The caller's fallback timer continues for calls from the bedside to a family device; bedside incoming calls release the server call and telephone leg.

Incoming ordinary-call audio is owned by an application-level session rather than a view controller and survives leaving Porch or locking the device. A video answer connects audio first, then turns the camera on once Porch is in the foreground: always on the bedside, and on a family phone unless **Call settings → Start with my camera on** is off. Backgrounding turns it off. Outgoing calls, drop-in, legacy rooms and phone-fallback media retain their existing foreground lifecycle.

## Server setup

Set these server-only variables alongside the existing Redis and LiveKit settings, then deploy the server before distributing the new app:

| Variable | Value |
| --- | --- |
| `APNS_KEY_ID` | Key ID for an Apple Developer APNs signing key |
| `APNS_TEAM_ID` | Apple Developer team ID (`7U9T57JPF7`) |
| `APNS_PRIVATE_KEY` | APNs `.p8` PEM contents; literal `\n` separators are accepted |
| `APNS_BUNDLE_ID` | `com.ethanteng.helloporch` |

Create the key in Apple Developer → Certificates, Identifiers & Profiles → Keys, with APNs access for this app/team. This is separate from the App Store Connect upload key. Keep the key in server secret storage; never put it in the app, public environment variables or Git.

The sender uses HTTP/2, ES256 provider authentication, the `.voip` topic, priority 10 and expiration 0. Each registration carries its sandbox/production environment; the app cannot choose an arbitrary APNs URL or topic. Invalid/unregistered tokens are removed without deleting a newer token registered during delivery. Token values and credentials are omitted from public household snapshots and push payloads. Push payloads include the caller's display name, mode, call UUID, recipient ID and expiry.

Without these variables, existing foreground calling and regular-phone fallback continue. The family app reports background delivery unavailable. A registered token alone does not prove delivery; the real-device checks below are required.

## Apple signing and installation

1. Enable **Push Notifications** for App ID `com.ethanteng.helloporch` in Apple Developer. Regenerate development and App Store distribution profiles. Replace the `IOS_APPSTORE_PROFILE` TestFlight secret with the updated profile; the upload script requires production `aps-environment`.
2. The app includes Push Notifications, `voip` and `audio` background modes. Debug uses the development entitlement and sandbox APNs; Release/TestFlight uses production. For an unusual signing configuration, set `APS_ENVIRONMENT` (`development` or `production`) and `PORCH_APNS_ENVIRONMENT` (`sandbox` or `production`) consistently with the signed profile.
3. Build/install the updated app. Open it in **Family** or **Bedside** mode, pair if needed, and allow microphone access while the app is open. Existing paired calling credentials for either role migrate to device-only Keychain protection accessible after the first unlock, so a cold launch can authenticate while locked. Caregiver PINs, activation secrets and phone approvals retain unlocked-only protection.
4. Confirm the family home screen says incoming calls can ring while locked. The message confirms registration and server configuration, not a completed APNs delivery test.

The registry is created at application launch, before a scene is required. Tokens are updated at launch/resume and after pairing, invalidated by PushKit, unregistered from the inactive device role on mode changes and removed when caregiver access is revoked. Replacing a family pairing unregisters the prior device credential first. A revoked prior pairing can be replaced without retaining access. Existing bedside installations must open the updated app once while unlocked to register and migrate their saved calling credential.

## Physical-device acceptance checks

Use a signed iPhone and bedside iPad, with a fallback phone number configured. Simulator tests do not establish APNs wakeup, lock-screen audio or actual telephone behavior.

- Background Porch, lock the iPhone, then call its keypad contact. Check the system caller name and Answer/Decline controls, with exactly one incoming call. Answer without unlocking; confirm two-way audio and that the fallback number is never dialed after the configured wait.
- Repeat with audio and video calls. A locked video answer must keep the camera off. Unlock and open Porch: the camera turns on by itself. Lock again: audio continues and the camera stops; reopen Porch and it turns back on. Turn the camera off, leave and reopen Porch: it stays off. With **Call settings → Start with my camera on** turned off, reopening Porch keeps the camera off until you tap **Camera on**, and outgoing video calls start with it off. Verify mute and hangup from both system controls and Porch, plus Bluetooth routing and audio interruption/recovery.
- Ignore a call. Confirm the existing configured wait leads to exactly one regular-phone fallback and that the Porch ring is dismissed. Repeat with waits longer than 30 seconds and with caller cancellation before answer. Delayed/duplicate pushes must not reconnect an ended call.
- Race Answer against the fallback boundary; only one path may win. Decline and hangup from the lock screen; confirm the caller leaves the Porch call. Remove family access during a call and confirm disconnection.
- Terminate Porch through the development tools without explicitly force-quitting it, lock the phone, and repeat. Also record behavior after a deliberate app-switcher force-quit; do not promise that case without device evidence. After reboot, unlock once and reopen Porch before checking locked delivery.
- Check airplane mode, offline APNs delivery, Focus/Do Not Disturb and revoked microphone access. Background ringing is best effort; the saved phone-number fallback remains the recovery path for unreachable/unanswered Porch attempts.
- Verify both sandbox development and production TestFlight delivery. Update/reinstall and re-pair to confirm token renewal, prior-pairing removal and invalid-token cleanup. Confirm foreground ordinary calls ring once and bedside/drop-in announcements retain their current behavior.

Automated coverage includes APNs signing/headers and response handling, registration authorization, token secrecy/rotation, offline call reservation, concurrent callers, cancellation, heartbeats, revocation and the atomic answer/fallback race. UIKit tests cover Keychain protection migration. Actual APNs credentials and hardware acceptance remain release prerequisites.

Reference: [Apple's PushKit handling requirements](https://developer.apple.com/documentation/pushkit/responding-to-voip-notifications-from-pushkit), [APNs request format](https://developer.apple.com/documentation/usernotifications/sending-notification-requests-to-apns), and [LiveKit Swift 2.17 CallKit integration](https://github.com/livekit/client-sdk-swift/blob/2.17.0/README.md#integration-with-callkit).
