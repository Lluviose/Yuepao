import SwiftUI
import SwiftData

struct HealthTestListView: View {
    @Query(sort: \HealthTest.date, order: .reverse) private var tests: [HealthTest]
    @Environment(\.modelContext) private var context
    @State private var editing: HealthTest?
    @State private var creating = false

    var body: some View {
        List {
            ForEach(tests) { t in
                Button {
                    editing = t
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(Fmt.date(t.date)).foregroundStyle(.primary)
                            Spacer()
                            if !t.result.isEmpty {
                                Badge(text: t.result, color: t.result == "阴性" ? Palette.status : (t.result == "阳性" ? Palette.period : Palette.fertile))
                            }
                        }
                        if !t.items.isEmpty {
                            Text(t.items).font(.caption).foregroundStyle(.secondary)
                        }
                        if let next = t.nextDate {
                            Text("下次：\(Fmt.date(next))").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .onDelete { idx in
                idx.map { tests[$0] }.forEach { context.delete($0) }
                try? context.save()
            }
        }
        .overlay {
            if tests.isEmpty {
                ContentUnavailableView("还没有检测记录", systemImage: "cross.case",
                                       description: Text("定期检测，对自己和别人都负责"))
            }
        }
        .navigationTitle("检测记录")
        .toolbar {
            Button {
                creating = true
            } label: {
                Image(systemName: "plus")
            }
        }
        .sheet(isPresented: $creating) {
            HealthTestEditView(test: nil)
        }
        .sheet(item: $editing) { t in
            HealthTestEditView(test: t)
        }
    }
}

/// 新建 / 编辑一次检测：常见项目点选，结果、下次检测都是一点即选
struct HealthTestEditView: View {
    let test: HealthTest?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @State private var date: Date
    @State private var picked: [String]
    @State private var result: String
    @State private var note: String
    @State private var nextDate: Date?

    static let commonItems = ["HIV", "梅毒", "淋病", "衣原体", "支原体", "HPV", "乙肝", "丙肝", "疱疹"]

    init(test: HealthTest?) {
        self.test = test
        _date = State(initialValue: test?.date ?? Date())
        _picked = State(initialValue: Self.split(test?.items ?? "HIV、梅毒、淋病、衣原体"))
        _result = State(initialValue: test?.result ?? "")
        _note = State(initialValue: test?.note ?? "")
        _nextDate = State(initialValue: test?.nextDate)
    }

    /// 旧数据是手填的一串，按常见分隔符拆开
    static func split(_ raw: String) -> [String] {
        raw.components(separatedBy: CharacterSet(charactersIn: "、,，/;；")).map(\.trimmed).filter { !$0.isEmpty }
    }

    private var allItems: [String] {
        Self.commonItems + picked.filter { !Self.commonItems.contains($0) }
    }

    private func monthsLater(_ months: Int) -> Date {
        Calendar.current.date(byAdding: .month, value: months, to: Calendar.current.startOfDay(for: date)) ?? date
    }

    var body: some View {
        ComposerShell(title: test == nil ? "新建检测" : "编辑检测",
                      onCancel: { dismiss() },
                      onSave: { save() }) {
            HStack {
                ComposerLabel("检测日期")
                DatePicker("检测日期", selection: $date, displayedComponents: .date)
                    .labelsHidden()
            }

            VStack(alignment: .leading, spacing: 10) {
                ComposerLabel("检测项目")
                FlowLayout(spacing: 8) {
                    ForEach(allItems, id: \.self) { item in
                        TagChip(title: item, selected: picked.contains(item)) {
                            withAnimation(.snappy(duration: 0.2)) {
                                if let i = picked.firstIndex(of: item) {
                                    picked.remove(at: i)
                                } else {
                                    picked.append(item)
                                }
                            }
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                ComposerLabel("结果")
                HStack(spacing: 8) {
                    ForEach(Choices.testResults, id: \.self) { r in
                        ChoiceChip(title: r, selected: result == r) {
                            result = result == r ? "" : r
                        }
                    }
                }
                if result == "阳性" {
                    Label("按医生的建议治疗；治好之前做好防护，也记得告诉最近的伴侣。", systemImage: "cross.case")
                        .font(.footnote)
                        .foregroundStyle(Palette.period)
                        .transition(.opacity)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                ComposerLabel("下次检测")
                ChipRow {
                    ChoiceChip(title: "不设", selected: nextDate == nil) { nextDate = nil }
                    ForEach([1, 3, 6], id: \.self) { months in
                        let target = monthsLater(months)
                        ChoiceChip(title: "\(months) 个月后",
                                   selected: nextDate.map { Calendar.current.isDate($0, inSameDayAs: target) } ?? false) {
                            nextDate = target
                        }
                    }
                }
                if nextDate != nil {
                    DatePicker("下次检测", selection: Binding(get: { nextDate ?? Date() }, set: { nextDate = $0 }),
                               displayedComponents: .date)
                        .transition(.opacity)
                }
            }

            TextField("备注（医院、费用…）", text: $note, axis: .vertical)
                .lineLimit(2...6)
                .composerField()
        }
        .composerSheet(detents: [.large])
    }

    private func save() {
        let target: HealthTest
        if let test {
            target = test
        } else {
            target = HealthTest()
            context.insert(target)
        }
        target.date = date
        target.items = picked.joined(separator: "、")
        target.result = result
        target.note = note
        target.nextDate = nextDate
        try? context.save()
        AchievementCenter.shared.refresh(context: context)
        dismiss()
    }
}
