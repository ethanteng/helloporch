// Makes a QR code for a link as a small SVG, and checks that it reads back as that link.
//   swift qr.swift <url> <out.svg>
// The pilot guides show these beside the TestFlight and Google Play test links (app/(site)/pilot/links.ts).
import CoreImage
import Foundation

let url = CommandLine.arguments[1], out = CommandLine.arguments[2]
let filter = CIFilter(name: "CIQRCodeGenerator")!
filter.setValue(Data(url.utf8), forKey: "inputMessage")
filter.setValue("M", forKey: "inputCorrectionLevel")
let code = filter.outputImage!
let context = CIContext()
let cg = context.createCGImage(code, from: code.extent)!

// One pixel per module: read which are dark, and drop Core Image's own margin.
let w = cg.width, h = cg.height
var pixels = [UInt8](repeating: 0, count: w * h)
let gray = CGContext(data: &pixels, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                     space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
gray.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
let dark = (0..<h).map { y in (0..<w).map { x in pixels[y * w + x] < 128 } }
let rows = dark.indices.filter { dark[$0].contains(true) }, cols = (0..<w).filter { x in dark.contains { $0[x] } }
let top = rows.first!, left = cols.first!, size = rows.last! - top + 1
let quiet = 4, side = size + 2 * quiet

var path = ""
for y in 0..<size {
  for x in 0..<size where dark[top + y][left + x] { path += "M\(x + quiet) \(y + quiet)h1v1h-1z" }
}
let svg = """
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 \(side) \(side)" shape-rendering="crispEdges">\
<rect width="\(side)" height="\(side)" fill="#fff"/><path fill="#2e1d15" d="\(path)"/></svg>

"""
try svg.write(toFile: out, atomically: true, encoding: .utf8)

// Read it back from a scaled-up drawing of the same modules.
let scale = 10, px = side * scale
let check = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
check.setFillColor(gray: 1, alpha: 1); check.fill(CGRect(x: 0, y: 0, width: px, height: px))
check.setFillColor(gray: 0, alpha: 1)
for y in 0..<size { for x in 0..<size where dark[top + y][left + x] {
  check.fill(CGRect(x: (x + quiet) * scale, y: px - (y + quiet + 1) * scale, width: scale, height: scale))
} }
let detector = CIDetector(ofType: CIDetectorTypeQRCode, context: nil, options: [CIDetectorAccuracy: CIDetectorAccuracyHigh])!
let read = (detector.features(in: CIImage(cgImage: check.makeImage()!)).first as? CIQRCodeFeature)?.messageString
guard read == url else { fatalError("the code reads as \(read ?? "nothing"), not \(url)") }
print("\(out): \(size)×\(size) modules, reads back as \(url)")
