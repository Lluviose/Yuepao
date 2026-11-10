import Foundation
import SwiftData
import CryptoKit
import CommonCrypto
import SwiftUI
import UniformTypeIdentifiers

// MARK: - 备份文件结构

struct BackupFile: Codable {
    var version: Int = 1
    var exportedAt: Date = Date()
    var config: AppConfig
    var girls: [GirlRecord]
    var places: [PlaceRecord]
    var encounters: [EncounterRecord]
    var healthTests: [HealthTestRecord]
    var photos: [String: Data]
    /// 0.2 起才有，旧备份里没有
    var todos: [TodoRecord]?
    /// 0.3 起才有
    var wishes: [WishRecord]?
    /// 2 版起照片视频不放在这里，而是跟在清单后面流式写入；这里记数量
    var mediaCount: Int?

    var mediaTotal: Int { mediaCount ?? photos.count }
}

extension BackupFile {
    /// 去掉某些照片 / 视频的引用（比如备份时选了不带视频）
    func removingMedia(_ removed: Set<String>) -> BackupFile {
        guard !removed.isEmpty else { return self }
        var copy = self
        copy.girls = girls.map { record in
            var record = record
            var d = JSONCoding.decode(GirlDetails.self, from: record.detailsData, fallback: GirlDetails())
            d.photoIDs.removeAll { removed.contains($0) }
            record.detailsData = JSONCoding.encode(d)
            return record
        }
        copy.encounters = encounters.map { record in
            var record = record
            var d = JSONCoding.decode(EncounterDetails.self, from: record.detailsData, fallback: EncounterDetails())
            d.photoIDs.removeAll { removed.contains($0) }
            record.detailsData = JSONCoding.encode(d)
            return record
        }
        return copy
    }
}

struct WishRecord: Codable {
    var id: UUID
    var createdAt: Date
    var title: String
    var kind: String
    var note: String
    var girlID: UUID?
    var isDone: Bool
    var doneAt: Date?
}

struct TodoRecord: Codable {
    var id: UUID
    var createdAt: Date
    var title: String
    var notes: String
    var dueDate: Date?
    var hasTime: Bool
    var remind: Bool
    var isDone: Bool
    var doneAt: Date?
    var girlID: UUID?
    var category: String
}

struct GirlRecord: Codable {
    var id: UUID
    var createdAt: Date
    var name: String
    var statusRaw: String
    var rank: String
    var city: String
    var latitude: Double?
    var longitude: Double?
    var avatarID: String?
    var detailsData: Data
}

struct PlaceRecord: Codable {
    var id: UUID
    var createdAt: Date
    var name: String
    var typeRaw: String
    var latitude: Double?
    var longitude: Double?
    var city: String
    var district: String
    var address: String
    var note: String
    var rating: Int
}

struct EncounterRecord: Codable {
    var id: UUID
    var date: Date
    var durationMinutes: Int
    var overnight: Bool
    var count: Int
    var protectionRaw: String
    var condomBroke: Bool
    var rating: Int
    var totalCost: Double
    var detailsData: Data
    var placeID: UUID?
    var girlIDs: [UUID]
}

struct HealthTestRecord: Codable {
    var id: UUID
    var date: Date
    var items: String
    var result: String
    var note: String
    var nextDate: Date?
}

enum BackupError: LocalizedError {
    case badFormat, wrongPassword, crypto
    case restoreRecovery(String)

    var errorDescription: String? {
        switch self {
        case .badFormat: return "不是有效的备份文件"
        case .wrongPassword: return "密码错误，或文件已损坏"
        case .crypto: return "加密失败"
        case .restoreRecovery(let reason): return "恢复未完成，原数据仍保留。请重新启动 App 后重试：\(reason)"
        }
    }
}

// MARK: - 导出 / 导入

@MainActor
enum BackupService {
    /// 当前全部数据（照片视频另外流式写入）
    static func makeManifest(context: ModelContext) throws -> BackupFile {
        let girls = try context.fetch(FetchDescriptor<Girl>())
        let places = try context.fetch(FetchDescriptor<Place>())
        let encounters = try context.fetch(FetchDescriptor<Encounter>())
        let tests = try context.fetch(FetchDescriptor<HealthTest>())
        let todos = try context.fetch(FetchDescriptor<TodoItem>())
        let wishes = try context.fetch(FetchDescriptor<WishItem>())

        return BackupFile(
            version: 2,
            config: ConfigStore.shared.config,
            girls: girls.map {
                GirlRecord(id: $0.id, createdAt: $0.createdAt, name: $0.name, statusRaw: $0.statusRaw,
                           rank: $0.rank, city: $0.city, latitude: $0.latitude, longitude: $0.longitude,
                           avatarID: $0.avatarID, detailsData: $0.detailsData)
            },
            places: places.map {
                PlaceRecord(id: $0.id, createdAt: $0.createdAt, name: $0.name, typeRaw: $0.typeRaw,
                            latitude: $0.latitude, longitude: $0.longitude, city: $0.city, district: $0.district,
                            address: $0.address, note: $0.note, rating: $0.rating)
            },
            encounters: encounters.map {
                EncounterRecord(id: $0.id, date: $0.date, durationMinutes: $0.durationMinutes, overnight: $0.overnight,
                                count: $0.count, protectionRaw: $0.protectionRaw, condomBroke: $0.condomBroke,
                                rating: $0.rating, totalCost: $0.totalCost, detailsData: $0.detailsData,
                                placeID: $0.place?.id, girlIDs: $0.girls.map(\.id))
            },
            healthTests: tests.map {
                HealthTestRecord(id: $0.id, date: $0.date, items: $0.items, result: $0.result,
                                 note: $0.note, nextDate: $0.nextDate)
            },
            photos: [:],
            todos: todos.map {
                TodoRecord(id: $0.id, createdAt: $0.createdAt, title: $0.title, notes: $0.notes, dueDate: $0.dueDate,
                           hasTime: $0.hasTime, remind: $0.remind, isDone: $0.isDone, doneAt: $0.doneAt,
                           girlID: $0.girlID, category: $0.category)
            },
            wishes: wishes.map {
                WishRecord(id: $0.id, createdAt: $0.createdAt, title: $0.title, kind: $0.kind, note: $0.note,
                           girlID: $0.girlID, isDone: $0.isDone, doneAt: $0.doneAt)
            }
        )
    }

    /// 档案头像、档案相册、记录里用到的全部照片视频
    static func referencedMediaIDs(context: ModelContext) -> Set<String> {
        var ids = Set<String>()
        for g in (try? context.fetch(FetchDescriptor<Girl>())) ?? [] {
            if let avatar = g.avatarID { ids.insert(avatar) }
            ids.formUnion(g.details.photoIDs)
        }
        for e in (try? context.fetch(FetchDescriptor<Encounter>())) ?? [] {
            ids.formUnion(e.details.photoIDs)
        }
        return ids
    }

    /// 数据库只提交一次；在同一事务里写回执，媒体目录在提交前始终留有旧副本。
    static func replaceAll(with file: BackupFile, context: ModelContext, mediaStore: MediaStore = .shared,
                           saveChanges: (ModelContext) throws -> Void = { try $0.save() }) throws {
        // 先保存用户原有的待提交编辑，rollback 才不会撤掉恢复前的操作。
        try context.save()
        let autosave = context.autosaveEnabled
        context.autosaveEnabled = false
        defer { context.autosaveEnabled = autosave }
        let receiptID = UUID()
        try mediaStore.commitStaging(receiptID: receiptID, config: file.config) {
            do {
                try deleteRecords(context: context)
                insertManifest(file, context: context)
                context.insert(RestoreReceipt(id: receiptID))
                try saveChanges(context)
            } catch {
                context.rollback()
                throw error
            }
            ConfigStore.shared.config = file.config
        }
    }

    private static func insertManifest(_ file: BackupFile, context: ModelContext) {
        var placeMap: [UUID: Place] = [:]
        for r in file.places {
            let p = Place(name: r.name)
            context.insert(p)
            p.id = r.id
            p.createdAt = r.createdAt
            p.typeRaw = r.typeRaw
            p.latitude = r.latitude
            p.longitude = r.longitude
            p.city = r.city
            p.district = r.district
            p.address = r.address
            p.note = r.note
            p.rating = r.rating
            placeMap[r.id] = p
        }

        var girlMap: [UUID: Girl] = [:]
        for r in file.girls {
            let g = Girl(name: r.name)
            context.insert(g)
            g.id = r.id
            g.createdAt = r.createdAt
            g.statusRaw = r.statusRaw
            g.rank = r.rank
            g.city = r.city
            g.latitude = r.latitude
            g.longitude = r.longitude
            g.avatarID = r.avatarID
            g.detailsData = r.detailsData
            girlMap[r.id] = g
        }

        for r in file.encounters {
            let e = Encounter(date: r.date)
            context.insert(e)
            e.id = r.id
            e.durationMinutes = r.durationMinutes
            e.overnight = r.overnight
            e.count = r.count
            e.protectionRaw = r.protectionRaw
            e.condomBroke = r.condomBroke
            e.rating = r.rating
            e.totalCost = r.totalCost
            e.detailsData = r.detailsData
            e.place = r.placeID.flatMap { placeMap[$0] }
            e.girls = r.girlIDs.compactMap { girlMap[$0] }
        }

        for r in file.healthTests {
            let t = HealthTest(date: r.date)
            context.insert(t)
            t.id = r.id
            t.items = r.items
            t.result = r.result
            t.note = r.note
            t.nextDate = r.nextDate
        }

        for r in file.todos ?? [] {
            let t = TodoItem(title: r.title)
            context.insert(t)
            t.id = r.id
            t.createdAt = r.createdAt
            t.notes = r.notes
            t.dueDate = r.dueDate
            t.hasTime = r.hasTime
            t.remind = r.remind
            t.isDone = r.isDone
            t.doneAt = r.doneAt
            t.girlID = r.girlID
            t.category = r.category
        }

        for r in file.wishes ?? [] {
            let w = WishItem(title: r.title)
            context.insert(w)
            w.id = r.id
            w.createdAt = r.createdAt
            w.kind = r.kind
            w.note = r.note
            w.girlID = r.girlID
            w.isDone = r.isDone
            w.doneAt = r.doneAt
        }
    }

    /// 清空全部数据和照片（选项配置保留）
    static func wipeAll(context: ModelContext) throws {
        try deleteRecords(context: context)
        try context.save()
        MediaStore.shared.deleteAll()
    }

    private static func deleteRecords(context: ModelContext) throws {
        for e in try context.fetch(FetchDescriptor<Encounter>()) { context.delete(e) }
        for g in try context.fetch(FetchDescriptor<Girl>()) { context.delete(g) }
        for p in try context.fetch(FetchDescriptor<Place>()) { context.delete(p) }
        for t in try context.fetch(FetchDescriptor<HealthTest>()) { context.delete(t) }
        for t in try context.fetch(FetchDescriptor<TodoItem>()) { context.delete(t) }
        for w in try context.fetch(FetchDescriptor<WishItem>()) { context.delete(w) }
        for receipt in try context.fetch(FetchDescriptor<RestoreReceipt>()) { context.delete(receipt) }
    }

    static var defaultFilename: String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmm"
        return "手账备份-\(f.string(from: Date())).ypbak"
    }
}

/// 恢复前先读出来、等用户确认的备份
struct PendingRestore {
    enum Source {
        /// 2 版：照片视频在文件里，确认后再流式读出
        case archive(URL, password: String)
        /// 1 版：整份已经在内存里
        case legacy
    }

    let file: BackupFile
    let source: Source
}

/// 备份文件读写（不在主线程跑）。
/// 2 版格式：文件头 "YPBK2" + 16 字节 salt，后面是用密码派生的密钥分块加密（见 `ChunkCipher`）的一条字节流，
/// 由若干条记录组成：[1 字节类型][8 字节长度][内容]。
/// 依次是清单（LZFSE 压缩的 JSON）、每个照片视频文件（[2 字节名字长度][名字][原始数据]）、结束标记。
/// 照片视频都是原文件，几个 GB 的视频也是边读边写，不会占满内存。
enum BackupArchive {
    static let magic = Data("YPBK2".utf8)
    private static let legacyMagic = Data("YPBK1".utf8)
    private static let saltSize = 16

    private enum Tag: UInt8 {
        case manifest = 1
        case media = 2
        case end = 0xFF
    }

    // MARK: 写

    /// 写一份备份到临时目录，返回文件位置
    static func write(manifest: BackupFile, mediaIDs: [String], password: String, filename: String,
                      progress: @escaping (Double) -> Void) throws -> URL {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("Backup", isDirectory: true)
        try? fm.removeItem(at: dir)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(filename)

        let salt = try BackupCrypto.randomBytes(saltSize)
        let key = try BackupCrypto.deriveKey(password: password, salt: salt)
        let writer = try ChunkWriter(url: url, key: key, prefix: magic + salt)
        do {
            let json = try JSONEncoder().encode(manifest)
            let compressed = try (json as NSData).compressed(using: .lzfse) as Data
            try writeRecordHeader(.manifest, length: UInt64(compressed.count), to: writer)
            try writer.write(compressed)

            let store = MediaStore.shared
            let total = max(mediaIDs.reduce(Int64(0)) { $0 + store.diskSize($1) }, 1)
            var done: Int64 = 0
            for id in mediaIDs {
                try autoreleasepool {
                    try writeMedia(id, store: store, to: writer) { bytes in
                        done += bytes
                        progress(min(Double(done) / Double(total), 1))
                    }
                }
            }
            try writeRecordHeader(.end, length: 0, to: writer)
            try writer.finish()
            progress(1)
            return url
        } catch {
            writer.abort()
            throw error
        }
    }

    private static func writeMedia(_ id: String, store: MediaStore, to writer: ChunkWriter,
                                   advance: (Int64) -> Void) throws {
        guard MediaStore.isValidID(id), store.exists(id), let info = store.info(id) else { return }
        try writeBlob(name: "\(id)/info", data: try JSONEncoder().encode(info), to: writer)
        if let thumb = store.thumbnailData(id) {
            try writeBlob(name: "\(id)/thumb", data: thumb, to: writer)
        }
        if store.isLegacy(id) {
            guard let data = store.legacyData(id) else { return }
            try writeBlob(name: "\(id)/main", data: data, to: writer)
            advance(Int64(data.count))
            return
        }
        for (part, role) in [(MediaStore.Part.main, "main"), (MediaStore.Part.pair, "pair")] {
            guard let reader = try store.reader(id, part) else { continue }
            try writeMediaHeader(name: "\(id)/\(role)", length: UInt64(reader.plainSize), to: writer)
            try reader.forEachChunk { chunk in
                try writer.write(chunk)
                advance(Int64(chunk.count))
            }
        }
    }

    private static func writeRecordHeader(_ tag: Tag, length: UInt64, to writer: ChunkWriter) throws {
        var header = Data([tag.rawValue])
        header.append(ByteCoding.bytes(length, count: 8))
        try writer.write(header)
    }

    private static func writeMediaHeader(name: String, length: UInt64, to writer: ChunkWriter) throws {
        let nameData = Data(name.utf8)
        try writeRecordHeader(.media, length: 2 + UInt64(nameData.count) + length, to: writer)
        var header = ByteCoding.bytes(UInt64(nameData.count), count: 2)
        header.append(nameData)
        try writer.write(header)
    }

    private static func writeBlob(name: String, data: Data, to writer: ChunkWriter) throws {
        try writeMediaHeader(name: name, length: UInt64(data.count), to: writer)
        try writer.write(data)
    }

    // MARK: 读

    /// 读出备份清单，等用户确认。新旧两种格式都认
    static func readPending(url: URL, password: String) throws -> PendingRestore {
        let head = try readHead(url)
        if head.starts(with: magic) {
            let stream = try openStream(url: url, password: password)
            let file = try readManifest(stream)
            return PendingRestore(file: file, source: .archive(url, password: password))
        }
        guard head.starts(with: legacyMagic) else { throw BackupError.badFormat }
        let data = try Data(contentsOf: url)
        return PendingRestore(file: try readLegacy(data, password: password), source: .legacy)
    }

    /// 把备份里的照片视频放进暂存目录。全部成功后再由 `BackupService.replaceAll` 换上
    static func stageMedia(for pending: PendingRestore, store: MediaStore = .shared,
                           progress: @escaping (Double) -> Void) throws {
        try store.beginStaging()
        do {
            switch pending.source {
            case .legacy:
                let photos = pending.file.photos
                var done = 0
                for (id, data) in photos {
                    guard MediaStore.isValidID(id) else { throw BackupError.badFormat }
                    try autoreleasepool {
                        _ = try store.importPhoto(data: data, id: id, staging: true)
                    }
                    done += 1
                    progress(Double(done) / Double(max(photos.count, 1)))
                }
            case .archive(let url, let password):
                try stageArchive(url: url, password: password, store: store, progress: progress)
            }
        } catch {
            store.discardStaging()
            throw error
        }
    }

    private static func stageArchive(url: URL, password: String, store: MediaStore,
                                     progress: @escaping (Double) -> Void) throws {
        let stream = try openStream(url: url, password: password)
        _ = try readManifest(stream)
        let total = Double(max(stream.totalSize, 1))
        while true {
            guard let tag = try stream.read(1).first else { throw BackupError.badFormat }
            let length = try stream.readInt(8)
            if tag == Tag.end.rawValue { break }
            guard tag == Tag.media.rawValue, length >= 2 else {
                try skip(length, in: stream)
                continue
            }
            let nameLength = try stream.readInt(2)
            guard length >= 2 + nameLength else { throw BackupError.badFormat }
            let name = String(decoding: try stream.read(Int(nameLength)), as: UTF8.self)
            var remaining = length - 2 - nameLength
            let parts = name.split(separator: "/").map(String.init)
            guard parts.count == 2, MediaStore.isValidID(parts[0]) else {
                try skip(remaining, in: stream)
                continue
            }
            let id = parts[0]
            switch parts[1] {
            case "main", "pair":
                let writer = try store.stagingWriter(id, parts[1] == "main" ? .main : .pair)
                do {
                    while remaining > 0 {
                        let piece = try autoreleasepool {
                            try stream.read(Int(min(remaining, UInt64(ChunkCipher.defaultChunkSize))))
                        }
                        try writer.write(piece)
                        remaining -= UInt64(piece.count)
                        progress(min(Double(stream.consumed) / total, 1))
                    }
                    try writer.finish()
                } catch {
                    writer.abort()
                    throw error
                }
            case "info", "thumb":
                guard remaining < 64 << 20 else { throw BackupError.badFormat }
                let data = try stream.read(Int(remaining))
                try store.stageSealed(data, id: id, part: parts[1] == "info" ? .info : .thumb)
            default:
                try skip(remaining, in: stream)
            }
        }
        progress(1)
    }

    private static func readHead(_ url: URL) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        return try handle.read(upToCount: magic.count + saltSize) ?? Data()
    }

    private static func openStream(url: URL, password: String) throws -> ChunkStream {
        let head = try readHead(url)
        guard head.count == magic.count + saltSize, head.starts(with: magic) else { throw BackupError.badFormat }
        let salt = Data(head.suffix(saltSize))
        let key = try BackupCrypto.deriveKey(password: password, salt: salt)
        let reader = try ChunkReader(url: url, key: key, offset: Int64(magic.count + saltSize))
        return ChunkStream(reader)
    }

    private static func readManifest(_ stream: ChunkStream) throws -> BackupFile {
        let tag: Data
        do {
            tag = try stream.read(1)
        } catch {
            // 第一块就解不开：密码不对
            throw BackupError.wrongPassword
        }
        guard tag.first == Tag.manifest.rawValue else { throw BackupError.badFormat }
        let length = try stream.readInt(8)
        guard length < 256 << 20 else { throw BackupError.badFormat }
        let compressed = try stream.read(Int(length))
        guard let json = try? (compressed as NSData).decompressed(using: .lzfse) as Data,
              let file = try? JSONDecoder().decode(BackupFile.self, from: json) else {
            throw BackupError.badFormat
        }
        return file
    }

    private static func skip(_ count: UInt64, in stream: ChunkStream) throws {
        var remaining = count
        while remaining > 0 {
            let piece = try stream.read(Int(min(remaining, UInt64(ChunkCipher.defaultChunkSize))))
            remaining -= UInt64(piece.count)
        }
    }

    /// 1 版备份：整份 JSON（照片在里面）压缩后整体加密
    static func readLegacy(_ data: Data, password: String) throws -> BackupFile {
        let compressed = try BackupCrypto.decrypt(data, password: password)
        guard let json = try? (compressed as NSData).decompressed(using: .lzfse) as Data,
              let file = try? JSONDecoder().decode(BackupFile.self, from: json) else {
            throw BackupError.badFormat
        }
        return file
    }
}

// MARK: - 加密

enum BackupCrypto {
    private static let magic = Data("YPBK1".utf8)
    private static let rounds: UInt32 = 200_000

    static func decrypt(_ data: Data, password: String) throws -> Data {
        guard data.count > magic.count + 16, data.prefix(magic.count) == magic else {
            throw BackupError.badFormat
        }
        let salt = data.subdata(in: magic.count..<(magic.count + 16))
        let body = data.subdata(in: (magic.count + 16)..<data.count)
        let key = try deriveKey(password: password, salt: salt)
        do {
            let box = try AES.GCM.SealedBox(combined: body)
            return try AES.GCM.open(box, using: key)
        } catch {
            throw BackupError.wrongPassword
        }
    }

    static func randomBytes(_ count: Int) throws -> Data {
        var data = Data(count: count)
        let status = data.withUnsafeMutableBytes { ptr in
            SecRandomCopyBytes(kSecRandomDefault, count, ptr.baseAddress!)
        }
        guard status == errSecSuccess else { throw BackupError.crypto }
        return data
    }

    static func deriveKey(password: String, salt: Data) throws -> SymmetricKey {
        let saltBytes = [UInt8](salt)
        var derived = [UInt8](repeating: 0, count: 32)
        let status = CCKeyDerivationPBKDF(
            CCPBKDFAlgorithm(kCCPBKDF2),
            password, password.utf8.count,
            saltBytes, saltBytes.count,
            CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
            rounds,
            &derived, derived.count
        )
        guard status == Int32(kCCSuccess) else { throw BackupError.crypto }
        return SymmetricKey(data: Data(derived))
    }
}
