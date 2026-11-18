// A successful simctl launch can precede the simulator's boot animation, and a launch shows a plain launch screen first.
// Pass only a screenshot of Porch: its cream page, the dark People screen, or the bedside clock's sky and hills.
// Screenshots read back a little off the app's colors (ink #2E1D15 as about #3C2418, the page #F9EFDA as about
// #F8F0E0), the same on CI as on a Mac, so the ranges below are in screenshot colors. Rely only on what Porch draws
// itself: CI's simulators run an older iOS than a current Mac, and its bars, buttons and sidebars look different there.
// Boot screens, the launch screen and the home screen's warm wallpaper all fail by a wide margin.
import AppKit
import Foundation

guard CommandLine.arguments.count == 2,
      let data = try? Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])),
      let bitmap = NSBitmapImageRep(data: data) else { exit(1) }
var cream = 0
var clockInk = 0
var warmDark = 0
var lightText = 0
var clockWarmLight = 0
var lightSky = 0
var dark = 0
var hills = 0
for row in 1...40 {
    for column in 1...40 {
        let x = bitmap.pixelsWide * column / 41
        let y = bitmap.pixelsHigh * row / 41
        guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
        let r = color.redComponent, g = color.greenComponent, b = color.blueComponent
        // The page behind caregiver mode, setup and the family app. Nothing else on a simulator is this color.
        if r > 0.94 && (0.90...0.975).contains(g) && (0.82...0.92).contains(b) && r - b > 0.05 { cream += 1 }
        // The daytime clock's digits.
        if (7...31).contains(row), (0.15...0.32).contains(r), (0.08...0.20).contains(g), (0.04...0.15).contains(b), r - g > 0.06, g > b {
            clockInk += 1
        }
        // The People screen's cards.
        if (0.12...0.24).contains(r) && (0.08...0.18).contains(g) && (0.06...0.16).contains(b) && r - b > 0.03 { warmDark += 1 }
        // Names and numbers on those cards.
        if r > 0.8 && g > 0.78 && b > 0.74 { lightText += 1 }
        // The night clock's digits.
        if (7...31).contains(row), (0.80...0.95).contains(r), r - b > 0.04, r - b < 0.16, g < r, g > b { clockWarmLight += 1 }
        if r > 0.5 && g > 0.55 && b > 0.5 && max(r, g, b) - min(r, g, b) > 0.015 { lightSky += 1 }
        // The night sky. At dusk and before dawn it's lighter, and the plain clock shows whatever hour CI runs at: below
        // 0.2, with 1,000 needed, 6 PM scored 925 and 5 AM 980, and failed. Now they score about 1,080 of 800.
        if max(r, g, b) < 0.26 { dark += 1 }
        // The clock's green hills along the bottom.
        if row > 30 && g > r + 0.03 && g > b { hills += 1 }
    }
}
let page = cream > 400
let people = warmDark > 600 && lightText > 8
// The hills and the digits' colors tell the clock from other screens; the sky only tells day from night.
let clock = hills > 60 && ((lightSky > 1000 && clockInk > 30) || (dark > 800 && clockWarmLight > 30))
exit(page || people || clock ? 0 : 1)
