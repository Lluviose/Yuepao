import Foundation
import SwiftData

/// 与恢复的数据在同一次数据库事务中保存，用来判断中断的恢复是否已经提交。
@Model
final class RestoreReceipt {
    var id: UUID

    init(id: UUID) {
        self.id = id
    }
}
