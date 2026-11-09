// Renders a captioned walkthrough video from app screenshots.
//   swift render.swift storyboard.json
// The storyboard: { output, poster, layout: tablet|phone|pair, beats: [{ label, caption, main, side?, tap?: {on: main|side, x, y}, hold? }] }
// Tap points are fractions of the screenshot (0…1 across and down).
import AppKit
import AVFoundation
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct Tap: Codable { var on: String?; var x: Double; var y: Double }
struct Beat: Codable { var label: String?; var caption: String; var main: String; var side: String?; var tap: Tap?; var hold: Double? }
/// background: the frame's color as "#RRGGBB"; dark: light captions for a dark background.
struct Board: Codable {
  var output: String; var poster: String?; var layout: String; var beats: [Beat]; var width: Int?; var height: Int?
  var background: String?; var dark: Bool?
}

let boardURL = URL(fileURLWithPath: CommandLine.arguments[1])
let board = try JSONDecoder().decode(Board.self, from: Data(contentsOf: boardURL))
let base = boardURL.deletingLastPathComponent()
let W = board.width ?? 1280, H = board.height ?? 960
let fps = 30
let fade = 0.45

func color(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
  CGColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255, blue: CGFloat(hex & 0xff) / 255, alpha: a)
}
let dark = board.dark ?? false
let bg = color(board.background.flatMap { UInt32($0.dropFirst(), radix: 16) } ?? 0xF9EFDA)
let ink = dark ? color(0xFDFBF6) : color(0x2E1D15), tomato = color(0xE05D3D)
let tomatoDeep = dark ? color(0xF29A7E) : color(0xC0401F)
let bezel = color(0x1F1A17)

var cache: [String: CGImage] = [:]
func image(_ path: String) -> CGImage {
  if let hit = cache[path] { return hit }
  let url = path.hasPrefix("/") ? URL(fileURLWithPath: path) : base.appendingPathComponent(path)
  guard let src = CGImageSourceCreateWithURL(url as CFURL, nil), let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { fatalError("can't read \(url.path)") }
  cache[path] = img
  return img
}

// Layout, in top-left coordinates.
struct Slot { var rect: CGRect; var radius: CGFloat; var bezel: CGFloat }
func fit(_ img: CGImage, width: CGFloat? = nil, height: CGFloat? = nil) -> CGSize {
  let ratio = CGFloat(img.width) / CGFloat(img.height)
  if let w = width { return CGSize(width: w, height: w / ratio) }
  return CGSize(width: height! * ratio, height: height!)
}
func slots(for beat: Beat) -> (main: Slot, side: Slot?, caption: CGRect, align: CTTextAlignment) {
  let m = image(beat.main)
  switch board.layout {
  case "phone":
    let size = fit(m, height: CGFloat(H) - 96)
    let rect = CGRect(x: 150, y: 48, width: size.width, height: size.height)
    let left = rect.maxX + 90
    return (Slot(rect: rect, radius: size.width * 0.12, bezel: 11), nil, CGRect(x: left, y: 0, width: CGFloat(W) - left - 90, height: CGFloat(H)), .left)
  case "pair":
    // Caption on top, where no video player puts its controls; the screens below.
    let s = image(beat.side ?? beat.main)
    let gap: CGFloat = 56
    let top: CGFloat = 214, h = CGFloat(H) - top - 40
    let tablet = fit(m, height: h), phone = fit(s, height: h)
    let scale = min(1, (CGFloat(W) - 80) / (tablet.width + gap + phone.width))
    let tw = tablet.width * scale, th = tablet.height * scale, pw = phone.width * scale, ph = phone.height * scale
    let x0 = (CGFloat(W) - (tw + gap + pw)) / 2
    return (Slot(rect: CGRect(x: x0, y: top + (ph - th) / 2, width: tw, height: th), radius: tw * 0.022, bezel: 12),
            Slot(rect: CGRect(x: x0 + tw + gap, y: top, width: pw, height: ph), radius: pw * 0.12, bezel: 9),
            CGRect(x: 60, y: 14, width: CGFloat(W) - 120, height: top - 34), .center)
  default: // tablet: caption on top, where no video player puts its controls; the screen below.
    let top: CGFloat = 214
    var size = fit(m, width: CGFloat(W) - 120)
    if size.height > CGFloat(H) - top - 40 { size = fit(m, height: CGFloat(H) - top - 40) }
    let rect = CGRect(x: (CGFloat(W) - size.width) / 2, y: top, width: size.width, height: size.height)
    return (Slot(rect: rect, radius: size.width * 0.022, bezel: 14), nil,
            CGRect(x: 60, y: 14, width: CGFloat(W) - 120, height: top - 34), .center)
  }
}

// Drawing happens in Core Graphics' bottom-left space; flip top-left rects with this.
func cg(_ r: CGRect) -> CGRect { CGRect(x: r.minX, y: CGFloat(H) - r.maxY, width: r.width, height: r.height) }

func drawDevice(_ ctx: CGContext, _ img: CGImage, _ slot: Slot) {
  let screen = cg(slot.rect)
  let outer = screen.insetBy(dx: -slot.bezel, dy: -slot.bezel)
  ctx.saveGState()
  ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 34, color: color(0x3A2412, 0.28))
  ctx.addPath(CGPath(roundedRect: outer, cornerWidth: slot.radius + slot.bezel, cornerHeight: slot.radius + slot.bezel, transform: nil))
  ctx.setFillColor(bezel)
  ctx.fillPath()
  ctx.restoreGState()
  ctx.saveGState()
  ctx.addPath(CGPath(roundedRect: screen, cornerWidth: slot.radius, cornerHeight: slot.radius, transform: nil))
  ctx.clip()
  ctx.interpolationQuality = .high
  ctx.draw(img, in: screen)
  ctx.restoreGState()
}

func paragraph(_ text: String, size: CGFloat, weight: NSFont.Weight, color: CGColor, align: CTTextAlignment, kern: CGFloat = 0, lineHeight: CGFloat) -> NSAttributedString {
  let style = NSMutableParagraphStyle()
  style.alignment = align == .center ? .center : .left
  style.minimumLineHeight = lineHeight
  style.maximumLineHeight = lineHeight
  return NSAttributedString(string: text, attributes: [
    .font: NSFont.systemFont(ofSize: size, weight: weight),
    NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
    .paragraphStyle: style,
    .kern: kern,
  ])
}

func textHeight(_ s: NSAttributedString, width: CGFloat) -> CGFloat {
  let fs = CTFramesetterCreateWithAttributedString(s)
  return CTFramesetterSuggestFrameSizeWithConstraints(fs, CFRange(location: 0, length: 0), nil, CGSize(width: width, height: 10000), nil).height
}
func drawText(_ ctx: CGContext, _ s: NSAttributedString, in r: CGRect) {
  let fs = CTFramesetterCreateWithAttributedString(s)
  let frame = CTFramesetterCreateFrame(fs, CFRange(location: 0, length: 0), CGPath(rect: cg(r), transform: nil), nil)
  ctx.saveGState()
  ctx.textMatrix = .identity
  CTFrameDraw(frame, ctx)
  ctx.restoreGState()
}

func drawCaption(_ ctx: CGContext, _ beat: Beat, _ area: CGRect, _ align: CTTextAlignment) {
  let phone = board.layout == "phone"
  let caption = paragraph(beat.caption, size: phone ? 46 : 42, weight: .semibold, color: ink, align: align, lineHeight: phone ? 58 : 52)
  let label = beat.label.map { paragraph($0.uppercased(), size: phone ? 22 : 21, weight: .bold, color: tomatoDeep, align: align, kern: 1.8, lineHeight: 28) }
  let ch = textHeight(caption, width: area.width) + 2
  let lh = label.map { textHeight($0, width: area.width) + 10 } ?? 0
  let top = area.minY + (area.height - ch - lh) / 2
  if let label { drawText(ctx, label, in: CGRect(x: area.minX, y: top, width: area.width, height: lh)) }
  drawText(ctx, caption, in: CGRect(x: area.minX, y: top + lh, width: area.width, height: ch + 4))
}

func ease(_ x: Double) -> Double { let t = min(max(x, 0), 1); return t * t * (3 - 2 * t) }

func drawTap(_ ctx: CGContext, at p: CGPoint, local t: Double, hold: Double) {
  let start = hold - fade - 1.25
  guard t >= start else { return }
  let k = t - start
  let appear = ease(k / 0.3)
  let press = ease((k - 0.75) / 0.18)
  let r: CGFloat = 26 * (1.5 - 0.5 * CGFloat(appear)) * (1 - 0.12 * CGFloat(press))
  let q = CGPoint(x: p.x, y: CGFloat(H) - p.y)
  ctx.saveGState()
  ctx.setAlpha(CGFloat(appear))
  ctx.setFillColor(tomato.copy(alpha: 0.22 + 0.25 * CGFloat(press))!)
  ctx.fillEllipse(in: CGRect(x: q.x - r, y: q.y - r, width: 2 * r, height: 2 * r))
  ctx.setStrokeColor(tomato)
  ctx.setLineWidth(4)
  ctx.strokeEllipse(in: CGRect(x: q.x - r, y: q.y - r, width: 2 * r, height: 2 * r))
  if k > 0.75 { // ripple
    let rk = min((k - 0.75) / 0.5, 1)
    let rr = r + CGFloat(rk) * 26
    ctx.setStrokeColor(tomato.copy(alpha: CGFloat(1 - rk))!)
    ctx.setLineWidth(3)
    ctx.strokeEllipse(in: CGRect(x: q.x - rr, y: q.y - rr, width: 2 * rr, height: 2 * rr))
  }
  ctx.restoreGState()
}

func holdTime(_ b: Beat) -> Double {
  if let h = b.hold { return h }
  let words = Double(b.caption.split(separator: " ").count)
  return max(2.4, 0.9 + words * 0.25) + (b.tap != nil ? 0.9 : 0) + fade
}

func drawScene(_ ctx: CGContext, _ i: Int, local t: Double, captionAlpha: CGFloat = 1, screensAlpha: CGFloat = 1) {
  let beat = board.beats[i]
  let s = slots(for: beat)
  ctx.saveGState()
  ctx.setAlpha(screensAlpha)
  drawDevice(ctx, image(beat.main), s.main)
  if let side = s.side { drawDevice(ctx, image(beat.side ?? beat.main), side) }
  ctx.restoreGState()
  ctx.saveGState()
  ctx.setAlpha(captionAlpha)
  drawCaption(ctx, beat, s.caption, s.align)
  ctx.restoreGState()
  if let tap = beat.tap {
    let slot = tap.on == "side" ? s.side! : s.main
    let p = CGPoint(x: slot.rect.minX + CGFloat(tap.x) * slot.rect.width, y: slot.rect.minY + CGFloat(tap.y) * slot.rect.height)
    ctx.saveGState()
    ctx.setAlpha(screensAlpha)
    drawTap(ctx, at: p, local: t, hold: holdTime(beat))
    ctx.restoreGState()
  }
}

let holds = board.beats.map(holdTime)
let total = holds.reduce(0, +) + 0.6
var starts: [Double] = []
var acc = 0.0
for h in holds { starts.append(acc); acc += h }

func render(_ ctx: CGContext, at time: Double) {
  ctx.setFillColor(bg)
  ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
  var i = starts.lastIndex(where: { $0 <= time }) ?? 0
  i = min(i, board.beats.count - 1)
  let local = time - starts[i]
  let h = holds[i]
  if i + 1 < board.beats.count, local > h - fade {
    let a = CGFloat(ease((local - (h - fade)) / fade))
    let cur = board.beats[i], next = board.beats[i + 1]
    let sameScreens = cur.main == next.main && cur.side == next.side
    // Screens: crossfade the old into the new. Captions: the old one fades out, the new one fades in.
    drawScene(ctx, i, local: local, captionAlpha: 1 - a, screensAlpha: 1)
    if sameScreens {
      drawScene(ctx, i + 1, local: 0, captionAlpha: a, screensAlpha: 0)
    } else {
      // Draw only the next screens on top with alpha, then its caption.
      drawScene(ctx, i + 1, local: 0, captionAlpha: 0, screensAlpha: a)
      ctx.saveGState(); ctx.setAlpha(a)
      let s = slots(for: next); drawCaption(ctx, next, s.caption, s.align)
      ctx.restoreGState()
    }
  } else {
    drawScene(ctx, i, local: local)
  }
}

// Write the video.
let out = URL(fileURLWithPath: board.output.hasPrefix("/") ? board.output : base.appendingPathComponent(board.output).path)
try? FileManager.default.removeItem(at: out)
let writer = try AVAssetWriter(outputURL: out, fileType: .mp4)
let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
  AVVideoCodecKey: AVVideoCodecType.h264,
  AVVideoWidthKey: W, AVVideoHeightKey: H,
  AVVideoCompressionPropertiesKey: [
    AVVideoAverageBitRateKey: 700_000,
    AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
    AVVideoMaxKeyFrameIntervalKey: fps * 4,
    AVVideoExpectedSourceFrameRateKey: fps,
  ],
  AVVideoColorPropertiesKey: [
    AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
    AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
    AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
  ],
])
input.expectsMediaDataInRealTime = false
let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
  kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
  kCVPixelBufferWidthKey as String: W, kCVPixelBufferHeightKey as String: H,
])
writer.add(input)
writer.shouldOptimizeForNetworkUse = true
writer.startWriting()
writer.startSession(atSourceTime: .zero)

let space = CGColorSpace(name: CGColorSpace.sRGB)!
let frames = Int(total * Double(fps))
for f in 0..<frames {
  while !input.isReadyForMoreMediaData { usleep(2000) }
  var pb: CVPixelBuffer?
  CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &pb)
  guard let buffer = pb else { fatalError("no pixel buffer") }
  CVPixelBufferLockBaseAddress(buffer, [])
  let ctx = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: W, height: H, bitsPerComponent: 8,
                      bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: space,
                      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
  render(ctx, at: Double(f) / Double(fps))
  CVPixelBufferUnlockBaseAddress(buffer, [])
  adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(f), timescale: CMTimeScale(fps)))
}
input.markAsFinished()
let done = DispatchSemaphore(value: 0)
writer.finishWriting { done.signal() }
done.wait()
if writer.status != .completed { fatalError("writing failed: \(String(describing: writer.error))") }

// The poster: the first beat, before any tap ring shows.
if let poster = board.poster {
  let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
  render(ctx, at: 0.5)
  let url = URL(fileURLWithPath: poster.hasPrefix("/") ? poster : base.appendingPathComponent(poster).path)
  let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
  CGImageDestinationAddImage(dest, ctx.makeImage()!, [kCGImageDestinationLossyCompressionQuality: 0.78] as CFDictionary)
  CGImageDestinationFinalize(dest)
}
let bytes = (try? FileManager.default.attributesOfItem(atPath: out.path)[.size] as? Int) ?? 0
print(String(format: "%@: %.1f s, %d frames, %.2f MB", out.lastPathComponent, total, frames, Double(bytes) / 1_048_576))

if CommandLine.arguments.count > 2 {
  let cols = 3, scale = 0.34
  let tw = Int(Double(W) * scale), th = Int(Double(H) * scale)
  let rows = (board.beats.count + cols - 1) / cols
  let sheet = CGContext(data: nil, width: tw * cols, height: th * rows, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                        bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
  sheet.setFillColor(CGColor(gray: 1, alpha: 1)); sheet.fill(CGRect(x: 0, y: 0, width: tw * cols, height: th * rows))
  for (i, start) in starts.enumerated() {
    let frame = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                          bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
    render(frame, at: start + holds[i] - fade - 0.3)
    let c = i % cols, r = i / cols
    sheet.interpolationQuality = .high
    sheet.draw(frame.makeImage()!, in: CGRect(x: c * tw, y: (rows - 1 - r) * th, width: tw - 4, height: th - 4))
  }
  let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: CommandLine.arguments[2]) as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
  CGImageDestinationAddImage(dest, sheet.makeImage()!, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
  CGImageDestinationFinalize(dest)
}
