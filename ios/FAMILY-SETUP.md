# Bedside and family beta

One universal Porch app supports iPad bedside mode and iPhone/iPad family mode. iPhones start in family mode; iPads keep the bedside clock. Change modes from caregiver settings or the family screen. Each mode keeps its own device pairing.

## Pair your family

1. Install the same updated TestFlight build on Mom's iPad and family members' iPhones.
2. On the iPad, hold the **gear** for 1.5 seconds. Open **Family & drop-in**, enter a bedside name such as Mom, and choose and confirm a six-digit caregiver PIN. If this iPad already has the old long setup code saved, Porch migrates it automatically. A fresh installation must use the PIN already configured for the server.
3. Choose **Invite a family member**, enter their name, and select audio and/or video drop-in if appropriate. Both permissions start off. Porch asks for the corresponding iPad media permissions during setup.
4. Share the private invitation using the system share sheet. The recipient opens it on their iPhone or pastes it into **Invitation → Join your family**. Invitations expire after 15 minutes and work for one device. Invite each additional device separately.
5. On the iPad, turn on **Allow approved drop-ins**. Return to the clock. The family member can now make audio/video calls or use the drop-in types you approved.
6. To let Mom call that person with a keypad number, edit the slot, select **Porch → Link a family member**, and choose voice or video. Optionally add a fallback phone number. Contacts imports and typed numbers are normalized to E.164 (for example, `(415) 867-6937` in the US becomes `+14158676937`). National numbers use the device's region; include `+country code` for overseas contacts. Extensions aren't supported.

Paired calls use the bundled server address and private device credentials. Family members never enter a server address, shared calling code, or caregiver PIN. Old manual rooms and browser calling remain under **Advanced calling connection**.

## How calls behave

- Both devices must have Porch open, unlocked and ready. Caregiver screens and pairing screens don't auto-answer. **This beta has no background/lock-screen incoming calls or push notifications on iPhone.** Leaving Porch ends an active call. CallKit/PushKit integration remains future work.
- Ordinary incoming calls show **Answer** and **Decline**. Drop-ins announce the caller and audio/video mode, give a five-second countdown and a **Don't connect** button, then answer automatically. An audio drop-in never enables the camera.
- Drop-in needs both the master switch and that device's specific audio/video approval. Pause drop-ins, change permissions, cancel unused invitations or remove a family device in **Family & drop-in**. Removing access ends its current call and requires a new invitation to reconnect.
- Mom's outgoing calls try Porch first. An unavailable family app or an unanswered call can fall back to its configured regular phone number. The wait remains configurable under **Call preferences**. Porch's answer and the phone handoff are coordinated atomically so an answered Porch call doesn't also dial the phone. Ringback plays during both dialing stages.
- Only one Porch call can be active per household. Presence is checked every few seconds; this prototype can take several seconds to show an incoming call. Decline, hangup, expiry or lost-device heartbeats release the call. Calls are limited to 30 minutes; phone fallback retains its shorter server limits.

## Caregiver PIN

Once paired, holding the gear opens a six-digit PIN prompt. Change the PIN under **Family & drop-in → Change caregiver PIN**. Five incorrect guesses cause a 15-minute server lockout. Internet access is required to unlock settings.

The server stores only a salted PIN digest, using the server secret as a pepper. The original long `PORCH_CONTACT_SETUP_CODE` remains server-side for recovery and signing phone approvals. **Do not replace that environment variable with six digits.** Existing device phone approvals survive a PIN change. Other bedside devices using that server must enter the updated PIN when next needed.

For a server with no existing bedside installation, an operator can initialize the PIN with the `/api/family` `setCaregiverPIN` action authenticated by the long recovery secret, then enter the chosen PIN on the new bedside device. Do not send recovery secrets or PINs in chat, logs or Git. This beta uses one caregiver PIN per server, not independent account passwords.

## Server and privacy

Keep the LiveKit/SIP settings and long signing/recovery secret from the root setup guide. Connect Upstash Redis and provide either `UPSTASH_REDIS_REST_URL`/`UPSTASH_REDIS_REST_TOKEN` or Vercel's `KV_REST_API_URL`/`KV_REST_API_TOKEN` aliases. The free database was provisioned with automatic paid upgrades disabled. Deploy the new server before using the new app; older manual-room builds remain compatible.

The default data namespace is `porch:family:v1:`. Local verification must set an isolated `PORCH_FAMILY_STORE_PREFIX=porch:family:preview:v1:`. Redis CAS operations coordinate shared state across server instances. Storage outages fail closed; there is no process-memory fallback. Use TLS and keep write credentials server-side.

Redis stores household/display names, hashed device/invitation secrets, permissions, presence, the current call and hashed PIN/lockout state. It doesn't store media, full contact books or fallback numbers. Local slots remain on the device. Keychain stores private device credentials, caregiver credentials and scoped phone approvals. LiveKit handles media/connection metadata; SIP fallback sends its destination to LiveKit and the telephone provider. No recording is configured. Transport encryption is used; application-level end-to-end encryption isn't configured. Update App Store privacy disclosures for this data handling before distributing the beta.

This is device pairing, without email accounts or account recovery UI. Legacy shared-code rooms retain their older trust model. Public release still needs push delivery, recovery/deletion flows, abuse controls and distributed SIP dialing limits. Revocation deletes the active media room; issued media join tokens last up to one minute, so token replay/rejoin remains a prototype limitation.

## Verify

Run Node tests, type checking, the Next production build, PorchCore tests and UIKit tests on iPhone and iPad. Backend tests use fake media clients and never place telephone calls.

For local simulator verification only:

```sh
# .env.local must contain an isolated preview namespace and private server settings.
npm run dev -- --port 3028
node --env-file=.env.local scripts/seed-family-preview.mjs http://localhost:3028 /tmp/porch-family-preview
```

The seed creates fictional devices and private mode-0600 fixture files with the preview PIN `246810`. Copy the appropriate file into the simulator app's Documents directory as `PorchDebugFamily.json`, then launch Debug with `--family-fixture --family-silent`. Fixtures are consumed once. Silent mode suppresses microphone publication and ringback for automated verification. Build with `CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=-` for simulator Keychain testing; Xcode embeds the simulated entitlements. Unsigned build artifacts don't have Keychain access. Release builds contain no fixture loader or silent mode.

Physical-device acceptance: pair and relaunch both devices; approve audio only and confirm video is unavailable; enable video and test both directions; stop/pause/revoke during a drop-in; leave the iPad in caregiver mode or background and verify it doesn't auto-answer; test caller cancellation during the countdown; test permission denial, network loss and concurrent callers; verify real microphone/camera, speaker routing, Guided Access, and phone fallback with your authorized test number.
