# TestFlight, development and fallback builds

Use the same feature branches and shared application code for every build. Apple
approved Cell2Jack DriverKit distribution on 2026-11-10 (request 8AR5R3NKZD), so
the TestFlight build is now `Porch`, with the driver, for every device: iPhones and
iPads, bedside or family. The first was 0.1.0 (76.1). `PorchFamily`, the same app
without the driver, stays only as a fallback that has to be chosen by hand.

| Use | Xcode scheme | Cell2Jack driver | Installation |
| --- | --- | --- | --- |
| Every TestFlight tester | `Porch` | Included; optional and off by default | TestFlight (`variant=cell2jack`, the default); no Developer Mode |
| Mom's bedside iPad, for now | `Porch` | Included; optional and off by default | Development signing, install from the Mac |
| Fallback only | `PorchFamily` | Excluded | TestFlight (`variant=family`), chosen by hand |

All use the existing `com.ethanteng.helloporch` app identity and ordinary Porch
UI. They replace one another on the same device. The driver only runs on an iPad
with an M chip and iPadOS 16 or later, once it's turned on in Settings → Porch.
Family iPhones use the touchscreen. A bedside iPad without an M chip uses the
Porch phone adapter or the touchscreen, and Porch doesn't try the driver there. Never install a
`PorchFamily` build on a bedside that uses a Cell2Jack plugged straight in,
since it has no driver. Mom's iPad keeps getting `Porch`
development builds in place until it moves to TestFlight on a visit
(ONBOARDING-PLAN.md, phase 0); do not uninstall it first.

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
- Test new features normally, in `Porch`. CI still builds `PorchFamily` and runs
  the family app's tests on an iPhone simulator with it, so keep it building.
  Update configuration-specific settings in both app targets when necessary.

## TestFlight workflow

**Upload Porch to TestFlight** defaults to `variant=cell2jack` and
`verify_only=true`. After verification succeeds, explicitly choose
`verify_only=false` to upload. That run also deploys the calling server as before.
Uploading does not itself invite testers or publish to the App Store. Keep existing
internal/external TestFlight groups and beta review requirements.

Don't upload `variant=family` in the normal course: its build number would be
higher than the driver build's, so it would replace the driver build on every
tester's device. Choose it only as a deliberate fallback, such as if a driver
build can't pass beta review. Family verification needs only the app profile, and
checks that the signed archive and exported IPA contain no driver or driver
settings and request no DriverKit entitlements.

`variant=cell2jack` selects `Porch` and retains the stricter app/driver profile,
certificate, signature, USB matching, and matching build-number checks. Its
driver profile, **Porch Cell2Jack TestFlight**, was regenerated with Apple's grant
on 2026-11-10 and is the `IOS_DRIVER_APPSTORE_PROFILE` secret. Apple granted the
Cell2Jack's vendor (`idVendor` 6790) without a product, and App Store validation
rejects a driver signature that asks for anything else, so the driver's
distribution entitlement names only the vendor. The driver's `IOKitPersonalities`
still match only the Cell2Jack (product 29987, device release 612, configuration 1,
interface 0), and the check requires that.

Do not strip a driver from an already signed archive or reuse a development
profile for TestFlight. Build the intended variant from the start.

Local package/configuration checks:

```bash
python3 ios/scripts/check-build-variants.py
python3 -m unittest discover -s ios/scripts -p 'test_distribution_profiles.py'
```
