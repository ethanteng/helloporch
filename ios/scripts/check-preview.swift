// A successful simctl launch can precede the simulator's boot animation.
// Require Porch's dark clock/people palette or light caregiver palette.
import AppKit
import Foundation

guard CommandLine.arguments.count == 2,
      let data = try? Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])),
      let bitmap = NSBitmapImageRep(data: data) else { exit(1) }
var light = 0
var green = 0
var night = 0
var nightText = 0
for row in 1...40 {
    for column in 1...40 {
        let x = bitmap.pixelsWide * column / 41
        let y = bitmap.pixelsHigh * row / 41
        guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
        let r = color.redComponent, g = color.greenComponent, b = color.blueComponent
        if r > 0.90 && g > 0.90 && b > 0.88 {
            light += 1
        }
        if (0.10...0.40).contains(r), g > r + 0.05, b < g { green += 1 }
        if r < 0.10 && (0.03...0.15).contains(g) && g > r && b < g { night += 1 }
        if (0.45...0.85).contains(r), g > r + 0.015, b < g {
            nightText += 1
        }
    }
}
exit((light > 720 && green > 4) || (night > 720 && nightText > 12) ? 0 : 1)
