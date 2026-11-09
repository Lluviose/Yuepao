import UIKit
import AVFoundation
import CryptoKit
import ImageIO
import UniformTypeIdentifiers

/// 照片 / 实况 / 视频
enum MediaKind: String, Codable, CaseIterable, Identifiable {
    case photo, live, video

    var id: String { rawValue }

    var title: String {
        switch self {
        case .photo: return "照片"
        case .live: return "实况"
        case .video: return "视频"
        }
    }

    var symbol: String {
        switch self {
        case .photo: return "photo"
        case .live: return "livephoto"
        case .video: return "video"
        }
    }
}

/// 每个文件的说明，加密存在 `<id>.info` 里
struct MediaInfo: Codable, Hashable {
    var kind: MediaKind
    /// 原文件类型，比如 public.heic、com.apple.quicktime-movie
    var type: String
    /// 实况照片配对视频的类型
    var pairType: String?
    var width: Int = 0
    var height: Int = 0
    /// 视频 / 实况视频的时长（秒）
    var duration: Double?
    /// 原文件大小（实况 = 照片 + 视频）
    var bytes: Int64 = 0
    /// 拍摄时间（照片 EXIF / 视频元数据）
    var capturedAt: Date?
    var importedAt = Date()
    /// 旧版本压缩过的照片（2048 像素 JPEG）
    var legacy = false

    var aspect: CGFloat {
        guard width > 0, height > 0 else { return 1 }
        return CGFloat(width) / CGFloat(height)
    }

    /// HEIC / JPEG / MOV …
    var format: String {
        guard let ut = UTType(type) else { return "" }
        if ut.conforms(to: .heic) || ut.conforms(to: .heif) { return "HEIC" }
        if ut.conforms(to: .jpeg) { return "JPEG" }
        if ut.conforms(to: .png) { return "PNG" }
        if ut.conforms(to: .gif) { return "GIF" }
        if ut.conforms(to: .rawImage) { return "RAW" }
        if ut.conforms(to: .quickTimeMovie) { return "MOV" }
        if ut.conforms(to: .mpeg4Movie) { return "MP4" }
        return (ut.preferredFilenameExtension ?? "").uppercased()
    }

    /// 「1200 万像素」「4K」这类说法
    var resolution: String? {
        guard width > 0, height > 0 else { return nil }
        if kind == .video {
            let short = min(width, height)
            switch short {
            case 2160...: return "4K"
            case 1440..<2160: return "2K"
            case 1080..<1440: return "1080p"
            case 720..<1080: return "720p"
            default: return "\(width) × \(height)"
            }
        }
        let mp = Double(width * height) / 1_000_000
        if mp >= 1 { return "\(Int(mp.rounded())) MP" }
        return "\(width) × \(height)"
    }

    /// 「HEIC · 12 MP · 3.1 MB」
    var summary: String {
        var parts: [String] = []
        if legacy {
            parts.append("旧版压缩图")
        } else if !format.isEmpty {
            parts.append(format)
        }
        if let resolution { parts.append(resolution) }
        if bytes > 0 { parts.append(Fmt.bytes(bytes)) }
        return parts.joined(separator: " · ")
    }
}

/// 媒体占用统计
struct MediaUsage: Equatable {
    var photos = 0
    var lives = 0
    var videos = 0
    var bytes: Int64 = 0
    var videoBytes: Int64 = 0

    var count: Int { photos + lives + videos }

    var summary: String {
        var parts: [String] = []
        if photos > 0 { parts.append("\(photos) 张照片") }
        if lives > 0 { parts.append("\(lives) 个实况") }
        if videos > 0 { parts.append("\(videos) 个视频") }
        return parts.isEmpty ? "还没有照片或视频" : parts.joined(separator: " · ")
    }
}

/// 照片、视频、实况的加密存储。
/// - 原样保存：HEIC 就是 HEIC，视频不转码，实况照片连同配对视频一起存，不缩放、不重新压缩；
/// - 大文件分块加密（见 `ChunkCipher`），视频也不用整个读进内存；
/// - 另存一张小缩略图，列表、头像、地图都用它，不必每次解原图；
/// - 文件都在 App 沙盒里，密钥在钥匙串，不进系统相册。
final class MediaStore {
    static let shared = MediaStore()

    enum Part: String, CaseIterable {
        /// 旧版：缩到 2048 像素的 JPEG，整个加密
        case legacy = "enc"
        /// 原文件：照片 / 视频 / 实况的照片
        case main = "media"
        /// 实况的配对视频
        case pair = "pair"
        case thumb = "thumb"
        case info = "info"
    }

    /// 缩略图最长边（像素）
    static let thumbPixels: CGFloat = 720
    /// 缓存分档，避免同一张图缓存太多尺寸
    static let buckets: [CGFloat] = [96, 192, 384, 720]

    let directory: URL
    let stagingDirectory: URL
    let playbackDirectory: URL
    let incomingDirectory: URL

    private let fm = FileManager.default
    private let thumbCache = NSCache<NSString, UIImage>()
    private let cacheLock = NSLock()
    private let keyLock = NSLock()
    private var infoCache: [String: MediaInfo] = [:]
    private var cachedKey: SymmetricKey?

    private init() {
        let files = FileManager.default
        let base = files.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        directory = base.appendingPathComponent("Photos", isDirectory: true)
        stagingDirectory = base.appendingPathComponent("PhotosRestore", isDirectory: true)
        playbackDirectory = files.temporaryDirectory.appendingPathComponent("Playback", isDirectory: true)
        incomingDirectory = files.temporaryDirectory.appendingPathComponent("Incoming", isDirectory: true)
        for dir in [directory, playbackDirectory, incomingDirectory] {
            try? files.createDirectory(at: dir, withIntermediateDirectories: true,
                                       attributes: [.protectionKey: FileProtectionType.complete])
        }
        thumbCache.totalCostLimit = 96 << 20
    }

    func url(_ id: String, _ part: Part, in dir: URL? = nil) -> URL {
        (dir ?? directory).appendingPathComponent("\(id).\(part.rawValue)")
    }

    static func isValidID(_ id: String) -> Bool {
        !id.isEmpty && id.count <= 64 && !id.contains("/") && !id.contains("..") && !id.hasPrefix(".")
    }

    func encryptionKey() throws -> SymmetricKey {
        keyLock.lock()
        defer { keyLock.unlock() }
        if let cachedKey { return cachedKey }
        let key = try KeychainKey.loadOrCreate()
        cachedKey = key
        return key
    }

    // MARK: - 导入

    /// 照片原样保存。`staging` 为 true 时写到恢复用的暂存目录
    @discardableResult
    func importPhoto(data: Data, id: String = UUID().uuidString, staging: Bool = false) throws -> String {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0 else { throw MediaError.unsupported }
        var info = MediaInfo(kind: .photo, type: Self.imageType(source))
        Self.readImageProperties(source, into: &info)
        info.bytes = Int64(data.count)
        let dir: URL? = staging ? stagingDirectory : nil
        do {
            try writeChunked(data, to: url(id, .main, in: dir))
            try writeThumbnail(from: source, id: id, in: dir)
            try saveInfo(info, id: id, in: dir)
        } catch {
            if staging {
                for part in Part.allCases { try? fm.removeItem(at: url(id, part, in: dir)) }
            } else {
                delete(id)
            }
            throw error
        }
        return id
    }

    /// 视频原文件加密保存（不转码）
    func importVideo(at fileURL: URL, id: String = UUID().uuidString) async throws -> String {
        let asset = AVURLAsset(url: fileURL)
        let meta = await Self.videoMetadata(asset)
        var info = MediaInfo(kind: .video, type: Self.typeIdentifier(for: fileURL, fallback: .quickTimeMovie))
        info.width = meta.width
        info.height = meta.height
        info.duration = meta.duration
        info.capturedAt = meta.capturedAt
        info.bytes = fileSize(fileURL)
        let poster = await Self.posterFrame(asset, maxPixels: Self.thumbPixels)
        do {
            try copyEncrypted(from: fileURL, to: url(id, .main))
            if let poster { try writeThumbnail(poster, id: id) }
            try saveInfo(info, id: id)
        } catch {
            delete(id)
            throw error
        }
        return id
    }

    /// 实况照片：照片和配对视频都按原文件保存
    func importLive(photoURL: URL, videoURL: URL, id: String = UUID().uuidString) async throws -> String {
        let photoData = try Data(contentsOf: photoURL)
        guard let source = CGImageSourceCreateWithData(photoData as CFData, nil),
              CGImageSourceGetCount(source) > 0 else { throw MediaError.unsupported }
        var info = MediaInfo(kind: .live, type: Self.imageType(source))
        Self.readImageProperties(source, into: &info)
        info.pairType = Self.typeIdentifier(for: videoURL, fallback: .quickTimeMovie)
        let meta = await Self.videoMetadata(AVURLAsset(url: videoURL))
        info.duration = meta.duration
        if info.capturedAt == nil { info.capturedAt = meta.capturedAt }
        info.bytes = Int64(photoData.count) + fileSize(videoURL)
        do {
            try writeChunked(photoData, to: url(id, .main))
            try copyEncrypted(from: videoURL, to: url(id, .pair))
            try writeThumbnail(from: source, id: id)
            try saveInfo(info, id: id)
        } catch {
            delete(id)
            throw error
        }
        return id
    }

    /// 头像只要清晰就够了：缩到 1200 像素另存一份
    func importAvatar(data: Data) throws -> String {
        guard let image = Self.downsample(data, maxPixels: 1200),
              let jpeg = image.jpegData(compressionQuality: 0.9) else { throw MediaError.unsupported }
        return try importPhoto(data: jpeg)
    }

    /// 用相册里的一项做头像：另存一份，删掉原图不影响头像
    func makeAvatar(from id: String) -> String? {
        let image: UIImage?
        if kind(id) == .video {
            image = thumbnailData(id).flatMap { Self.downsample($0, maxPixels: 1200) }
        } else {
            image = displayImage(id, maxPixels: 1200)
        }
        guard let jpeg = image?.jpegData(compressionQuality: 0.9) else { return nil }
        return try? importPhoto(data: jpeg)
    }

    // MARK: - 读取

    func exists(_ id: String) -> Bool {
        fm.fileExists(atPath: url(id, .main).path) || fm.fileExists(atPath: url(id, .legacy).path)
    }

    func isLegacy(_ id: String) -> Bool {
        !fm.fileExists(atPath: url(id, .main).path) && fm.fileExists(atPath: url(id, .legacy).path)
    }

    func info(_ id: String) -> MediaInfo? {
        cacheLock.lock()
        let cached = infoCache[id]
        cacheLock.unlock()
        if let cached { return cached }
        var result: MediaInfo?
        if let data = readSealed(url(id, .info)) {
            result = try? JSONDecoder().decode(MediaInfo.self, from: data)
        }
        if result == nil, fm.fileExists(atPath: url(id, .legacy).path) {
            result = legacyInfo(id)
        }
        if let result { cacheInfo(result, id: id) }
        return result
    }

    func kind(_ id: String) -> MediaKind {
        info(id)?.kind ?? .photo
    }

    /// 照片 / 实况照片的原始数据；视频返回 nil
    func stillData(_ id: String) -> Data? {
        if fm.fileExists(atPath: url(id, .main).path) {
            guard kind(id) != .video else { return nil }
            return try? readChunked(url(id, .main))
        }
        return readSealed(url(id, .legacy))
    }

    /// 全屏看图：直接从原图解码，超大的图按 maxPixels 缩小，避免占太多内存
    func displayImage(_ id: String, maxPixels: CGFloat) -> UIImage? {
        guard let data = stillData(id) else { return nil }
        return Self.downsample(data, maxPixels: maxPixels)
    }

    /// 缩略图，size 是像素。同步读取、带缓存；列表里用 `loadThumbnail`
    func thumbnail(_ id: String, size: CGFloat = 240) -> UIImage? {
        let pixels = Self.bucket(size)
        let key = Self.cacheKey(id, pixels)
        if let cached = thumbCache.object(forKey: key) { return cached }
        guard let data = thumbnailData(id), let image = Self.downsample(data, maxPixels: pixels) else { return nil }
        thumbCache.setObject(image, forKey: key, cost: Self.cost(of: image))
        return image
    }

    func cachedThumbnail(_ id: String, size: CGFloat) -> UIImage? {
        thumbCache.object(forKey: Self.cacheKey(id, Self.bucket(size)))
    }

    func loadThumbnail(_ id: String, size: CGFloat) async -> UIImage? {
        if let cached = cachedThumbnail(id, size: size) { return cached }
        return await Task.detached(priority: .userInitiated) {
            MediaStore.shared.thumbnail(id, size: size)
        }.value
    }

    /// 缩略图 JPEG；旧照片或缺缩略图的照片现做一张存起来
    func thumbnailData(_ id: String) -> Data? {
        let file = url(id, .thumb)
        if let data = readSealed(file) { return data }
        guard let original = stillData(id),
              let source = CGImageSourceCreateWithData(original as CFData, nil) else { return nil }
        try? writeThumbnail(from: source, id: id)
        return readSealed(file)
    }

    /// 解密到临时文件（播放视频、实况、存回系统相册、分享用）。关闭查看器时统一删掉
    func plainFile(_ id: String, part: Part = .main, progress: ((Double) -> Void)? = nil) throws -> URL {
        let info = self.info(id)
        let type = part == .pair ? info?.pairType : info?.type
        let ext = type.flatMap { UTType($0)?.preferredFilenameExtension } ?? (part == .pair ? "mov" : "jpg")
        let dest = playbackDirectory.appendingPathComponent("\(id)-\(part.rawValue).\(ext)")
        if fm.fileExists(atPath: dest.path) { return dest }
        try? fm.createDirectory(at: playbackDirectory, withIntermediateDirectories: true)
        let temp = playbackDirectory.appendingPathComponent(UUID().uuidString + ".partial")
        do {
            if part == .main, isLegacy(id) {
                guard let data = readSealed(url(id, .legacy)) else { throw MediaError.missing }
                try data.write(to: temp, options: .completeFileProtection)
            } else {
                let reader = try ChunkReader(url: url(id, part), key: try encryptionKey())
                guard fm.createFile(atPath: temp.path, contents: nil,
                                    attributes: [.protectionKey: FileProtectionType.complete]) else {
                    throw MediaError.writeFailed
                }
                let out = try FileHandle(forWritingTo: temp)
                defer { try? out.close() }
                var done = 0
                let total = reader.chunkCount
                try reader.forEachChunk { chunk in
                    try out.write(contentsOf: chunk)
                    done += 1
                    progress?(Double(done) / Double(total))
                }
            }
            if fm.fileExists(atPath: dest.path) {
                try? fm.removeItem(at: temp)
            } else {
                try fm.moveItem(at: temp, to: dest)
            }
            return dest
        } catch {
            try? fm.removeItem(at: temp)
            throw error
        }
    }

    /// 关掉查看器后删掉解密出来的临时文件
    func purgePlayback() {
        try? fm.removeItem(at: playbackDirectory)
        try? fm.createDirectory(at: playbackDirectory, withIntermediateDirectories: true,
                                attributes: [.protectionKey: FileProtectionType.complete])
    }

    /// 启动时清掉上次没处理完的临时文件
    func purgeTemporary() {
        purgePlayback()
        discardStaging()
        try? fm.removeItem(at: fm.temporaryDirectory.appendingPathComponent("Backup", isDirectory: true))
        try? fm.removeItem(at: incomingDirectory)
        try? fm.createDirectory(at: incomingDirectory, withIntermediateDirectories: true,
                                attributes: [.protectionKey: FileProtectionType.complete])
    }

    /// 从相册选择器收到的原文件先放这里，导入完就删
    func incomingURL(ext: String) -> URL {
        try? fm.createDirectory(at: incomingDirectory, withIntermediateDirectories: true,
                                attributes: [.protectionKey: FileProtectionType.complete])
        let clean = ext.isEmpty ? "dat" : ext.lowercased()
        return incomingDirectory.appendingPathComponent("\(UUID().uuidString).\(clean)")
    }

    // MARK: - 删除 / 统计

    func delete(_ id: String) {
        guard Self.isValidID(id) else { return }
        for part in Part.allCases {
            try? fm.removeItem(at: url(id, part))
        }
        forget(id)
        if let files = try? fm.contentsOfDirectory(at: playbackDirectory, includingPropertiesForKeys: nil) {
            for file in files where file.lastPathComponent.hasPrefix(id) {
                try? fm.removeItem(at: file)
            }
        }
    }

    func delete(_ ids: [String]) {
        ids.forEach { delete($0) }
    }

    func deleteAll() {
        if let files = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
            files.forEach { try? fm.removeItem(at: $0) }
        }
        cacheLock.lock()
        infoCache.removeAll()
        cacheLock.unlock()
        thumbCache.removeAllObjects()
        purgePlayback()
    }

    func allIDs() -> [String] {
        let files = (try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        var ids = Set<String>()
        for file in files where file.pathExtension == Part.main.rawValue || file.pathExtension == Part.legacy.rawValue {
            ids.insert(file.deletingPathExtension().lastPathComponent)
        }
        return ids.sorted()
    }

    func diskSize(_ id: String) -> Int64 {
        Part.allCases.reduce(Int64(0)) { $0 + fileSize(url(id, $1)) }
    }

    func usage(of ids: [String]) -> MediaUsage {
        var usage = MediaUsage()
        for id in ids where exists(id) {
            let size = diskSize(id)
            switch kind(id) {
            case .photo: usage.photos += 1
            case .live: usage.lives += 1
            case .video:
                usage.videos += 1
                usage.videoBytes += size
            }
            usage.bytes += size
        }
        return usage
    }

    func fileSize(_ url: URL) -> Int64 {
        let attributes = try? fm.attributesOfItem(atPath: url.path)
        return (attributes?[.size] as? NSNumber)?.int64Value ?? 0
    }

    // MARK: - 备份用

    /// 读某个部分（不存在时返回 nil）
    func reader(_ id: String, _ part: Part) throws -> ChunkReader? {
        let file = url(id, part)
        guard fm.fileExists(atPath: file.path) else { return nil }
        return try ChunkReader(url: file, key: try encryptionKey())
    }

    /// 旧版照片的 JPEG 数据
    func legacyData(_ id: String) -> Data? {
        readSealed(url(id, .legacy))
    }

    /// 恢复备份时先写到暂存目录，全部成功后再替换，失败了不影响现有数据
    func beginStaging() {
        try? fm.removeItem(at: stagingDirectory)
        try? fm.createDirectory(at: stagingDirectory, withIntermediateDirectories: true,
                                attributes: [.protectionKey: FileProtectionType.complete])
    }

    func stagingWriter(_ id: String, _ part: Part) throws -> ChunkWriter {
        try ChunkWriter(url: url(id, part, in: stagingDirectory), key: try encryptionKey())
    }

    func stageSealed(_ data: Data, id: String, part: Part) throws {
        try writeSealed(data, to: url(id, part, in: stagingDirectory))
    }

    func commitStaging() throws {
        let files = try fm.contentsOfDirectory(at: stagingDirectory, includingPropertiesForKeys: nil)
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true,
                                attributes: [.protectionKey: FileProtectionType.complete])
        for file in files {
            let dest = directory.appendingPathComponent(file.lastPathComponent)
            try? fm.removeItem(at: dest)
            try fm.moveItem(at: file, to: dest)
        }
        try? fm.removeItem(at: stagingDirectory)
        cacheLock.lock()
        infoCache.removeAll()
        cacheLock.unlock()
        thumbCache.removeAllObjects()
    }

    func discardStaging() {
        try? fm.removeItem(at: stagingDirectory)
    }

    // MARK: - 内部

    private func cacheInfo(_ info: MediaInfo, id: String) {
        cacheLock.lock()
        infoCache[id] = info
        cacheLock.unlock()
    }

    private func forget(_ id: String) {
        cacheLock.lock()
        infoCache[id] = nil
        cacheLock.unlock()
        for bucket in Self.buckets {
            thumbCache.removeObject(forKey: Self.cacheKey(id, bucket))
        }
    }

    private func saveInfo(_ info: MediaInfo, id: String, in dir: URL? = nil) throws {
        try writeSealed(try JSONEncoder().encode(info), to: url(id, .info, in: dir))
        if dir == nil { cacheInfo(info, id: id) }
    }

    private func legacyInfo(_ id: String) -> MediaInfo? {
        let file = url(id, .legacy)
        guard let data = readSealed(file) else { return nil }
        var info = MediaInfo(kind: .photo, type: UTType.jpeg.identifier)
        info.legacy = true
        info.bytes = Int64(data.count)
        if let source = CGImageSourceCreateWithData(data as CFData, nil) {
            Self.readImageProperties(source, into: &info)
        }
        let attributes = try? fm.attributesOfItem(atPath: file.path)
        info.importedAt = (attributes?[.creationDate] as? Date) ?? Date()
        return info
    }

    private func writeSealed(_ data: Data, to file: URL) throws {
        let box = try AES.GCM.seal(data, using: try encryptionKey())
        guard let combined = box.combined else { throw MediaError.writeFailed }
        try combined.write(to: file, options: [.atomic, .completeFileProtection])
    }

    private func readSealed(_ file: URL) -> Data? {
        guard let encrypted = try? Data(contentsOf: file),
              let key = try? encryptionKey(),
              let box = try? AES.GCM.SealedBox(combined: encrypted),
              let plain = try? AES.GCM.open(box, using: key) else { return nil }
        return plain
    }

    private func readChunked(_ file: URL) throws -> Data {
        try ChunkReader(url: file, key: try encryptionKey()).readAll()
    }

    private func writeChunked(_ data: Data, to file: URL) throws {
        let writer = try ChunkWriter(url: file, key: try encryptionKey())
        do {
            var index = data.startIndex
            while index < data.endIndex {
                let end = data.index(index, offsetBy: ChunkCipher.defaultChunkSize, limitedBy: data.endIndex) ?? data.endIndex
                try writer.write(data.subdata(in: index..<end))
                index = end
            }
            try writer.finish()
        } catch {
            writer.abort()
            throw error
        }
    }

    private func copyEncrypted(from source: URL, to file: URL) throws {
        let input = try FileHandle(forReadingFrom: source)
        defer { try? input.close() }
        let writer = try ChunkWriter(url: file, key: try encryptionKey())
        do {
            var finished = false
            while !finished {
                try autoreleasepool {
                    if let piece = try input.read(upToCount: ChunkCipher.defaultChunkSize), !piece.isEmpty {
                        try writer.write(piece)
                    } else {
                        finished = true
                    }
                }
            }
            try writer.finish()
        } catch {
            writer.abort()
            throw error
        }
    }

    private func writeThumbnail(from source: CGImageSource, id: String, in dir: URL? = nil) throws {
        guard let image = Self.thumbnail(from: source, maxPixels: Self.thumbPixels) else { return }
        try writeThumbnail(image, id: id, in: dir)
    }

    private func writeThumbnail(_ image: UIImage, id: String, in dir: URL? = nil) throws {
        guard let jpeg = image.jpegData(compressionQuality: 0.82) else { return }
        try writeSealed(jpeg, to: url(id, .thumb, in: dir))
    }

    // MARK: - 工具

    static func bucket(_ size: CGFloat) -> CGFloat {
        buckets.first { $0 >= size } ?? thumbPixels
    }

    static func cacheKey(_ id: String, _ pixels: CGFloat) -> NSString {
        "\(id)-\(Int(pixels))" as NSString
    }

    static func cost(of image: UIImage) -> Int {
        guard let cg = image.cgImage else { return 1 }
        return cg.bytesPerRow * cg.height
    }

    static func imageType(_ source: CGImageSource) -> String {
        (CGImageSourceGetType(source) as String?) ?? UTType.jpeg.identifier
    }

    static func typeIdentifier(for file: URL, fallback: UTType) -> String {
        (UTType(filenameExtension: file.pathExtension) ?? fallback).identifier
    }

    static func thumbnail(from source: CGImageSource, maxPixels: CGFloat) -> UIImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: cg)
    }

    static func downsample(_ data: Data, maxPixels: CGFloat) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else { return nil }
        return thumbnail(from: source, maxPixels: maxPixels)
    }

    private static let exifFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return f
    }()

    static func readImageProperties(_ source: CGImageSource, into info: inout MediaInfo) {
        guard let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] else { return }
        var width = (props[kCGImagePropertyPixelWidth as String] as? NSNumber)?.intValue ?? 0
        var height = (props[kCGImagePropertyPixelHeight as String] as? NSNumber)?.intValue ?? 0
        // 方向 5~8 是转了 90 度的
        if let orientation = (props[kCGImagePropertyOrientation as String] as? NSNumber)?.intValue, orientation >= 5 {
            swap(&width, &height)
        }
        info.width = width
        info.height = height
        if let exif = props[kCGImagePropertyExifDictionary as String] as? [String: Any],
           let text = exif[kCGImagePropertyExifDateTimeOriginal as String] as? String {
            info.capturedAt = exifFormatter.date(from: text)
        }
    }

    struct VideoMetadata {
        var width = 0
        var height = 0
        var duration: Double?
        var capturedAt: Date?
    }

    static func videoMetadata(_ asset: AVAsset) async -> VideoMetadata {
        var meta = VideoMetadata()
        if let duration = try? await asset.load(.duration), duration.seconds.isFinite {
            meta.duration = duration.seconds
        }
        if let track = try? await asset.loadTracks(withMediaType: .video).first,
           let loaded = try? await track.load(.naturalSize, .preferredTransform) {
            let rect = CGRect(origin: .zero, size: loaded.0).applying(loaded.1)
            meta.width = Int(abs(rect.width).rounded())
            meta.height = Int(abs(rect.height).rounded())
        }
        if let item = try? await asset.load(.creationDate),
           let date = try? await item.load(.dateValue) {
            meta.capturedAt = date
        }
        return meta
    }

    static func posterFrame(_ asset: AVAsset, maxPixels: CGFloat) async -> UIImage? {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxPixels, height: maxPixels)
        guard let result = try? await generator.image(at: .zero) else { return nil }
        return UIImage(cgImage: result.0)
    }
}
