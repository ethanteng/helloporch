# Porch phone adapter

A small board between the Cell2Jack and the iPad that makes the big-button phone look like a USB number pad. Porch then reads the phone's keys the way it reads any keypad, so:

- **No DriverKit driver,** so no wait for Apple's approval. Families use the normal TestFlight build, with no Developer Mode.
- **Any iPad works,** not only M-series ones, because the iPad sees a keyboard.
- **Putting the receiver back still hangs up.** The adapter types F24 for it, which Porch treats like the driver's hang-up.

**Status:** tested on hardware on 2026-11-07, on a Mac and on an iPad with the TestFlight build: connecting, all twelve keys, hanging up with the receiver, and recovering after the Cell2Jack or the adapter is unplugged. For the pilot I flash and test each family's adapter, then mail it or drop it off. An overnight run is the one check still to do.

## Parts

| Part | Notes |
| --- | --- |
| [Adafruit Feather RP2040 with USB Type A Host](https://www.adafruit.com/product/5723) | $17.50, or $15.75 each for ten or more. Its USB-A port is the host port the Cell2Jack plugs into, and its USB-C port goes to the iPad |
| USB-C data cable | From the Feather to the iPad's hub. A charge-only cable won't work |
| The pilot's usual parts | Cell2Jack, big-button phone set to tone dialing, and the USB-C hub with a charging port |

Connected: phone → Cell2Jack's phone port; Cell2Jack's USB cable → Feather's USB-A port; Feather's USB-C port → hub → iPad.

## Build and flash

```sh
phone-adapter/build.sh
```

The first run installs `arduino-cli`'s pinned RP2040 core (6.3.2, which includes Adafruit TinyUSB) and Pico PIO USB (0.7.3). It writes `phone-adapter/build/porch_phone_adapter.ino.uf2`. To flash it, hold **BOOT** on the Feather, press **RESET**, and copy the file onto the `RPI-RP2` drive that appears.

`phone-adapter/test.sh` runs the host tests, and CI runs them too. Pass it a raw Cell2Jack capture (`Documents/cell2jack-usb-tail.bin` from a bedside, or a test app's `received.bin`) to print what the adapter would type for it.

## What it does

The Feather's two cores split the work ([porch_phone_adapter.ino](firmware/porch_phone_adapter/porch_phone_adapter.ino)):

- **Core 1, the Cell2Jack.** It accepts only USB ID 1A86:7523 and repeats the sequence the iPad driver proved on hardware: DTR and RTS off, 2,000,000 baud, 8N1, `/v`, 500 ms, then `/d`. If no log arrives within two seconds it sends `/q` and tries again, three times, then waits 1, 2, 4, 8 and 15 seconds between rounds ([cell2jack_session.c](firmware/porch_phone_adapter/cell2jack_session.c)). It sends only `/v`, `/d` and `/q`.
- **The parser** ([cell2jack_parser.c](firmware/porch_phone_adapter/cell2jack_parser.c)) is a line-for-line port of `Cell2JackDTMFParser.swift`, and [adapter_tests.c](tests/adapter_tests.c) replays the same captures as `DTMFParserTests.swift`. So the phantom 1 on pickup, diagnostic repeats, joined lines and the ON_HOOK at startup are all handled the same way. Change both parsers together.
- **Core 0, the keyboard.** It types each key as a USB keyboard named "Porch Phone Adapter", one at a time. Keys more than a second old are dropped, as Porch does with the driver.

| Phone | Key the iPad sees |
| --- | --- |
| 0–9 | Keypad 0–9 |
| * and # | Keypad * and keypad # |
| Receiver back on the cradle, after a pickup | F24 |
| Pulse digits, diagnostic repeats, A–D | Nothing |

The red LED is off with no Cell2Jack, blinks while connecting, and stays on once keys will work. It flickers for each key typed. The USB-C side also has a serial port that prints the adapter's status and echoes the Cell2Jack log, for a Mac during bring-up. If an iPad refuses the adapter because of that port, set `PORCH_ADAPTER_SERIAL_LOG` to 0.

## In Porch

In setup, **How will Mom call? → Corded phone** opens **Connect the phone**, which checks a key and the receiver going back. **This iPad → Connect the physical phone** opens it again and has **Hang up when the receiver is put back**, which is on by default. Both are in every build.

The digits work like any number pad's. Hanging up needs the Porch build of 2026-11-04 or later, which reads F24 ([CallTrigger.receiverHangUpKey](../ios/PorchCore/Sources/PorchCore/CallTrigger.swift), routed in `PorchWindow` and [Cell2JackKeypad.receiveAdapterHangUp](../ios/Porch/Cell2JackKeypad.swift)). From the adapter's first hang-up on, Porch keeps its usual trace in `Documents/cell2jack-call-actions.json`, with `rawLine` set to `phone adapter`, even though the driver is off.

## Testing it

1. **On a Mac first.** Flash the Feather, plug the Cell2Jack into it, and plug the Feather into the Mac. Open the serial port, for example with `arduino-cli monitor -p /dev/cu.usbmodem…`. Expect "connecting to the Cell2Jack", then the `CJ Version = a06` reply and log lines, then "ready" with the LED on.
2. Lift the receiver and press `1 2 3 4 5 6 7 8 9 0 * #`. Each should print "typed key". With TextEdit in front, the digits appear there too. Put the receiver back and look for `typed key 0x73`.
3. Unplug and replug the Cell2Jack, and the Feather. Each time the adapter should reach "ready" again by itself.
4. **On an iPad,** through the hub with its charger. Run Porch's **This iPad → Connect the phone** check, then call someone with a key, and end the call by putting the receiver back. Also try # on a key that has an action, an incoming call answered with the call-control key, and a call that rings while a screen is opening.
5. Leave it connected overnight and check that it still works in the morning.

## What the hardware tests showed

- **Connecting** takes about 3 seconds. The first `/d` gets no reply and the second works, as with the iPad driver, so the retry matters.
- **DTR and RTS at plug-in:** the brief pulse while TinyUSB sets up the CH340 did no harm.
- **Power:** the Cell2Jack runs from the Feather's USB-A port and plays its dial tone.
- **Keys on iPadOS:** keypad # (0xCC) and F24 both reach Porch. A Mac's TextEdit shows nothing for keypad #, because macOS has no character for it, so check # on the iPad.
- **Serial port:** the iPad ignores it and uses the keyboard.
- **Noise in the log:** the Cell2Jack goes into Bluetooth pairing mode and warns about a missing microphone. That's the Cell2Jack's own chatter and doesn't affect the keys.
