# Native HelloPorch keypad preview

On `feature/cell2jack-ipad-version-poc`, select the **PorchKeypadPreview** scheme in
`Porch.xcodeproj`. Build 10 installs as **Porch Preview** on the M3 iPad. It uses
`com.ethanteng.helloporch.cell2jackpoc`, replacing Porch USB Test and retaining
its driver permission and captures. The regular Porch app has its own identity.
The USB extension remains the verified driver build 6, ABI 2.

## Using the installed preview

1. Connect Cell2Jack to the iPad with its USB data cable. Keep its driver enabled
   in Porch Preview's app settings.
2. Open Porch Preview, leave **Test state** on **Clock**, and tap **Start phone
   preview**. Lift the handset and press the phone keys slowly.
3. The result card shows the selected person or action, including the saved
   contact photo when available. Tap **Stop** when finished.
4. Choose another **Test state** to preview incoming, voice/video call,
   drop-in countdown, or message playback actions. These states are simulated.
   The screen keypad feeds the same preview resolver and identifies its source
   separately from physical USB events.

USB capture stops after two minutes, at its 4 MiB limit, or when the app leaves
the foreground. Normal Stop sends `/q` and closes the USB session. Cell2Jack's
own phone behavior remains active; this app only disables HelloPorch calling.

With the current saved setup, 1 and 2 select people, 3 is empty, 9 has no camera
action from Clock, 0 has no active call to answer/end, and * / # are unassigned.
In the simulated Video call state, 9 toggles the simulated camera and 0 previews
hanging up. Incoming 0 previews answering. Digit logs do not include reliable
key-down/up timing, so they cannot establish hold-to-decline behavior.

## Saved setup and safety boundary

The preview reuses PorchCore's contact and keypad models, the native Porch UI
style, and a pure `KeypadActionPreview` resolver. A read-only snapshot of this
iPad's ten saved slots, including two assigned contacts and their photo files,
was copied locally during setup. It is not a live view into the regular app's
sandbox. If assignments change, refresh that snapshot before comparing results.
A missing or invalid snapshot disables preview input on a physical iPad; sample
contacts require an explicit simulator-only launch option.

Snapshot files in the preview's Documents directory:

- `porch-preview-slots.json`: the existing `porch.slots.v2` data (keys 0–9).
- `porch-preview-symbol-slots.json`: the `porch.slots.v2.symbols` data (keys * and #),
  when the setup has it. Without it, * and # preview as empty person keys.
- `porch-preview-photos/`: the referenced contact photo files.

`CallSlots.snapshot` decodes without migration, preference writes, photo writes,
or pruning. The preview target compiles only its app/controller, shared styling,
USB bridge/capture/parser/result, and PorchCore. It does not compile the normal
app coordinator, family service, call controller, incoming-call handler, or link
LiveKit, CallKit, or PushKit. It has no call URL handlers, microphone/camera
permission entries, or background call modes. Check the closed source/package
boundary and optional built binary before installing:

```sh
python3 ios/scripts/check-keypad-preview.py \
  ios/build/PorchKeypadPreview/Build/Products/Debug-iphoneos/PorchKeypadPreview.app
```

Development signing and distribution limits remain as documented in
[CELL2JACK-POC.md](CELL2JACK-POC.md). This is not an approved TestFlight build.

## Verification

The user tested the physical M3 iPad directly connected to Cell2Jack and
confirmed that both contact cards and the other actions looked correct.
The saved USB and action traces agree:

| Physical key, in order | Clock preview outcome |
| --- | --- |
| 1 | First saved contact, video call selected |
| 2 | Second saved contact, video call selected |
| 3 | No person assigned |
| 9 | Camera key, no video call |
| 0 | No call to answer or end |
| * | No action assigned |
| # | No action assigned |

The capture recorded seven primary digit events, 1,060 log bytes, and manual
Stop with `/q sent; USB session closed.` This proves the direct iPad USB input
through preview routing for these seven keys in Clock state. The Mac retrieved
the records; it did not relay phone input. The user confirmed the displayed
contacts matched their saved setup. The regular Porch saved assignment bytes were
identical before and after the preview test.

Additional checks: all 68 PorchCore tests passed; both preview device/simulator
builds and the regular Porch simulator regression build passed. The signed
device binary passed the preview boundary check. Simulator Video call input
`990` produced camera off, camera on, then hang-up previews. The remaining
simulated contexts and saved remappings are covered by resolver tests; they
have not all been physically exercised on this iPad. No real Porch call was
placed by the preview.

`Documents/porch-preview-actions.json` records the source, raw USB line when
applicable, symbol, simulated state, and result. USB capture folders retain the
raw bytes and parser events separately. These local diagnostic records can
contain contact names; do not commit them or snapshot data to the repository.
