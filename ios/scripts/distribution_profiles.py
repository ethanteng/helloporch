#!/usr/bin/env python3
"""Validate App Store profiles and signed Porch/DriverKit bundles without uploads."""
import argparse
import datetime as dt
import hashlib
import json
import plistlib
import subprocess
import tempfile
from pathlib import Path

DRIVER = "com.apple.developer.driverkit"
USB = DRIVER + ".transport.usb"
COMMUNICATES = DRIVER + ".communicates-with-drivers"
ASSOCIATED_DOMAINS = "com.apple.developer.associated-domains"


def require(condition, message):
    if not condition:
        raise ValueError(message)


def validate_profile(profile, team, bundle, driver=False, now=None, communicates=True):
    ent = profile.get("Entitlements", {})
    label = "Driver" if driver else "App"
    now = now or dt.datetime.now(dt.timezone.utc)
    expiry = profile["ExpirationDate"]
    if expiry.tzinfo is None:
        expiry = expiry.replace(tzinfo=dt.timezone.utc)
    require(team in profile.get("TeamIdentifier", []), f"{label}: wrong Apple team")
    app_id = ent.get("application-identifier", ent.get("com.apple.application-identifier"))
    require(app_id == f"{team}.{bundle}", f"{label}: wrong bundle identifier")
    require("iOS" in profile.get("Platform", []), f"{label}: profile does not support iPadOS")
    require(expiry > now, f"{label}: expired provisioning profile")
    require(not profile.get("ProvisionedDevices") and not profile.get("ProvisionsAllDevices")
            and not ent.get("get-task-allow") and ent.get("beta-reports-active") is True,
            f"{label}: use an App Store Connect profile, not development/ad hoc/enterprise")
    require(bool(profile.get("DeveloperCertificates")), f"{label}: no signing certificate")
    if driver:
        require(ent.get(DRIVER) is True, "Driver: Apple has not authorized the DriverKit distribution entitlement")
        grants = ent.get(USB, [])
        require(isinstance(grants, list) and any(
            isinstance(g, dict) and g.get("idVendor") == 6790
            and ("idProduct" not in g or g["idProduct"] == 29987) for g in grants),
            "Driver: profile lacks USB distribution permission for Cell2Jack (VID 0x1A86, PID 0x7523)")
    else:
        require(ent.get("aps-environment") == "production", "App: production Push Notifications are missing")
        # Invitation links from helloporch.store open the app. App Store profiles grant the capability as "*".
        domains = ent.get(ASSOCIATED_DOMAINS)
        require(domains == "*" or (isinstance(domains, list) and "applinks:helloporch.store" in domains),
                "App: Associated Domains is missing; enable it for the App ID, then regenerate the profile")
        if communicates:
            require(ent.get(COMMUNICATES) is True, "App: DriverKit Communicates with Drivers is missing")
    return {"name": profile["Name"], "uuid": profile["UUID"], "bundleID": bundle,
            "expires": expiry.isoformat(), "driver": driver}


def validate_pair(app, driver, team, app_id, driver_id):
    summaries = [validate_profile(app, team, app_id), validate_profile(driver, team, driver_id, True)]
    require(bool(set(app["DeveloperCertificates"]) & set(driver["DeveloperCertificates"])),
            "App and driver profiles must authorize a common distribution certificate")
    return summaries


def decode_profile(path):
    return plistlib.loads(subprocess.run(["security", "cms", "-D", "-i", str(path)],
                                        capture_output=True, check=True).stdout)


def verify_bundle(bundle, team, app_id, driver_id, variant="cell2jack"):
    drivers = list((bundle / "SystemExtensions").glob("*.dext"))
    family = variant == "family"
    require(len(drivers) == (0 if family else 1),
            "Family build must not embed a driver" if family else "Signed app must embed exactly one Cell2Jack driver")
    profiles = [decode_profile(bundle / "embedded.mobileprovision")]
    products, identifiers = [bundle], [app_id]
    if family:
        settings = [path for path in (bundle / "Settings.bundle").rglob("*") if path.is_file()]
        require(not any(b"cell2jack" in path.read_bytes().lower() for path in settings),
                "Family build must not include Cell2Jack driver settings")
        require((bundle / "Settings.bundle" / "Acknowledgements.plist").is_file(),
                "Family build must include open-source acknowledgements")
        summaries = [validate_profile(profiles[0], team, app_id, communicates=False)]
    else:
        profiles.append(decode_profile(drivers[0] / "embedded.provisionprofile"))
        products.append(drivers[0]); identifiers.append(driver_id)
        summaries = validate_pair(*profiles, team, app_id, driver_id)
    subprocess.run(["codesign", "--verify", "--deep", "--strict", str(bundle)], check=True)
    for index, (product, identifier, profile) in enumerate(zip(products, identifiers, profiles)):
        info = plistlib.loads((product / "Info.plist").read_bytes())
        require(info["CFBundleIdentifier"] == identifier, "Signed product has the wrong bundle ID")
        ent = plistlib.loads(subprocess.run(["codesign", "-d", "--entitlements", ":-", str(product)],
                                           capture_output=True, check=True).stdout)
        require(not ent.get("get-task-allow"), "Signed product still permits development debugging")
        require(ent.get("com.apple.developer.team-identifier") == team, "Signature has the wrong team")
        signed_id = ent.get("application-identifier", ent.get("com.apple.application-identifier"))
        require(signed_id == f"{team}.{identifier}", "Signature has the wrong application identifier")
        if index == 0:
            require(ent.get("aps-environment") == "production", "App signature is missing production push")
            if family:
                require(not any(key.startswith(DRIVER) for key in ent),
                        "Family signature must not request DriverKit entitlements")
            else:
                require(ent.get(COMMUNICATES) is True, "App signature is missing driver communication")
        else:
            require(ent.get(DRIVER) is True and ent.get(USB) == [{"idVendor": 6790, "idProduct": 29987}],
                    "Driver signature must contain DriverKit and the exact Cell2Jack USB restriction")
        with tempfile.TemporaryDirectory() as tmp:
            prefix = str(Path(tmp) / "signer-")
            subprocess.run(["codesign", "-d", f"--extract-certificates={prefix}", str(product)],
                           capture_output=True, check=True)
            cert = Path(prefix + "0").read_bytes()
            require(cert in profile["DeveloperCertificates"], "Actual signer is not authorized by its embedded profile")
            summaries[index]["signerSHA256"] = hashlib.sha256(cert).hexdigest()
    if not family:
        require(summaries[0]["signerSHA256"] == summaries[1]["signerSHA256"], "App and driver use different signers")
        require(plistlib.loads((bundle / "Info.plist").read_bytes())["CFBundleVersion"] ==
                plistlib.loads((drivers[0] / "Info.plist").read_bytes())["CFBundleVersion"],
                "App and embedded driver build numbers differ")
    return summaries


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["prepare", "verify"])
    parser.add_argument("--team", required=True)
    parser.add_argument("--app-id", required=True)
    parser.add_argument("--driver-id", required=True)
    parser.add_argument("--variant", choices=["family", "cell2jack"], default="cell2jack")
    parser.add_argument("--directory", type=Path, required=True)
    parser.add_argument("--bundle", type=Path)
    args = parser.parse_args()
    try:
        if args.action == "prepare":
            app = plistlib.loads((args.directory / "profile.plist").read_bytes())
            if args.variant == "family":
                summaries = [validate_profile(app, args.team, args.app_id, communicates=False)]
            else:
                driver = plistlib.loads((args.directory / "driver-profile.plist").read_bytes())
                summaries = validate_pair(app, driver, args.team, args.app_id, args.driver_id)
            options = {"method": "app-store-connect", "destination": "export", "signingStyle": "manual",
                       "teamID": args.team, "signingCertificate": "Apple Distribution",
                       "provisioningProfiles": {s["bundleID"]: s["uuid"] for s in summaries},
                       "manageAppVersionAndBuildNumber": False, "stripSwiftSymbols": True, "uploadSymbols": True}
            (args.directory / "ExportOptions.plist").write_bytes(plistlib.dumps(options))
            for prefix, summary in zip(["profile", "driver-profile"], summaries):
                for field in ["name", "uuid"]:
                    (args.directory / f"{prefix}-{field}").write_text(summary[field])
        else:
            require(args.bundle is not None, "--bundle is required for signed bundle verification")
            summaries = verify_bundle(args.bundle, args.team, args.app_id, args.driver_id, args.variant)
        (args.directory / f"{args.action}-verification.json").write_text(json.dumps(summaries, indent=2) + "\n")
        print(f"{args.action}: {args.variant} distribution checks passed")
    except (ValueError, KeyError, OSError, subprocess.CalledProcessError, plistlib.InvalidFileException) as error:
        parser.exit(1, f"Distribution verification blocked: {error}\n")


if __name__ == "__main__":
    main()
