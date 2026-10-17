# Incoming telephone calls

A regular phone can dial a household's Twilio number and ring its paired bedside iPad. The caller needs no Porch app. The call is always microphone-only. It requires Answer on the screen or the configured keypad call-control key, unless the caregiver approved the caller's number for [audio drop-in](#audio-drop-in-by-phone) and the caller's phone company verified that number. Caller ID by itself never grants drop-in or automatic answer.

Each household has its own number. Managed Redis stores `phone-number:<E.164 number>` with `{ householdID, bedsideID, trunkID }`. Routing uses the number dialed, not the caller's phone number. The initial setup reuses the existing Twilio outbound caller-ID number. It does not purchase or port a number. Multiple households can share the Porch backend and LiveKit project while their calls remain isolated.

## Call behavior

- With the updated app, microphone permission, and APNs configured, incoming calls can ring a backgrounded or locked bedside iPad through PushKit and Apple's CallKit screen. Open Porch once after installing the update to migrate its saved credential and register the bedside push token. Without push registration, keep Porch open and unlocked on the bedside clock. Foreground iPads poll every two seconds while idle and every second while ringing.
- The screen shows the caller's telephone number, or “Phone caller” when caller ID is unavailable. The number is display information, not authentication. There is no shared-number menu or caller recognition for routing.
- All callers reaching the assigned number can ring it; callers don't need to be paired app members. Calls require a manual answer, except [approved, verified drop-ins](#audio-drop-in-by-phone).
- Answer connects two-way audio. The camera stays off. Mute, keypad hangup, either person's hangup, and automatic silence hangup work with the existing call controls.
- A call reserves the same household slot as ordinary Porch calls and drop-ins. A second caller cannot interrupt or join the first call. Busy/unavailable callers are disconnected; this version has no voicemail or call waiting. The provider determines which tone/message they hear.
- LiveKit keeps the telephone caller ringing until the iPad joins and publishes audio. Ringing is limited to 45 seconds and the SIP call is limited to 30 minutes. Decline and room deletion release the telephone leg.
- Paired app calls and outbound phone fallback continue to use their existing flows. Existing family builds can decode the incoming audio call; the updated build adds faster ringing, telephone connection status, and confirmed phone hangup retries.

## Audio drop-in by phone

A caregiver can let specific phone numbers drop in with audio, the same way an approved family app can. When such a call arrives, the bedside iPad plays the chime, speaks the caregiver's name for that person, counts down five seconds with **Don't connect**, then connects two-way audio. The camera never turns on.

Approve a number in either place:

- **Family & drop-in → Audio drop-in by phone → Approve a phone number** (name, number, or **Choose from Contacts**). Approved numbers are listed there with **Remove**. Caregivers on approved family phones can also manage this list from caregiver mode.
- When editing a keypad person on the bedside iPad, turn on **Call their phone**, enter their number, then turn on **Drop-in by phone → Audio drop-in when they call**. **Save** approves that number under the person's name. Changing their number moves the approval to the new number in a single update. Removing their number, turning the switch off, removing the person, or giving their key a different action withdraws it. The keypad list shows **Phone drop-in on**.

Approving on the bedside iPad asks for microphone access. Approvals are stored per household, at most 20 numbers. Each phone drop-in needs all of these; otherwise the call rings for a normal answer:

1. **Allow approved drop-ins** is on.
2. The caller's number exactly matches an approved number. Withheld caller ID never matches.
3. Twilio's STIR/SHAKEN check on the call reports full attestation, `TN-Validation-Passed-A`. Partial (B/C) attestation, a failed check, diverted/forwarded calls, and calls with no carrier signature ring normally. Twilio performs this check only for US calls, and not every carrier signs. Most US mobile numbers calling directly get A attestation; many landlines, VoIP services and international numbers won't.
4. Porch is open and ready on the bedside clock. A backgrounded or locked iPad, or one in caregiver mode, never auto-answers: with push set up it rings through CallKit for a manual answer; otherwise Porch is unavailable, as for any phone call.

Why verification matters: caller ID is easy to fake. Without it, anyone who knew an approved number and the household's Porch number could open the microphone in the room. Twilio's verification is read from LiveKit's own record of the SIP participant, never from the webhook body. The header reaches LiveKit only on the restricted inbound trunk, which accepts SIP from Twilio's signaling gateways alone. This doesn't defend against a compromised carrier or a stolen phone. The spoken announcement and countdown are the last safeguard, and the caregiver should approve only people who are welcome to listen in without an answer.

Removing a number, or turning off **Allow approved drop-ins**, ends that phone drop-in immediately, whether it is still announcing or already connected, and hangs up the telephone leg. On an ordinary phone call the bedside screen shows the number, never a saved person's name, so a faked caller ID can't borrow a family member's name or photo. A verified drop-in shows the matching keypad person's name and photo, if there is one, or the approval's name.

## Configure the existing number

Deploy the server containing `POST /api/calls/inbound/webhook` before enabling provider routing. It uses the existing LiveKit API credentials and managed family Redis configuration. No new app secret is needed.

1. Obtain the intended household UUID from its family state or managed Redis. Confirm the household and its bedside member before assignment. A server operator assigns numbers; ordinary family credentials cannot assign or change them.
2. Load the managed store credentials into an ignored local env file if needed. For the linked calling project:

   ```sh
   vercel env pull .env.inbound-production.local --environment=production
   ```

   Vercel may omit Secret values when pulling. Keep the working LiveKit credentials in `.env.local`; the second `--env-file` below takes precedence. Never commit either file.

3. Run the read-only setup plan:

   ```sh
   node --env-file=.env.inbound-production.local --env-file=.env.local \
     scripts/configure-inbound.mjs --household=HOUSEHOLD_UUID
   ```

   With a single number on the existing Twilio outbound trunk, the script selects it automatically. Otherwise set `PORCH_INBOUND_NUMBER` privately to the intended number on that trunk. The plan verifies household ownership, existing trunks and dispatch rules, and refuses to reassign a number from another household.

4. Repeat with `--apply` to create the inbound trunk, configure Twilio SIP signaling source ranges, set 45-second ringing and a 30-minute SIP limit, map Twilio's `X-Twilio-VerStat` verification header to the `porch.callerVerification` participant attribute, create an individual dispatch rule with at most two participants, and persist the number assignment. A household configured before phone drop-in needs this `--apply` run once more for the header mapping; until then, every phone call rings for a normal answer. The script is safe to repeat for the same assignment; it does not overwrite unrelated trunks or routes. IDs and the selected number are saved privately in `.env.inbound-setup.local`.
5. In LiveKit Cloud → project Settings → Webhooks, add the calling server's public HTTPS endpoint:

   ```text
   https://YOUR-CALLING-SERVER/api/calls/inbound/webhook
   ```

   Select the API key matching the server's `LIVEKIT_API_KEY`. Preserve other existing webhook endpoints. This route validates LiveKit's JWT and body checksum. Do not put shared secrets in the URL, disable verification, or send webhooks to a login-protected preview.
6. Copy the project's **SIP URI** from LiveKit project settings. In Twilio → Elastic SIP Trunking → the existing trunk → **Origination**, add this URI with TCP transport:

   ```text
   sip:YOUR-PROJECT.sip.livekit.cloud;transport=tcp
   ```

   Set it enabled, with priority 1 and weight 1 if this is the only origination destination. Keep the existing Termination and credentials. Confirm the existing voice number is associated with this trunk. Use the SIP URI shown by LiveKit, rather than the app's WebSocket URL.
7. Install the updated app, open the bedside clock, and place a real test call from another phone. Twilio account/trial restrictions and provider charges still apply.

The Twilio SIP signaling CIDRs in the script come from [Twilio's official gateway list](https://www.twilio.com/docs/sip-trunking/ip-addresses); review them if the provider changes its network. Twilio Elastic SIP Trunking origination does not support the outbound trunk's username/password authentication, so this trunk restricts SIP sources by IP instead. See [LiveKit's Twilio setup](https://docs.livekit.io/telephony/start/providers/twilio/) and [inbound authentication](https://docs.livekit.io/telephony/accepting-calls/inbound-trunk/).

## Delivery and cleanup

The dispatch rule creates a unique `porch-inbound-…` room for each call. LiveKit's signed `participant_joined` webhook identifies the SIP caller and dialed number. Porch verifies the participant against LiveKit, looks up the number assignment, and atomically reserves the household if its bedside device is foreground-ready or has a registered VoIP token with APNs configured. One atomic delivery claim per SIP room prevents duplicate webhooks from sending repeated pushes. A failed push releases an unreachable telephone leg, while an authenticated receipt or answer preserves the call. Invalid-token removal preserves a newer registration.

CallKit owns ordinary incoming calls in both device modes. Its application-level session answers while locked, keeps audio connected in the background, and polls for caller hangup. The foreground bedside screen retains touch and keypad Answer/Decline; active calls retain keypad hangup/camera controls and configured silence disconnection. Telephone calls never enable the camera, and require explicit acceptance unless they are approved, verified drop-ins. Backgrounding an ordinary incoming call leaves CallKit ringing. Drop-in, including phone drop-in, continues to require a foreground bedside announcement and consent window; it never sends a push or auto-answers while locked. See [APNs setup](INCOMING-CALLS.md).

The telephone leg never becomes a fake paired device or needs a device heartbeat. Only the actual bedside member can accept and obtain a room-scoped, microphone-only token. SIP connection details remain server-side. Phone calls cannot use the outbound fallback action or inherit a paired member's drop-in permissions; phone drop-in uses its own per-number approvals.

Signed participant-left and room-finished webhooks end the call and delete the SIP room. Terminal markers and session IDs prevent duplicate, delayed, and reordered delivery from reviving calls or ending a newer call. A five-second participant reconciliation during signaling recovers missed hangup events; Answer and Join check the caller immediately. API outages return retryable errors rather than being mistaken for a hangup. Failed room cleanup remains retryable. The updated active-call screen retries remote phone hangup and offers “Retry ending phone call” if confirmation fails.

## Verification

Automated tests never dial a real number:

```sh
npm test
npm run typecheck
npm run build
swift test --package-path ios/PorchCore
xcodebuild -project ios/Porch.xcodeproj -scheme Porch \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- build
```

Before relying on the feature, test with the bedside iPad and a real phone:

- Dial the assigned number, hear ringing, answer by touch and by the keypad, and verify two-way audio with the camera off.
- Hang up from each end, decline, ignore for 45 seconds, cancel before the iPad answers, and retry immediately afterward.
- Call during an existing Porch call, during outbound phone fallback, and from two phones at once. Only one conversation may reach the bedside device, with no audio shared across calls.
- Open the updated app once, allow microphone access, then background Porch and dial the number. Repeat with the iPad locked; answer without unlocking and verify two-way audio, system mute/hangup, foreground keypad controls, and audio continuing after another lock.
- Cancel before answer, ignore the call, decline from the lock screen, disconnect Wi-Fi, restore it, and call again. Test Focus/Do Not Disturb, a cold launch after unlocking once since reboot, and production TestFlight push delivery. Record deliberate force-quit behavior on hardware; simulator tests cannot prove APNs wakeup or ringing.
- Verify caller ID withheld, microphone permission denied, mute, speaker/Bluetooth output, and automatic silence hangup.
- Phone drop-in: approve a US mobile number, turn on **Allow approved drop-ins**, and call from that phone with Porch open. Confirm the chime, spoken name and countdown, then two-way audio with no Answer. Repeat with **Don't connect** and the keypad stop key, with drop-ins paused, after removing the number, with the iPad locked (it should ring normally), and from an unapproved number and a landline or VoIP number (they should ring normally). Remove the number or pause drop-ins during a connected call; it should hang up. If an approved mobile never drops in, check that the inbound trunk has the `X-Twilio-VerStat` mapping and inspect the SIP participant's `porch.callerVerification` attribute in LiveKit. Some carriers don't sign calls.
- Test the configured 30-minute SIP limit. Inspect LiveKit and Twilio logs for failed provider routing; never paste credentials or private call payloads into public logs.

To disable inbound calling, disable its Twilio Origination destination. Outbound Termination can remain enabled. Number assignments and per-call state are scoped to the configured Redis namespace; keep preview/test namespaces separate from production.
