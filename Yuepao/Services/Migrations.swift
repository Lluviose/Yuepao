import Foundation
import SwiftData

/// 选项改版后的一次性数据整理，每项只跑一次
@MainActor
enum DataMigrations {
    private static let playV2Key = "migration.playOptionsV2"

    static func run(_ context: ModelContext) {
        // 内存数据库（UI 测试、或数据库没打开）里不做，免得把标记记下来却没整理到真数据
        guard !TestSupport.isUITesting, Persistence.loadError == nil else { return }
        migratePlayOptions(context)
    }

    /// 旧版的「玩法 / 道具」是一张表，现在拆成玩法、道具、穿着。
    /// 只在没自定义过玩法选项时整理：旧的默认值换成新名字，制服和丝袜挪到「穿着」
    private static func migratePlayOptions(_ context: ModelContext) {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: playV2Key) else { return }
        defer { defaults.set(true, forKey: playV2Key) }
        guard ConfigStore.shared.config.options[OptionKey.play.rawValue] == nil else { return }

        let renames = ["捆绑": "束缚", "镜子": "镜前", "浴室": "共浴"]
        let toOutfits: Set<String> = ["制服", "丝袜"]
        func renamed(_ list: [String]) -> [String] {
            var seen = Set<String>()
            return list.map { renames[$0] ?? $0 }.filter { seen.insert($0).inserted }
        }

        var changed = false
        let encounters = (try? context.fetch(FetchDescriptor<Encounter>())) ?? []
        for e in encounters {
            let d = e.details
            guard d.play.contains(where: { renames[$0] != nil || toOutfits.contains($0) }) else { continue }
            var updated = d
            let moving = d.play.filter { toOutfits.contains($0) }
            updated.play = renamed(d.play.filter { !toOutfits.contains($0) })
            updated.outfits = d.outfits + moving.filter { !d.outfits.contains($0) }
            e.details = updated
            changed = true
        }
        let girls = (try? context.fetch(FetchDescriptor<Girl>())) ?? []
        for g in girls {
            let liked = g.details.likedPlay
            guard liked.contains(where: { renames[$0] != nil }) else { continue }
            g.update { $0.likedPlay = renamed(liked) }
            changed = true
        }
        if changed { try? context.save() }
    }
}
