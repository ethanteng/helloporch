# Incoming telephone calls

A regular phone can dial a household's Twilio number and ring its paired bedside iPad. The caller needs no Porch app. The call is always microphone-only. It requires Answer on the screen or the configured keypad call-control key, unless the caregiver approved the caller's number for [audio drop-in](#audio-drop-in-by-phone) and the caller's phone company verified that number. Caller ID by itself never grants drop-in or automatic answer.

Each household has its own number. Managed Redis stores `phone-number:<E.164 number>` with `{ householdID, bedsideID, trunkID }`. Routing uses the number dialed, not the caller's phone number. The initial setup reuses the existing Twilio outbound caller-ID number. It does not purchase or port a number. Multiple households can share the Porch backend and LiveKit project while their calls remain isolated.

## Call behavior

- With the updated app, microphone permission, and APNs configured, incoming calls can ring a backgrounded or locked bedside iPad through PushKit and Apple's CallKit screen. Open Porch once after installing the update to migrate its saved credential and register the bedside push token. Without push registration, keep Porch open and unlocked on the bedside clock. Foreground iPads poll every two seconds while idle and every second while ringing.
- The screen shows the caller's telephone number, or “Phone caller” when caller ID is unavailable. The number is display information, not authentication. There is no shared-number menu or caller recognition for routing.
- All callers reaching the assigned number can ring it; callers don't need to be paired app members. Calls require a manual answer, except [approved, verified drop-ins](#audio-drop-in-by-phone).
- Answer connects two-way audio. The camera stays off. Mute, keypad hangup, either person's hangup, and automatic silence hangup work with the existing call controls.
- A call reserves the same household slot as ordinary Porch calls and drop-ins. A second caller cannot interrupt or join the first call. There is no call waiting. With [voicemail](#voicemail) set up, callers who aren't answered, are declined, or find Porch busy or offline can leave a message. Without it they are disconnected, and the provider decides which tone or message they hear.
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

   With a single number on the existing Twilio outbound trunk, the script selects it automatically. Otherwise set `PORCH_INBOUND_NUMBER` privately to the intended number on that trunk. The plan names the bedside the number will ring, for example: Calls to this number will ring the bedside “Grandma”. Check that name before `--apply`, because household IDs are hard to tell apart. It also verifies existing trunks and dispatch rules, and refuses to take a number from another household unless you [reassign it](#move-a-number-to-another-household).

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

### Move a number to another household

Each number rings exactly one bedside. To move it, for example after setting up a second iPad, run the script for the household that should get the calls and add `--reassign`. Without that flag the plan stops and says which bedside the number rings now.

```sh
node --env-file=.env.inbound-production.local --env-file=.env.local \
  scripts/configure-inbound.mjs --household=NEW_HOUSEHOLD_UUID --reassign
```

The plan names both bedsides, for example: calls to this number will ring the bedside “Grandma” instead of “Grandpa”. Repeat with `--apply` to rename the LiveKit trunk and dispatch rule and swap the number's route in one atomic update. Twilio and the trunk's login stay the same, so there's nothing to change in the Twilio Console. Voicemail and messages already left stay with the old household. Call the number afterwards and check that the new bedside rings.

## Voicemail

Voicemail uses a Twilio **voice webhook** for the number instead of Elastic SIP Trunking origination. Twilio runs Porch's instructions for each call:

1. `POST /api/calls/inbound/voice` dials LiveKit (`<Dial><Sip>`) with a digest login. LiveKit rings the bedside exactly as before, and the caller hears ringing until Porch answers.
2. If the call isn't answered within 45 seconds, is declined, or Porch is busy or offline, Twilio asks `/api/calls/inbound/voice/dialed` what to do next. If messages are on and the queue has room, Porch plays a short English greeting and a beep, then records for up to two minutes. Silence for 5 seconds or `#` ends the recording.
3. When the recording is ready, Twilio calls `/api/calls/inbound/voice/recording`. The server downloads the MP3 and stores it in the private Blob store. It then **deletes Twilio's copy**, so the recording isn't kept at the phone provider.

The voicemail then waits for review:

- **Held for review.** Every phone voicemail starts out held. If the caller's number is saved on one of the bedside keypad contacts **and** the phone company verified the caller ID (STIR/SHAKEN `TN-Validation-Passed-A`, the same check as phone drop-in), the bedside iPad releases it and it plays like any other message, announced with that contact's name. Caller ID alone is easy to fake, so an unverified call from a saved number is held and announced by number. Otherwise an approved caregiver has to listen first and choose **Let it play on Porch** or **Remove**, either on the iPad (Family & drop-in → Review waiting messages) or from their phone. Caregivers' phones show "phone voicemail needs your review" on the home screen. Withheld numbers always need a caregiver.
- **Limits.** Held voicemail expires after a week like any other message. Each number can have 3 voicemails waiting, at most 10 can be held at once, and the queue holds 30. When voicemail is off or full, callers hear "please try again later".
- **Phone drop-in keeps working.** Twilio reports its STIR/SHAKEN result to the webhook as `StirVerstat`. The server forwards it to LiveKit as `X-Porch-VerStat`, and in voicemail mode the setup script maps that header (instead of `X-Twilio-VerStat`) to `porch.callerVerification`. Only the server can reach the trunk with the digest login, so callers can't set it themselves. Declining a phone drop-in with **Don't connect** sends the caller to voicemail.
- **Security.** Webhooks are accepted only when the `X-Twilio-Signature` matches the account's auth token and the request names the configured account. The SIP digest password is derived from `LIVEKIT_API_SECRET`, so no extra secret is stored. Rotating the LiveKit secret means re-running the setup script.

### Turn on voicemail

1. In Vercel → the calling project → Settings → Environment Variables (Production), add:
   - `TWILIO_ACCOUNT_SID` and `TWILIO_AUTH_TOKEN`, from Twilio Console → Account info. Mark both sensitive.
   - `LIVEKIT_SIP_URI`, the project's SIP URI from LiveKit Cloud → Settings, for example `sip:abc123.sip.livekit.cloud`.

   Messages must already be set up (`BLOB_READ_WRITE_TOKEN`). Redeploy.
2. Switch the LiveKit inbound trunk to the digest login:

   ```sh
   node --env-file=.env.inbound-production.local --env-file=.env.local \
     scripts/configure-inbound.mjs --household=HOUSEHOLD_UUID --voicemail --apply
   ```

   This replaces the Twilio IP allowlist with the login, because Twilio doesn't publish the addresses its voice webhook dials from. Once a trunk has the login, later runs keep it.
3. In Twilio → Elastic SIP Trunking → the existing trunk → **Numbers**, remove the Porch number. Keep the trunk itself and its Termination settings: outbound phone calls still use them, and a number on your account remains a valid caller ID. Then go to Phone Numbers → the number → **Voice configuration** and set "A call comes in" to **Webhook**, `https://YOUR-CALLING-SERVER/api/calls/inbound/voice`, HTTP POST.
4. Test from a phone that isn't saved on the keypad. Let it ring out, leave a message, approve it from caregiver mode, and check that it plays on the iPad. Then test from a saved contact's phone, whose voicemail should play without approval. Also place an outbound phone-fallback call to confirm outbound calling still works.

Between steps 2 and 3, incoming calls on the old routing fail, so do them together. To turn voicemail off again, point the number's voice webhook somewhere else or turn off messages in caregiver mode. Callers then hear "please try again later" when no one answers.

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

To disable inbound calling, disable its Twilio Origination destination, or with voicemail, remove the number's voice webhook. Outbound Termination can remain enabled. Number assignments and per-call state are scoped to the configured Redis namespace; keep preview/test namespaces separate from production.
