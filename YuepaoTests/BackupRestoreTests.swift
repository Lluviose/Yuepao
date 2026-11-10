import XCTest
import SwiftData
@testable import Yuepao

final class BackupRestoreTests: XCTestCase {
    private enum InjectedFailure: Error { case move, save }

    private func withMediaStore(_ body: (MediaStore, URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = MediaStore(baseDirectory: root, temporaryDirectory: root.appendingPathComponent("Temporary"))
        try Data("original media".utf8).write(to: store.directory.appendingPathComponent("original.media"))
        try store.beginStaging()
        try Data("restored media".utf8).write(to: store.stagingDirectory.appendingPathComponent("restored.media"))
        try body(store, root)
    }

    @MainActor
    private func makeContainer(at url: URL? = nil) throws -> ModelContainer {
        let configuration: ModelConfiguration
        if let url {
            configuration = ModelConfiguration(schema: Persistence.schema, url: url, cloudKitDatabase: .none)
        } else {
            configuration = ModelConfiguration(schema: Persistence.schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        }
        return try ModelContainer(for: Persistence.schema, configurations: [configuration])
    }

    @MainActor
    private func seed(_ context: ModelContext) throws -> BackupFile {
        let girl = Girl(name: "original profile")
        let place = Place(name: "original place")
        let encounter = Encounter()
        context.insert(girl)
        context.insert(place)
        context.insert(encounter)
        encounter.girls = [girl]
        encounter.place = place
        girl.update { $0.notes = "private notes" }
        try context.save()
        return try BackupService.makeManifest(context: context)
    }

    func testFailedDirectoryInstallRestoresOldMediaAndNeverCommitsDatabase() throws {
        try withMediaStore { store, _ in
            var databaseCommitted = false
            XCTAssertThrowsError(try store.commitStaging(receiptID: UUID(), config: AppConfig(), moveItem: { from, to in
                if from == store.stagingDirectory { throw InjectedFailure.move }
                try FileManager.default.moveItem(at: from, to: to)
            }, commitDatabase: { databaseCommitted = true }))
            XCTAssertFalse(databaseCommitted)
            XCTAssertEqual(try Data(contentsOf: store.directory.appendingPathComponent("original.media")), Data("original media".utf8))
            XCTAssertFalse(FileManager.default.fileExists(atPath: store.directory.appendingPathComponent("restored.media").path))
        }
    }

    @MainActor
    func testFailedDatabaseSaveRollsBackModelsRelationshipsAndMedia() throws {
        try withMediaStore { store, _ in
            let container = try makeContainer()
            let context = container.mainContext
            let original = try seed(context)
            var replacement = original
            replacement.girls[0].name = "replacement profile"
            let oldAutosave = context.autosaveEnabled
            XCTAssertThrowsError(try BackupService.replaceAll(with: replacement, context: context, mediaStore: store,
                                                             saveChanges: { _ in throw InjectedFailure.save }))
            XCTAssertEqual(context.autosaveEnabled, oldAutosave)
            let girls = try context.fetch(FetchDescriptor<Girl>())
            let encounters = try context.fetch(FetchDescriptor<Encounter>())
            XCTAssertEqual(girls.map(\.name), ["original profile"])
            XCTAssertEqual(girls.first?.details.notes, "private notes")
            XCTAssertEqual(encounters.first?.girls.first?.id, girls.first?.id)
            XCTAssertEqual(encounters.first?.place?.name, "original place")
            XCTAssertTrue(try context.fetch(FetchDescriptor<RestoreReceipt>()).isEmpty)
            XCTAssertEqual(try Data(contentsOf: store.directory.appendingPathComponent("original.media")), Data("original media".utf8))
            XCTAssertFalse(FileManager.default.fileExists(atPath: store.directory.appendingPathComponent("restored.media").path))
        }
    }

    @MainActor
    func testSuccessfulRestoreReplacesDataAndRetainsRelationships() throws {
        let oldConfig = ConfigStore.shared.config
        defer { ConfigStore.shared.config = oldConfig }
        try withMediaStore { store, root in
            let container = try makeContainer()
            var replacement = try seed(container.mainContext)
            replacement.girls[0].name = "restored profile"
            try BackupService.replaceAll(with: replacement, context: container.mainContext, mediaStore: store)
            let girls = try container.mainContext.fetch(FetchDescriptor<Girl>())
            let encounters = try container.mainContext.fetch(FetchDescriptor<Encounter>())
            XCTAssertEqual(girls.map(\.name), ["restored profile"])
            XCTAssertEqual(encounters.first?.girls.first?.id, girls.first?.id)
            XCTAssertEqual(girls.first?.encounters.count, 1)
            XCTAssertEqual(encounters.first?.place?.name, "original place")
            XCTAssertEqual(try container.mainContext.fetch(FetchDescriptor<RestoreReceipt>()).count, 1)
            XCTAssertFalse(FileManager.default.fileExists(atPath: store.directory.appendingPathComponent("original.media").path))
            XCTAssertTrue(FileManager.default.fileExists(atPath: store.directory.appendingPathComponent("restored.media").path))
            XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("PhotosRestoreTransaction").path))
        }
    }

    @MainActor
    func testRestartBeforeDatabaseCommitRestoresOriginalMedia() throws {
        try withMediaStore { store, root in
            let database = root.appendingPathComponent("test.store")
            try autoreleasepool {
                let container = try makeContainer(at: database)
                _ = try seed(container.mainContext)
            }
            let journal = MediaRestoreJournal(mediaDirectory: store.directory, stagingDirectory: store.stagingDirectory)
            try journal.prepare(id: UUID(), config: AppConfig())
            try journal.install() // Simulate termination before the database transaction commits.
            let reopened = try makeContainer(at: database)
            let restartedStore = MediaStore(baseDirectory: root, temporaryDirectory: root.appendingPathComponent("Temporary"))
            try restartedStore.recoverRestore(isCommitted: { id in
                try reopened.mainContext.fetch(FetchDescriptor<RestoreReceipt>()).contains { $0.id == id }
            }, applyConfig: { _ in XCTFail("Uncommitted config must not be applied") })
            XCTAssertEqual(try reopened.mainContext.fetch(FetchDescriptor<Girl>()).map(\.name), ["original profile"])
            XCTAssertTrue(FileManager.default.fileExists(atPath: store.directory.appendingPathComponent("original.media").path))
            XCTAssertFalse(FileManager.default.fileExists(atPath: store.directory.appendingPathComponent("restored.media").path))
            XCTAssertFalse(FileManager.default.fileExists(atPath: journal.directory.path))
        }
    }

    @MainActor
    func testAddingRestoreReceiptPreservesExistingStore() throws {
        try withMediaStore { _, root in
            let database = root.appendingPathComponent("upgrade.store")
            try autoreleasepool {
                let oldSchema = Schema([Girl.self, Encounter.self, Place.self, HealthTest.self, TodoItem.self, WishItem.self])
                let configuration = ModelConfiguration(schema: oldSchema, url: database, cloudKitDatabase: .none)
                let oldContainer = try ModelContainer(for: oldSchema, configurations: [configuration])
                _ = try seed(oldContainer.mainContext)
            }
            let upgraded = try makeContainer(at: database)
            let encounters = try upgraded.mainContext.fetch(FetchDescriptor<Encounter>())
            XCTAssertEqual(try upgraded.mainContext.fetch(FetchDescriptor<Girl>()).map(\.name), ["original profile"])
            XCTAssertEqual(encounters.first?.girls.first?.name, "original profile")
            XCTAssertEqual(encounters.first?.place?.name, "original place")
            XCTAssertTrue(try upgraded.mainContext.fetch(FetchDescriptor<RestoreReceipt>()).isEmpty)
        }
    }

    @MainActor
    func testRestartAfterDatabaseCommitKeepsNewMediaAndFinishesConfig() throws {
        try withMediaStore { store, root in
            let database = root.appendingPathComponent("test.store")
            let receiptID = UUID()
            var config = AppConfig()
            config.options["ranks"] = ["restored option"]
            let journal = MediaRestoreJournal(mediaDirectory: store.directory, stagingDirectory: store.stagingDirectory)
            try journal.prepare(id: receiptID, config: config)
            try journal.install()
            try autoreleasepool {
                let container = try makeContainer(at: database)
                container.mainContext.insert(Girl(name: "restored profile"))
                container.mainContext.insert(RestoreReceipt(id: receiptID))
                try container.mainContext.save() // Simulate termination before config/journal cleanup.
            }
            let reopened = try makeContainer(at: database)
            var recoveredConfig: AppConfig?
            let restartedStore = MediaStore(baseDirectory: root, temporaryDirectory: root.appendingPathComponent("Temporary"))
            try restartedStore.recoverRestore(isCommitted: { id in
                try reopened.mainContext.fetch(FetchDescriptor<RestoreReceipt>()).contains { $0.id == id }
            }, applyConfig: { recoveredConfig = $0 })
            XCTAssertEqual(try reopened.mainContext.fetch(FetchDescriptor<Girl>()).map(\.name), ["restored profile"])
            XCTAssertEqual(recoveredConfig?.options["ranks"], ["restored option"])
            XCTAssertTrue(FileManager.default.fileExists(atPath: store.directory.appendingPathComponent("restored.media").path))
            XCTAssertFalse(FileManager.default.fileExists(atPath: store.directory.appendingPathComponent("original.media").path))
            XCTAssertFalse(FileManager.default.fileExists(atPath: journal.directory.path))
        }
    }

    func testLegacyPhotoImportErrorIsPropagatedAndStagingIsDiscarded() throws {
        try withMediaStore { store, _ in
            let manifest = BackupFile(config: AppConfig(), girls: [], places: [], encounters: [], healthTests: [],
                                      photos: ["legacy-photo": Data("not a photo".utf8)])
            let pending = PendingRestore(file: manifest, source: .legacy)
            XCTAssertThrowsError(try BackupArchive.stageMedia(for: pending, store: store, progress: { _ in }))
            XCTAssertFalse(FileManager.default.fileExists(atPath: store.stagingDirectory.path))
            XCTAssertEqual(try Data(contentsOf: store.directory.appendingPathComponent("original.media")), Data("original media".utf8))
        }
    }

    func testMissingStagingDirectoryDoesNotReplaceOldMedia() throws {
        try withMediaStore { store, _ in
            store.discardStaging()
            XCTAssertThrowsError(try store.commitStaging(receiptID: UUID(), config: AppConfig(), commitDatabase: {
                XCTFail("A missing stage must not commit an empty media collection")
            }))
            XCTAssertTrue(FileManager.default.fileExists(atPath: store.directory.appendingPathComponent("original.media").path))
        }
    }
}
