// A successful simctl launch can precede the simulator's boot animation, and a launch shows a plain launch screen first.
// Pass only a screenshot in Porch's brand colors: a cream page with ink or accent on it, the dark People screen, or the
// bedside clock's sky and hills. Screenshots read back a little off the app's colors (ink #2E1D15 as about #3C2418, the
// page #F9EFDA as about #F8F0E0), the same on CI as on a Mac, so the ranges below are in screenshot colors.
// Boot screens, the launch screen and the home screen's warm wallpaper all fail by a wide margin.
import AppKit
import Foundation

guard CommandLine.arguments.count == 2,
      let data = try? Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])),
      let bitmap = NSBitmapImageRep(data: data) else { exit(1) }
var cream = 0
var ink = 0
var clockInk = 0
var accent = 0
var warmDark = 0
var warmLight = 0
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
        // The page behind caregiver mode, setup and the family app.
        if r > 0.94 && (0.90...0.975).contains(g) && (0.82...0.92).contains(b) && r - b > 0.05 { cream += 1 }
        // Text, dark buttons and the daytime clock's digits.
        if (0.15...0.32).contains(r) && (0.08...0.20).contains(g) && (0.04...0.15).contains(b) && r - g > 0.06 && g > b {
            ink += 1
            if (7...31).contains(row) { clockInk += 1 }
        }
        if (0.65...0.92).contains(r) && (0.2...0.45).contains(g) && (0.05...0.3).contains(b) { accent += 1 }
        // The People screen's cards.
        if (0.12...0.24).contains(r) && (0.08...0.18).contains(g) && (0.06...0.16).contains(b) && r - b > 0.03 { warmDark += 1 }
        // Names on those cards and the night clock's digits.
        if (0.80...0.95).contains(r) && r - b > 0.04 && r - b < 0.16 && g < r && g > b {
            warmLight += 1
            if (7...31).contains(row) { clockWarmLight += 1 }
        }
        if r > 0.5 && g > 0.55 && b > 0.5 && max(r, g, b) - min(r, g, b) > 0.015 { lightSky += 1 }
        if max(r, g, b) < 0.2 { dark += 1 }
        // The clock's green hills along the bottom.
        if row > 30 && g > r + 0.03 && g > b { hills += 1 }
    }
}
let page = cream > 400 && ink + accent > 8
let people = warmDark > 600 && warmLight > 8
let clock = hills > 60 && ((lightSky > 1000 && clockInk > 30) || (dark > 1000 && clockWarmLight > 30))
exit(page || people || clock ? 0 : 1)
