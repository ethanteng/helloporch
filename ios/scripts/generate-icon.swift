// Run with: swift ios/scripts/generate-icon.swift
import AppKit
import Foundation

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let assets = root.appendingPathComponent("Porch/Assets.xcassets")
let icons = assets.appendingPathComponent("AppIcon.appiconset")
try FileManager.default.createDirectory(at: icons, withIntermediateDirectories: true)
let cream = CGColor(red: 0.97, green: 0.94, blue: 0.87, alpha: 1)
let clay = CGColor(red: 0.60, green: 0.26, blue: 0.16, alpha: 1)

func icon(size: Int) throws {
    let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                            bytesPerRow: size * 4, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    context.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
    context.setFillColor(clay)
    context.fill(CGRect(x: 0, y: 0, width: 1024, height: 1024))
    // A porch arch around a video camera, drawn as opaque vector shapes.
    context.setFillColor(cream)
    context.fill(CGRect(x: 224, y: 160, width: 576, height: 400))
    context.fillEllipse(in: CGRect(x: 224, y: 272, width: 576, height: 576))
    context.setFillColor(clay)
    context.fill(CGRect(x: 286, y: 160, width: 452, height: 400))
    context.fillEllipse(in: CGRect(x: 286, y: 334, width: 452, height: 452))
    context.setFillColor(cream)
    context.addPath(CGPath(roundedRect: CGRect(x: 354, y: 380, width: 216, height: 170), cornerWidth: 28, cornerHeight: 28, transform: nil))
    context.fillPath()
    context.move(to: CGPoint(x: 586, y: 436))
    context.addLine(to: CGPoint(x: 674, y: 384))
    context.addLine(to: CGPoint(x: 674, y: 546))
    context.addLine(to: CGPoint(x: 586, y: 494))
    context.closePath()
    context.fillPath()
    let bitmap = NSBitmapImageRep(cgImage: context.makeImage()!)
    try bitmap.representation(using: .png, properties: [:])!.write(to: icons.appendingPathComponent("icon-\(size).png"))
}

let entries: [(String, String, String, Int)] = [
    ("ipad", "20x20", "1x", 20), ("ipad", "20x20", "2x", 40),
    ("ipad", "29x29", "1x", 29), ("ipad", "29x29", "2x", 58),
    ("ipad", "40x40", "1x", 40), ("ipad", "40x40", "2x", 80),
    ("ipad", "76x76", "1x", 76), ("ipad", "76x76", "2x", 152),
    ("ipad", "83.5x83.5", "2x", 167), ("ios-marketing", "1024x1024", "1x", 1024)
]
for size in Set(entries.map { $0.3 }) { try icon(size: size) }
let images = entries.map { ["idiom": $0.0, "size": $0.1, "scale": $0.2, "filename": "icon-\($0.3).png"] }
try JSONSerialization.data(withJSONObject: ["images": images, "info": ["author": "xcode", "version": 1]], options: [.prettyPrinted, .sortedKeys]).write(to: icons.appendingPathComponent("Contents.json"))
try JSONSerialization.data(withJSONObject: ["info": ["author": "xcode", "version": 1]], options: [.prettyPrinted, .sortedKeys]).write(to: assets.appendingPathComponent("Contents.json"))
