# helloporch

Landing page for **Porch**, a tablet plus large-button keypad that lets individuals with dementia or limited dexterity start a video call with one press. Implements design 3a from the Claude Design handoff.

## Develop

The native iPhone/iPad calling prototype lives in [`ios/`](ios/README.md). Open `ios/Porch.xcodeproj` in Xcode. It supports in-app LiveKit voice/video calls as well as the existing FaceTime/Shortcut methods.

```sh
npm install
npm run dev
```

## Bedside and family calling

The universal app now includes family pairing, ordinary incoming calls and approved audio/video drop-in while Mom’s iPad is open. Start with the [family setup guide](ios/FAMILY-SETUP.md) for invitations, the six-digit caregiver PIN, managed storage, permissions and beta limits. Ordinary calls to family iPhones support APNs VoIP delivery and CallKit ringing while locked or backgrounded once the server and Apple signing are configured; see [incoming-call setup](ios/INCOMING-CALLS.md). The existing regular-phone fallback remains in place. Existing manual rooms remain available for browser testing.

Regular phones can also call a household's assigned Twilio number and ring its bedside iPad with a manual-answer, audio-only call. Each household uses its own number; routing never depends on recognizing the caller. See [inbound telephone setup](ios/INBOUND-PHONE-CALLS.md) for the LiveKit trunk, signed webhook, number assignment, and Twilio Origination configuration.

## Native voice and video calling prototype

The instructions in this section describe browser calling and older native builds. Current apps use the family setup guide above; manual-room and connection fields have been removed. The iPad and browser join a private LiveKit room manually. There is no incoming app-call notification, background calling, account system, or recording in this version. An optional phone fallback rings a regular phone if Porch isn't answered. Each new room is configured for at most two participants. Use a distinct room name for each contact, and use the same voice/video mode on both devices.

1. Create a LiveKit Cloud project and get its WebSocket URL, API key, and API secret from its dashboard.
2. Copy `.env.example` to `.env.local`. Fill in `LIVEKIT_URL` (`wss://…`), `LIVEKIT_API_KEY`, and `LIVEKIT_API_SECRET`. Generate a separate `PORCH_CALL_ACCESS_CODE` with `openssl rand -hex 24` and save it in that file too. Never put API credentials in `NEXT_PUBLIC_` variables or in the iPad app.
3. Run `npm install` and `npm run dev`. Open [the browser call page](http://localhost:3000/call). For testing with a physical iPad or another computer, host this server over HTTPS and set the same four environment variables there. Plain HTTP localhost works only on the same computer (including the iPad simulator).
4. In an older iPad build’s setup → **Calling connection**, enter this server's HTTPS origin and the prototype access code. Use `http://localhost:3000` for simulator testing. The access code is saved in the iPad Keychain.
5. Configure a person with **Porch**, a room such as `family-david`, and **Voice** or **Video**. Tap Done and press their number.
6. On the browser page, enter your name, the same room, access code, and mode, then **Join call**. You can also configure the same room/mode on a second iPad. Both people should join within 90 seconds, or 20 seconds if phone fallback is enabled; either person can join first.

Calls support mute, camera on/off in video mode, ending, reconnect status, and return to the people screen when the other person leaves. Voice mode never requests camera access and its server token permits only microphone publication. Voice and video rooms have separate namespaces; changing modes requires ending and starting a new call. Leaving the iPad app or locking it ends the prototype call.

The shared access code grants access to all prototype rooms. It is intended for trusted testers, not public distribution. Before production, replace it with family/device authentication, per-family contact management, rate limiting, and incoming-call delivery. Tokens are room-scoped, valid for initial join for ten minutes, and returned with `Cache-Control: no-store`; API credentials remain server-side. Tokens issued before an access-code rotation remain usable until expiry, and existing calls continue. Calls use LiveKit transport encryption; application-level end-to-end encryption is not configured. Review App Store privacy disclosures for the media and metadata handled by LiveKit before distributing this version.

Checks (Node.js 24+ for the built-in TypeScript test runner):

```sh
npm test
npm run typecheck
npm run build
swift test --package-path ios/PorchCore
```

The token tests verify authentication, input validation, signed token expiry, room isolation, two-person room configuration, and camera restrictions. Real microphone, camera, network-recovery, and Guided Access behavior still require testing on the intended devices with a configured LiveKit project. See [`ios/README.md`](ios/README.md) for iPad details.

## Porch first, then phone fallback

For a Porch contact, enable **Call their phone if Porch isn't answered** and enter their number with `+` and the country code. Pressing their button **always attempts Porch first**. If nobody joins within the configured wait (20 seconds by default), or the initial Porch connection fails before anyone joins, the iPad releases the camera, leaves the Porch room, and dials their regular phone in a separate microphone-only room. If someone joins Porch, the fallback is cancelled. Once a Porch call is answered, hanging up doesn't trigger a second phone call. A late join to the original room cannot enter the telephone conversation. An existing mute setting is preserved across fallback. On the iPad, **Caregiver mode → Call preferences** changes the wait from 5 to 120 seconds in 5-second steps. A local ringback tone plays while waiting for a Porch answer and stops on connection or exit; The same local tone also plays during phone fallback dialing; updated clients suppress the SIP tone to prevent overlap, while older builds keep SIP ringback.

To enable real telephone dialing:

1. Configure an outbound SIP trunk in your LiveKit project with your telephone provider's credentials and an authorized outgoing caller-ID number. Follow [LiveKit's outbound trunk setup](https://docs.livekit.io/telephony/making-calls/outbound-trunk/). Provider credentials stay in LiveKit; nothing is provisioned automatically by this prototype.
2. Set `LIVEKIT_SIP_OUTBOUND_TRUNK_ID` on the Porch server to that trunk's ID.
3. Generate a separate `PORCH_CONTACT_SETUP_CODE` with `openssl rand -hex 24` and set it on the server once. It must differ from `PORCH_CALL_ACCESS_CODE`. Restart or redeploy once after adding it.
4. Install the updated iPad build. In **Calling connection**, enter the caregiver setup code once; keep it private and share only the calling access code with other call participants.
5. Add or edit a Porch contact, enable phone fallback, and enter the number with `+` and its country code. **Save** automatically approves the number using the caregiver code. Saving requires internet and never places a call. Failed approval leaves the original saved contact unchanged. New contacts no longer require a Vercel environment change.

Older iPad builds still use `PORCH_PHONE_NUMBERS`, an optional comma-separated list of destinations. Keep it during migration; once all iPads are updated and configured with the caregiver code, it can be removed. Removing it does not disable dialing for approved contacts. To disable new phone calls, remove `LIVEKIT_SIP_OUTBOUND_TRUNK_ID` and redeploy; hangup remains available for active sessions.

Contact approvals are server-signed, bound to one exact phone number and server origin, valid for 30 days, and stored in the iPad Keychain. The iPad renews them as needed using its saved caregiver PIN or legacy setup code, so there is no monthly manual step. The shared calling access code alone cannot authorize new phone contacts. Changing the six-digit PIN preserves approvals. Rotating/removing the long server signing/recovery secret invalidates existing approvals; configure the new code on the iPads and save contacts again. These stateless approvals survive server restarts without a database. Removing a contact stops calls from that app slot but does not centrally revoke a copied approval before expiry. Paired family devices can now be revoked; these legacy stateless phone approvals retain their expiry limitation.

The recipient answers a normal mobile or landline voice call and needs no Porch app. Telephone and LiveKit SIP charges apply. The iPad still needs an internet connection. Native Porch contacts support this fallback; FaceTime/Shortcut handoffs cannot report call outcomes, so they don't offer automatic fallback. Browser guests join Porch calls but do not initiate phone fallback themselves.

Dialing begins only after the iPad joins the voice room. A signed, short-lived control ticket fixes the destination and limits hang-up access to that call. Client tokens have no SIP calling privileges. End Call, backgrounding, no-answer, and a disconnected recipient all trigger room deletion to release the telephone leg. The client retries a failed hangup and shows **Retry ending phone call** if it cannot confirm cleanup. An offline or terminated iPad cannot guarantee immediate remote hangup; server-side calls have a 45-second ring limit and a 15-minute maximum duration. Voicemail can answer a regular call; answering-machine detection isn't configured.

Dial requests are never automatically retried. A participant marker blocks sequential replays, and a process-local guard blocks simultaneous submissions to the same process. Distributed atomic SIP dialing locks, durable telephone-call status, abuse rate limits and provider-side spending limits are still needed before public use. Paired devices now have family/role authorization. This remains a trusted-tester prototype. The server forwards the approved phone number to LiveKit and the telephone provider; regular telephone calls do not provide application-level end-to-end encryption.

Phone tests use fake LiveKit service clients and **never place real calls**. Device verification still needed with a configured trunk: saving a new phone number without a Vercel edit, failed/ offline save preserving the old contact, caregiver-code errors, approval renewal, answer Porch before 20 seconds (no telephone call), leave Porch unanswered (one telephone call), camera release and mute preservation, cancel during dialing, busy/no-answer/voicemail, hang up from either end, backgrounding, unavailable server, and recovery after a failed hangup.

## First-time US test setup

Start with LiveKit's free **Build** plan and a **Twilio trial**, checking the limits shown in each account. Twilio supports trial SIP calls to verified destinations; verify the US phone you will answer during testing. Keep account upgrades, phone-number purchases, and test traffic within your chosen budget ($10 for this setup). No paid service is enabled by the repository scripts. Account registration, terms acceptance, and phone/email verification must be completed by the account owner.

1. Register at [LiveKit Cloud](https://cloud.livekit.io/login), create a project named **Porch Prototype**, and choose Build. Get the project WebSocket URL and an API key/secret. Porch needs rooms and media; it does not need an AI agent.
2. Enter the URL, API key, and secret directly in the private `.env.local` file. A Porch access code has already been generated there for this checkout; keep it private. Do not send credentials in chat. Run `npm run calls:check` to check LiveKit authentication without starting a call.
3. Register for a [Twilio trial](https://www.twilio.com/try-twilio). Complete account verification, verify the test recipient's US phone number, and obtain the trial voice number if offered. Stay on the trial while testing; check the account's actual allowances before enabling paid features.
4. In Twilio, create an **Elastic SIP Trunk** named **Porch Prototype**. In **Termination**, choose a unique URI ending in `.pstn.twilio.com`. Create and attach a **Credential List** with a SIP username/password. Associate the outgoing Twilio voice number with the trunk. These SIP credentials are distinct from Twilio's account Auth Token. Outbound fallback only needs termination. To also receive calls on this number, follow the separate [inbound telephone setup](ios/INBOUND-PHONE-CALLS.md). See [LiveKit's Twilio guide](https://docs.livekit.io/telephony/start/providers/twilio/).
5. In LiveKit → **Telephony → SIP trunks → Create new trunk → JSON editor → Outbound**, enter this configuration with your actual values, then create the trunk:

```json
{
  "name": "Porch Prototype outbound",
  "address": "YOUR-UNIQUE-TRUNK.pstn.twilio.com",
  "numbers": ["+1YOUR_TWILIO_NUMBER"],
  "authUsername": "YOUR_SIP_USERNAME",
  "authPassword": "YOUR_SIP_PASSWORD"
}
```

6. Put the **LiveKit** outbound trunk ID (`ST_…`, not Twilio's trunk SID) in `.env.local` as `LIVEKIT_SIP_OUTBOUND_TRUNK_ID`. Generate and set a separate `PORCH_CONTACT_SETUP_CODE` for automatic approval of saved phone contacts. The number in the trunk's `numbers` list is the **outgoing caller ID**; the contact in Porch contains the **recipient**. Run `npm run calls:check -- --phone` to verify the trunk exists. This lookup doesn't test provider authentication or place a call.
7. Run the Porch server at an HTTPS origin accessible from the iPad, using these same calling environment variables, including the separate caregiver setup code. The Mac's `localhost` is not reachable as `localhost` from a physical iPad. Verify a deployed server with `npm run calls:check -- --phone --endpoint=https://YOUR-PORCH-SERVER` before configuring the device. Preview deployment protection must allow the native app to reach the API; a protected login page cannot act as the token endpoint.
8. Install this branch's iPad build using Xcode (select your connected iPad, Porch scheme, and development signing team), or upload this branch through the existing TestFlight workflow. In **Caregiver mode → Calling connection**, save the Porch server's HTTPS origin and the **Porch access code** from `.env.local`. Also enter the separate caregiver setup code to enable phone contacts. Never enter a LiveKit API secret on the iPad.
9. Add a Porch contact with room `family-test`. First disable phone fallback: test Voice, then Video, with another device joining `/call` on the server using that room, mode, and Porch access code. Allow microphone/camera permissions as requested. Once those work, enable phone fallback with your verified recipient number, leave the Porch room unanswered for 20 seconds, and answer the normal phone call. End Call should disconnect both ends. Twilio trial calls may play a trial announcement.

Configuration check commands print status only, never API secrets, access codes, tokens, trunk passwords, or destination phone numbers. They perform read-only LiveKit lookups and optionally request an unused join token from Porch; they never dial, publish media, or create SIP trunks. The SIP credentials stay in LiveKit and Twilio, while the Porch server needs its LiveKit API credentials, outbound trunk ID, and separate calling/caregiver codes. Endpoint checking also verifies caregiver authentication with an invalid destination; it never approves a phone number.

## Waitlist

Both forms post to `/api/waitlist`, which adds the email to MailerLite. The follow-up "who would use Porch?" answer is saved to the subscriber's `porch_who` custom field. Each request is also logged to the function logs as JSON (`waitlist_signup` / `waitlist_who`), but Vercel keeps those only briefly, so MailerLite is the record.

Set these env vars in Vercel:

- `MAILERLITE_API_KEY`: required to enable MailerLite
- `MAILERLITE_GROUP_ID`: optional group to add subscribers to

## Demo video

The demo video defaults to the v2 file on Vercel Blob. To use a different one, set `NEXT_PUBLIC_DEMO_VIDEO_URL` in Vercel to the new `.mp4` URL and redeploy. The value is built into the page, so changing it has no effect until the next deployment.
