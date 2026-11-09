#!/usr/bin/env bash
# Builds Porch for Android and puts it on Google Play's internal testing track, for the Android release workflow or a
# release from this computer (android/README.md, "Release to Google Play"). It asks Play for the next versionCode,
# builds the bundle signed with the upload key, and uploads it with the release notes. --verify-only builds and has Play
# check the bundle without uploading it.
#
#   PLAY_SERVICE_ACCOUNT_JSON="$(cat play-service-account.json)" PORCH_ANDROID_UPLOAD=/path/to/helloporch-android-upload.properties \
#     android/scripts/release.sh --notes "What changed" [--version-name 0.3] [--verify-only]
set -euo pipefail
cd "$(dirname "$0")/.."

notes="" version_name="" verify_only=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --notes) notes="${2:-}"; shift 2 ;;
    --version-name) version_name="${2:-}"; shift 2 ;;
    --verify-only) verify_only=true; shift ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

: "${PLAY_SERVICE_ACCOUNT_JSON:?PLAY_SERVICE_ACCOUNT_JSON is missing: the Play service account key's JSON}"
: "${PORCH_ANDROID_UPLOAD:?PORCH_ANDROID_UPLOAD is missing: the upload key's properties file}"
if [[ ! -f "$PORCH_ANDROID_UPLOAD" ]]; then echo "No upload key properties at $PORCH_ANDROID_UPLOAD" >&2; exit 1; fi
# Without it, phones in the release wouldn't ring while Porch is closed.
if [[ ! -f app/google-services.json ]]; then echo "android/app/google-services.json is missing" >&2; exit 1; fi

version_code="$(node scripts/play.mjs next-version-code)"
version_name="${version_name:-0.$version_code}"
echo "Building versionCode $version_code ($version_name)."
./gradlew --console=plain :core:test :app:bundleRelease \
  -Pporch.upload="$PORCH_ANDROID_UPLOAD" -Pporch.versionCode="$version_code" -Pporch.versionName="$version_name"

bundle=app/build/outputs/bundle/release/app-release.aab
# A release build without the key is left unsigned, which Play would refuse anyway; say why here instead.
if ! unzip -l "$bundle" | grep -qE ' META-INF/[^/]+\.(RSA|EC|DSA)$'; then echo "$bundle isn't signed with the upload key" >&2; exit 1; fi

if [[ "$verify_only" == true ]]; then
  node scripts/play.mjs upload "$bundle" --notes "$notes" --verify-only
else
  node scripts/play.mjs upload "$bundle" --notes "$notes"
fi
