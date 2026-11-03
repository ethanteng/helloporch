#!/bin/sh
# Builds the phone adapter firmware into phone-adapter/build/porch_phone_adapter.ino.uf2.
# Needs arduino-cli (brew install arduino-cli). The first run installs the pinned
# RP2040 core and Pico PIO USB library; the core includes Adafruit TinyUSB.
# To flash, copy the .uf2 onto the Feather's RPI-RP2 drive (see README.md).
set -eu
here=$(cd "$(dirname "$0")" && pwd)
core=rp2040:rp2040@6.3.2
pio_usb="Pico PIO USB@0.7.3"
fqbn=rp2040:rp2040:adafruit_feather_usb_host:freq=120,usbstack=tinyusb
index=https://github.com/earlephilhower/arduino-pico/releases/download/global/package_rp2040_index.json

if ! arduino-cli core list | grep -q "^rp2040:rp2040 *6.3.2"; then
  arduino-cli core update-index --additional-urls "$index"
  arduino-cli core install "$core" --additional-urls "$index"
fi
arduino-cli lib list | grep -q "^Pico PIO USB *0.7.3" || arduino-cli lib install "$pio_usb"

mkdir -p "$here/build"
arduino-cli compile --fqbn "$fqbn" --warnings default \
  --library "$(arduino-cli config get directories.user)/libraries/Pico_PIO_USB" \
  --output-dir "$here/build" "$here/firmware/porch_phone_adapter"
echo "Firmware: $here/build/porch_phone_adapter.ino.uf2"
