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

    var errorDescription: String? {
        switch self {
        case .badFormat: return "不是有效的备份文件"
        case .wrongPassword: return "密码错误，或文件已损坏"
        case .crypto: return "加密失败"
        }
    }
}

// MARK: - 导出 / 导入

@MainActor
enum BackupService {
    static func makeBackup(context: ModelContext, password: String) throws -> Data {
        let girls = try context.fetch(FetchDescriptor<Girl>())
        let places = try context.fetch(FetchDescriptor<Place>())
        let encounters = try context.fetch(FetchDescriptor<Encounter>())
        let tests = try context.fetch(FetchDescriptor<HealthTest>())
        let todos = try context.fetch(FetchDescriptor<TodoItem>())

        var photos: [String: Data] = [:]
        for id in PhotoStore.shared.allIDs() {
            if let data = PhotoStore.shared.rawData(id) { photos[id] = data }
        }

        let file = BackupFile(
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
            photos: photos,
            todos: todos.map {
                TodoRecord(id: $0.id, createdAt: $0.createdAt, title: $0.title, notes: $0.notes, dueDate: $0.dueDate,
                           hasTime: $0.hasTime, remind: $0.remind, isDone: $0.isDone, doneAt: $0.doneAt,
                           girlID: $0.girlID, category: $0.category)
            }
        )

        let json = try JSONEncoder().encode(file)
        let compressed = try (json as NSData).compressed(using: .lzfse) as Data
        return try BackupCrypto.encrypt(compressed, password: password)
    }

    static func readBackup(_ data: Data, password: String) throws -> BackupFile {
        let compressed = try BackupCrypto.decrypt(data, password: password)
        guard let json = try? (compressed as NSData).decompressed(using: .lzfse) as Data,
              let file = try? JSONDecoder().decode(BackupFile.self, from: json) else {
            throw BackupError.badFormat
        }
        return file
    }

    /// 用备份内容覆盖当前全部数据
    static func restore(_ file: BackupFile, context: ModelContext) throws {
        try wipeAll(context: context)

        for (id, data) in file.photos {
            PhotoStore.shared.importRaw(data, id: id)
        }

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

        try context.save()
        ConfigStore.shared.config = file.config
    }

    /// 清空全部数据和照片（选项配置保留）
    static func wipeAll(context: ModelContext) throws {
        for e in try context.fetch(FetchDescriptor<Encounter>()) { context.delete(e) }
        for g in try context.fetch(FetchDescriptor<Girl>()) { context.delete(g) }
        for p in try context.fetch(FetchDescriptor<Place>()) { context.delete(p) }
        for t in try context.fetch(FetchDescriptor<HealthTest>()) { context.delete(t) }
        for t in try context.fetch(FetchDescriptor<TodoItem>()) { context.delete(t) }
        try context.save()
        PhotoStore.shared.deleteAll()
    }

    static var defaultFilename: String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmm"
        return "手账备份-\(f.string(from: Date())).ypbak"
    }
}

// MARK: - 加密

enum BackupCrypto {
    private static let magic = Data("YPBK1".utf8)
    private static let rounds: UInt32 = 200_000

    static func encrypt(_ plain: Data, password: String) throws -> Data {
        var salt = Data(count: 16)
        let status = salt.withUnsafeMutableBytes { ptr in
            SecRandomCopyBytes(kSecRandomDefault, 16, ptr.baseAddress!)
        }
        guard status == errSecSuccess else { throw BackupError.crypto }
        let key = try deriveKey(password: password, salt: salt)
        let sealed = try AES.GCM.seal(plain, using: key)
        guard let combined = sealed.combined else { throw BackupError.crypto }
        return magic + salt + combined
    }

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

    private static func deriveKey(password: String, salt: Data) throws -> SymmetricKey {
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

// MARK: - 文件导出用的 Document

struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.data] }

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
