// A successful simctl launch can precede the simulator's boot animation.
// Require Porch's cream background and terracotta call button to be visible.
import AppKit
import Foundation

guard CommandLine.arguments.count == 2,
      let bitmap = NSBitmapImageRep(contentsOfFile: CommandLine.arguments[1]) else { exit(1) }
var cream = 0
var clay = 0
for row in 1...20 {
    for column in 1...20 {
        let x = bitmap.pixelsWide * column / 21
        let y = bitmap.pixelsHigh * row / 21
        guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
        if color.redComponent > 0.92 && color.greenComponent > 0.87 && color.blueComponent > 0.78 {
            cream += 1
        }
        if (0.50...0.70).contains(color.redComponent),
           (0.18...0.35).contains(color.greenComponent),
           (0.08...0.25).contains(color.blueComponent) {
            clay += 1
        }
    }
}
exit(cream > 200 && clay > 8 ? 0 : 1)
