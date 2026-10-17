# Bedside and family beta

One universal Porch app supports iPad bedside mode and iPhone/iPad family mode. iPhones start in family mode; iPads keep the bedside clock. Change modes from caregiver settings, the family screen's **gear → Use as the bedside Porch**, or (on a device that isn't set up as a bedside yet) **Use this device as a family member** on the bedside setup screen. Each mode keeps its own device pairing, so switching never removes your family pairing.

## Pair your family

1. Install the same updated TestFlight build on Mom's iPad and family members' iPhones.
2. On the iPad, tap the **gear** (a half-second hold works too). On first caregiver entry, choose and confirm your own six-digit PIN. An already-paired iPad needs no preset code. An older installation can enroll using its saved credentials. A brand-new bedside device uses a private activation link as described below. The initial display name is **Your loved one**; edit it in **Family & drop-in → Display name**.
3. Choose a keypad slot under **Keypad · people & controls**, keep **Person** selected, enter their name, and choose **Default calling mode → Voice-only / Video**. Choose **Invite them**, then select audio and/or video drop-in if appropriate. Both drop-in permissions start off. Porch asks for the corresponding iPad media permissions during setup. You can also invite a device from **Family & drop-in** without assigning a keypad slot.
4. Share the private invitation using the system share sheet. The recipient opens it on their iPhone or pastes it into **Invitation → Join your family**. Invitations expire after 15 minutes and work for one device. Invite each additional device separately.
5. On the iPad, turn on **Allow approved drop-ins**. Return to the clock. The family member can now make audio/video calls or use the drop-in types you approved.
6. After sharing, tap **Done**, then **Save** the person. The editor shows **Waiting to accept invite**. Acceptance links that exact invitation to the saved person automatically; there is no additional linking step. Expired/cancelled invitations can be sent again. For a device already in your Porch, use **Choose from your Porch**. Optionally add a fallback phone number. Contacts imports and typed numbers are normalized to E.164 (for example, `(415) 867-6937` in the US becomes `+14158676937`). National numbers use the device's region; include `+country code` for overseas contacts. Extensions aren't supported.

Paired calls use the bundled server address and private device credentials. Family members never enter a server address or shared calling code; only family members approved for caregiver mode enter the caregiver PIN. Contacts have one combined details section with their name, Contacts import, audio/video preference and paired app. The app no longer offers calling-method, room, advanced-connection or daily-use settings. The browser prototype remains available for legacy manual-room testing.

## Caregiver mode from a family phone

The caregiver can approve family members to manage access from their own phone. Turn on **Caregiver mode** when creating their invitation, or later for an existing device in **Family & drop-in**. An approved family member opens **gear → Caregiver mode** on their phone and enters the household's six-digit caregiver PIN. Tap **Family mode** to return.

From a phone, caregiver mode covers the settings the server holds: the display name, drop-in on/off, each device's audio/video drop-in and caregiver access, phone numbers approved for audio drop-in, invitations, and removing devices. Keypad numbers, contacts, photos, call preferences, the bedside display and the caregiver PIN can only be changed on the bedside iPad, which keeps its own copy of the PIN to renew phone-fallback approvals. Drop-ins enabled from a phone connect only if the bedside iPad already allows microphone and camera access.

The PIN is kept in the phone's memory only. Caregiver mode locks after ten idle minutes, when Porch leaves the foreground, or when the PIN or approval changes. Wrong PINs from a phone count against that phone alone (five per 15 minutes), so they can't lock out the bedside iPad. A caregiver can't remove their own phone or change their own caregiver access; another caregiver or the bedside iPad can.

To move a phone to a different family, open **gear → Join a different family** and use the new family's invitation. The phone stays in its current family until the new invitation is accepted, then leaves the old one automatically.

## Messages and voicemail

Family members can send an audio or video message (up to two minutes) from **Send a message** on their Porch screen. When a call isn't answered, or the bedside Porch isn't available, the family app offers **Leave a message**: it beeps and records audio, like voicemail. On the bedside iPad, **Call preferences → Ring before voicemail** sets how long a call rings first, from 15 seconds to 2 minutes (45 seconds by default). The same wait applies to regular phone callers; family phones need the updated app to follow it, and older builds keep ringing for 45 seconds. Messages don't need the bedside iPad to be open; they wait until played.

On the bedside clock, a **Play 2 messages** notice appears at the top left once messages have downloaded. Tapping it plays them oldest first: a chime, then "Message from Ethan. Sent today at 2:14 PM" in the bedside language and voice, then the message. For a video message, a banner at the top ("Message from Ethan · Sent Today at 2:14 PM") stays on screen while the video plays. Playback continues until none are left. **Stop**, the keypad's messages key or the hang-up key stops it, and an incoming call or drop-in takes over. A message stopped partway stays in the queue; one played to the end is removed and won't play again. To give the messages notice a key, edit any keypad number in caregiver mode and choose **Messages**.

Senders see only their own messages, under **Your messages**: waiting to download, on their Porch (not played yet), played (with the time), expired (not played within a week), removed by a caregiver, or unsent. They can unsend a message before it plays, and play back their own message (**Watch again** / **Listen again**) for as long as the recording is kept: while it waits, and for 90 days after it's played. Video messages show a preview frame, kept on the phone after the first view.

In **Family & drop-in → Messages**, caregivers (on the iPad, or from an approved phone with the PIN) can turn messages off, and preview or remove any waiting message. Removing a family member's access also removes their unplayed messages.

People calling the Porch phone number from a regular phone can leave voicemail too (setup: [incoming phone calls](INBOUND-PHONE-CALLS.md#voicemail)). If the caller's number is saved on a bedside keypad contact and the phone company verified the caller ID, it plays like any other message, announced with that contact's name. Caller ID can be faked, so unverified calls always wait for a caregiver. Otherwise it waits for a caregiver: approved caregivers see "phone voicemail needs your review" on their Porch screen, and **Let it play on Porch** or **Remove** in the waiting list.

## How calls behave

- Keep the bedside iPad open, unlocked and ready. With [APNs and Apple signing configured](INCOMING-CALLS.md), ordinary calls to paired family iPhones ring through CallKit while Porch is backgrounded, suspended, or the phone is locked. Open Porch once after installing/updating and allow microphone access to register. The family home screen reports whether background delivery is configured. Caregiver and pairing screens never auto-answer. Incoming family audio can continue behind the lock screen; outgoing and bedside/drop-in calls still need the app open.
- Ordinary incoming calls on family devices use the system **Answer** and **Decline** controls. Answering starts audio; for video, unlock/open Porch and tap **Camera on**. Locking or leaving Porch turns the camera off while incoming audio continues. Bedside incoming calls ring repeatedly and show **Answer** and **Decline**. Drop-ins play a chime and speak the caller's name and audio/video mode, then start the five-second countdown with a **Don't connect** button before answering automatically. If playback or speech fails, the call waits for manual acceptance instead of silently auto-answering. An audio drop-in never enables the camera. A short chime confirms connection or turning video on.
- Incoming names follow the caregiver's saved keypad contact on the bedside iPad, including spoken announcements and the active call screen. Renaming Ethan to David takes effect without a new invite. Matching uses the paired device/invitation ID, so two people with the same name don't become linked. An approved caller without a slot keeps the caregiver-assigned invitation name.
- Drop-in needs both the master switch and that device's specific audio/video approval. Pause drop-ins, change permissions, cancel unused invitations or remove a family device in **Family & drop-in**. Removing access ends its current call and requires a new invitation to reconnect.
- People without the app can drop in with audio by calling the household's Porch phone number, if the caregiver approves their number under **Family & drop-in → Audio drop-in by phone**, or with **Drop-in by phone** when editing a keypad person. These calls get the same announcement and countdown. They drop in only while the master switch is on, the bedside clock is open, and their phone company verifies the caller ID. Other calls ring for a normal answer. See [inbound telephone calls](INBOUND-PHONE-CALLS.md#audio-drop-in-by-phone).
- Mom's outgoing calls try Porch first. An unavailable family app or an unanswered call can fall back to its configured regular phone number. The wait remains configurable under **Call preferences**. Porch's answer and the phone handoff are coordinated atomically so an answered Porch call doesn't also dial the phone. Ringback plays during both dialing stages.
- Only one Porch call can be active per household. Foreground presence and call state are checked every few seconds; family background ringing uses a VoIP push followed by authenticated call-state checks. Decline, hangup, expiry or lost-device heartbeats release the call. Calls are limited to 30 minutes; phone fallback retains its shorter server limits.

## Keypad actions

There are ten stable slots, in telephone order **1–9, 0**. Existing six-person setups keep their assignments; **7 and 8** start empty, **9** initially toggles video, and **0** initially controls calls. Edit any slot to choose **Person**, **Call control**, or **Video toggle**. All ten slots can call people if reassigned, and any digit can be a control. Touch controls remain available even if no keypad controls are assigned.

For the call-control key: tap and release to answer an ordinary incoming call; hold one second to decline it. Tap to stop a drop-in during its announcement, or to hang up an active/dialing call, including phone fallback. The video key toggles your camera during a video call; voice-only and regular phone calls keep it off. Holding a digit does not repeatedly trigger it. Keys work while Porch is foregrounded; caregiver text fields continue to accept typing.

## Typing in caregiver settings

The native iPad/iPhone keyboard is the default. Connecting or disconnecting a USB/Bluetooth keypad doesn't change that choice. **Porch keyboard** opens the optional built-in touch keyboard. Switching keeps the text already entered.

iPadOS can hide its software keyboard when an external keypad is attached, and its system keyboard controls may also be absent. **Disconnect the keypad during setup to use the native keyboard**, or choose **Porch keyboard** to keep the keypad connected. With a keypad connected, the native-keyboard button is labeled **Keyboard help** and explains these choices. It does not promise to force the system keyboard open. Opening help from the Porch keyboard keeps that input method selected until you choose another option.

If the system Shortcuts bar is available, its keyboard button → **Show Keyboard** is another option, as described in [Apple's keyboard guide](https://support.apple.com/en-euro/guide/ipad/ipaddd28d7ed/27/ipados/27). Porch preserves the system assistant controls, but cannot guarantee that iPadOS displays them. In Guided Access, keep **Touch** and **Software Keyboards** enabled during setup; these controls are in **Session Settings** (or **Options**) when the session is paused. See [Apple's Guided Access instructions](https://support.apple.com/en-nz/111795).

## Bedside display

Open **Caregiver mode → Bedside display** and choose **Default** (the dark clock) or **Dynamic**. **Both always show the current local date and time in large text.** Dynamic adds the time-of-day and season in words, a sun or moon traveling across the sky, and a seasonal tree and landscape. The background brightens through the morning to a blue daytime sky, warms to peach and pink near sunset, and darkens to navy at night. The large clock uses dark lettering on a light wash by day and light lettering on a dark wash at night, keeping the current date and time readable throughout the cycle. The scene updates each minute with a short dissolve; Reduce Motion removes that dissolve. There is no perpetual decorative animation, location request, or external weather service.

Set **Day begins** and **Night begins** to match the loved one's routine (initially 6 AM and 6 PM). The scene illustrates that schedule, rather than calculating astronomical sunrise/sunset or moon phase. Seasons use calendar months and the chosen **Northern / Southern** hemisphere (initially northern). Keep the iPad's date, time, and time zone correct in system settings.

Choose a language under **Bedside language** and tap **Save** to translate the clock/date, day/night and seasons, contact picker, incoming calls and call controls.

| Option | Display language | Drop-in announcement voice |
| --- | --- | --- |
| English | English | English (`en-US`) |
| 繁體中文 | Traditional Chinese | Taiwan Mandarin (`zh-TW`) |
| 简体中文 | Simplified Chinese | Mainland Mandarin (`zh-CN`) |
| 廣東話 | Cantonese in Traditional characters | Cantonese (`zh-HK`) |
| Español | Spanish | Spanish (`es-ES`) |

English remains the default; caregiver settings and family mode stay in English. Names stay exactly as entered by the caregiver. Language changes preserve the daily schedule, hemisphere, contacts and pairing. The contact picker uses much larger names and keypad numbers, with wrapping text and no phone icon; scroll to reach additional people.

Under **Announcement voice** on the same screen, choose **System default** or a voice available on this iPad for the selected bedside language. English and Spanish include regional accents. Taiwan Mandarin, mainland Mandarin and Cantonese each show their own matching voices; a voice cannot be used across all five languages. On iPadOS 17 and later, novelty voices such as Bubbles or Zarvox are not listed. Voice names include the locale and, when available, Enhanced or Premium quality. Each language remembers its own choice on this device. **Preview announcement** plays the current selection without saving or placing a call; tap **Save** to keep it. Leaving without saving discards changes.

To add voices, download them in the iPad's Accessibility speech settings and return to Porch. Availability varies with iPadOS and downloaded voices. If a saved voice is removed or no longer matches the language, Porch uses that language's system default and shows a message in the picker. If no matching voice can play, drop-ins require manual acceptance.

In **Call preferences**, use **Test ringing** and **Test video announcement** before relying on drop-in. These play only on this device and do not place a call. The screen reports the current audio output and media volume. Turn up media volume with the physical volume buttons and verify that sound reaches the intended iPad speaker or connected audio device. Alerts explicitly acquire a playback session shared with LiveKit; they do not depend on a one-shot system notification sound. A voice for the selected language must be available for spoken announcements. If speech cannot play, the call requires manual acceptance. Zero volume, connected headphones, or system interruptions can still make audio inaudible; check the actual bedside iPad.

## Caregiver PIN

The first caregiver entry prompts you to choose and confirm a PIN. Later entries ask for that PIN. Tap the gear or hold it for half a second. Change the PIN under **Family & drop-in → Change caregiver PIN**. Five incorrect guesses cause a 15-minute lockout for that household. Internet access is required to unlock settings.

The server stores only a salted PIN digest, using the server secret as a pepper. The original long `PORCH_CONTACT_SETUP_CODE` remains server-side for recovery and signing phone approvals. **Do not replace that environment variable with six digits.** Existing device phone approvals survive a PIN change. Other households have independent PINs and attempt limits.

## A completely new bedside iPad

A server operator creates a private, one-use activation link. This authorizes enrollment without shipping a shared secret inside the app or accepting anonymous registrations to the calling service.

```sh
node --env-file=.env.local scripts/create-bedside-invite.mjs
```

The command reads the server's long recovery secret privately and writes `.env.bedside-activation.local` with mode 0600. It never prints the activation URL or PIN. Open the link on the new iPad, or paste it into the first caregiver setup screen. Choose the bedside name, choose and confirm a PIN, and continue. Links work for one device, expire after 24 hours and support a retry on the same device after a lost response. Each additional household gets its own PIN. There is no generated/default caregiver PIN file in the new setup flow. Keep activation links private; family recipients use separate family invitations.

Existing paired devices choose a PIN once without a new activation link. After that, changing it requires the current PIN. Legacy shared PINs are accepted only as a compatibility fallback for households that haven't chosen their own PIN yet; a household-specific PIN supersedes that fallback. Keep the long server recovery/signing secret for operator recovery and existing phone approvals.

## Server and privacy

Keep the LiveKit/SIP settings and long signing/recovery secret from the root setup guide. For messages, create a **private** Vercel Blob store and connect it to the calling server project, which adds `BLOB_READ_WRITE_TOKEN`; then redeploy. Without it, sending a message reports that messages aren't set up. For incoming iPhone calls, configure the APNs signing key and app ID as described in [incoming-call setup](INCOMING-CALLS.md). Connect Upstash Redis and provide either `UPSTASH_REDIS_REST_URL`/`UPSTASH_REDIS_REST_TOKEN` or Vercel's `KV_REST_API_URL`/`KV_REST_API_TOKEN` aliases. The free database was provisioned with automatic paid upgrades disabled. Deploy the new server before using the new app; older manual-room builds remain compatible.

The default data namespace is `porch:family:v1:`. Local verification must set an isolated `PORCH_FAMILY_STORE_PREFIX=porch:family:preview:v1:`. Redis CAS operations coordinate shared state across server instances. Storage outages fail closed; there is no process-memory fallback. Use TLS and keep write credentials server-side.

Redis stores household/display names, hashed device/invitation secrets, permissions, presence, the current call and hashed PIN/lockout state. It also keeps message records: each sender's history (type, length, sent/delivered/played times) and the bedside queue. Message audio and video are stored in the private Blob store; devices only receive signed upload/download links that expire within an hour. Unplayed messages are deleted after seven days; played messages' media is deleted after 90 days, while the record stays. The bedside iPad keeps downloaded messages until they're played or removed. Redis doesn't store full contact books or fallback numbers. It does store the phone numbers and names a caregiver approves for phone drop-in, which only the bedside and caregiver mode can see. Local slots remain on the device. Keychain stores private device credentials, caregiver credentials and scoped phone approvals. LiveKit handles media/connection metadata; SIP fallback sends its destination to LiveKit and the telephone provider. Calls aren't recorded; only messages people choose to record are stored. Transport encryption is used; application-level end-to-end encryption isn't configured. Update App Store privacy disclosures for this data handling before distributing the beta.

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

Physical-device acceptance: test all ten physical digits and remapped controls; tap/hold answer/decline and hangup during dialing/phone fallback; toggle the video camera; confirm the current date/time stay visible in both bedside views, landscape/portrait and Reduce Motion; accept an invite and confirm the saved person links after relaunch; pair and relaunch both devices; approve audio only and confirm video is unavailable; enable video and test both directions; stop/pause/revoke during a drop-in; leave the iPad in caregiver mode or background and verify it doesn't auto-answer; test caller cancellation during the countdown; test permission denial, network loss and concurrent callers; verify real microphone/camera, speaker routing, Guided Access, and phone fallback with your authorized test number.

Language/audio acceptance: repeat with 繁體中文, 简体中文, 廣東話 and Español. Save, relaunch and verify date/time and contact cards remain readable in both orientations; check names are unchanged and all call controls use the selected language. Confirm the language choice fits on a small phone and that changing it preserves the daily schedule and hemisphere. Rename a linked person, relaunch, then confirm ordinary calls and audio/video drop-ins show and announce the new name, including after answering. Run both local sound tests at the bedside. Verify repeating incoming ringing, audio/video announcements in the selected language (including Cantonese for 廣東話) followed by a full five-second countdown, cancellation during speech/countdown, the connection/video-on chime, and ringback during Porch and phone fallback. Simulator waveforms and injected-audio checks do not confirm physical speaker audibility.

Voice picker acceptance: for each of the five languages, check that only matching voices appear, preview an available choice, save and relaunch, then confirm **Call preferences → Test video announcement** and real audio/video drop-ins use that voice. Switch between languages and confirm each choice is remembered. Preview a different voice and leave without saving; the saved voice should remain. Confirm preview stops when switching language or leaving settings. Download a new matching voice in system settings, return, and confirm it appears. Remove a saved downloaded voice and verify the picker reports the fallback and announcements still use the correct language. Test on the bedside iPad's actual speakers, including Enhanced/Premium voices if installed.

Keyboard acceptance: with the keypad disconnected, tap name, phone and PIN fields and type with the native keyboard. Connect the physical keypad while editing; confirm native input remains selected even if iPadOS hides the software keyboard. Tap **Keyboard help** and verify its instructions, use **Porch keyboard** and type with the keypad connected, then disconnect the keypad and return to **iPad keyboard**. Confirm text and focus are preserved. Repeat with Guided Access enabled and on a family iPhone. Simulator input/focus checks do not prove physical keypad/software-keyboard compatibility.
