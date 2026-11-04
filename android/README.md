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

## Keeping the apps in step

`ContractFixtureTest` decodes the server responses in [tests/fixtures](../tests/fixtures), as PorchCore's `ContractFixtureTests` does. When a change to the server alters them, the server's own test fails until they're rewritten with `UPDATE_CONTRACT_FIXTURES=1 npm test`, and then both apps' tests show whether they still read them.
