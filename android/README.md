# Porch for Android

The Android app for both Porch devices, the bedside tablet and family phones. [PLAN.md](PLAN.md) describes the port and what's left.

- `core/` is plain Kotlin: PorchCore from [ios/PorchCore](../ios/PorchCore), ported with its tests. It has no Android code, so its tests run on any JVM.
- `app/` is the Android app, in Compose.
- [`gradle/libs.versions.toml`](gradle/libs.versions.toml) pins every version.

## Build

You need JDK 21 and the Android SDK with platform 37. Point Gradle at them, then build from this folder:

```bash
export JAVA_HOME=/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home ANDROID_HOME="$HOME/Library/Android/sdk"
echo "sdk.dir=$ANDROID_HOME" > local.properties
./gradlew :core:test :app:assembleDebug :app:lintDebug
```

CI runs the same command ([android-build.yml](../.github/workflows/android-build.yml)).

## Release to Google Play

Pilot families install Porch from Google Play's **internal testing** track, which needs no review and takes up to 100 testers by Google account. Play App Signing signs what families install; a release build is signed with Porch's upload key, which stays outside the repo with its passwords in a properties file beside it:

```properties
storeFile=helloporch-android-upload.jks
storePassword=…
keyAlias=upload
keyPassword=…
```

Build the bundle with that file, a `versionCode` higher than the last upload's, and `app/google-services.json` in place so phones ring while Porch is closed:

```bash
./gradlew :app:bundleRelease -Pporch.upload=/path/to/helloporch-android-upload.properties -Pporch.versionCode=2 -Pporch.versionName=0.2
```

Upload `app/build/outputs/bundle/release/app-release.aab` to **Internal testing** in the Play Console, and add each tester's Google account email to its list. The test's opt-in link is what the [Android pilot guide](../app/(site)/pilot/android/page.tsx) and invitation pages show, from `NEXT_PUBLIC_PLAY_TESTING_URL` on the website's Vercel project. The app signing key's SHA-256 (Play Console → **Test and release** → **App integrity**) goes in `androidCertificates` in [lib/invite-links.ts](../lib/invite-links.ts), so invitation and setup links open Porch. If the upload key is lost, Google can register a new one.

## Try it against a local server

[`scripts/local-family-server.mjs`](../scripts/local-family-server.mjs) runs the server's real `/api/family` handler on this computer with an in-memory store. It sets up a stand-in bedside, "Mom", which checks in every few seconds, and prints an invitation link and a setup link for a new bedside tablet. Nothing leaves the process: no Redis, LiveKit or push, and Porch numbers are made up by a stand-in for Twilio (area code 212 has none, to try choosing another). Photos are kept in memory and served from the same port, and a stand-in for `/api/calls/contacts/authorize` approves keypad numbers with the caregiver PIN, refusing `+44` numbers so a refusal can be tried. Nothing there takes real phone calls, so `curl -X POST 'http://localhost:3010/local/blocked-call?number=%2B14155550100'` makes up a call that Block unknown callers turned away, and `curl -X POST 'http://localhost:3010/local/text?from=%2B14155550200&body=Hi%20Mom&pictures=1'` makes up a text to the Porch number for every household, held for a caregiver unless the number is on the keypad or allowed. Debug builds may use plain HTTP to `localhost` only.

```bash
node scripts/local-family-server.mjs
```

In another terminal, with an emulator or phone connected (`$ANDROID_HOME/platform-tools` on your PATH):

```bash
adb reverse tcp:3010 tcp:3010
adb install -r android/app/build/outputs/apk/debug/app-debug.apk
adb shell am start -a android.intent.action.VIEW -d '<the porch://pair link it printed>'
```

Tap **Join family**. The server prints when the phone comes online, and the phone shows the bedside as on and ready. Press Home and the server shows it going offline. That invitation makes the phone a caregiver, so its family card has **Caregiver mode**, which opens with the caregiver PIN the server printed.

On a tablet emulator, open the `porch://activate` link instead to set the tablet up as a bedside. The server prints each device as it starts checking in and whether it can take calls, and the link for each invitation the tablet makes, such as setup's QR code, so a phone can join without a camera.

### Calls

Calls start without LiveKit but never connect. To connect them, run LiveKit's open-source server on this computer in dev mode (`brew install livekit`), whose keys are public test values, and start the local server with `--livekit`:

```bash
livekit-server --dev --bind 127.0.0.1 --node-ip 127.0.0.1
```

```bash
node scripts/local-family-server.mjs 3010 --livekit
```

Then forward LiveKit's signaling port and its TCP media port to each device, as well as the server's:

```bash
adb reverse tcp:3010 tcp:3010 && adb reverse tcp:7880 tcp:7880 && adb reverse tcp:7881 tcp:7881
```

Media goes over TCP through `adb`, because the LiveKit server offers only `127.0.0.1`. The apps accept an unencrypted `ws://` LiveKit address only for this device; Porch's server only gives out `wss://` ones. A tablet over wireless debugging works the same way.

### Phone fallback

When someone on the bedside's keypad doesn't answer Porch, the bedside calls their regular phone. LiveKit's dev server can't call phones, so `--phone` makes those calls real: through LiveKit Cloud's phone trunk and Twilio, which ring a real phone and cost money. It takes LiveKit Cloud's address, key and secret and the outbound trunk ID from an env file, and nothing else, so it never reaches Redis. `--phone-from` is the caller ID. It must be a number the Twilio account owns, since the local household's own number is made up.

```bash
node scripts/local-family-server.mjs 3010 --livekit --phone .env.local --phone-from +15105550123
```

On the bedside, give a key a family member and your own phone number. Press it, leave the family phone ringing, and your phone rings after the fallback wait (20 seconds unless a caregiver changed it). A key with only a phone number calls it straight away. Only put your own numbers on the keypad. Calls to the household's Porch number need Twilio to reach the server, so they can't be tried locally.

### Ringing while Porch is closed

A family phone rings through Firebase Cloud Messaging when Porch isn't open. The app reads Firebase's settings from `android/app/google-services.json`, which the Firebase console gives for the app `com.ethanteng.helloporch`. The repo is public, so that file stays out of git, and a build without it has push turned off. `--fcm` makes the local server send real pushes, with the Firebase project's service account key, which belongs outside the repo:

```bash
node scripts/local-family-server.mjs 3010 --livekit --fcm ../firebase-adminsdk.json
```

On the phone, allow notifications, the microphone and the camera from the card on the family screen, then press Home or turn the screen off and call it from the bedside. The server prints `FCM push -> 200` when a push goes out.

## Keeping the apps in step

`ContractFixtureTest` decodes the server responses in [tests/fixtures](../tests/fixtures), as PorchCore's `ContractFixtureTests` does. When a change to the server alters them, the server's own test fails until they're rewritten with `UPDATE_CONTRACT_FIXTURES=1 npm test`, and then both apps' tests show whether they still read them.
