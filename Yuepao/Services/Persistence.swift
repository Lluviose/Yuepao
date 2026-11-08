import Foundation
import SwiftData

enum Persistence {
    static let schema = Schema([Girl.self, Encounter.self, Place.self, HealthTest.self])

    /// 打开数据库失败时的错误描述（这时会退回内存数据库，避免崩溃丢数据）
    private(set) static var loadError: String?

    static var storeDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Store", isDirectory: true)
    }

    static func makeContainer() -> ModelContainer {
        let dir = storeDirectory
        try? FileManager.default.createDirectory(
            at: dir,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUnlessOpen]
        )
        let url = dir.appendingPathComponent("yuepao.store")
        let configuration = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        do {
            let container = try ModelContainer(for: schema, configurations: [configuration])
            protectFiles(in: dir)
            return container
        } catch {
            loadError = error.localizedDescription
            let memory = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
            // swiftlint:disable:next force_try
            return try! ModelContainer(for: schema, configurations: [memory])
        }
    }

    /// 数据库文件在锁屏后不可读（已打开的文件除外）
    static func protectFiles(in dir: URL) {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return }
        for file in files {
            try? fm.setAttributes([.protectionKey: FileProtectionType.completeUnlessOpen], ofItemAtPath: file.path)
        }
    }
}
