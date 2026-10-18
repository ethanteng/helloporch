#!/usr/bin/env bash
set -euo pipefail
umask 077

verify_only="${PORCH_VERIFY_ONLY:-true}"
if [[ "$verify_only" != true && "$verify_only" != false ]]; then
  echo "PORCH_VERIFY_ONLY must be true or false" >&2
  exit 1
fi
export IOS_DRIVER_BUNDLE_ID="${IOS_DRIVER_BUNDLE_ID:-com.ethanteng.helloporch.usbdriver}"

for name in APPLE_TEAM_ID IOS_BUNDLE_ID ASC_KEY_ID ASC_ISSUER_ID ASC_PRIVATE_KEY IOS_DISTRIBUTION_P12 IOS_DISTRIBUTION_PASSWORD IOS_APPSTORE_PROFILE IOS_DRIVER_APPSTORE_PROFILE RUNNER_TEMP GITHUB_RUN_NUMBER GITHUB_RUN_ATTEMPT; do
  if [[ -z "${!name:-}" ]]; then
    echo "Missing TestFlight configuration: $name" >&2
    exit 1
  fi
done

signing_dir="$RUNNER_TEMP/porch-signing"
keychain_path="$RUNNER_TEMP/porch-signing.keychain-db"
mkdir -p "$signing_dir" "$HOME/.appstoreconnect/private_keys"
export PORCH_SIGNING_DIR="$signing_dir"

python3 - <<'PY'
import base64, os
from pathlib import Path
folder = Path(os.environ['PORCH_SIGNING_DIR'])
for secret, filename in [('IOS_DISTRIBUTION_P12', 'distribution.p12'), ('IOS_APPSTORE_PROFILE', 'Porch.mobileprovision'), ('IOS_DRIVER_APPSTORE_PROFILE', 'PorchDriver.mobileprovision')]:
    (folder / filename).write_bytes(base64.b64decode(os.environ[secret], validate=True))
key_id = os.environ['ASC_KEY_ID']
if not key_id.isalnum():
    raise SystemExit('Invalid ASC_KEY_ID')
key_file = Path.home() / '.appstoreconnect' / 'private_keys' / f'AuthKey_{key_id}.p8'
key_file.write_text(os.environ['ASC_PRIVATE_KEY'])
key_file.chmod(0o600)
PY

security cms -D -i "$signing_dir/Porch.mobileprovision" > "$signing_dir/profile.plist"
security cms -D -i "$signing_dir/PorchDriver.mobileprovision" > "$signing_dir/driver-profile.plist"
python3 ios/scripts/distribution_profiles.py prepare \
  --directory "$signing_dir" --team "$APPLE_TEAM_ID" \
  --app-id "$IOS_BUNDLE_ID" --driver-id "$IOS_DRIVER_BUNDLE_ID"

profile_name="$(cat "$signing_dir/profile-name")"
profile_uuid="$(cat "$signing_dir/profile-uuid")"
driver_profile_name="$(cat "$signing_dir/driver-profile-name")"
driver_profile_uuid="$(cat "$signing_dir/driver-profile-uuid")"
profile_folder="$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"
mkdir -p "$profile_folder"
cp "$signing_dir/Porch.mobileprovision" "$profile_folder/$profile_uuid.mobileprovision"
cp "$signing_dir/PorchDriver.mobileprovision" "$profile_folder/$driver_profile_uuid.mobileprovision"

keychain_password="$(openssl rand -hex 24)"
echo "::add-mask::$keychain_password"
security create-keychain -p "$keychain_password" "$keychain_path"
security set-keychain-settings -lut 21600 "$keychain_path"
security unlock-keychain -p "$keychain_password" "$keychain_path"
security import "$signing_dir/distribution.p12" -k "$keychain_path" -P "$IOS_DISTRIBUTION_PASSWORD" -T /usr/bin/codesign -T /usr/bin/security
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$keychain_password" "$keychain_path" >/dev/null
security list-keychains -d user -s "$keychain_path" "$HOME/Library/Keychains/login.keychain-db"

archive_path="$PWD/ios/build/Porch.xcarchive"
export_path="$PWD/ios/build/export"
build_number="${GITHUB_RUN_NUMBER}.${GITHUB_RUN_ATTEMPT}"
xcodebuild -version
# The project keeps separate bundle IDs and profile settings for app and driver.
# A global PRODUCT_BUNDLE_IDENTIFIER would also rename the nested driver.
xcodebuild -project ios/Porch.xcodeproj -scheme Porch \
  -configuration Release -destination 'generic/platform=iOS' \
  -archivePath "$archive_path" \
  DEVELOPMENT_TEAM="$APPLE_TEAM_ID" \
  CURRENT_PROJECT_VERSION="$build_number" \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY='Apple Distribution' \
  PORCH_APP_PROVISIONING_PROFILE="$profile_name" \
  PORCH_CELL2JACK_CALLS_DRIVER_PROFILE="$driver_profile_name" archive

python3 ios/scripts/distribution_profiles.py verify \
  --directory "$signing_dir" --team "$APPLE_TEAM_ID" \
  --app-id "$IOS_BUNDLE_ID" --driver-id "$IOS_DRIVER_BUNDLE_ID" \
  --bundle "$archive_path/Products/Applications/Porch.app"
cp "$signing_dir/verify-verification.json" "$signing_dir/archive-verification.json"

xcodebuild -exportArchive -archivePath "$archive_path" \
  -exportPath "$export_path" -exportOptionsPlist "$signing_dir/ExportOptions.plist"

ditto -x -k "$export_path/Porch.ipa" "$signing_dir/exported"
python3 ios/scripts/distribution_profiles.py verify \
  --directory "$signing_dir" --team "$APPLE_TEAM_ID" \
  --app-id "$IOS_BUNDLE_ID" --driver-id "$IOS_DRIVER_BUNDLE_ID" \
  --bundle "$signing_dir/exported/Payload/Porch.app"
cp "$signing_dir/verify-verification.json" "$signing_dir/export-verification.json"

xcrun altool --validate-app --type ios --file "$export_path/Porch.ipa" \
  --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID"
if [[ "$verify_only" == true ]]; then
  if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
    echo "Porch app and Cell2Jack driver profiles, signed archive, exported IPA, and App Store validation passed. No upload was performed." >> "$GITHUB_STEP_SUMMARY"
  fi
  exit 0
fi

xcrun altool --upload-app --type ios --file "$export_path/Porch.ipa" \
  --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID"

if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  echo "Uploaded Porch 0.1.0 ($build_number) to App Store Connect. Wait for Apple processing, then assign it to a TestFlight group." >> "$GITHUB_STEP_SUMMARY"
fi
