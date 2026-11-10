import Foundation
import CryptoKit
import Security

enum MediaError: LocalizedError {
    case corrupt, unsupported, writeFailed, missing, keyUnavailable, notAuthorized

    var errorDescription: String? {
        switch self {
        case .corrupt: return "文件已损坏"
        case .unsupported: return "不支持这种格式"
        case .writeFailed: return "写入失败，可能是空间不够"
        case .missing: return "文件不存在"
        case .keyUnavailable: return "暂时读不到加密密钥，请解锁手机后再试"
        case .notAuthorized: return "没有相册权限，可以去系统设置里打开"
        }
    }
}

/// 大端整数和字节互转
enum ByteCoding {
    static func bytes(_ value: UInt64, count: Int) -> Data {
        var out = [UInt8](repeating: 0, count: count)
        for i in 0..<count {
            out[count - 1 - i] = UInt8(truncatingIfNeeded: value >> (8 * UInt64(i)))
        }
        return Data(out)
    }

    static func value<D: DataProtocol>(_ data: D) -> UInt64 {
        data.reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
    }
}

/// 分块加密格式：原图、视频、备份都用它。
/// 文件头 "YPC1" + 块大小（UInt32 大端），之后每块 = nonce(12) + 密文 + tag(16)。
/// 每块的附加认证数据是「块序号 + 是否最后一块」，块被调换、截断都能发现。
/// 好处是几百 MB 的视频也不用一次读进内存。
enum ChunkCipher {
    static let magic = Data("YPC1".utf8)
    static let headerSize = 8
    static let overhead = 28
    static let defaultChunkSize = 1 << 20

    static func associatedData(index: UInt64, isFinal: Bool) -> Data {
        var data = ByteCoding.bytes(index, count: 8)
        data.append(isFinal ? 1 : 0)
        return data
    }
}

/// 边写边加密。写完一定要调 `finish()`，出错时调 `abort()` 删掉半截文件
final class ChunkWriter {
    let url: URL
    private let handle: FileHandle
    private let key: SymmetricKey
    private let chunkSize: Int
    private var buffer = Data()
    private var index: UInt64 = 0
    private var closed = false
    private(set) var plainCount: Int64 = 0

    /// `prefix` 会原样写在加密内容前面（备份文件的文件头用）
    init(url: URL, key: SymmetricKey, prefix: Data = Data(), chunkSize: Int = ChunkCipher.defaultChunkSize) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: url.path) { try fm.removeItem(at: url) }
        guard fm.createFile(atPath: url.path, contents: nil,
                            attributes: [.protectionKey: FileProtectionType.complete]) else {
            throw MediaError.writeFailed
        }
        let handle = try FileHandle(forWritingTo: url)
        var header = prefix
        header.append(ChunkCipher.magic)
        header.append(ByteCoding.bytes(UInt64(chunkSize), count: 4))
        do {
            try handle.write(contentsOf: header)
        } catch {
            try? handle.close()
            try? fm.removeItem(at: url)
            throw error
        }
        self.url = url
        self.handle = handle
        self.key = key
        self.chunkSize = chunkSize
    }

    deinit {
        if !closed { try? handle.close() }
    }

    func write(_ data: Data) throws {
        guard !data.isEmpty else { return }
        buffer.append(data)
        plainCount += Int64(data.count)
        // 总留着最后一块，等 finish 时才知道它是不是最后一块
        while buffer.count > chunkSize {
            let chunk = Data(buffer.prefix(chunkSize))
            buffer = Data(buffer.dropFirst(chunkSize))
            try seal(chunk, isFinal: false)
        }
    }

    func finish() throws {
        guard !closed else { return }
        try seal(buffer, isFinal: true)
        buffer = Data()
        closed = true
        try handle.close()
    }

    func abort() {
        if !closed {
            closed = true
            try? handle.close()
        }
        try? FileManager.default.removeItem(at: url)
    }

    private func seal(_ chunk: Data, isFinal: Bool) throws {
        let box = try AES.GCM.seal(chunk, using: key,
                                   authenticating: ChunkCipher.associatedData(index: index, isFinal: isFinal))
        guard let combined = box.combined else { throw MediaError.writeFailed }
        try handle.write(contentsOf: combined)
        index += 1
    }
}

/// 按块解密，可以顺序读，也可以只读某一块
final class ChunkReader {
    let plainSize: Int64
    let chunkCount: Int
    private let handle: FileHandle
    private let key: SymmetricKey
    private let chunkSize: Int
    private let fileSize: Int64
    private let base: Int64
    private var closed = false

    /// `offset`：加密内容在文件里的起点（备份文件前面有自己的文件头）
    init(url: URL, key: SymmetricKey, offset: Int64 = 0) throws {
        let handle = try FileHandle(forReadingFrom: url)
        do {
            try handle.seek(toOffset: UInt64(offset))
            guard let header = try handle.read(upToCount: ChunkCipher.headerSize),
                  header.count == ChunkCipher.headerSize,
                  Data(header.prefix(4)) == ChunkCipher.magic else { throw MediaError.corrupt }
            let chunkSize = Int(ByteCoding.value(header.suffix(4)))
            guard chunkSize > 0, chunkSize <= 64 << 20 else { throw MediaError.corrupt }
            let fileSize = Int64(try handle.seekToEnd())
            let base = offset + Int64(ChunkCipher.headerSize)
            let body = fileSize - base
            let stride = Int64(chunkSize + ChunkCipher.overhead)
            var count = Int(body / stride)
            var plain = Int64(count) * Int64(chunkSize)
            let rest = body % stride
            if rest > 0 {
                guard rest >= Int64(ChunkCipher.overhead) else { throw MediaError.corrupt }
                count += 1
                plain += rest - Int64(ChunkCipher.overhead)
            }
            guard count > 0 else { throw MediaError.corrupt }
            self.handle = handle
            self.key = key
            self.chunkSize = chunkSize
            self.fileSize = fileSize
            self.base = base
            self.chunkCount = count
            self.plainSize = plain
        } catch {
            try? handle.close()
            throw error
        }
    }

    deinit {
        close()
    }

    func close() {
        guard !closed else { return }
        closed = true
        try? handle.close()
    }

    func chunk(at index: Int) throws -> Data {
        guard index >= 0, index < chunkCount else { throw MediaError.corrupt }
        let stride = Int64(chunkSize + ChunkCipher.overhead)
        let start = base + Int64(index) * stride
        let length = Int(min(stride, fileSize - start))
        try handle.seek(toOffset: UInt64(start))
        guard let sealed = try handle.read(upToCount: length), sealed.count == length else {
            throw MediaError.corrupt
        }
        let box = try AES.GCM.SealedBox(combined: sealed)
        let aad = ChunkCipher.associatedData(index: UInt64(index), isFinal: index == chunkCount - 1)
        return try AES.GCM.open(box, using: key, authenticating: aad)
    }

    func forEachChunk(_ body: (Data) throws -> Void) throws {
        for i in 0..<chunkCount {
            try autoreleasepool {
                try body(try chunk(at: i))
            }
        }
    }

    func readAll() throws -> Data {
        var out = Data(capacity: Int(plainSize))
        try forEachChunk { out.append($0) }
        return out
    }
}

/// 把解密后的内容当成一条连续的字节流来读（解析备份用）
final class ChunkStream {
    private let reader: ChunkReader
    private var buffer = Data()
    private var next = 0
    private(set) var consumed: Int64 = 0

    init(_ reader: ChunkReader) {
        self.reader = reader
    }

    var totalSize: Int64 { reader.plainSize }

    func read(_ count: Int) throws -> Data {
        guard count > 0 else { return Data() }
        while buffer.count < count {
            guard next < reader.chunkCount else { throw MediaError.corrupt }
            buffer.append(try reader.chunk(at: next))
            next += 1
        }
        let out = Data(buffer.prefix(count))
        buffer = Data(buffer.dropFirst(count))
        consumed += Int64(count)
        return out
    }

    func readInt(_ byteCount: Int) throws -> UInt64 {
        ByteCoding.value(try read(byteCount))
    }
}

/// 照片密钥：放在钥匙串里，只存在这台设备上
enum KeychainKey {
    private static let service = "com.lluviose.yuepao.photo-key"

    static func loadOrCreate() throws -> SymmetricKey {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess, let data = result as? Data, data.count == 32 {
            return SymmetricKey(data: data)
        }
        // 只有确实没有密钥时才新建。钥匙串暂时读不了（比如开机后还没解锁过）就报错，
        // 绝不能新建一把覆盖掉旧的，否则以前的照片就再也打不开了
        guard status == errSecItemNotFound else { throw MediaError.keyUnavailable }
        let key = SymmetricKey(size: .bits256)
        let data = key.withUnsafeBytes { Data($0) }
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        guard SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess else { throw MediaError.keyUnavailable }
        return key
    }
}
