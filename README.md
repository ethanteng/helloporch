# HelloPorch

**Porch** is one-button video calling for people with dementia, Parkinson's or limited dexterity. An iPad by the bed shows a quiet clock and works with a large-button keypad. Each button is someone they love, and one press starts a call. Family answer on their phones in the Porch app, and anyone can reach the bedside from a regular phone by calling the household's own Porch number.

This repository holds the whole product: the website at [helloporch.store](https://helloporch.store), the calling server, and the iPhone and iPad app.

Porch is in a small private pilot. Families install it through TestFlight, and everyone else can join the waitlist on the website. See [Status](#status).

## What's here

| Path | What it is |
|---|---|
| `app/`, `components/`, `public/` | The Next.js 16 website, plus the calling server's API routes under `app/api/` |
| `lib/calls/`, `lib/family/` | Server logic: households, pairing, calls, messages, phone numbers, push and speech |
| `ios/` | The universal iOS and iPadOS app, the `PorchCore` Swift package and the Cell2Jack USB driver ([ios/README.md](ios/README.md)) |
| `scripts/` | Operator scripts for setup, number provisioning and checks |
| `tests/` | Node tests for the server |
| `.github/workflows/` | CI, the calling-server deploy and the TestFlight upload |

## What Porch does

**At the bedside.** The iPad starts as a clock, either the default one or a dynamic one that follows the day, night and seasons.

- **Keypad.** Twelve keys (0–9, * and #). Each one can call a person, answer or hang up, turn video on or off, play messages, or do nothing.
- **What drives it.** The keys work from a USB or Bluetooth number pad, a keyboard, the touchscreen, or a big-button photo phone connected through a Cell2Jack adapter. On that phone, putting the receiver back hangs up.
- **Calling out.** Pressing a key says who it's calling ("Calling David.") and rings that person's Porch app. If nobody answers, by default after 20 seconds, Porch rings their regular phone instead.
- **Answering.** Ordinary calls ring and wait for someone to answer. Family the caregiver approves can drop in with audio or video. The bedside announces them and counts down for five seconds, with a **Don't connect** button.
- **Messages.** Family send audio and video messages, which wait until they're played. They can play on their own when someone sits down, using on-device face detection. When a call from the bedside isn't answered, the bedside records a message for that person.
- **Languages.** English, Traditional Chinese, Simplified Chinese, Cantonese and Spanish, spoken with the iPad's own voices or natural ElevenLabs voices.

**For family**, on an iPhone or iPad in family mode:

- Private invitations and pairing, with no server addresses or codes to type.
- Calls ring through CallKit, even when the phone is locked.
- Send messages, and get a notification when the bedside leaves one.
- On a call with the bedside, ring in another family member with video. A caregiver can also add a regular phone number, such as a bank that needs the loved one on the line.

**For caregivers.** A six-digit PIN protects caregiver mode, which can also be opened remotely from an approved family phone. Caregivers set up the keypad, names and photos, and drop-in permissions. They also review call history and blocked callers.

**On the phone network.**

- **A number per household.** Households set up in the app get their own US number, bought from Twilio during setup.
- **Incoming calls.** Calls to that number ring the bedside, audio-only, for a manual answer. Numbers the caregiver approves can drop in with audio when the phone company verifies their caller ID.
- **Blocking and voicemail.** Unknown callers can be blocked; new households start with blocking on. Voicemail from regular phones is held for a caregiver, unless the caller is a verified keypad contact.
- **Outgoing caller ID.** Phone fallback and added phone numbers show the household's number, so calling back rings the bedside.

The [family setup guide](ios/FAMILY-SETUP.md) describes all of this in detail.

## How it fits together

- **The apps talk to the calling server.** Almost everything goes through `POST /api/family`, which handles setup, pairing, the PIN, calls, presence, messages, profiles, phone numbers and history.
- **Calls.** Live audio and video run on LiveKit Cloud. Phone calls in both directions go through LiveKit SIP and a Twilio Elastic SIP trunk, and Twilio voice webhooks handle voicemail.
- **Storage.** Household state lives in Upstash Redis. Photos, messages, recordings and cached speech go to a private Vercel Blob store.
- **Push and speech.** The server sends Apple push notifications (VoIP and alerts) directly over APNs. Speech comes from ElevenLabs and is cached.
- **Hosting.** This repo deploys to two Vercel projects: `helloporch`, the website at helloporch.store, and `porch-calling-prototype`, the calling server the apps use.

| Route | Purpose | Code |
|---|---|---|
| `POST /api/family` | Everything the apps do | `lib/family/service.ts` |
| `/api/calls/phone/{prepare,start,end}` | Phone fallback and dialing out | `lib/calls/phone.ts` |
| `/api/calls/contacts/authorize` | Signed approvals for phone contacts | `lib/calls/contacts.ts` |
| `/api/calls/inbound/webhook` | LiveKit SIP webhook for incoming calls | `lib/family/inbound.ts` |
| `/api/calls/inbound/voice/…` | Twilio voice and voicemail webhooks | `lib/family/voicemail.ts` |
| `GET /api/calls/health` | Release health check | `lib/calls/health.ts` |
| `/api/waitlist` | Website waitlist (MailerLite) | `app/api/waitlist/route.ts` |
| `/api/calls/token` | Legacy browser-call token (see [Legacy](#legacy)) | `lib/calls/server.ts` |

## Develop

### Website and server

Requires Node.js 24 or newer, the same version CI uses.

```sh
npm install
cp .env.example .env.local
npm run dev
```

The site runs at http://localhost:3000. Fill in only the services you need. Never put credentials in `NEXT_PUBLIC_` variables or in the app.

| Service | Variables |
|---|---|
| LiveKit | `LIVEKIT_URL`, `LIVEKIT_API_KEY`, `LIVEKIT_API_SECRET`, `LIVEKIT_SIP_OUTBOUND_TRUNK_ID`, `LIVEKIT_SIP_URI` |
| Upstash Redis | `UPSTASH_REDIS_REST_URL`, `UPSTASH_REDIS_REST_TOKEN` (or `KV_REST_API_URL`, `KV_REST_API_TOKEN`), optional `PORCH_FAMILY_STORE_PREFIX` |
| Vercel Blob | `BLOB_READ_WRITE_TOKEN` |
| Apple push | `APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_PRIVATE_KEY`, `APNS_BUNDLE_ID` |
| Twilio | `TWILIO_ACCOUNT_SID`, `TWILIO_AUTH_TOKEN` |
| Phone numbers | `PORCH_SERVER_ORIGIN`, `PORCH_MAX_PHONE_NUMBERS` (nothing is bought without it), optional `PORCH_INBOUND_NUMBER` |
| ElevenLabs | `ELEVENLABS_API_KEY` |
| Server secrets | `PORCH_CONTACT_SETUP_CODE` (signing and recovery secret), legacy `PORCH_CALL_ACCESS_CODE` and `PORCH_PHONE_NUMBERS` |
| Website | `MAILERLITE_API_KEY`, `MAILERLITE_GROUP_ID`, `NEXT_PUBLIC_DEMO_VIDEO_URL` |

To try the apps against a local server without real families, `scripts/seed-family-preview.mjs` creates sample devices in an isolated store prefix ([details](ios/FAMILY-SETUP.md#verify)).

### iPhone and iPad app

Open `ios/Porch.xcodeproj` in Xcode 26 or newer. The app runs on iOS and iPadOS 15 and later.

| Scheme | Use |
|---|---|
| `Porch` | The full app with the optional Cell2Jack USB driver. Bedside iPads that use Cell2Jack get this as a development build. |
| `PorchFamily` | The same app without the driver. This is the TestFlight build for family devices and touchscreen or number-pad bedsides. |
| `PorchCell2Jack`, `PorchCell2JackCalls`, `PorchKeypadPreview` | Earlier experiments and test fixtures. CI still runs some of their tests. |

See [ios/README.md](ios/README.md) for building, Debug preview flags, TestFlight and App Review. [ios/BUILD-VARIANTS.md](ios/BUILD-VARIANTS.md) explains which build goes where.

### Checks

```sh
npm test
npm run typecheck
npm run build
swift test --package-path ios/PorchCore
```

The Node tests use fake LiveKit and Twilio clients and never place real calls. UIKit and Cell2Jack tests run in Xcode or through the commands in [ios/README.md](ios/README.md#build-and-verify). Real microphone, camera, push, telephone and keypad behavior still needs testing on devices. See the [acceptance checks](ios/FAMILY-SETUP.md#verify).

## Release

| Workflow | When it runs | What it does |
|---|---|---|
| Calling server checks | Pushes and PRs that touch the server | `npm test`, typecheck and build |
| iPhone and iPad build | Pushes and PRs that touch `ios/` | Simulator builds, UIKit and Cell2Jack tests, and Release builds of both variants |
| Deploy calling server | Server changes merged to `main`, or before each TestFlight upload | Stages a production deployment, checks `/api/calls/health` for the expected commit, then promotes it |
| Upload Porch to TestFlight | Manually | Deploys the matching server, then builds and uploads the `family` (default) or `cell2jack` variant |

See [RELEASING.md](RELEASING.md) for setup and recovery.

## Operating

| Script | Purpose |
|---|---|
| `scripts/create-bedside-invite.mjs` | Make a one-use activation link for a new bedside iPad |
| `scripts/provision-number.mjs` | Give a household set up by hand a phone number, either an existing one or a newly bought one |
| `scripts/configure-inbound.mjs` | Plan or apply the LiveKit inbound trunk, dispatch rule and number route |
| `scripts/prepare-app-review.mjs` | Build the private access pack for Apple's App Review |
| `scripts/verify-calling-deployment.mjs` | The health and commit check CI runs on each deploy |
| `scripts/voice-samples.mjs` | Make a page for comparing ElevenLabs voices |
| `npm run calls:check` | Check LiveKit credentials and the outbound trunk, without calling anyone |

Setup guides:

- [Family setup](ios/FAMILY-SETUP.md): pairing, the caregiver PIN, messages, call behavior and verification.
- [Incoming calls](ios/INCOMING-CALLS.md): APNs and CallKit ringing on locked devices.
- [Incoming telephone calls](ios/INBOUND-PHONE-CALLS.md): per-household numbers, the inbound trunk, blocking and voicemail.
- [Cell2Jack and backup keypads](ios/CELL2JACK-CALLS.md): the USB driver, the photo phone and diagnostics.

Phone fallback needs a LiveKit outbound SIP trunk connected to Twilio, with its ID in `LIVEKIT_SIP_OUTBOUND_TRUNK_ID`. Follow LiveKit's [outbound trunk](https://docs.livekit.io/telephony/making-calls/outbound-trunk/) and [Twilio](https://docs.livekit.io/telephony/start/providers/twilio/) guides. Buying numbers automatically needs an upgraded Twilio account. Telephone, SIP and number charges apply.

## Website

The site at helloporch.store has the home page, [features](https://helloporch.store/features), the [pilot](https://helloporch.store/pilot) guide, the [story](https://helloporch.store/story) and the [privacy policy](https://helloporch.store/privacy).

- **Waitlist.** Both waitlist forms post to `/api/waitlist`, which adds the email to MailerLite. The follow-up "who would use Porch?" answer goes in the subscriber's `porch_who` field. Each request is also logged as JSON (`waitlist_signup` / `waitlist_who`), but Vercel keeps those logs only briefly, so MailerLite is the record.
- **Demo video.** It defaults to the v2 file on Vercel Blob. To change it, set `NEXT_PUBLIC_DEMO_VIDEO_URL` to the new `.mp4` URL and redeploy. The value is built into the page.
- **Analytics.** Google Analytics runs only on production deployments.

## Status

- **Pilot.** Families join by invitation. Bedsides that use Cell2Jack run development builds installed from a Mac, while family devices and other bedsides use TestFlight.
- **Waiting on Apple.** A TestFlight build with the Cell2Jack driver needs Apple's DriverKit USB entitlement, which was requested on 2026-10-18. App Review access is described in [ios/README.md](ios/README.md#app-review-access-and-resubmission).
- **Self-serve setup.** It's planned in [ONBOARDING-PLAN.md](ONBOARDING-PLAN.md). So far, only per-household phone numbers are built. Porch won't open to families beyond the pilot until Apple approves the driver.

## Legacy

The browser call page at `/call` and its token route, `/api/calls/token`, come from the original prototype. It joined manual LiveKit rooms with a shared `PORCH_CALL_ACCESS_CODE`. The current apps don't use either; they pair through invitations and call through `/api/family`. `npm run calls:check` still asks for that access code. Older builds may still need the `PORCH_PHONE_NUMBERS` allowlist for phone fallback.

## License

Copyright © 2026 Ethan Teng Consulting LLC. All rights reserved.

This is proprietary software. The repository is public so it can be viewed, but you get no license to use, copy, modify or distribute it. See [LICENSE](LICENSE). Third-party components keep their own licenses. The app lists the ones it includes in **Settings → Porch → Acknowledgements**.
