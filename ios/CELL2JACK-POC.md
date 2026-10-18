# Cell2Jack version-only iPad proof of concept

This experiment is on `feature/cell2jack-ipad-version-poc`. Open `ios/Porch.xcodeproj`
and select the **PorchCell2Jack** scheme. It builds a separate **Porch USB Test**
app (`com.ethanteng.helloporch.cell2jackpoc`) containing a USB DriverKit extension
(`com.ethanteng.helloporch.cell2jackpoc.usbdriver`). The normal Porch scheme, app ID,
entitlements, contact data, calling code, and release workflow are unchanged.
Delete this test app to remove the experiment from the iPad.

## What the test does

On **Read Cell2Jack version**, the app opens only its named DriverKit service,
asks for one version response, then closes the user client. The driver matches
USB **VID 1A86 / PID 7523 / interface 0 / configuration 1 / device revision
0x0264**, discovers bulk endpoints, identifies
the CH34x serial-chip revision, and configures its volatile serial registers
for **2,000,000 baud, 8N1, no hardware flow control, DTR/RTS inactive**. The only
serial bytes it sends are **`2f 76` (`/v`)**. It collects up to 256 received
bytes with a bounded receive window, preserving fragmented packets. The app
shows the `CJ Version = a06` header when present, raw text/hex, serial-chip
revision, and the USB error/stage when an operation fails. The copy button
copies that result for troubleshooting.

No `/d`, bootloader/recovery packets, arbitrary write interface, call actions,
network connection, Mac bridge, firmware image or flash operation is included.
The `/v` response was verified on the user's Mac. The CH34x register setup and
iPad transport are new and **have not yet been verified on a physical iPad**.
Serial-chip revisions below `0x30` intentionally report unsupported: older
line-control variants need separate implementation and testing.

The USB ID is shared by other CH34x adapters. Enable this experimental driver
only for this test, and connect **only Cell2Jack**, not other adapters with that
ID. The app rejects multiple matching driver instances. The extension does
not grant access to unrelated apps; the iPad app/driver share a parent bundle.

## Build and verification

Requirements: full Xcode with iOS and DriverKit SDKs. DriverKit deployment target
22.0 corresponds to its initial iPadOS 16 support; the test app targets iPadOS
16+. The intended test device is the user's **iPad Air 11-inch (M3), iPadOS
18.7.2**. An A-series iPad cannot run this driver.

Run host-side response/ABI/baud checks (no hardware access):

```sh
ios/scripts/test-cell2jack.sh
```

Build the complete app and embedded driver without signing:

```sh
xcodebuild -project ios/Porch.xcodeproj -scheme PorchCell2Jack \
  -configuration Debug -destination 'generic/platform=iOS' \
  -derivedDataPath /tmp/PorchCell2JackDerived CODE_SIGNING_ALLOWED=NO build
```

This creates a compile-verifiable app, **not an installable signed build**.
The simulator build omits the extension and cannot perform USB I/O. Pressing
Read in Simulator reports that a physical M-series iPad is required; it never
substitutes fake hardware success. The regular `Porch` scheme has no dependency
on the experimental driver.

## Signing prerequisite — required before the physical-device test

Xcode automatic provisioning successfully created **development** profiles for
both experiment identifiers on this Mac. The signed development app and its
embedded driver now build successfully. The app profile contains
`com.apple.developer.driverkit.communicates-with-drivers`; the driver profile
contains DriverKit and a development USB matching allowance. The Debug driver uses Apple's required development-only wildcard USB
entitlement. Its matching personality remains restricted to
1A86:7523/interface 0; the Release entitlement file retains the vendor/product
restriction and requires separate distribution approval.
This does **not** establish approval for TestFlight/App Store distribution.

| Target | Required entitlement |
| --- | --- |
| PorchCell2Jack | `com.apple.developer.driverkit.communicates-with-drivers = true` |
| PorchCell2JackDriver | `com.apple.developer.driverkit = true` |
| PorchCell2JackDriver (Debug) | `com.apple.developer.driverkit.transport.usb = [{idVendor: "*"}]` |
| PorchCell2JackDriver (Release) | `com.apple.developer.driverkit.transport.usb = [{idVendor: 6790, idProduct: 29987}]` |

For the first physical test, temporarily connect and unlock the **M3 iPad** on
the development Mac, accept the normal device pairing/development setup, and
select it in Xcode. Automatic provisioning must include **that iPad's UDID**
before installation. Both development profiles now include the M3 iPad. The app was successfully
installed and launched on the physical iPad on 2026-10-17. Direct Cell2Jack
communication is still awaiting the driver-enable and USB connection test. The Mac is
only needed for provisioning/installing this development build, not at runtime.

Rebuild/sign with the device selected, or use:

```sh
xcodebuild -project ios/Porch.xcodeproj -scheme PorchCell2Jack \
  -configuration Debug -destination 'id=THE_M3_IPAD_UDID' \
  -derivedDataPath ios/build/Cell2JackSigned \
  -allowProvisioningUpdates -allowProvisioningDeviceRegistration build
```

Use an ignored build folder under the repository rather than an iCloud-synced
Documents directory. During this session Finder metadata on a generated bundle
under Documents caused `codesign` to reject it; the same sources signed cleanly
from `ios/build/Cell2JackSigned`.

For distribution beyond the development test, request the appropriate DriverKit
USB permissions from Apple. Explain that this is **third-party WCH USB serial
hardware inside Cell2Jack**, not hardware manufactured by our team; we do not
own vendor ID 1A86. Distribution approval is not assumed. Do not disable iPad
security checks or install an unsigned build. The existing Porch TestFlight
workflow intentionally does not upload this experiment. The driver profile
can be explicitly selected with `PORCH_CELL2JACK_DRIVER_PROFILE` if required.

## Physical acceptance test

1. Install the signed **Porch USB Test** app on the M3 iPad.
2. Tap **Open app settings** in the test app and enable its system-provided driver
   switch if present. Alternatively, look for **Drivers** under **Settings →
   Privacy & Security** or **General**; Apple's documentation gives different
   locations. Build 2 includes a `Settings.bundle` so iPadOS always creates an
   app settings page. This follows Apple's [suggested workaround for missing
   driver settings](https://developer.apple.com/forums/thread/843589), but does
   not guarantee the driver switch appears. The bundle contains no custom driver
   toggle: only iPadOS can grant this permission. If absent in all locations,
   investigate system registration rather than assuming the device is silent.
3. Use a USB-C data adapter/cable to connect Cell2Jack's USB port to the iPad.
   If simultaneous charging or extra power is needed, use an appropriate powered
   USB-C hub; a charge-only cable will not work.
4. Open the test app and tap **Read Cell2Jack version**. Expect `a06`, matching
   the Mac response, plus the received raw bytes. No Mac is involved in this path.
5. Copy the result. Retry three times; unplug/replug the adapter and repeat.
   Also verify a disconnected device gives a clear failure rather than a stale
   version. Report chip revision, failing stage and hexadecimal result on errors.
6. Disable/remove the driver after testing. HelloPorch calls, audio routing and
   DTMF control are outside this first milestone.

## Protocol references and limits

- Apple's [Creating drivers for iPadOS](https://developer.apple.com/documentation/driverkit/creating-drivers-for-ipados)
  and [DriverKit entitlements](https://developer.apple.com/documentation/driverkit/requesting-entitlements-for-driverkit-development).
- Apple's [DriverKit/user-client sample](https://developer.apple.com/documentation/driverkit/communicating-between-a-driverkit-extension-and-a-client-app)
  informed service registration and user-client plumbing; its license is retained
  in `Cell2JackDriver/APPLE-SAMPLE-LICENSE.txt`.
- The primary CH34x register/baud reference is the Linux driver's
  [`ch341.c`](https://github.com/torvalds/linux/blob/master/drivers/usb/serial/ch341.c).
  This experiment implements a narrow fixed-speed transaction, not a port of
  that general-purpose serial driver. For this speed the 48 MHz clock, prescaler
  3, factor 0, divisor 3 yield the fixed divisor register `fd03` (or `fd83` with
  the short-packet bit). Hardware verification is still required.
- Cell2Jack `/v` bytes and speed come from static analysis of the user's logger/
  Mac utility followed by the user's successful HW5/a06 Mac test. No trailing
  newline, debug activation, or recovery is added to this version request.

### Physical-device signing correction

Installation initially rejected a cached driver profile that covered only the
previous A16 iPad. Regenerating under the experiment's `.usbdriver` identifier
included the M3. iPadOS then rejected the numeric vendor entitlement because
the development profile grants the development-only wildcard variant, not
the distribution variant. Debug now uses
`Cell2JackDriver.Development.entitlements`; Release keeps the restricted
`Cell2JackDriver.entitlements`. This follows Apple's
[How to sign a DEXT](https://developer.apple.com/forums/thread/809202).
The physical device accepted this build and launched the app. These install
checks are in addition to host compilation and signature verification; they
do not yet verify the actual USB version transaction.

### USB matching correction after the first iPad attempt

The user enabled the driver in the app's settings and connected Cell2Jack, but
app build 2 reported no running driver service. That error occurs before the
version request and cannot establish a baud-rate or firmware failure.

App build 3 / driver build 2 adds the missing `bConfigurationValue` property to
the USB interface personality. Apple's documented vendor/product interface
matching combination requires configuration and interface number as well as
vendor and product. The configuration uses the documented string wildcard `*`
because the actual descriptor value has not been captured from this unit;
vendor, product, and interface remain exact. This is a concrete metadata defect
correction, but hardware retesting is required to determine whether it resolves
the observed failure. Unplug Cell2Jack during driver replacement, then reconnect
it with the driver's switch enabled.

References: Apple's [USB interface matching combinations](https://developer.apple.com/documentation/iousbhost/iousbhostinterface/creatematchingdictionary(vendorid:productid:bcddevice:interfacenumber:configurationvalue:interfaceclass:interfacesubclass:interfaceprotocol:speed:productidarray:))
and [USB matching rules and string wildcards](https://developer.apple.com/library/archive/qa/qa1076/_index.html).

### Confirmed iPad registry observations and more-specific matching

The first matching correction did not resolve the failure. A read-only snapshot
captured from the physical iPad showed one matching `IOUSBHostDevice`, one
matching `IOUSBHostInterface`, and an `AppleUSBCHCOM` child of that interface
(`IOUserSerial`). No `IOUserService` with our `IOUserClass` was present. Thus the
USB device and interface are visible, and Apple's built-in serial driver has
attached; this is stronger evidence than the previous generic app error.

Individual property reads were filtered by iPadOS even though the APIs reported
success. Exact `IOPropertyMatch` queries confirmed configuration 1, interface 0,
and `bcdDevice=612` (`0x0264`) for VID 6790 / PID 29987. Configuration 2, several
other device revisions, and an unrelated VID/PID negative control gave zero
matches. These are observed descriptor matches, not assumed values. This USB
device revision is distinct from the serial-chip revision read by the USB
vendor request, and from Cell2Jack firmware `a06`.

App build 5 / driver build 3 uses all five exact interface matching fields. The
documented score is 100000 rather than the wildcard configuration's 89000. The
Mac's installed AppleUSBCHCOM metadata uses the four-field 90000 combination;
the exact iPad Apple personality has not been dumped. Outmatching the observed
Apple driver is the intended correction, and still requires a detach/reattach
test. No custom `IOProbeScore`, driver disabling, or system security change is
used.

The app also preserves a read-only `Documents/usb-diagnostics.txt` snapshot on
launch and failure and `Documents/version-result.txt` after a version attempt.
Snapshots cover only our USB IDs, service, child names/classes, and bounded
exact matching checks. The developer-only launch argument
`--read-cell2jack-version` performs the same `/v` action as the visible button;
ordinary launch still sends no serial request.
