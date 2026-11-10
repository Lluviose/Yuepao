import Foundation
import SwiftData

enum Persistence {
    static let schema = Schema([Girl.self, Encounter.self, Place.self, HealthTest.self, TodoItem.self, WishItem.self, RestoreReceipt.self])

    /// 打开数据库或恢复失败时的错误；根视图会阻止编辑，内存容器只供错误页面初始化。
    private(set) static var loadError: String?

    @MainActor
    static func reportUnavailable(_ message: String) {
        loadError = message
        NotificationCenter.default.post(name: Notification.Name("persistenceUnavailable"), object: nil)
    }

    static var storeDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Store", isDirectory: true)
    }

    @MainActor
    static func makeContainer() -> ModelContainer {
        if TestSupport.isUITesting {
            let memory = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
            // swiftlint:disable:next force_try
            return try! ModelContainer(for: schema, configurations: [memory])
        }
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
            // 在任何页面读取媒体前，先完成上次被系统中断的恢复。
            try MediaStore.shared.recoverRestore(isCommitted: { id in
                let descriptor = FetchDescriptor<RestoreReceipt>(predicate: #Predicate { $0.id == id })
                return !(try container.mainContext.fetch(descriptor)).isEmpty
            }, applyConfig: { ConfigStore.shared.config = $0 })
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
