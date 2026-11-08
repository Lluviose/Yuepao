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
                                Badge(text: t.result, color: t.result == "阴性" ? .green : (t.result == "阳性" ? .red : .orange))
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

struct HealthTestEditView: View {
    let test: HealthTest?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @State private var date: Date
    @State private var items: String
    @State private var result: String
    @State private var note: String
    @State private var nextDate: Date?

    init(test: HealthTest?) {
        self.test = test
        _date = State(initialValue: test?.date ?? Date())
        _items = State(initialValue: test?.items ?? "HIV、梅毒、淋病、衣原体")
        _result = State(initialValue: test?.result ?? "")
        _note = State(initialValue: test?.note ?? "")
        _nextDate = State(initialValue: test?.nextDate)
    }

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("检测日期", selection: $date, displayedComponents: .date)
                TextField("检测项目", text: $items, axis: .vertical)
                Picker("结果", selection: $result) {
                    Text("未填").tag("")
                    ForEach(Choices.testResults, id: \.self) { r in
                        Text(r).tag(r)
                    }
                }
                OptionalDateRow(title: "下次检测", date: $nextDate)
                TextField("备注（医院、费用…）", text: $note, axis: .vertical)
            }
            .navigationTitle(test == nil ? "新建检测" : "编辑检测")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("保存") { save() } }
            }
        }
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
        target.items = items.trimmed
        target.result = result
        target.note = note
        target.nextDate = nextDate
        try? context.save()
        dismiss()
    }
}
