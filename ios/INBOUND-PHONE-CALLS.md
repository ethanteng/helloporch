# Incoming telephone calls

A regular phone can dial a household's Twilio number and ring its paired bedside iPad. The caller needs no Porch app. The call is always microphone-only and requires Answer on the screen or the configured keypad call-control key. Telephone caller ID never grants drop-in permission or automatic answer.

Each household has its own number. Managed Redis stores `phone-number:<E.164 number>` with `{ householdID, bedsideID, trunkID }`. Routing uses the number dialed, not the caller's phone number. The initial setup reuses the existing Twilio outbound caller-ID number. It does not purchase or port a number. Multiple households can share the Porch backend and LiveKit project while their calls remain isolated.

## Call behavior

- Keep Porch open and unlocked on the bedside iPad. Settings screens and backgrounded devices do not accept calls. Current iPads poll every two seconds while idle and every second while ringing or in a call.
- The screen shows the caller's telephone number, or “Phone caller” when caller ID is unavailable. The number is display information, not authentication. There is no shared-number menu or caller recognition for routing.
- All callers reaching the assigned number can ring it; this first version does not require callers to be paired app members. Every call requires a manual answer, even if Porch drop-in is enabled.
- Answer connects two-way audio. The camera stays off. Mute, keypad hangup, either person's hangup, and automatic silence hangup work with the existing call controls.
- A call reserves the same household slot as ordinary Porch calls and drop-ins. A second caller cannot interrupt or join the first call. Busy/unavailable callers are disconnected; this version has no voicemail or call waiting. The provider determines which tone/message they hear.
- LiveKit keeps the telephone caller ringing until the iPad joins and publishes audio. Ringing is limited to 45 seconds and the SIP call is limited to 30 minutes. Decline and room deletion release the telephone leg.
- Paired app calls and outbound phone fallback continue to use their existing flows. Existing family builds can decode the incoming audio call; the updated build adds faster ringing, telephone connection status, and confirmed phone hangup retries.

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

4. Repeat with `--apply` to create the inbound trunk, configure Twilio SIP signaling source ranges, set 45-second ringing and a 30-minute SIP limit, create an individual dispatch rule with at most two participants, and persist the number assignment. The script is safe to repeat for the same assignment; it does not overwrite unrelated trunks or routes. IDs and the selected number are saved privately in `.env.inbound-setup.local`.
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

The dispatch rule creates a unique `porch-inbound-…` room for each call. LiveKit's signed `participant_joined` webhook identifies the SIP caller and dialed number. Porch verifies the participant against LiveKit, looks up the number assignment, and atomically reserves the household if its bedside device is ready. The iPad's existing authenticated family polling delivers the call.

The telephone leg never becomes a fake paired device or needs a device heartbeat. Only the actual bedside member can accept and obtain a room-scoped, microphone-only token. SIP connection details remain server-side. Phone calls cannot use the outbound fallback action or inherit a paired member's drop-in permissions.

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
- Close Porch, lock the iPad, open caregiver settings, disconnect Wi-Fi, and restore it. Unavailable calls must end and later calls must work again.
- Verify caller ID withheld, microphone permission denied, mute, speaker/Bluetooth output, and automatic silence hangup.
- Test the configured 30-minute SIP limit. Inspect LiveKit and Twilio logs for failed provider routing; never paste credentials or private call payloads into public logs.

To disable inbound calling, disable its Twilio Origination destination. Outbound Termination can remain enabled. Number assignments and per-call state are scoped to the configured Redis namespace; keep preview/test namespaces separate from production.
