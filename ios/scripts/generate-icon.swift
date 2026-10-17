// Run with: swift ios/scripts/generate-icon.swift
import AppKit
import Foundation

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let assets = root.appendingPathComponent("Porch/Assets.xcassets")
let icons = assets.appendingPathComponent("AppIcon.appiconset")
try FileManager.default.createDirectory(at: icons, withIntermediateDirectories: true)
let butter = CGColor(red: 0.974, green: 0.910, blue: 0.670, alpha: 1)   // #f8e8ab
let tomato = CGColor(red: 0.877, green: 0.366, blue: 0.240, alpha: 1)   // #e05d3d

func icon(size: Int) throws {
    let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                            bytesPerRow: size * 4, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    context.setFillColor(butter)
    context.fill(CGRect(x: 0, y: 0, width: size, height: size))
    // Flip to y-down and map the 140-unit design grid (origin at -20,-20) onto the icon.
    let k = CGFloat(size) / 140
    context.translateBy(x: 0, y: CGFloat(size))
    context.scaleBy(x: k, y: -k)
    context.translateBy(x: 20, y: 20)
    // A ring with a smile, and a short stem hanging from its left side.
    context.setStrokeColor(tomato)
    context.setLineWidth(9)
    context.setLineCap(.round)
    context.move(to: CGPoint(x: 20, y: 44)); context.addLine(to: CGPoint(x: 20, y: 91)); context.strokePath()
    context.strokeEllipse(in: CGRect(x: 20, y: 12, width: 64, height: 64))
    context.move(to: CGPoint(x: 36, y: 42)); context.addQuadCurve(to: CGPoint(x: 68, y: 42), control: CGPoint(x: 52, y: 60)); context.strokePath()
    let bitmap = NSBitmapImageRep(cgImage: context.makeImage()!)
    try bitmap.representation(using: .png, properties: [:])!.write(to: icons.appendingPathComponent("icon-\(size).png"))
}

let entries: [(String, String, String, Int)] = [
    ("iphone", "20x20", "2x", 40), ("iphone", "20x20", "3x", 60),
    ("iphone", "29x29", "2x", 58), ("iphone", "29x29", "3x", 87),
    ("iphone", "40x40", "2x", 80), ("iphone", "40x40", "3x", 120),
    ("iphone", "60x60", "2x", 120), ("iphone", "60x60", "3x", 180),
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
