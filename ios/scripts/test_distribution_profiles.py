import datetime as dt
import plistlib
import tempfile
import unittest
from types import SimpleNamespace
from pathlib import Path
from unittest.mock import patch

from distribution_profiles import COMMUNICATES, DRIVER, USB, main, validate_pair, validate_profile, verify_bundle

TEAM = "TESTTEAM42"
APP = "example.porch"
DRIVER_ID = APP + ".usbdriver"


def profile(driver=False):
    return {
        "Name": "Test driver" if driver else "Test app", "UUID": "driver" if driver else "app",
        "TeamIdentifier": [TEAM], "Platform": ["iOS"],
        "ExpirationDate": dt.datetime.now(dt.timezone.utc) + dt.timedelta(days=1),
        "DeveloperCertificates": [b"synthetic shared certificate"],
        "Entitlements": {
            "application-identifier": TEAM + "." + (DRIVER_ID if driver else APP),
            "beta-reports-active": True, "get-task-allow": False,
            **({DRIVER: True, USB: [{"idVendor": 6790, "idProduct": 29987}]} if driver else
               {"aps-environment": "production", COMMUNICATES: True})}}


class DistributionProfileTests(unittest.TestCase):
    def test_family_prepare_needs_only_app_profile_and_exports_only_app(self):
        candidate = profile()
        del candidate["Entitlements"][COMMUNICATES]
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder)
            (path / "profile.plist").write_bytes(plistlib.dumps(candidate))
            with patch("sys.argv", ["profiles", "prepare", "--variant", "family", "--directory", folder,
                                    "--team", TEAM, "--app-id", APP, "--driver-id", DRIVER_ID]):
                main()
            options = plistlib.loads((path / "ExportOptions.plist").read_bytes())
            self.assertEqual(options["provisioningProfiles"], {APP: "app"})
            self.assertFalse((path / "driver-profile-uuid").exists())

    def test_family_still_requires_production_push(self):
        candidate = profile()
        del candidate["Entitlements"]["aps-environment"]
        with self.assertRaisesRegex(ValueError, "Push Notifications"):
            validate_profile(candidate, TEAM, APP, communicates=False)

    def test_family_rejects_accidentally_embedded_driver(self):
        with tempfile.TemporaryDirectory() as folder:
            bundle = Path(folder)
            (bundle / "SystemExtensions" / "unexpected.dext").mkdir(parents=True)
            with self.assertRaisesRegex(ValueError, "must not embed"):
                verify_bundle(bundle, TEAM, APP, DRIVER_ID, "family")

    def test_family_rejects_driver_settings(self):
        with tempfile.TemporaryDirectory() as folder:
            bundle = Path(folder)
            (bundle / "Settings.bundle").mkdir()
            (bundle / "Settings.bundle" / "Root.plist").write_bytes(plistlib.dumps(
                {"PreferenceSpecifiers": [{"Type": "PSGroupSpecifier", "FooterText": "Enable the Cell2Jack driver"}]}))
            with patch("distribution_profiles.decode_profile", return_value=profile()):
                with self.assertRaisesRegex(ValueError, "driver settings"):
                    verify_bundle(bundle, TEAM, APP, DRIVER_ID, "family")

    def test_family_signed_bundle_checks_signer_and_forbids_driver_entitlements(self):
        candidate = profile()
        for driver_entitlement in [False, True]:
            with self.subTest(driver_entitlement=driver_entitlement), tempfile.TemporaryDirectory() as folder:
                bundle = Path(folder)
                (bundle / "Info.plist").write_bytes(plistlib.dumps({"CFBundleIdentifier": APP, "CFBundleVersion": "1"}))
                (bundle / "Settings.bundle").mkdir()
                (bundle / "Settings.bundle" / "Acknowledgements.plist").write_bytes(plistlib.dumps(
                    {"PreferenceSpecifiers": [{"Type": "PSGroupSpecifier", "Title": "PhoneNumberKit"}]}))
                entitlements = {"application-identifier": TEAM + "." + APP,
                                "com.apple.developer.team-identifier": TEAM, "aps-environment": "production"}
                if driver_entitlement:
                    entitlements[COMMUNICATES] = True
                def codesign(command, **kwargs):
                    for value in command:
                        if value.startswith("--extract-certificates="):
                            Path(value.split("=", 1)[1] + "0").write_bytes(candidate["DeveloperCertificates"][0])
                    return SimpleNamespace(stdout=plistlib.dumps(entitlements))
                with patch("distribution_profiles.decode_profile", return_value=candidate), \
                     patch("distribution_profiles.subprocess.run", side_effect=codesign):
                    if driver_entitlement:
                        with self.assertRaisesRegex(ValueError, "must not request DriverKit"):
                            verify_bundle(bundle, TEAM, APP, DRIVER_ID, "family")
                    else:
                        result = verify_bundle(bundle, TEAM, APP, DRIVER_ID, "family")
                        self.assertEqual(len(result), 1)
                        self.assertIn("signerSHA256", result[0])

    def test_separate_profiles_keep_both_bundle_ids(self):
        result = validate_pair(profile(), profile(True), TEAM, APP, DRIVER_ID)
        self.assertEqual([item["bundleID"] for item in result], [APP, DRIVER_ID])

    def test_actual_portal_shape_without_driver_grants_is_rejected(self):
        candidate = profile(True)
        del candidate["Entitlements"][DRIVER]
        del candidate["Entitlements"][USB]
        with self.assertRaisesRegex(ValueError, "not authorized the DriverKit"):
            validate_pair(profile(), candidate, TEAM, APP, DRIVER_ID)

    def test_wildcard_development_usb_is_not_distribution_permission(self):
        candidate = profile(True)
        candidate["Entitlements"][USB] = [{"idVendor": "*"}]
        with self.assertRaisesRegex(ValueError, "lacks USB distribution permission"):
            validate_profile(candidate, TEAM, DRIVER_ID, True)

    def test_vendor_grant_covers_restricted_product(self):
        candidate = profile(True)
        candidate["Entitlements"][USB] = [{"idVendor": 6790}]
        validate_profile(candidate, TEAM, DRIVER_ID, True)

    def test_other_vendor_or_product_cannot_authorize_cell2jack(self):
        for grant in [{"idVendor": 1, "idProduct": 29987}, {"idVendor": 6790, "idProduct": 1}]:
            with self.subTest(grant=grant):
                candidate = profile(True)
                candidate["Entitlements"][USB] = [grant]
                with self.assertRaisesRegex(ValueError, "lacks USB"):
                    validate_profile(candidate, TEAM, DRIVER_ID, True)

    def test_development_ad_hoc_enterprise_and_wrong_platform_are_rejected(self):
        for modification in [{"ProvisionedDevices": ["test-device"]}, {"ProvisionsAllDevices": True},
                             {"Platform": ["OSX"]}, {"TeamIdentifier": ["OTHERTEAM"]},
                             {"ExpirationDate": dt.datetime.now(dt.timezone.utc) - dt.timedelta(days=1)}]:
            with self.subTest(modification=modification):
                candidate = profile(True)
                candidate.update(modification)
                with self.assertRaises(ValueError):
                    validate_profile(candidate, TEAM, DRIVER_ID, True)

    def test_required_app_store_and_app_capabilities_cannot_be_omitted(self):
        for key in ["beta-reports-active", "aps-environment", COMMUNICATES]:
            with self.subTest(key=key):
                candidate = profile()
                del candidate["Entitlements"][key]
                with self.assertRaises(ValueError):
                    validate_profile(candidate, TEAM, APP)

    def test_wrong_application_id_and_debuggable_profile_are_rejected(self):
        for key, value in [("application-identifier", TEAM + "." + DRIVER_ID), ("get-task-allow", True)]:
            with self.subTest(key=key):
                candidate = profile()
                candidate["Entitlements"][key] = value
                with self.assertRaises(ValueError):
                    validate_profile(candidate, TEAM, APP)

    def test_nonoverlapping_certificates_are_rejected(self):
        candidate = profile(True)
        candidate["DeveloperCertificates"] = [b"different certificate"]
        with self.assertRaisesRegex(ValueError, "common distribution certificate"):
            validate_pair(profile(), candidate, TEAM, APP, DRIVER_ID)


if __name__ == "__main__":
    unittest.main()
