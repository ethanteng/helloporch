// Encodes numbered PNG frames into an H.264 MP4 with AVFoundation, for scripts/render-three-way-film.mjs.
// Usage: swift scripts/encode-frames.swift <frames-folder> <fps> <out.mp4>
import AVFoundation
import Foundation
import ImageIO

func image(at url: URL) -> CGImage? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    return CGImageSourceCreateImageAtIndex(source, 0, nil)
}

let arguments = CommandLine.arguments
guard arguments.count == 4, let fps = Int32(arguments[2]) else {
    print("Usage: swift encode-frames.swift <frames-folder> <fps> <out.mp4>")
    exit(1)
}
let folder = URL(fileURLWithPath: arguments[1])
let output = URL(fileURLWithPath: arguments[3])
let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
    .filter { $0.pathExtension == "png" }
    .sorted { $0.lastPathComponent < $1.lastPathComponent }
guard let first = files.first, let probe = image(at: first) else {
    print("No PNG frames in \(folder.path)")
    exit(1)
}
let width = probe.width, height = probe.height

try? FileManager.default.removeItem(at: output)
let writer = try AVAssetWriter(outputURL: output, fileType: .mp4)
let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
    AVVideoCodecKey: AVVideoCodecType.h264,
    AVVideoWidthKey: width,
    AVVideoHeightKey: height,
    AVVideoCompressionPropertiesKey: [
        AVVideoAverageBitRateKey: 4_000_000,
        AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
        AVVideoMaxKeyFrameIntervalKey: Int(fps) * 2,
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
    kCVPixelBufferWidthKey as String: width,
    kCVPixelBufferHeightKey as String: height,
])
writer.add(input)
writer.shouldOptimizeForNetworkUse = true
guard writer.startWriting() else {
    print("Couldn't start writing: \(writer.error?.localizedDescription ?? "unknown error")")
    exit(1)
}
writer.startSession(atSourceTime: .zero)

for (index, file) in files.enumerated() {
    guard let frame = image(at: file), let pool = adaptor.pixelBufferPool else {
        print("Couldn't read \(file.lastPathComponent)")
        exit(1)
    }
    while !input.isReadyForMoreMediaData { Thread.sleep(forTimeInterval: 0.005) }
    var buffer: CVPixelBuffer?
    CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
    guard let buffer else { print("Couldn't make a pixel buffer"); exit(1) }
    CVPixelBufferLockBaseAddress(buffer, [])
    let context = CGContext(
        data: CVPixelBufferGetBaseAddress(buffer), width: width, height: height, bitsPerComponent: 8,
        bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
    )
    context?.draw(frame, in: CGRect(x: 0, y: 0, width: width, height: height))
    CVPixelBufferUnlockBaseAddress(buffer, [])
    adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(index), timescale: fps))
}

input.markAsFinished()
let finished = DispatchSemaphore(value: 0)
writer.finishWriting { finished.signal() }
finished.wait()
guard writer.status == .completed else {
    print("Encoding failed: \(writer.error?.localizedDescription ?? "unknown error")")
    exit(1)
}
print("Wrote \(output.path): \(files.count) frames, \(width) × \(height) at \(fps) fps")
