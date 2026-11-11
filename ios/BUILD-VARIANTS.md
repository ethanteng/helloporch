# Development and family TestFlight builds

Use the same feature branches and shared application code for both builds. Apple
approved Cell2Jack DriverKit distribution on 2026-11-10 (request 8AR5R3NKZD), so
`Porch` can now go to TestFlight too. Until a `Porch` TestFlight build has been
checked on an iPhone and an iPad without an M chip, `PorchFamily` stays the default.

| Use | Xcode scheme | Cell2Jack driver | Installation |
| --- | --- | --- | --- |
| Mom's bedside iPad | `Porch` | Included; optional and off by default | Development signing, install from the Mac |
| Family iPhones/iPads | `PorchFamily` | Excluded | Normal TestFlight; no Developer Mode |

Both use the existing `com.ethanteng.helloporch` app identity and ordinary Porch
UI. They replace one another on the same device. Do not install the family
TestFlight build over Mom's Cell2Jack development installation. Update her app
in place with a new `Porch` development build; do not uninstall it first. The Mac
is needed for installation, not for everyday operation.

## Developing features

- Bring current `main` into feature branches, preserving Cell2Jack integration.
- App sources, frameworks, and feature resources are shared build phases. Add new
  feature files to those shared phases so both variants receive them. Each variant
  has one resource phase of its own, holding only its Settings bundle:
  `Porch/Settings.bundle` has the driver settings and acknowledgements, and
  `Porch/FamilySettings/Settings.bundle` has only the acknowledgements.
- Keep standard USB/Bluetooth keypad and touchscreen paths independent of
  Cell2Jack. Family builds compile out the USB transport/bridge, omit DriverKit
  entitlements and driver settings, and hide the Cell2Jack caregiver section.
- Test new features normally. Use `PorchFamily` to verify the family package and
  `Porch` for actual Cell2Jack hardware testing. Update configuration-specific
  settings in both app targets when necessary.

## TestFlight workflow

**Upload Porch to TestFlight** defaults to `variant=family` and
`verify_only=true`. Family verification needs only the existing app distribution
profile and signing credentials; no driver profile is required. It verifies the
signed archive and exported IPA contain no driver or driver settings and request
no DriverKit entitlements, and then runs App Store validation.

After verification succeeds, explicitly choose `verify_only=false` to upload.
That run also deploys the calling server as before. Uploading does not itself
invite testers or publish to the App Store. Keep existing internal/external
TestFlight groups and beta review requirements.

`variant=cell2jack` selects `Porch` and retains the stricter app/driver profile,
certificate, signature, USB matching, and matching build-number checks. Its
driver profile, **Porch Cell2Jack TestFlight**, was regenerated with Apple's grant
on 2026-11-10 and is the `IOS_DRIVER_APPSTORE_PROFILE` secret. Apple granted the
Cell2Jack's vendor (`idVendor` 6790) without a product, and App Store validation
rejects a driver signature that asks for anything else, so the driver's
distribution entitlement names only the vendor. The driver's `IOKitPersonalities`
still match only the Cell2Jack (product 29987), and the check requires that.

Do not strip a driver from an already signed archive or reuse a development
profile for TestFlight. Build the intended variant from the start.

Local package/configuration checks:

```bash
python3 ios/scripts/check-build-variants.py
python3 -m unittest discover -s ios/scripts -p 'test_distribution_profiles.py'
```
