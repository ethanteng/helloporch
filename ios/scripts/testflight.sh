#!/usr/bin/env bash
set -euo pipefail
umask 077

for name in APPLE_TEAM_ID IOS_BUNDLE_ID ASC_KEY_ID ASC_ISSUER_ID ASC_PRIVATE_KEY IOS_DISTRIBUTION_P12 IOS_DISTRIBUTION_PASSWORD IOS_APPSTORE_PROFILE RUNNER_TEMP GITHUB_RUN_NUMBER GITHUB_RUN_ATTEMPT; do
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
for secret, filename in [('IOS_DISTRIBUTION_P12', 'distribution.p12'), ('IOS_APPSTORE_PROFILE', 'Porch.mobileprovision')]:
    (folder / filename).write_bytes(base64.b64decode(os.environ[secret], validate=True))
key_id = os.environ['ASC_KEY_ID']
if not key_id.isalnum():
    raise SystemExit('Invalid ASC_KEY_ID')
key_file = Path.home() / '.appstoreconnect' / 'private_keys' / f'AuthKey_{key_id}.p8'
key_file.write_text(os.environ['ASC_PRIVATE_KEY'])
key_file.chmod(0o600)
PY

security cms -D -i "$signing_dir/Porch.mobileprovision" > "$signing_dir/profile.plist"
python3 - <<'PY'
import datetime, os, plistlib
from pathlib import Path
folder = Path(os.environ['PORCH_SIGNING_DIR'])
profile = plistlib.loads((folder / 'profile.plist').read_bytes())
team = os.environ['APPLE_TEAM_ID']
bundle = os.environ['IOS_BUNDLE_ID']
if team not in profile['TeamIdentifier']:
    raise SystemExit('Provisioning profile does not match APPLE_TEAM_ID')
if profile['Entitlements'].get('application-identifier') != f'{team}.{bundle}':
    raise SystemExit('Provisioning profile does not match IOS_BUNDLE_ID')
if profile['ExpirationDate'] <= datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None):
    raise SystemExit('Provisioning profile has expired')
if profile.get('ProvisionedDevices') or profile.get('ProvisionsAllDevices') or profile['Entitlements'].get('get-task-allow'):
    raise SystemExit('Use an App Store distribution profile, not development, ad hoc, or enterprise')
(folder / 'profile-name').write_text(profile['Name'])
(folder / 'profile-uuid').write_text(profile['UUID'])
options = {
    'method': 'app-store-connect', 'destination': 'export',
    'signingStyle': 'manual', 'teamID': team,
    'signingCertificate': 'Apple Distribution',
    'provisioningProfiles': {bundle: profile['UUID']},
    'manageAppVersionAndBuildNumber': False,
    'stripSwiftSymbols': True, 'uploadSymbols': True
}
(folder / 'ExportOptions.plist').write_bytes(plistlib.dumps(options))
PY

profile_name="$(cat "$signing_dir/profile-name")"
profile_uuid="$(cat "$signing_dir/profile-uuid")"
profile_folder="$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"
mkdir -p "$profile_folder"
cp "$signing_dir/Porch.mobileprovision" "$profile_folder/$profile_uuid.mobileprovision"

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
# Only the app target consumes this profile; Swift package resource bundles do not.
xcodebuild -project ios/Porch.xcodeproj -scheme Porch \
  -configuration Release -destination 'generic/platform=iOS' \
  -archivePath "$archive_path" \
  DEVELOPMENT_TEAM="$APPLE_TEAM_ID" PRODUCT_BUNDLE_IDENTIFIER="$IOS_BUNDLE_ID" \
  CURRENT_PROJECT_VERSION="$build_number" \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY='Apple Distribution' \
  PORCH_APP_PROVISIONING_PROFILE="$profile_name" archive

xcodebuild -exportArchive -archivePath "$archive_path" \
  -exportPath "$export_path" -exportOptionsPlist "$signing_dir/ExportOptions.plist"

xcrun altool --validate-app --type ios --file "$export_path/Porch.ipa" \
  --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID"
xcrun altool --upload-app --type ios --file "$export_path/Porch.ipa" \
  --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID"

if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  echo "Uploaded Porch 0.1.0 ($build_number) to App Store Connect. Wait for Apple processing, then assign it to a TestFlight group." >> "$GITHUB_STEP_SUMMARY"
fi
