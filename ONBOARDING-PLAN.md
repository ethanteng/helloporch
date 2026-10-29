# Self-serve onboarding plan

A family you invite should be able to go from your private link to a working Porch on their own: a bedside iPad with its Cell2Jack phone and its own phone number, the caregiver's phone paired, and their relatives invited. Drafted 2026-10-24, with the decisions below folded in the same day. Nothing here is built yet.

## Requirements

- **No families beyond ours until Apple approves the Cell2Jack driver** for distribution (requested 2026-10-18). Everything else can be built and tried on our own family before then. Inviting other families waits for the approval.
- **Families are invited privately.** You invite each one; nobody signs up on the website. Open sign-up is a possible later step, not part of this plan's first phase.
- Little to no manual work for you per family: making an invitation takes a few clicks on the admin page. No scripts, consoles or per-family configuration.
- Families never create accounts with Twilio or any other service.
- **Every household gets its own Porch phone number**, set up automatically during setup. It isn't optional, and it stays until the household is deleted.
- **You are the global administrator,** on a protected admin page on the web that you use from a computer. From it you invite families, see every Porch, and can delete one. The phone app has nothing for the administrator.
- Purchases and paid vs free are out of scope for now.
- **US only at launch:** families, their Porch numbers and the area-code search. Calls out to Canadian numbers keep working, as phone guests allow today.

## Decisions

Settled on 2026-10-24.

| Question | Decision |
| --- | --- |
| Cell2Jack for every family | Part of setup, with **Do this later** for families still waiting on hardware. The touchscreen works meanwhile, and the checklist reminds them |
| Invitation lifetime | 14 days |
| TestFlight builds after the driver is approved | One `Porch` build with the driver for every device; `PorchFamily` retires |
| Offline households | Keep the number until a caregiver or the administrator deletes the household. Nothing is deleted or released automatically |
| Administration | A protected admin page at `admin.helloporch.store`, signed in with a passkey, for use from a computer. Nothing for the administrator in the phone app |
| Keypad backup | Yes. The bedside keeps a copy of its keypad and settings on the server, restored on a replacement iPad (phase 6) |
| Unknown callers | Blocked by default on new households |
| Area code | Suggested from the iPad's location, and can be changed |
| QR code to add the caregiver's phone | Yes |
| Countries | US only at launch |
| Hainie's phone routing | Stays on its own trunk |
| Mom's current number | Hainie keeps it for good. The app can never buy Hainie a new number, and Porch never releases a number it didn't buy itself |

## What needs you today

| Step | Today | After this plan |
| --- | --- | --- |
| Create a household | `scripts/create-bedside-invite.mjs` makes a one-use activation link with the recovery secret ([service.ts:160](lib/family/service.ts:160)) | You click **Invite a new family** on the admin page and send the link |
| Get Porch onto the bedside iPad | Mom's iPad gets development builds from the Mac, because TestFlight builds can't include the Cell2Jack driver | One TestFlight build with the driver, for every device |
| Phone number | Buy it, run `scripts/configure-inbound.mjs`, set the Twilio voice webhook and LiveKit by hand | Bought and routed during setup |
| Get Porch onto relatives' phones | Invites are `porch://pair?…` links, which do nothing without the app, so the TestFlight link goes out separately | Invites are `https://helloporch.store/join#…` links that open Porch or explain how to get it |
| Replace a bedside iPad, forgotten PIN, delete a household | Not possible without you | Caregivers do it from their phone or the iPad. You can also do each of them from the admin page |

Problems that appear as soon as there's a second real family:

- **Every household calls out from Hainie's number.** Phone fallback and phone guests dial through the one outbound trunk without a `fromNumber` ([phone.ts:131](lib/calls/phone.ts:131), [phone-guests.ts:146](lib/family/phone-guests.ts:146)), so the trunk's number, Hainie's, is the caller ID for everyone. A callback rings Mom's iPad.
- **Phone fallback dials anywhere.** It approves any E.164 number worldwide ([contacts.ts:46](lib/calls/contacts.ts:46)); only Twilio's geographic permissions stop it. The ElevenLabs allowance is per household, with no overall ceiling. Invited families are trusted, but a mistake still costs money.
- **No deletion.** A family that stops using Porch can't remove its data or release its number. App Store guideline 5.1.1(v) will also require in-app deletion, because a household counts as an account.

## What everyone experiences

**You**, on a computer: `https://admin.helloporch.store`, signed in with your passkey (Touch ID on the Mac).

- **Invite a new family:** type who it's for, such as "Lee family". The page shows the link with **Copy link** and **Copy message**: "Here's your private link to set up Porch. Open it on the iPad that will stay with your loved one: https://helloporch.store/setup#…". Send it by text or email.
- **Invitations:** each shows as waiting, set up, expired or cancelled.
- **Porches:** every household, ours included. Each shows its bedside name, Porch number, when it was set up, when the bedside was last seen, and "Setup not finished" or "Offline for 20 days" when that applies. Each has **Delete this Porch**, **New bedside link** and **Allow a PIN reset**.
- **System:** how many numbers are in use against the limit, natural-voice use this month, and the health check.
- **Activity:** everything done on the admin page, and when.

**The family's caregiver**, usually an adult child, opens the link on the iPad.

1. The page lists what they need:
   - an iPad with an M-series chip (M1 or later)
   - a Cell2Jack
   - a corded phone set to tone dialing, such as a big-button picture phone
   - Wi-Fi

   Then it walks through installing TestFlight, **Get Porch**, and **Open setup in Porch**. If Porch is already installed, the link opens it directly.
2. Setup, one screen at a time:
   1. **Who is this Porch for?** A name, such as "Mom".
   2. **Choose a caregiver PIN**, entered twice.
   3. **Mom's Porch phone number.** "People can call Mom's Porch from any phone." The area code is suggested from where the iPad is and can be changed. **Get number** shows the number.
   4. **Allow the microphone, camera and notifications**, each with a sentence on why.
   5. **Connect the phone**, or **Do this later**.
      - Plug the phone into the Cell2Jack and the Cell2Jack into the iPad.
      - Turn on Porch's driver in Settings.
      - Unplug the Cell2Jack for ten seconds and plug it back in.
      - Lift the receiver and press a key: "Porch heard 3."
      - Put the receiver back: "Porch heard you hang up."
   6. **Add your phone.** A QR code to scan with their iPhone camera, or **Send an invite instead**. This first invite has caregiver access on.
   7. **Done**, showing the number and how calls to it work: "Only people on the keypad and numbers you allow can call this number. Anyone else is turned away and listed under Blocked numbers, where you can allow them." Then **Put people on the keypad**.
3. A checklist stays at the top of caregiver mode until finished: number, phone keypad, your phone, people on the keypad, drop-in (optional), language and display, **Test ringing**.

**Their relatives** receive invites from the caregiver in Messages: "Join Mom's Porch: https://helloporch.store/join#… If you don't have Porch yet, the link shows you how to get it."

- With Porch installed, the link opens it and joins.
- Without it, the page links to TestFlight, then shows **Open invitation in Porch** for after installing. TestFlight can't carry the link through an install, so this second tap is needed.

Their Porch home screen shows **Mom's Porch number** with **Add to Contacts**.

TestFlight's public link appears on these pages, but on its own it gives an app that can't set anything up. A Porch invitation is what lets someone in.

## One-time setup for you

None of this repeats per family.

**Apple, when the driver is approved** (blocks inviting other families)
- Regenerate the driver's App Store profile with the approved DriverKit and USB entitlements and save it as `IOS_DRIVER_APPSTORE_PROFILE`, as [CELL2JACK-CALLS.md](ios/CELL2JACK-CALLS.md#distribution-verification-2026-10-18) describes.
- Add **Associated Domains** to the `com.ethanteng.helloporch` App ID, regenerate the app's App Store profile, and replace the `IOS_APPSTORE_PROFILE` GitHub secret. Doing both profile changes at the same time avoids regenerating twice. Development profiles update through automatic signing.
- In App Store Connect: an external TestFlight group, a public link with a tester limit, and Beta App Review for the first build. Each later version needs review again, and builds expire after 90 days.

**Twilio**
- Confirm the account is upgraded. Trial accounts can own only one number.
- Voice geographic permissions: US and Canada only, since phone guests can already call Canadian numbers.
- Usage triggers that email on number count and monthly spend.
- Trust Hub business profile for SHAKEN/STIR, so outgoing calls from new numbers aren't labeled "Spam Likely". New numbers are then added to it by the server.

**LiveKit**
- Nothing to create: Porch makes the shared inbound trunk and its dispatch rule with the first number it buys (1.2).
- Check the plan's limits on numbers per trunk.

**Vercel, calling project (`porch-calling-prototype`)**
- `PORCH_MAX_PHONE_NUMBERS`, `PORCH_SPEECH_MONTHLY_CHARACTERS`, `CRON_SECRET`.
- `PORCH_SERVER_ORIGIN`, so the Twilio voice webhook always points at the live address and never at a deployment URL.
- Already set: `TWILIO_ACCOUNT_SID`, `TWILIO_AUTH_TOKEN`, `LIVEKIT_SIP_URI`, `LIVEKIT_SIP_OUTBOUND_TRUNK_ID`.

**Vercel, website project (`helloporch`)**
- `NEXT_PUBLIC_TESTFLIGHT_URL`, the public TestFlight link.

**Admin page** (phase 2)
- In Vercel, add `admin.helloporch.store` to the calling project (`porch-calling-prototype`), with its DNS record. The admin page runs there because Redis, Twilio and LiveKit are already set up in that project; the website project has none of them.
- Set `PORCH_ADMIN_ENABLED=1` in the calling project only, so the website project never serves the admin page.
- Run a new `scripts/admin-setup-link.mjs` once with the recovery secret. It writes a private one-use link, valid for an hour, to register your passkey. Run it again only if every passkey is lost.

## Phase 0: the Cell2Jack build for everyone (when Apple approves)

Size: small, but it blocks inviting other families. Everything else can be built first.

- Run **Upload Porch to TestFlight** with `variant=cell2jack` and `verify_only=true`, then upload once it passes. Its existing checks cover the driver's approved USB grant and signatures ([BUILD-VARIANTS.md](ios/BUILD-VARIANTS.md)).
- **One build for every device.** Apple DTS says the same app runs on iOS, with DriverKit used only on iPadOS ([CELL2JACK-CALLS.md](ios/CELL2JACK-CALLS.md)). Confirm the `Porch` TestFlight build installs and works on an iPhone. Then:
  - change the workflow's default `variant` to `cell2jack`
  - stop uploading `PorchFamily` builds
  - remove the `PorchFamily` scheme and target, and the variant checks for it
- **Mom's iPad** can then move from development builds to TestFlight. The driver's distribution signature replaces the development one, so re-check that the driver is on in Settings, replug the Cell2Jack, and check **Phone keypad ready**. Do it on another M-series iPad first if there is one. Otherwise do it at a quiet time with someone at her iPad. Until then, keep following the development-build steps.
- App Review notes ([prepare-app-review.mjs](scripts/prepare-app-review.mjs)) stop saying the build excludes the driver. They explain that the Cell2Jack is optional hardware and that touch works without it.

## Phase 1: a phone number for every household (server)

Size: large. Nothing in the app depends on it, so it can ship first.

**Status:** built on the branch `claude/porch-phone-numbers` (PR 1), in [numbers.ts](lib/family/numbers.ts), with its tests in [phone-numbers.test.mjs](tests/phone-numbers.test.mjs). It's documented in [INBOUND-PHONE-CALLS.md](ios/INBOUND-PHONE-CALLS.md#a-number-for-each-household). Merged in PR #62.

Tried for real on 2026-10-28:
- Hainie's existing number was recorded with `--adopt`.
- Bella Vista got a bought 510 number, the first purchase, which also created the shared trunk. Calls to it ring Bella Vista and reach voicemail, its phone fallback shows it as caller ID, calling back rings Bella Vista, and Mom's number still rings Mom.

### 1.1 Each household calls out from its own number

- `authorizeBedsideCalling` ([service.ts](lib/family/service.ts)) returns the household's number with its calling settings, and `start` ([phone.ts](lib/calls/phone.ts)) passes it as `fromNumber` to `createSipParticipant`.
- Phone guests ([phone-guests.ts](lib/family/phone-guests.ts)) pass the household's number too.
- Each new number goes on the outbound trunk's `numbers` (`updateSipOutboundTrunkFields`, adding to the list). LiveKit may not require it, but Twilio Termination only accepts caller IDs owned by the account, and having it on the trunk keeps both sides consistent. Verify with a real call.
- A household without a number yet uses the trunk default, as before. The legacy shared-code path is unchanged.
- **Before a second number goes on the outbound trunk,** give every household that calls regular phones its Porch number (1.7). LiveKit doesn't document which listed number a call without `fromNumber` uses.

### 1.2 One shared inbound trunk

- New numbers go on one shared trunk, **Porch inbound (shared)**, which Porch makes with the first number it buys, under a lock. It uses the same settings as `configure-inbound.mjs --voicemail`: the digest login ([inbound.ts](lib/family/inbound.ts) `sipInboundCredentials`), the forwarded caller-verification header, a 120-second ringing cap and a 30-minute limit. It also gets one individual dispatch rule with the `porch-inbound-` room prefix.
- It's never empty, since an inbound trunk without numbers takes calls to any number. Porch refuses to make it while a dispatch rule without trunks exists.
- Routing already works by the number dialed (`phone-number:<E.164>` in Redis), and [inbound.ts:126](lib/family/inbound.ts:126) checks the route's `trunkID`, which is the shared trunk's ID.
- Hainie keeps its own trunk and routing, untouched.

### 1.3 Buying and setting up a number

New `lib/family/numbers.ts`, calling Twilio's REST API with `fetch` the way [voicemail.ts:114](lib/family/voicemail.ts:114) already does:

- **Search:** `AvailablePhoneNumbers/US/Local.json?VoiceEnabled=true` with `AreaCode`, or `NearLatLong` and `Distance` from Vercel's `x-vercel-ip-latitude` and `x-vercel-ip-longitude` headers. Return a suggested area code and a few nearby alternatives. When the iPad's location is outside the US or unknown, there's no suggestion and the caregiver types an area code.
- **Buy:** `POST IncomingPhoneNumbers.json` with `PhoneNumber`, `VoiceUrl=<PORCH_SERVER_ORIGIN>/api/calls/inbound/voice`, `VoiceMethod=POST` and `FriendlyName=Porch <householdID>`.
- **Release** belongs with deleting a household (6.1).

`ensurePorchNumber(store, householdID, …)` runs these steps under a short per-household lock, so two requests can't buy two numbers. Each step is safe to repeat:

1. Use the saved `number-order:<householdID>` if there is one.
2. Otherwise look the number up by `FriendlyName`, in case a purchase went through but its response was lost. Otherwise search the area code, count the household against `PORCH_MAX_PHONE_NUMBERS` (`numbers:households`) once, and buy, then save the order. A search that finds nothing, or fails, takes no place.
3. Add it to the shared inbound trunk, making the trunk with the first number (1.2).
4. Add it to the outbound trunk.
5. Create `phone-number:<n>` → `{ householdID, bedsideID, trunkID }`, failing if the route belongs to another household.
6. Save `porchNumber: { number, sid, assignedAt }` on the household with `mutate`, and clear `phoneSetup`.

A failure records `phoneSetup: { areaCode, attempts, retryAt, error }`. Retries ride on the bedside's existing poll: once `retryAt` has passed, the poll calls `ensurePorchNumber` again, after a minute, then twice as long each time, up to an hour. The retry runs after the poll is answered (Next's `after`), since Twilio and LiveKit can take longer than the iPad's 12-second poll timeout, and the family route allows 60 seconds. An area code with no numbers (`needsChoice`) waits for the caregiver instead. No separate job is needed. Only households that asked for a number are retried, so nobody is sold one by their polls alone. A household never gets a second number.

### 1.4 New API actions

Both are caregiver actions on the bedside, with the PIN.
- `phoneNumberOptions`: a suggested area code from the iPad's location, plus up to four nearby ones. It returns none outside the US, without location headers, or if the search fails; the caregiver types one instead.
- `assignPhoneNumber`: an area code. It returns the number, or `pending` while Porch keeps trying. An area code with no numbers returns 409 `noNumbers`, and Porch's limit returns 503 `numberLimit`. Calling it again after success returns the same number.

### 1.5 Showing the number

The snapshot ([service.ts](lib/family/service.ts)) adds `porchNumber` for every member, plus `phoneSetup` (area code and any error) for the bedside and caregivers while it's still being set up.

### 1.6 New households block unknown callers

- A household created by setup starts with `blockUnknownCallers: true` and `keypadNumbers: []`. Blocking today can't turn on until the iPad has reported its keypad numbers ([screening.ts:94](lib/family/screening.ts:94)); a new household's keypad is known to be empty, so the empty list is accurate.
- Callers who aren't on the keypad or allowed are turned away and listed under **Blocked numbers**, as now. That includes relatives calling from a regular phone before they're added.
- Existing households keep their current setting.

### 1.7 Existing households

[scripts/provision-number.mjs](scripts/provision-number.mjs) prints a read-only plan that names the bedside, then saves it with `--apply`.

- **Hainie:** `--adopt` saves the number its route already uses as its `porchNumber`, without changing any routing. It needs that number to be on the outbound trunk, so outgoing calls keep the same caller ID.
  - Mom's number is safe even before that: only households made by the app's setup (`numberFromSetup`) can get a number from the app, so Hainie can never be sold a new one, whatever the app shows.
  - Nothing in this PR releases a number.
- **Bella Vista:** `--area-code=…` buys it a number the way setup does, or delete it from the admin page once phase 6.1 exists, if it's only a test household. Do one or the other before any other household gets a number (1.1).

### 1.8 Tests

`tests/phone-numbers.test.mjs`, with fake Twilio `fetch` and fake LiveKit clients. Like the existing phone tests, it never buys a number or places a call. Cover:

- a timeout during buying followed by a retry
- two requests at once
- a failure partway through
- the global cap
- caller ID in phone fallback and phone guests
- blocking on for new households
- a shared trunk left half-made, and a dispatch rule without trunks
- the Twilio request format, and errors that leave the number out

## Phase 2: private invitations and the admin page

Size: medium to large. This replaces the recovery-secret script for new families. Read the Next.js 16 guides in `node_modules/next/dist/docs/01-app/02-guides/` (`authentication.md`, `data-security.md`, `content-security-policy.md`) before building it, since this Next.js differs from older versions.

### 2.1 Where it runs

- Pages live in this repo under a route group of their own, `app/(admin)/admin/…`, so they get none of the website's layout or Google Analytics.
- The calling project serves them at `admin.helloporch.store`. Next.js Proxy (`proxy.ts`) sends that host's requests to the `/admin` routes and nothing else.
- The `/admin` routes answer 404 on any other host, and on any deployment without `PORCH_ADMIN_ENABLED`, which includes the website project.
- Every admin response is `noindex` and `Cache-Control: no-store`, with a content security policy that allows no third-party scripts and `frame-ancestors 'none'`.

### 2.2 Signing in with a passkey

- **Passkeys (WebAuthn),** with `@simplewebauthn/server` and its browser package, rather than writing the signature and CBOR checks by hand. The relying party is `admin.helloporch.store`, and user verification is required, so it's Touch ID or the device passcode every time. Passkeys sync through iCloud Keychain, so a phone works too if ever needed.
- **The first passkey** comes from the one-use link `admin-setup-link.mjs` writes. More can be added from the admin page while signed in, and removed, except the last one.
- **Sessions** are stored in Redis, as the Next.js guide recommends, not just in a signed cookie:
  - a random session ID saved as `admin-session:<hash>`
  - a 12-hour lifetime
  - a `__Host-` cookie that's HttpOnly, Secure and SameSite=Strict

  **Sign out** deletes the session, and **Sign out everywhere** deletes them all.
- **Rate limits:** sign-in attempts are limited per IP address.
- **Asking again for risky actions:** deleting a Porch, allowing a PIN reset and making a bedside link ask for the passkey again. Deleting also needs the Porch's name typed.
- **Checks on every action:** changes go through Server Actions, which Next.js only accepts from the same host. Each Server Action and each page also checks the session itself, since the guide treats Proxy checks as optimistic only.
- **Activity log:** `admin-log` in Redis keeps the last 500 entries: sign-ins, passkeys added or removed, invitations made or cancelled, deletions, PIN-reset allowances and bedside links.

### 2.3 Pages

- **Invitations:** a form for the label, then the link with **Copy link** and **Copy message**.
  - The link appears only once, since Porch keeps only a hash of it. If it's lost, **Cancel** it and make a new one.
  - The list shows each invitation's label, state, expiry and household once set up. Waiting ones have **Cancel**; expired ones have **Send again**, which makes a new link.
- **Porches:** a table of every household, and a page for each with **Delete this Porch** (6.1), **New bedside link** (6.2) and **Allow a PIN reset** (6.3).
- **System:** numbers in use against `PORCH_MAX_PHONE_NUMBERS`, natural-voice characters this month against the ceiling, and the result of the health check.
- **Activity** and **Passkeys.**

The admin page is built for a computer screen but stays usable at phone width.

### 2.4 Server

The admin page calls the same server functions the family API uses, never a copy of them.

- **Household list:** add a `households` list in Redis, written when a household is created, and add Hainie and Bella Vista to it once. The store can't scan keys, and both the admin page and the daily job (6.4) need it.
- **Invitations:**
  - **Create:** takes a label such as "Lee family" and creates the same `activation:<hash>` record `createBedsideInvite` makes today ([service.ts:160](lib/family/service.ts:160)), plus the label and when it was made. It lasts 14 days instead of 24 hours. It's still for one device, with the existing retry on the same device after a lost response.
  - **List** and **cancel.**
- **Porches list:** for every household: its bedside name, invitation label if any, Porch number, when it was set up, when the bedside was last seen, the number of family devices, and whether setup is finished. It never includes messages, family members' names, keypad contents or call details.
- **Setup from an invitation:** when `enrollBedside` uses an invitation ([service.ts:189](lib/family/service.ts:189)), it saves the new household's ID on the invitation.
- `createBedsideInvite` with the recovery secret stays, for App Review links and as a backup. [create-bedside-invite.mjs](scripts/create-bedside-invite.mjs) writes the new `https` link.
- With invitations as the only way in, no IP limits or App Attest are needed for families yet. `PORCH_MAX_PHONE_NUMBERS` stays as a safety limit.

### 2.5 Tests

Cover:
- signed out: every admin page and Server Action refuses
- sessions: expired, signed out, and deleted by **Sign out everywhere**
- the wrong host, and a deployment without `PORCH_ADMIN_ENABLED`, both answering 404
- passkey registration with a used or expired setup link, and refusing to remove the last passkey
- deleting, PIN resets and bedside links refused without asking for the passkey again
- invitations: expiry, a link used twice, and a cancelled link
- the Porches list holding no private details
- each action leaving an activity entry

## Phase 3: spending guards (server)

Size: small to medium. These ship before inviting other families.

- **Phone fallback destinations:** apply the US and Canada rules phone guests already use ([phone-guests.ts](lib/family/phone-guests.ts)) to fallback approvals in [contacts.ts](lib/calls/contacts.ts). This refuses Caribbean +1 numbers, 900 and 976 numbers, and anything outside +1. Existing approvals for other numbers stop working at their next renewal; Hainie has none.
- **Daily outgoing call cap per household:** `dial-count:<householdID>:<day>` covering fallback and phone guests, for example 40 a day. Over the cap, the app says "Porch can't call more phones today."
- **Overall natural-voice ceiling:** `speech-usage:<month>` against `PORCH_SPEECH_MONTHLY_CHARACTERS`. Once it's reached, households use the built-in voice, the same way the existing daily allowance falls back ([speech.ts:115](lib/family/speech.ts:115)).
- **Health check:** add `numbersConfigured` and how close each cap is to its limit, without numbers or names ([health.ts](lib/calls/health.ts)).

## Phase 4: links and website

Size: medium. Can run alongside phase 1.

**Status:** built in PR 3 on the branch `claude/porch-invite-links`. The links and helpers are in [invite-links.ts](lib/invite-links.ts), and the pages share [InviteLanding.tsx](components/InviteLanding.tsx). `/bedside` comes with replacing the bedside (PR 8), and the QR code on `/setup` is left for later.

### 4.1 Universal links

- `app/.well-known/apple-app-site-association/route.ts` serves JSON for app ID `7U9T57JPF7.com.ethanteng.helloporch` with paths `/join` and `/setup`, as `application/json`. `helloporch.store` serves it without a redirect; `www` redirects to it.
- Add `com.apple.developer.associated-domains` = `applinks:helloporch.store` to [Porch.entitlements](ios/Porch/Porch.entitlements), and to [PorchFamily.entitlements](ios/Porch/PorchFamily.entitlements) while that build still exists.
- [PorchApp.swift](ios/Porch/PorchApp.swift): handle `scene(_:continue:)` and `connectionOptions.userActivities` alongside `openURLContexts`.

### 4.2 `https` links in the app

- `FamilyInvitation` ([FamilyModels.swift](ios/PorchCore/Sources/PorchCore/FamilyModels.swift)) accepts `https://helloporch.store/join#code=<64 hex>`, and `BedsideInvitation` accepts `/setup`. A web link names no server: the app reads it as its own server (`PorchServerURL`, passed as `defaultOrigin`). An invitation for any other server keeps the porch:// form, so no allow list is needed. `porch://pair` and `porch://activate` keep working.
- New family invites are `https` links for the app's own server, with the share text above. `create-bedside-invite.mjs` writes an `https` setup link the same way. App Review links stay porch://, which every build opens.
- Codes stay after `#`, so they never reach server logs.
- PorchCore tests cover both formats.

### 4.3 Pages

Both read the fragment in a client component, clear it with `history.replaceState`, and are `noindex` with no referrer. Google Analytics never loads on them: [Analytics.tsx](components/Analytics.tsx) leaves it out for their paths, so a code can't reach it.

- **`/setup`** (the family's invitation): what they need, then **Get Porch** (TestFlight), **Open setup in Porch** (`porch://activate?…`, built from the fragment) and **Copy setup link** for the activation field. A QR code of the same link, for when it's opened on a computer, is left for later.
- **`/join`** (a relative's invitation): **Get Porch**, then **Open invitation in Porch**, and **Copy invitation** for the existing paste field.
- The porch:// buttons also let a Porch from before this change open the invitation.
- **`/bedside`** (replacing the bedside iPad, phase 6.2) comes with PR 8.

## Phase 5: setup in the app

Size: large. Depends on phases 1, 2 and 4.

- **5.1 Welcome screen** on a device with no pairing in either mode: **Set up Porch for someone** or **I'm joining my family**.
  - **Set up** asks for the setup link from the invitation, unless Porch was opened by it. Without one it says "Ask whoever invited you for your setup link."
  - On an iPhone, it explains that the bedside runs on the iPad that stays with them.
- **5.2 Bedside setup.** The steps above replace the creation form in `CaregiverPINViewController` ([PorchContainerViewController.swift:182](ios/Porch/PorchContainerViewController.swift:182)).
  - The number step can't be skipped. Call `assignPhoneNumber` with a longer timeout than the usual 12 seconds, such as 45, since the first number also makes the shared trunk. If buying is still pending because Twilio failed, **Continue** is allowed with "Porch will keep trying and let you know", so pairing family isn't blocked. The checklist shows the pending number.
  - The **Done** screen explains that unknown callers are blocked (1.6).
- **5.3 Connect the phone** (Cell2Jack):
  - **Model check:** check the iPad's model identifier (`hw.machine`) against known M-series iPads. On a known non-M iPad, such as an iPad mini or the base iPad, say the phone keypad needs an M-series iPad and continue with touch. An unknown model gets a try.
  - **Turn on the driver:** a button opens Porch's page in Settings (`UIApplication.openSettingsURLString`) to turn on the driver, then "Unplug the Cell2Jack for ten seconds, then plug it back in." Confirm the exact Settings wording on a device with the distribution build.
  - **Turned on for them:** when the Cell2Jack reports ready, Porch turns on **Use Cell2Jack phone keypad** itself. It stays off by default for existing installs and for anyone who chooses **Do this later**.
  - **Key test:** "Lift the receiver and press a key" shows the digit Porch heard, without acting on it. "Put the receiver back" confirms hang-up, and offers **Hang up when the receiver is put back** (on by default).
  - **Help after about 30 seconds of nothing:**
    - check the driver is on and replug
    - the phone must be on tone dialing, since pulse dialing isn't supported
    - the keys work only with the receiver lifted
    - the Cell2Jack may say the phone isn't connected when the receiver is lifted; pressing a key stops it
  - **Do this later** leaves **Connect the phone** on the checklist, which opens the same steps. The touchscreen works meanwhile.
  - **Phone guide:** write how Mom's picture phone is set up, including tone dialing and whatever its photo keys needed, for the `/setup` page and help.
- **5.4 Add your phone.** A QR code (`CIQRCodeGenerator`) for one invite with caregiver access, shown only in caregiver mode behind the PIN. It refreshes after it's used or expires. **Send an invite instead** opens the share sheet.
- **5.5 Checklist** at the top of caregiver mode on the bedside and caregiver phones. Items can be dismissed.
- **5.6 Porch number** on the family home screen and in caregiver mode, with **Add to Contacts** (`CNContactViewController`).
- **5.7 Device and accessibility tests** of the new screens with VoiceOver, large text, both orientations, the Porch keyboard, a standard keypad and the Cell2Jack.

## Phase 6: the household lifecycle

Size: large. **Delete this Porch** and the keypad backup should ship before inviting other families; the rest can follow.

### 6.1 Delete this Porch

Two ways to start it, with the same deletion:

- **A caregiver**, on the bedside: caregiver mode → **Family & drop-in → Delete this Porch**, with the PIN and typing the name to confirm.
- **You**, on the admin page: **Porches → the Porch → Delete this Porch**, typing its name and confirming with your passkey. Deleting Hainie asks a second time.

New `deleteHousehold` action:

- ends any call
- revokes every device
- deletes message, photo, speech and keypad-backup media in Blob. Check whether media paths include the household ID; add a per-household prefix if they don't.
- deletes the Redis records: the household, its devices and invites, its route, its keypad backup, the PIN and lockout keys, and its entries in `households` and `numbers:households`. The store needs a `delete` for this.
- releases the number, **only if Porch bought it**, meaning it has a `sid` and Twilio names it "Porch" and the household ID:
  - takes it off the shared inbound trunk and the outbound trunk, but never leaves either empty, since an empty inbound trunk takes calls to any number and an empty outbound trunk has no caller ID
  - releases it in Twilio by its `sid` (`DELETE IncomingPhoneNumbers/<sid>.json`)
  - for a number set up by hand, like Mom's, leaves Twilio, its trunk and the outbound trunk alone, and says so. Deleting Hainie would keep Mom's number in Twilio for a new bedside.
- marks its invitation on the admin page as deleted

Family phones and the bedside show "This Porch was deleted" and return to the welcome screen. When you delete it, caregivers' phones also get a notification first.

### 6.2 Replace the bedside iPad

- From a caregiver phone: **Set up a new bedside iPad** with the PIN. `createBedsideReplacement` makes a one-use, 24-hour `https://helloporch.store/bedside#code=…` link and QR code tied to the household. You can also make one with **New bedside link** on the admin page, for a family that has lost its PIN as well as its iPad. The admin page shows that link once, for you to send.
- The new iPad's welcome screen accepts it.
- `enrollBedside` with a replacement code adds the new bedside, revokes the old one, and updates the route's `bedsideID` with compare-and-set.
- The household keeps its number, messages, family, approvals and voices.
- The new iPad offers **Restore Mom's keypad and settings** from the backup (6.5), then goes through **Connect the phone**, since the driver setting belongs to the iPad.

### 6.3 Forgotten PIN

- **Forgot PIN?** on the bedside PIN screen sends a notification to caregiver phones: "Mom's Porch asked to reset the caregiver PIN."
- Approving on a caregiver phone uses its device credential, not the PIN, and lets the bedside set a new PIN for 15 minutes.
- Rate-limited.
- With no caregiver phones, the family asks you. **Allow a PIN reset** on the admin page lets that Porch's bedside set a new PIN for 15 minutes.

### 6.4 Daily check

A daily job, either Vercel Cron calling `/api/family/maintenance` with `CRON_SECRET`, or a GitHub Actions schedule. Vercel Cron in a shared `vercel.json` would also run on the website project, which has no Redis and should answer 503 harmlessly. It deletes nothing and releases no numbers:

- **Offline bedside:** notify caregivers at 14 and 30 days: "Mom's Porch has been offline for 14 days. Check that the iPad is charged, connected to Wi-Fi and has Porch open."
- **Setup not finished:** no family member joined and the bedside unseen for 7 days. It's flagged on the admin page, so you can follow up or delete it.
- The admin page shows both, with how long.

### 6.5 Keypad and settings backup

The bedside keeps a copy of its keypad and settings on the server. The iPad stays in charge: it saves a new copy whenever they change, and restores only when asked.

- **What's in it:**
  - the keypad: `CallSlots` ([CallSlots.swift](ios/PorchCore/Sources/PorchCore/CallSlots.swift)), including each key's action and contact (name, numbers, call mode, fallback, linked family member)
  - keypad photos the caregiver chose, uploaded to the private Blob store and referenced by SHA-256, like profile photos
  - call preferences, the bedside display, voice choices per language, and the Cell2Jack settings: whether it's on, and **Hang up when the receiver is put back**

  It leaves out family members' own names and photos, which the server already has. It also leaves out the driver setting, which belongs to the iPad.
- **Saving:** a versioned JSON record, `keypad-backup:<householdID>`, sent with the PIN. It replaces today's keypad-number report ([FamilyService.swift:254](ios/Porch/FamilyService.swift:254)), and the server takes `keypadNumbers` from it. Failed saves retry the same way the report does. Photos upload only when they change.
- **Restoring:** on a replacement iPad (6.2). Also on an iPad whose Porch was reinstalled and enrolled again into the same household.
- **Who can read it:** only the bedside and caregiver mode. The admin page never shows it.
- **Privacy:** the policy changes. Today it says Redis doesn't store the names on keypad contacts.
- **Later:** with a copy on the server, a caregiver could edit the keypad from their phone, which today only the bedside can do. That's not in this plan.
- **Tests:** saving after each kind of change; a photo changing or being removed; restore onto a new iPad; a backup from an older app version; a wrong PIN; deletion removing it.

## Phase 7: docs, privacy and the first invitations

Size: small.

- Rewrite onboarding in [FAMILY-SETUP.md](ios/FAMILY-SETUP.md). In [INBOUND-PHONE-CALLS.md](ios/INBOUND-PHONE-CALLS.md), describe automatic numbers, the shared trunk and blocking on by default, keeping `configure-inbound.mjs` for Hainie and recovery. Update [BUILD-VARIANTS.md](ios/BUILD-VARIANTS.md) and [CELL2JACK-CALLS.md](ios/CELL2JACK-CALLS.md) for one build, and [README.md](README.md).
- Privacy policy ([app/privacy](app/privacy/page.tsx)) and App Store privacy labels:
  - the iPad's approximate location from its IP address, used once to suggest an area code
  - the assigned number
  - the keypad and settings backup, including names, numbers and photos
  - the invitation label you type, and what the administrator can see
  - household deletion
- App Review notes: each review household gets a real number, so delete it from the admin page after review.
- Try the whole path on a second household of our own, from **Invite a new family** to a call to its new number, before inviting anyone else.
- Invite the first family.

## Order of pull requests

| # | PR | Depends on |
| --- | --- | --- |
| 1 | Each household calls out from its own number; shared inbound trunk made with the first number; `numbers.ts`; number actions and snapshot fields; blocking on for new households; `provision-number.mjs` for Hainie and Bella Vista; tests. **Built** | – |
| 2 | Spending guards: fallback destinations, daily call cap, voice ceiling, health check | – |
| 3 | Universal links, `https` invites, `/setup`, `/join`; the number message fix. **Built** | – |
| 4 | Keypad and settings backup | – |
| 5 | Private invitations and the admin page: passkey sign-in, sessions, household list, invitations, and the Porches, System, Activity and Passkeys pages | 3 |
| 6 | Welcome screen, setup flow, number step, Connect the phone, QR code, checklist, number display | 1, 3, 5 |
| 7 | Delete this Porch, by a caregiver or on the admin page | 1, 4, 5 |
| 8 | Replace the bedside with restore from backup, including the `/bedside` link and page; forgotten PIN | 3, 4, 5 |
| 9 | Daily check for offline and unfinished Porches | 5 |
| 10 | When the driver is approved: the Cell2Jack TestFlight build for everyone, `PorchFamily` retired, docs, privacy, first invitations | all, and Apple |

PRs 1 to 4 can be worked on at the same time. PRs 1 to 9 don't wait for Apple; they can be tried with development builds and TestFlight family builds on our own devices.

## Check early, before building on it

- ~~`fromNumber` with Twilio Termination for a number bought by the API.~~ Works (Bella Vista, 2026-10-28).
- LiveKit's limit on numbers per inbound trunk. Porch lists each number, which works.
- ~~That a number bought with `VoiceUrl` set rings through voicemail mode end to end on the first call.~~ Works (Bella Vista, 2026-10-28).
- Universal links in a TestFlight build, opened from Messages and from the Camera app.
- ~~Whether Google Analytics records `#` fragments on this site.~~ Moot: it never loads on invitation pages.
- How large a keypad backup gets with twelve photos, to size the Redis record and the Blob uploads.
- Where helloporch.store's DNS is managed, and that the calling project can take `admin.helloporch.store`.
- Passkey sign-in with `@simplewebauthn/server` in Next.js 16 Server Actions, and the Proxy rewrite for `admin.helloporch.store`, on a preview deployment.
- After approval: the `Porch` TestFlight build on an iPhone, and the driver switch on an M-series iPad.

## Device checks before inviting other families

- **A fresh M-series iPad from a `/setup` link through TestFlight:**
  - setup, number and permissions
  - Connect the phone: driver, replug, key test, hang-up
  - QR pairing of an iPhone that doesn't have Porch yet
- **The same setup choosing Do this later,** then connecting the phone from the checklist.
- **The same setup on a non-M iPad:** the phone step explains and touch works.
- **Calling the new number from a regular phone:** an unknown number is blocked and listed; after **Allow** it rings and can leave voicemail.
- **Outgoing caller ID:** phone fallback and **Add someone → A phone number** show the new household's own number, and a callback rings the new bedside, not Mom's.
- **A relative's invite** opened in Messages, with and without Porch installed.
- **The admin page:**
  - signing in with the passkey on the Mac
  - signed out, every page and action refuses
  - sessions end after 12 hours and on sign-out
  - risky actions ask for the passkey again
  - `helloporch.store/admin` on the website answers 404
  - it shows the new household, and cancel and expiry work for invitations
- **Deleting a household,** once by its caregiver and once from the admin page: the number is released, family phones are told, and calling the old number no longer rings anything.
- **Replacing a bedside:** the keypad, photos and settings come back, and the Cell2Jack connects again.
- **Resetting a forgotten PIN,** from a caregiver phone and from the admin page.
- **Mom's iPad:** incoming calls to Hainie's number, outgoing caller ID, blocking setting and the Cell2Jack keypad all unchanged, and its keypad backup saved. Her number is still in Twilio with its voice webhook unchanged.

## Later: open sign-up

Not part of this phase. If invitations ever need to give way to sign-up without you:

- App Attest as the gate. The app attests a key against a server challenge. The server checks:
  - the certificate chain to Apple's App Attestation Root CA
  - the nonce
  - `rpIdHash` for `7U9T57JPF7.com.ethanteng.helloporch`
  - the `appattest` or `appattestdevelop` AAGUID
- Limits: a switch to stop sign-ups, a total household cap, and per-IP limits.
- A sign-up step on `/setup` in place of the invitation code.
