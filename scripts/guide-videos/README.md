# Guide videos

The short videos in the pilot guides (`public/pilot/videos/`) are app screenshots with captions and tap rings, made
from the real apps against `scripts/local-family-server.mjs` with a made-up household, "Rose".

1. Capture the screens. iOS: the `PorchFamily` build on an iPad Air 11-inch and an iPhone 17 simulator, with
   `xcrun simctl io <udid> screenshot`. Android: the debug build on the `porch-tablet` and `porch-phone` emulators,
   with `adb exec-out screencap -p`. Name them as `boards.py` expects, under `<shots>/ios` and `<shots>/android`.
   The emulator has no USB host, so its setup hides Corded phone; for the setup video, temporarily make
   `usbHost` true in `BedsideSetupScreens.kt` and don't commit that.
2. `python3 -I boards.py <shots> <out>` writes one storyboard per video: each beat is a screenshot, its caption and
   where to show the tap, in the screenshot's own points or pixels.
3. `swiftc -O render.swift -o render && ./render <out>/<name>.json [sheet.jpg]` writes `<name>.mp4` and its poster
   `<name>.jpg` (1280×960, H.264, no sound). The optional contact sheet shows every beat with its tap ring.
4. Copy the `.mp4` and `.jpg` files into `public/pilot/videos/`.

Captions sit at the top of the frame, where video players don't put their controls. The frame is dark green
(`background` and `dark` in each storyboard), so the videos stand apart from the cream page.

## Link QR codes

The guides' "Before you start" shows the TestFlight app, and the TestFlight and Google Play test links, with a QR code each, from
`public/pilot/links/`. `swift qr.swift <url> <out.svg>` makes one and checks it reads back as that URL. The codes are
tied to the exact links in `app/(site)/pilot/links.ts`: if a link changes on Vercel, the guide shows it without a code
until you make a new one and update that list.
