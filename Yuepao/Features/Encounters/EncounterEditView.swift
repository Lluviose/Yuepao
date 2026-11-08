import SwiftUI
import SwiftData

struct EncounterEditView: View {
    let encounter: Encounter?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @ObservedObject private var config = ConfigStore.shared

    @State private var date: Date
    @State private var durationMinutes: Int
    @State private var overnight: Bool
    @State private var count: Int
    @State private var protection: Protection
    @State private var condomBroke: Bool
    @State private var rating: Int
    @State private var details: EncounterDetails
    @State private var girls: [Girl]
    @State private var place: Place?
    @State private var riskAlert = false
    @State private var showMore: Bool

    private let originalPhotos: Set<String>

    init(encounter: Encounter?, presetGirls: [Girl]) {
        self.encounter = encounter
        _date = State(initialValue: encounter?.date ?? Date())
        _durationMinutes = State(initialValue: encounter?.durationMinutes ?? 0)
        _overnight = State(initialValue: encounter?.overnight ?? false)
        _count = State(initialValue: encounter?.count ?? 1)
        _protection = State(initialValue: encounter?.protection ?? .unrecorded)
        _condomBroke = State(initialValue: encounter?.condomBroke ?? false)
        _rating = State(initialValue: encounter?.rating ?? 0)
        let d = encounter?.details ?? EncounterDetails()
        _details = State(initialValue: d)
        _girls = State(initialValue: encounter?.girls ?? presetGirls)
        _place = State(initialValue: encounter?.place)
        _showMore = State(initialValue: encounter != nil)
        originalPhotos = Set(d.photoIDs)
    }

    private var isRisky: Bool {
        switch protection {
        case .none, .withdrawal, .pill: return true
        case .condom, .both: return condomBroke
        case .unrecorded: return false
        }
    }

    private var pregnancyRisk: Bool {
        switch protection {
        case .none, .withdrawal: return true
        case .condom: return condomBroke
        default: return false
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                whoSection
                whenSection
                processSection
                safetySection
                if showMore {
                    detailSection
                    costSection
                    feelingSection
                    noteSection
                } else {
                    Section {
                        Button {
                            withAnimation { showMore = true }
                        } label: {
                            Label("填写更多（玩法、花费、评价、照片…）", systemImage: "chevron.down")
                        }
                    }
                }
            }
            .navigationTitle(encounter == nil ? "记一次" : "编辑记录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { cancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                }
            }
            .alert("这次有风险", isPresented: $riskAlert) {
                Button("知道了") { dismiss() }
            } message: {
                Text(riskMessage)
            }
        }
        .interactiveDismissDisabled()
    }

    private var riskMessage: String {
        var lines: [String] = []
        if pregnancyRisk && !details.pillTaken {
            lines.append("紧急避孕药 72 小时内有效，越早吃越好。")
        }
        lines.append("建议 2 周后做一次性病检测，6 周后做 HIV / 梅毒检测。")
        if Reminders.enabled && Reminders.riskEnabled {
            lines.append("已设置检测提醒。")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: Sections

    private var whoSection: some View {
        Section("对象和地点") {
            NavigationLink {
                GirlMultiSelectView(selection: $girls)
            } label: {
                LabeledContent("对象") {
                    Text(girls.isEmpty ? "未选择" : girls.map(\.name).joined(separator: "、"))
                        .foregroundStyle(girls.isEmpty ? HierarchicalShapeStyle.tertiary : HierarchicalShapeStyle.secondary)
                        .lineLimit(1)
                }
            }
            NavigationLink {
                PlaceSelectView(selection: $place)
            } label: {
                LabeledContent("地点") {
                    Text(place?.displayName ?? "未选择")
                        .foregroundStyle(place == nil ? HierarchicalShapeStyle.tertiary : HierarchicalShapeStyle.secondary)
                        .lineLimit(1)
                }
            }
        }
    }

    private var whenSection: some View {
        Section("时间") {
            DatePicker("开始时间", selection: $date)
            Picker("时长", selection: $durationMinutes) {
                ForEach(Choices.durations, id: \.self) { m in
                    Text(Choices.durationTitle(m)).tag(m)
                }
            }
            Toggle("过夜", isOn: $overnight)
        }
    }

    private var processSection: some View {
        Section("过程") {
            Stepper(value: $count, in: 0...20) {
                LabeledContent("回合数", value: "\(count)")
            }
            Picker("她高潮", selection: $details.herOrgasms) {
                Text("未记录").tag(-1)
                ForEach(Array(0...6), id: \.self) { n in
                    Text(n == 6 ? "6 次以上" : "\(n) 次").tag(n)
                }
            }
        }
    }

    private var safetySection: some View {
        Section {
            Picker("安全措施", selection: $protection) {
                ForEach(Protection.allCases) { p in
                    Text(p.title).tag(p)
                }
            }
            if protection == .condom || protection == .both {
                Toggle("破套 / 中途摘了", isOn: $condomBroke)
            }
            if pregnancyRisk {
                Toggle("已吃紧急避孕药", isOn: $details.pillTaken)
            }
        } header: {
            Text("安全")
        } footer: {
            if isRisky {
                Text("有风险：保存后会提醒你按时间做检测。")
                    .foregroundStyle(.orange)
            }
        }
    }

    private var detailSection: some View {
        Section("内容") {
            OptionMultiPicker(title: "约会内容", key: .activities, selection: $details.activities)
            Picker("谁主动约的", selection: $details.initiator) {
                ForEach(Choices.initiators, id: \.self) { i in
                    Text(i.isEmpty ? "未记录" : i).tag(i)
                }
            }
            OptionMultiPicker(title: "体位", key: .positions, selection: $details.positions)
            OptionMultiPicker(title: "玩法 / 道具", key: .play, selection: $details.play)
        }
    }

    private var costSection: some View {
        Section {
            ForEach($details.expenses) { $item in
                HStack {
                    Menu {
                        ForEach(config.options(.expenseCategories), id: \.self) { c in
                            Button(c) { item.category = c }
                        }
                    } label: {
                        Text(item.category).frame(minWidth: 48, alignment: .leading)
                    }
                    TextField("说明", text: $item.note)
                    DecimalField(title: "¥", value: $item.amount)
                        .frame(width: 90)
                }
            }
            .onDelete { details.expenses.remove(atOffsets: $0) }
            Button {
                details.expenses.append(ExpenseItem(category: config.options(.expenseCategories).first ?? "酒店"))
            } label: {
                Label("添加一笔", systemImage: "plus")
            }
        } header: {
            HStack {
                Text("花费")
                Spacer()
                if details.totalCost > 0 { Text("合计 \(Fmt.money(details.totalCost))") }
            }
        }
    }

    private var feelingSection: some View {
        Section("评价") {
            LabeledContent("满意度") { StarRating(value: $rating) }
            LabeledContent("化学反应") { StarRating(value: $details.chemistry) }
            OptionMultiPicker(title: "心情 / 氛围", key: .moods, selection: $details.moods)
        }
    }

    private var noteSection: some View {
        Group {
            Section("备注") {
                TextField("细节、对话、下次想试的…", text: $details.notes, axis: .vertical)
                    .lineLimit(3...12)
            }
            Section("照片") {
                PhotoGrid(photoIDs: $details.photoIDs)
            }
        }
    }

    // MARK: Actions

    private func cancel() {
        let added = Set(details.photoIDs).subtracting(originalPhotos)
        PhotoStore.shared.delete(Array(added))
        dismiss()
    }

    private func save() {
        let target: Encounter
        if let encounter {
            target = encounter
        } else {
            target = Encounter()
            context.insert(target)
        }
        target.date = date
        target.durationMinutes = durationMinutes
        target.overnight = overnight
        target.count = count
        target.protection = protection
        target.condomBroke = (protection == .condom || protection == .both) ? condomBroke : false
        target.rating = rating
        target.totalCost = details.totalCost
        var d = details
        d.expenses = d.expenses.filter { $0.amount != 0 || !$0.note.trimmed.isEmpty }
        target.details = d
        target.place = place
        target.girls = girls

        // 第一次发生关系：把"暧昧中"自动改成"在约"
        for girl in girls where girl.status == .flirting {
            girl.status = .active
            girl.update { $0.statusHistory.append(StatusChange(date: Date(), status: RelationStatus.active.rawValue)) }
        }

        let removed = originalPhotos.subtracting(d.photoIDs)
        PhotoStore.shared.delete(Array(removed))

        try? context.save()

        if target.stiRisk || target.pregnancyRisk {
            Reminders.scheduleRiskFollowUps(encounterID: target.id, date: target.date)
            // 只在新记录、且是最近 3 天内的事时弹提示
            if encounter == nil, Date().timeIntervalSince(date) < 72 * 3600 {
                riskAlert = true
                return
            }
        } else {
            Reminders.cancelRisk(encounterID: target.id)
        }
        dismiss()
    }
}

// MARK: - 选择对象

struct GirlMultiSelectView: View {
    @Binding var selection: [Girl]

    @Query(sort: \Girl.createdAt, order: .reverse) private var girls: [Girl]
    @State private var search = ""
    @State private var creating = false

    private var sorted: [Girl] {
        let q = search.trimmed
        let list = q.isEmpty ? girls : girls.filter { $0.name.contains(q) || $0.city.contains(q) }
        return list.sorted { a, b in
            if a.status.isCurrent != b.status.isCurrent { return a.status.isCurrent }
            return (a.lastInteraction() ?? a.createdAt) > (b.lastInteraction() ?? b.createdAt)
        }
    }

    var body: some View {
        List {
            Section {
                Button {
                    creating = true
                } label: {
                    Label("新建档案", systemImage: "person.crop.circle.badge.plus")
                }
            }
            Section {
                ForEach(sorted) { girl in
                    Button {
                        toggle(girl)
                    } label: {
                        HStack(spacing: 12) {
                            AvatarView(photoID: girl.avatarID, name: girl.name, size: 36, ring: girl.status.color)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(girl.name).foregroundStyle(.primary)
                                Text([girl.rank, girl.status.title].filter { !$0.isEmpty }.joined(separator: " · "))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if selection.contains(where: { $0.id == girl.id }) {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint)
                            } else {
                                Image(systemName: "circle").foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
            } footer: {
                Text("可多选")
            }
        }
        .searchable(text: $search, prompt: "搜索")
        .navigationTitle("选择对象")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $creating) {
            GirlEditView(girl: nil)
        }
    }

    private func toggle(_ girl: Girl) {
        if let i = selection.firstIndex(where: { $0.id == girl.id }) {
            selection.remove(at: i)
        } else {
            selection.append(girl)
        }
    }
}
