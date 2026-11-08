import SwiftUI
import SwiftData

struct GirlDetailView: View {
    let girl: Girl

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Girl.createdAt) private var allGirls: [Girl]
    @ObservedObject private var config = ConfigStore.shared

    @State private var sheet: DetailSheet?
    @State private var showSensitive = false
    @State private var confirmDelete = false

    enum DetailSheet: String, Identifiable {
        case edit, encounter, memo, said, gift, date, period
        var id: String { rawValue }
    }

    var body: some View {
        let d = girl.details
        List {
            Group {
                header(d)
                overview(d)
                alerts(d)
                basicInfo(d)
                bodyInfo(d)
                socialInfo(d)
                metInfo(d)
            }
            Group {
                haremInfo(d)
                saidSection(d)
                preferenceInfo(d)
                intimacyInfo(d)
                periodSection(d)
                datesSection(d)
            }
            Group {
                giftSection(d)
                memoSection(d)
                encounterSection
                photoSection
                customInfo(d)
                if !d.notes.isEmpty {
                    Section("备注") { Text(d.notes).textSelection(.enabled) }
                }
            }
        }
        .navigationTitle(girl.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button { sheet = .edit } label: { Label("编辑档案", systemImage: "pencil") }
                    Button { sheet = .encounter } label: { Label("记一次", systemImage: "plus.circle") }
                    Divider()
                    Button(role: .destructive) { confirmDelete = true } label: { Label("删除档案", systemImage: "trash") }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(item: $sheet) { which in
            sheetContent(which)
        }
        .confirmationDialog("删除「\(girl.name)」的档案？", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("删除档案，保留约会记录", role: .destructive) { delete(alsoEncounters: false) }
            Button("删除档案和只和她有关的记录", role: .destructive) { delete(alsoEncounters: true) }
        }
    }

    @ViewBuilder
    private func sheetContent(_ which: DetailSheet) -> some View {
        switch which {
        case .edit:
            GirlEditView(girl: girl)
        case .encounter:
            EncounterEditView(encounter: nil, presetGirls: [girl])
        case .memo:
            NoteSheet(title: "加一条备忘") { note in
                girl.update { $0.memos.append(note); $0.memos.sort { $0.date > $1.date } }
            }
        case .said:
            NoteSheet(title: "她说过的事") { note in
                girl.update { $0.saidNotes.append(note); $0.saidNotes.sort { $0.date > $1.date } }
            }
        case .gift:
            GiftSheet { gift in
                girl.update { $0.gifts.append(gift); $0.gifts.sort { $0.date > $1.date } }
            }
        case .date:
            ImportantDateSheet { item in
                girl.update { $0.importantDates.append(item) }
                Reminders.rescheduleDates(girls: allGirls)
            }
        case .period:
            PeriodSheet { date in
                girl.update { $0.periodStarts.append(date); $0.periodStarts.sort(by: >) }
            }
        }
    }

    private func delete(alsoEncounters: Bool) {
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            GirlActions.delete(girl, alsoEncounters: alsoEncounters, context: context)
        }
    }

    // MARK: - Header

    private func header(_ d: GirlDetails) -> some View {
        Section {
            VStack(spacing: 10) {
                AvatarView(photoID: girl.avatarID, name: girl.name, size: 92, ring: girl.status.color)
                HStack(spacing: 6) {
                    if !girl.rank.isEmpty { Badge(text: girl.rank) }
                    Badge(text: girl.status.title, color: girl.status.color)
                }
                let line = headerLine(d)
                if !line.isEmpty {
                    Text(line).font(.subheadline).foregroundStyle(.secondary)
                }
                if !d.personality.isEmpty || !d.tags.isEmpty {
                    ChipsView(items: d.personality + d.tags)
                }
                HStack(spacing: 10) {
                    actionButton("记一次", "plus.circle.fill") { sheet = .encounter }
                    actionButton("刚联系过", "message.fill") {
                        girl.update { $0.lastContactDate = Date() }
                    }
                    actionButton("编辑", "pencil.circle.fill") { sheet = .edit }
                }
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
    }

    private func headerLine(_ d: GirlDetails) -> String {
        var parts: [String] = []
        if let age = Fmt.age(d.birthday) { parts.append("\(age)岁") }
        if let z = Fmt.zodiac(d.birthday) { parts.append(z) }
        if !d.mbti.isEmpty { parts.append(d.mbti) }
        if !girl.city.isEmpty { parts.append(girl.city) }
        return parts.joined(separator: " · ")
    }

    private func actionButton(_ title: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: symbol).font(.title3)
                Text(title).font(.caption)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.borderless)
    }

    private func overview(_ d: GirlDetails) -> some View {
        let known = d.metDate ?? girl.createdAt
        let spending = girl.encounterSpending + d.giftSpending
        return Section("概况") {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                StatCell(value: "\(girl.encounters.count)", label: "约会次数")
                StatCell(value: "\(girl.totalRounds)", label: "总回合")
                StatCell(value: Fmt.daysAgo(girl.lastEncounterDate), label: "上次见面")
                StatCell(value: "\(max(Fmt.days(from: known), 0))", label: "认识天数")
                StatCell(value: Fmt.money(spending), label: "总投入")
                StatCell(value: "\(d.intimacy)", label: "亲密度")
            }
            .padding(.vertical, 4)
            if let first = girl.firstEncounterDate {
                InfoRow(label: "第一次", value: Fmt.date(first))
            }
            if let contact = d.lastContactDate {
                InfoRow(label: "上次联系", value: Fmt.daysAgo(contact))
            }
        }
    }

    @ViewBuilder
    private func alerts(_ d: GirlDetails) -> some View {
        let items = alertItems(d)
        if !items.isEmpty {
            Section {
                ForEach(items, id: \.self) { text in
                    Label(text, systemImage: "bell.badge").foregroundStyle(.orange)
                }
            }
        }
    }

    private func alertItems(_ d: GirlDetails) -> [String] {
        var items: [String] = []
        if let bd = d.birthday {
            let n = Reminders.daysUntilNext(bd)
            if n <= 30 { items.append(n == 0 ? "今天是她生日！" : "\(n) 天后是她生日") }
        }
        for item in d.importantDates {
            let n = Reminders.daysUntilNext(item.date)
            if n <= 14 { items.append(n == 0 ? "今天是\(item.title)" : "\(n) 天后是\(item.title)") }
        }
        if d.possiblyOnPeriod {
            items.append("她可能正在经期")
        } else if let next = d.nextPeriod {
            let n = Fmt.days(from: Date(), to: next)
            if (0...5).contains(n) { items.append(n == 0 ? "预计今天来例假" : "预计 \(n) 天后来例假") }
        }
        if d.contactGoalDays > 0, girl.status.isCurrent {
            let last = girl.lastInteraction(details: d) ?? girl.createdAt
            let n = Fmt.days(from: last)
            if n > d.contactGoalDays { items.append("已经 \(n) 天没联系了（目标 \(d.contactGoalDays) 天）") }
        }
        return items
    }

    // MARK: - Info sections

    @ViewBuilder
    private func basicInfo(_ d: GirlDetails) -> some View {
        if !d.realName.isEmpty || d.birthday != nil {
            Section {
                if !d.realName.isEmpty {
                    LabeledContent("真名") {
                        Text(showSensitive ? d.realName : "••••")
                            .textSelection(.enabled)
                    }
                }
                if let bd = d.birthday {
                    InfoRow(label: "生日", value: Fmt.date(bd))
                }
            } header: {
                sensitiveHeader("基本信息")
            }
        }
    }

    private func sensitiveHeader(_ title: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Button {
                showSensitive.toggle()
            } label: {
                Image(systemName: showSensitive ? "eye.slash" : "eye")
            }
            .buttonStyle(.borderless)
            .textCase(nil)
        }
    }

    @ViewBuilder
    private func bodyInfo(_ d: GirlDetails) -> some View {
        if d.hasBodyInfo {
            Section("身材外貌") {
                if let h = d.height { InfoRow(label: "身高", value: "\(h) cm") }
                if let w = d.weight { InfoRow(label: "体重", value: "\(w) kg") }
                if !d.cup.isEmpty { InfoRow(label: "罩杯", value: d.cup) }
                if d.bust != nil || d.waist != nil || d.hips != nil {
                    InfoRow(label: "三围", value: [d.bust, d.waist, d.hips].map { $0.map { String($0) } ?? "?" }.joined(separator: " / "))
                }
                if !d.bodyType.isEmpty { InfoRow(label: "体型", value: d.bodyType) }
                if !d.appearance.isEmpty { TextBlock(label: "外貌特征", text: d.appearance) }
            }
        }
    }

    @ViewBuilder
    private func socialInfo(_ d: GirlDetails) -> some View {
        if d.hasSocialInfo {
            Section {
                if !d.occupation.isEmpty { InfoRow(label: "职业", value: d.occupation) }
                if !d.education.isEmpty || !d.school.isEmpty {
                    InfoRow(label: "学历", value: [d.education, d.school].filter { !$0.isEmpty }.joined(separator: " · "))
                }
                if !d.hometown.isEmpty { InfoRow(label: "籍贯", value: d.hometown) }
                if !d.maritalStatus.isEmpty { InfoRow(label: "感情状况", value: d.maritalStatus) }
                if !d.district.isEmpty { InfoRow(label: "常驻区域", value: [girl.city, d.district].filter { !$0.isEmpty }.joined(separator: " ")) }
                ForEach(d.contacts) { c in
                    LabeledContent(c.type) {
                        Text(showSensitive ? c.value : "••••").textSelection(.enabled)
                    }
                }
            } header: {
                sensitiveHeader("社会信息")
            }
        }
    }

    @ViewBuilder
    private func metInfo(_ d: GirlDetails) -> some View {
        if d.hasMetInfo {
            Section("认识经过") {
                if !d.channel.isEmpty { InfoRow(label: "渠道", value: d.channel) }
                if let m = d.metDate { InfoRow(label: "认识日期", value: Fmt.date(m)) }
                if let f = d.firstDateDate { InfoRow(label: "首次见面", value: Fmt.date(f)) }
                if !d.introducer.isEmpty { InfoRow(label: "介绍人", value: d.introducer) }
                if !d.howWeMet.isEmpty { TextBlock(label: "经过", text: d.howWeMet) }
            }
        }
    }

    private func haremInfo(_ d: GirlDetails) -> some View {
        Section("后宫属性") {
            VStack(alignment: .leading, spacing: 6) {
                LabeledContent("亲密度", value: "\(d.intimacy) / 100")
                ProgressView(value: Double(d.intimacy), total: 100).tint(girl.status.color)
            }
            ForEach(scoreEntries(d)) { item in
                InfoRow(label: item.label, value: "\(item.value) 分")
            }
            if d.awarenessLevel != .unset {
                InfoRow(label: "她知道你有别人吗", value: d.awarenessLevel.title)
            }
            if d.contactGoalDays > 0 {
                InfoRow(label: "联系频率目标", value: "\(d.contactGoalDays) 天一次")
            }
            ForEach(d.connections) { conn in
                if let other = allGirls.first(where: { $0.id == conn.girlID }) {
                    NavigationLink {
                        GirlDetailView(girl: other)
                    } label: {
                        LabeledContent("认识 \(other.name)", value: conn.relation)
                    }
                }
            }
            if !d.statusHistory.isEmpty {
                NavigationLink {
                    StatusHistoryView(history: d.statusHistory)
                } label: {
                    LabeledContent("状态变化", value: "\(d.statusHistory.count) 条")
                }
            }
        }
    }

    private func scoreEntries(_ d: GirlDetails) -> [ScoreEntry] {
        [
            ScoreEntry(label: "颜值", value: d.ratingLooks),
            ScoreEntry(label: "身材", value: d.ratingBody),
            ScoreEntry(label: "性格", value: d.ratingPersonality),
            ScoreEntry(label: "床上表现", value: d.ratingSex),
            ScoreEntry(label: "综合", value: d.ratingOverall)
        ].filter { $0.value > 0 }
    }

    private func saidSection(_ d: GirlDetails) -> some View {
        Section {
            ForEach(d.saidNotes) { note in
                NoteRow(note: note)
            }
            .onDelete { idx in girl.update { $0.saidNotes.remove(atOffsets: idx) } }
            Button { sheet = .said } label: { Label("记一条", systemImage: "plus") }
        } header: {
            Text("她说过的事")
        } footer: {
            if d.saidNotes.isEmpty { Text("她提到的家人、经历、计划…记下来防止人多记混。") }
        }
    }

    @ViewBuilder
    private func preferenceInfo(_ d: GirlDetails) -> some View {
        if d.hasPreferences {
            Section("偏好与雷区") {
                if !d.favoriteFood.isEmpty { TextBlock(label: "爱吃", text: d.favoriteFood) }
                if !d.dislikedFood.isEmpty { TextBlock(label: "忌口", text: d.dislikedFood) }
                if !d.drinks.isEmpty { TextBlock(label: "饮品", text: d.drinks) }
                if !d.hobbies.isEmpty { TextBlock(label: "爱好", text: d.hobbies) }
                if !d.giftPrefs.isEmpty { TextBlock(label: "喜欢的礼物", text: d.giftPrefs) }
                if !d.taboos.isEmpty {
                    TextBlock(label: "雷点 / 禁忌", text: d.taboos)
                        .foregroundStyle(.red)
                }
            }
        }
    }

    @ViewBuilder
    private func intimacyInfo(_ d: GirlDetails) -> some View {
        if d.hasIntimacy {
            Section("亲密偏好") {
                if !d.likedPositions.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("体位").font(.subheadline).foregroundStyle(.secondary)
                        ChipsView(items: d.likedPositions)
                    }
                }
                if !d.likedPlay.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("玩法").font(.subheadline).foregroundStyle(.secondary)
                        ChipsView(items: d.likedPlay)
                    }
                }
                if !d.sensitiveSpots.isEmpty { TextBlock(label: "敏感点", text: d.sensitiveSpots) }
                if !d.boundaries.isEmpty { TextBlock(label: "边界", text: d.boundaries) }
                if !d.contraception.isEmpty { TextBlock(label: "避孕约定", text: d.contraception) }
            }
        }
    }

    private func periodSection(_ d: GirlDetails) -> some View {
        Section {
            if let last = d.periodStarts.max() {
                InfoRow(label: "上次开始", value: Fmt.date(last))
                InfoRow(label: "平均周期", value: "\(d.averageCycle) 天")
                if let next = d.nextPeriod {
                    InfoRow(label: "预计下次", value: "\(Fmt.shortDate(next))（\(Fmt.days(from: Date(), to: next)) 天后）")
                }
                NavigationLink {
                    PeriodHistoryView(girl: girl)
                } label: {
                    LabeledContent("全部记录", value: "\(d.periodStarts.count) 次")
                }
            }
            Button { sheet = .period } label: { Label("记录一次经期开始", systemImage: "drop") }
        } header: {
            Text("生理期")
        }
    }

    private func datesSection(_ d: GirlDetails) -> some View {
        Section("重要日期") {
            if let bd = d.birthday {
                LabeledContent("生日", value: "\(Fmt.shortDate(bd)) · \(Reminders.daysUntilNext(bd)) 天后")
            }
            ForEach(d.importantDates) { item in
                LabeledContent(item.title, value: "\(Fmt.date(item.date)) · \(Reminders.daysUntilNext(item.date)) 天后")
            }
            .onDelete { idx in
                girl.update { $0.importantDates.remove(atOffsets: idx) }
                Reminders.rescheduleDates(girls: allGirls)
            }
            Button { sheet = .date } label: { Label("添加纪念日", systemImage: "calendar.badge.plus") }
        }
    }

    private func giftSection(_ d: GirlDetails) -> some View {
        Section {
            ForEach(d.gifts) { gift in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(gift.item.isEmpty ? gift.occasion : gift.item)
                        Text([Fmt.date(gift.date), gift.occasion].filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(Fmt.money(gift.amount)).foregroundStyle(.secondary)
                }
            }
            .onDelete { idx in girl.update { $0.gifts.remove(atOffsets: idx) } }
            Button { sheet = .gift } label: { Label("记一笔礼物 / 红包", systemImage: "gift") }
        } header: {
            HStack {
                Text("礼物与红包")
                Spacer()
                if d.giftSpending > 0 { Text("合计 \(Fmt.money(d.giftSpending))") }
            }
        }
    }

    private func memoSection(_ d: GirlDetails) -> some View {
        Section("时间线备忘") {
            ForEach(d.memos) { note in
                NoteRow(note: note)
            }
            .onDelete { idx in girl.update { $0.memos.remove(atOffsets: idx) } }
            Button { sheet = .memo } label: { Label("加一条备忘", systemImage: "square.and.pencil") }
        }
    }

    private var encounterSection: some View {
        Section {
            ForEach(girl.sortedEncounters) { e in
                NavigationLink {
                    EncounterDetailView(encounter: e)
                } label: {
                    EncounterRow(encounter: e, showGirls: e.girls.count > 1)
                }
            }
            Button { sheet = .encounter } label: { Label("记一次", systemImage: "plus.circle") }
        } header: {
            Text("约会记录（\(girl.encounters.count)）")
        }
    }

    private var photoSection: some View {
        Section("相册") {
            PhotoGrid(photoIDs: livePhotoBinding(
                get: { girl.details.photoIDs },
                set: { ids in girl.update { $0.photoIDs = ids } }
            ))
        }
    }

    @ViewBuilder
    private func customInfo(_ d: GirlDetails) -> some View {
        let fields = config.config.customFields.filter { !(d.customValues[$0.id.uuidString] ?? "").isEmpty }
        if !fields.isEmpty {
            Section("自定义字段") {
                ForEach(fields) { f in
                    InfoRow(label: f.name, value: d.customValues[f.id.uuidString] ?? "")
                }
            }
        }
    }
}

struct ScoreEntry: Identifiable {
    let label: String
    let value: Int
    var id: String { label }
}

struct StatCell: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.headline)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

struct NoteRow: View {
    let note: NoteItem

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(note.text).textSelection(.enabled)
            Text(Fmt.date(note.date)).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - 小表单

struct NoteSheet: View {
    let title: String
    let onSave: (NoteItem) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var note = NoteItem()

    var body: some View {
        NavigationStack {
            Form {
                TextField("内容", text: $note.text, axis: .vertical).lineLimit(3...12)
                DatePicker("日期", selection: $note.date, displayedComponents: .date)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { onSave(note); dismiss() }.disabled(note.text.trimmed.isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

struct GiftSheet: View {
    let onSave: (GiftItem) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var gift = GiftItem()

    var body: some View {
        NavigationStack {
            Form {
                TextField("礼物 / 说明", text: $gift.item)
                LabeledContent("金额") { DecimalField(title: "¥", value: $gift.amount) }
                OptionSinglePicker(title: "场合", key: .giftOccasions, selection: $gift.occasion)
                DatePicker("日期", selection: $gift.date, displayedComponents: .date)
            }
            .navigationTitle("礼物 / 红包")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { onSave(gift); dismiss() }
                        .disabled(gift.item.trimmed.isEmpty && gift.occasion.isEmpty && gift.amount == 0)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

struct ImportantDateSheet: View {
    let onSave: (ImportantDate) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var item = ImportantDate()

    var body: some View {
        NavigationStack {
            Form {
                TextField("名称（如：在一起纪念日）", text: $item.title)
                DatePicker("日期", selection: $item.date, displayedComponents: .date)
                Toggle("每年提醒", isOn: $item.remind)
            }
            .navigationTitle("重要日期")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { onSave(item); dismiss() }.disabled(item.title.trimmed.isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

struct PeriodSheet: View {
    let onSave: (Date) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var date = Date()

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("开始日期", selection: $date, in: ...Date(), displayedComponents: .date)
                    .datePickerStyle(.graphical)
            }
            .navigationTitle("经期开始")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { onSave(Calendar.current.startOfDay(for: date)); dismiss() }
                }
            }
        }
        .presentationDetents([.large])
    }
}

struct PeriodHistoryView: View {
    let girl: Girl

    var body: some View {
        let starts = girl.details.periodStarts.sorted(by: >)
        List {
            ForEach(Array(starts.enumerated()), id: \.offset) { index, date in
                HStack {
                    Text(Fmt.date(date))
                    Spacer()
                    if index + 1 < starts.count {
                        let gap = Fmt.days(from: starts[index + 1], to: date)
                        Text("间隔 \(gap) 天").foregroundStyle(.secondary)
                    }
                }
            }
            .onDelete { idx in
                let toRemove = Set(idx.map { starts[$0] })
                girl.update { details in details.periodStarts.removeAll { toRemove.contains($0) } }
            }
        }
        .navigationTitle("经期记录")
    }
}

struct StatusHistoryView: View {
    let history: [StatusChange]

    var body: some View {
        List(history.sorted { $0.date > $1.date }) { item in
            HStack {
                let status = RelationStatus(rawValue: item.status) ?? .flirting
                Badge(text: status.title, color: status.color)
                Spacer()
                Text(Fmt.dateTime(item.date)).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("状态变化")
    }
}
