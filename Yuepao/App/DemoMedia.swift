#if DEBUG
import UIKit
import AVFoundation
import ImageIO
import UniformTypeIdentifiers

/// 只给 UI 测试用的演示照片和视频：程序画的渐变光斑，不是真照片
enum DemoMedia {
    struct Seeded {
        var profile: [String] = []
        var record: [String] = []
        var single: [String] = []
    }

    private static let palettes: [(UIColor, UIColor)] = [
        (UIColor(red: 0.36, green: 0.12, blue: 0.20, alpha: 1), UIColor(red: 0.88, green: 0.58, blue: 0.47, alpha: 1)),
        (UIColor(red: 0.10, green: 0.12, blue: 0.22, alpha: 1), UIColor(red: 0.56, green: 0.41, blue: 0.63, alpha: 1)),
        (UIColor(red: 0.62, green: 0.45, blue: 0.30, alpha: 1), UIColor(red: 0.98, green: 0.88, blue: 0.74, alpha: 1)),
        (UIColor(red: 0.13, green: 0.22, blue: 0.27, alpha: 1), UIColor(red: 0.62, green: 0.75, blue: 0.72, alpha: 1)),
        (UIColor(red: 0.42, green: 0.18, blue: 0.24, alpha: 1), UIColor(red: 0.96, green: 0.72, blue: 0.66, alpha: 1))
    ]

    /// 同步导入照片；实况和视频要编码，放到后台慢慢生成（id 先定好）
    @MainActor
    static func seed() -> Seeded {
        let store = MediaStore.shared
        store.deleteAll()
        let cal = Calendar.current
        func ago(_ days: Int, _ hour: Int) -> Date {
            let day = cal.date(byAdding: .day, value: -days, to: Date()) ?? Date()
            return cal.date(bySettingHour: hour, minute: 12, second: 0, of: day) ?? day
        }
        func add(_ seed: Int, _ size: CGSize, _ date: Date) -> String? {
            guard let data = photo(seed: seed, size: size, date: date) else { return nil }
            return try? store.importPhoto(data: data)
        }
        let portrait = CGSize(width: 1500, height: 2000)
        let landscape = CGSize(width: 2000, height: 1500)

        var result = Seeded()
        result.profile = [add(1, portrait, ago(30, 19)), add(2, landscape, ago(52, 15)), add(3, portrait, ago(75, 21))]
            .compactMap { $0 }
        let liveID = UUID().uuidString
        let videoID = UUID().uuidString
        result.record = [add(4, portrait, ago(4, 14)), liveID, videoID, add(0, landscape, ago(4, 16))].compactMap { $0 }
        result.single = [add(2, portrait, ago(2, 22))].compactMap { $0 }

        Task.detached(priority: .userInitiated) {
            await makeLive(id: liveID, seed: 1)
            await makeVideo(id: videoID, seed: 0)
        }
        return result
    }

    // MARK: 照片

    static func photo(seed: Int, size: CGSize, date: Date?) -> Data? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            draw(in: ctx.cgContext, size: size, seed: seed, phase: 0)
        }
        guard let cgImage = image.cgImage else { return nil }
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil) else {
            return nil
        }
        var properties: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 0.9]
        if let date {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "yyyy:MM:dd HH:mm:ss"
            properties[kCGImagePropertyExifDictionary] = [kCGImagePropertyExifDateTimeOriginal: f.string(from: date)]
        }
        CGImageDestinationAddImage(dest, cgImage, properties as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }

    /// 渐变底 + 柔和的光斑；phase 让视频里的光斑慢慢移动
    static func draw(in cg: CGContext, size: CGSize, seed: Int, phase: CGFloat) {
        let colors = palettes[abs(seed) % palettes.count]
        let space = CGColorSpaceCreateDeviceRGB()
        if let gradient = CGGradient(colorsSpace: space, colors: [colors.0.cgColor, colors.1.cgColor] as CFArray,
                                     locations: [0, 1]) {
            cg.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 0),
                                  end: CGPoint(x: size.width * 0.4, y: size.height),
                                  options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        }
        var rng = SeededGenerator(seed: seed)
        let glow = UIColor(white: 1, alpha: 0.38).cgColor
        let clear = UIColor(white: 1, alpha: 0).cgColor
        guard let bokeh = CGGradient(colorsSpace: space, colors: [glow, clear] as CFArray, locations: [0, 1]) else { return }
        let base = min(size.width, size.height)
        for i in 0..<16 {
            let r = CGFloat.random(in: base * 0.05...base * 0.2, using: &rng)
            let x = CGFloat.random(in: 0...size.width, using: &rng)
            let y = CGFloat.random(in: 0...size.height, using: &rng)
            let drift = sin(phase * .pi * 2 + CGFloat(i)) * base * 0.04
            let center = CGPoint(x: x + drift, y: y - drift * 0.6)
            cg.saveGState()
            cg.setAlpha(CGFloat.random(in: 0.25...0.8, using: &rng))
            cg.drawRadialGradient(bokeh, startCenter: center, startRadius: 0, endCenter: center, endRadius: r, options: [])
            cg.restoreGState()
        }
    }

    // MARK: 视频 / 实况

    private static func makeVideo(id: String, seed: Int) async {
        guard let url = await movie(seed: seed, seconds: 4) else { return }
        defer { try? FileManager.default.removeItem(at: url) }
        _ = try? await MediaStore.shared.importVideo(at: url, id: id)
    }

    private static func makeLive(id: String, seed: Int) async {
        let store = MediaStore.shared
        let photoURL = store.incomingURL(ext: "jpg")
        guard let data = photo(seed: seed, size: CGSize(width: 1080, height: 1440), date: Date().addingTimeInterval(-4 * 86400)),
              (try? data.write(to: photoURL)) != nil,
              let videoURL = await movie(seed: seed, seconds: 2, size: CGSize(width: 1080, height: 1440)) else { return }
        defer {
            try? FileManager.default.removeItem(at: photoURL)
            try? FileManager.default.removeItem(at: videoURL)
        }
        _ = try? await store.importLive(photoURL: photoURL, videoURL: videoURL, id: id)
    }

    private static func movie(seed: Int, seconds: Double, size: CGSize = CGSize(width: 720, height: 1280)) async -> URL? {
        let url = MediaStore.shared.incomingURL(ext: "mov")
        guard let writer = try? AVAssetWriter(outputURL: url, fileType: .mov) else { return nil }
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height)
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Int(size.width),
            kCVPixelBufferHeightKey as String: Int(size.height)
        ])
        guard writer.canAdd(input) else { return nil }
        writer.add(input)
        guard writer.startWriting() else { return nil }
        writer.startSession(atSourceTime: .zero)

        let fps: Int32 = 30
        let frames = Int(seconds * Double(fps))
        for frame in 0..<frames {
            while !input.isReadyForMoreMediaData {
                try? await Task.sleep(nanoseconds: 5_000_000)
            }
            guard let pool = adaptor.pixelBufferPool else { break }
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
            guard let buffer else { break }
            CVPixelBufferLockBaseAddress(buffer, [])
            if let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer),
                                       width: Int(size.width), height: Int(size.height),
                                       bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                                       space: CGColorSpaceCreateDeviceRGB(),
                                       bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                                           | CGBitmapInfo.byteOrder32Little.rawValue) {
                draw(in: context, size: size, seed: seed, phase: CGFloat(frame) / CGFloat(frames))
            }
            CVPixelBufferUnlockBaseAddress(buffer, [])
            _ = adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: fps))
        }
        input.markAsFinished()
        await writer.finishWriting()
        return writer.status == .completed ? url : nil
    }
}

/// 固定种子的随机数，演示图每次都一样
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: Int) {
        state = UInt64(truncatingIfNeeded: seed) &* 0x9E37_79B9_7F4A_7C15 &+ 0x2545_F491_4F6C_DD1D
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
#endif
