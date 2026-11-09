import SwiftUI
import SwiftData

struct GirlDetailView: View {
    let girl: Girl

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Girl.createdAt) private var allGirls: [Girl]
    @Query(sort: \TodoItem.createdAt, order: .reverse) private var allTodos: [TodoItem]
    @ObservedObject private var config = ConfigStore.shared

    @State private var sheet: DetailSheet?
    @State private var showSensitive = false
    @State private var confirmDelete = false
    @State private var editingTodo: TodoItem?
    @State private var contactPulse = 0

    enum DetailSheet: String, Identifiable {
        case edit, encounter, memo, said, gift, date, period, todo
        var id: String { rawValue }
    }

    private var herTodos: [TodoItem] {
        allTodos.filter { $0.girlID == girl.id && !$0.isDone }
            .sorted { ($0.fireDate ?? .distantFuture) < ($1.fireDate ?? .distantFuture) }
    }

    var body: some View {
        let d = girl.details
        List {
            Group {
                header(d)
                overview(d)
                alerts(d)
                cycleSection(d)
                todoSection
                timelineSection(d)
            }
            Group {
                basicInfo(d)
                bodyInfo(d)
                socialInfo(d)
                metInfo(d)
                haremInfo(d)
                saidSection(d)
                preferenceInfo(d)
            }
            Group {
                intimacyInfo(d)
                datesSection(d)
                giftSection(d)
                encounterSection
                photoSection
                customInfo(d)
                if !d.notes.isEmpty {
                    Section("备注") { Text(d.notes).textSelection(.enabled) }
                }
            }
        }
        .listSectionSpacing(.compact)
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
                .accessibilityIdentifier("girlMenu")
            }
        }
        .sheet(item: $sheet) { which in
            sheetContent(which)
        }
        .sheet(item: $editingTodo) { todo in
            TodoEditView(todo: todo)
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
            NoteSheet(title: "加一条备忘", girl: girl, prompt: "发生了什么、想记住的细节…") { note in
                withAnimation(.snappy) {
                    girl.update { $0.memos.append(note); $0.memos.sort { $0.date > $1.date } }
                }
            }
        case .said:
            NoteSheet(title: "她说过的事", girl: girl, prompt: "她提到的家人、经历、计划、喜好…") { note in
                withAnimation(.snappy) {
                    girl.update { $0.saidNotes.append(note); $0.saidNotes.sort { $0.date > $1.date } }
                }
                AchievementCenter.shared.refresh(context: context)
            }
        case .gift:
            GiftSheet { gift in
                withAnimation(.snappy) {
                    girl.update { $0.gifts.append(gift); $0.gifts.sort { $0.date > $1.date } }
                }
                AchievementCenter.shared.refresh(context: context)
            }
        case .date:
            ImportantDateSheet { item in
                withAnimation(.snappy) {
                    girl.update { $0.importantDates.append(item) }
                }
                Reminders.rescheduleDates(girls: allGirls)
            }
        case .period:
            PeriodEditSheet(entry: PeriodEntry(start: Calendar.current.startOfDay(for: Date()))) { entry in
                withAnimation(.snappy) {
                    girl.update { d in d.setPeriods(d.periodEntries + [entry]) }
                }
            }
        case .todo:
            TodoEditView(todo: nil, presetGirl: girl)
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
            VStack(spacing: 14) {
                AvatarView(photoID: girl.avatarID, name: girl.name, size: 104)
                    .overlay(Circle().stroke(Color.white.opacity(0.7), lineWidth: 3))
                    .shadow(color: .black.opacity(0.18), radius: 18, y: 10)
                    .padding(.top, 6)
                VStack(spacing: 6) {
                    Text(girl.name)
                        .font(Typo.display(30))
                    HStack(spacing: 6) {
                        if !girl.rank.isEmpty { Badge(text: girl.rank, color: Palette.gold) }
                        Badge(text: girl.status.title, color: girl.status.color)
                    }
                    let line = headerLine(d)
                    if !line.isEmpty {
                        Text(line)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                if !d.personality.isEmpty || !d.tags.isEmpty {
                    ChipsView(items: d.personality + d.tags)
                        .frame(maxWidth: .infinity)
                }
                HStack(spacing: 0) {
                    QuickAction(title: "记一次", symbol: "heart", tint: .accentColor) { sheet = .encounter }
                        .accessibilityIdentifier("logEncounter")
                    QuickAction(title: "联系过", symbol: "bubble.left") {
                        withAnimation(.snappy) { girl.update { $0.lastContactDate = Date() } }
                    }
                    QuickAction(title: "待办", symbol: "checklist") { sheet = .todo }
                    QuickAction(title: "备忘", symbol: "square.and.pencil") { sheet = .memo }
                        .accessibilityIdentifier("quickMemo")
                }
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .listRowBackground(heroBackground)
        }
    }

    /// 有头像时用模糊后的照片做底，没有时用她的头像色调
    @ViewBuilder
    private var heroBackground: some View {
        ZStack {
            Color(uiColor: .secondarySystemGroupedBackground)
            if let id = girl.avatarID, let image = PhotoStore.shared.thumbnail(id, size: 240) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .blur(radius: 40)
                    .opacity(0.55)
                    .clipped()
            } else {
                Palette.avatarGradient(for: girl.name).opacity(0.28)
            }
            LinearGradient(colors: [.clear, Color(uiColor: .secondarySystemGroupedBackground).opacity(0.92)],
                           startPoint: .center, endPoint: .bottom)
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
            BondRow(bond: BondLevel(count: girl.encounters.count))
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
                    Callout(symbol: "bell", tint: Palette.gold, title: text)
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
        let cycle = d.cycle
        if cycle.hasData, !cycle.isOngoing, let n = cycle.daysUntilNext, (0...3).contains(n) {
            items.append(n == 0 ? "预计今天来例假" : "预计 \(n) 天后来例假")
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
                let metrics = bodyMetrics(d)
                if !metrics.isEmpty {
                    MetricStrip(items: metrics)
                        .padding(.vertical, 8)
                }
                if !d.bodyType.isEmpty { InfoRow(label: "体型", value: d.bodyType) }
                if !d.appearance.isEmpty { TextBlock(label: "外貌特征", text: d.appearance) }
            }
        }
    }

    private func bodyMetrics(_ d: GirlDetails) -> [MetricItem] {
        var items: [MetricItem] = []
        if let h = d.height { items.append(MetricItem(label: "身高", value: "\(h)", unit: "cm")) }
        if let w = d.weight { items.append(MetricItem(label: "体重", value: "\(w)", unit: "kg")) }
        if !d.cup.isEmpty { items.append(MetricItem(label: "罩杯", value: d.cup)) }
        if d.bust != nil || d.waist != nil || d.hips != nil {
            let value = [d.bust, d.waist, d.hips].map { v in v.map { "\($0)" } ?? "?" }.joined(separator: "·")
            items.append(MetricItem(label: "三围", value: value))
        }
        return items
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
                if d.metDate != nil || !d.channel.isEmpty {
                    HStack(alignment: .top, spacing: 12) {
                        IconBadge(symbol: "bubble.left.and.bubble.right", color: .accentColor, size: 32)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(d.metDate.map { Fmt.date($0) } ?? d.channel)
                                .font(Typo.display(17))
                            Text(metLine(d))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
                if let f = d.firstDateDate { InfoRow(label: "首次见面", value: Fmt.date(f)) }
                if !d.introducer.isEmpty { InfoRow(label: "介绍人", value: d.introducer) }
                if !d.howWeMet.isEmpty { TextBlock(label: "经过", text: d.howWeMet) }
            }
        }
    }

    /// 「通过「探探」认识 · 已经认识 213 天」
    private func metLine(_ d: GirlDetails) -> String {
        var parts: [String] = []
        if d.metDate != nil, !d.channel.isEmpty { parts.append("通过「\(d.channel)」认识") }
        if d.metDate == nil { parts.append("认识渠道") }
        if let met = d.metDate { parts.append("已经认识 \(max(Fmt.days(from: met), 0)) 天") }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func haremInfo(_ d: GirlDetails) -> some View {
        Section("后宫属性") {
            IntimacyMeter(value: d.intimacy, tint: girl.status.color)
                .padding(.vertical, 4)
            let scores = scoreEntries(d)
            if !scores.isEmpty {
                ScoreBarsView(entries: scores)
                    .padding(.vertical, 4)
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
                QuoteRow(note: note)
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
                        .foregroundStyle(Palette.period)
                }
            }
        }
    }

    @ViewBuilder
    private func intimacyInfo(_ d: GirlDetails) -> some View {
        let habits = IntimacyHabits(encounters: girl.encounters)
        if d.hasIntimacy || !habits.isEmpty {
            Section {
                if !d.traits.isEmpty {
                    TagGroupView(title: "特质", symbol: "tag", items: d.traits, tint: Palette.gold)
                        .padding(.vertical, 3)
                }
                if !d.safeWord.isEmpty {
                    LabeledContent {
                        Text(d.safeWord)
                            .textSelection(.enabled)
                    } label: {
                        Label("安全词", systemImage: "lock.shield")
                    }
                }
                if !d.boundaries.isEmpty {
                    TextBlock(label: "底线", text: d.boundaries)
                        .foregroundStyle(Palette.period)
                }
                if !d.likedPositions.isEmpty {
                    TagGroupView(title: "喜欢的体位", symbol: "square.grid.2x2", items: d.likedPositions)
                        .padding(.vertical, 3)
                }
                if !d.likedPlay.isEmpty {
                    TagGroupView(title: "喜欢的玩法", symbol: "wand.and.stars", items: d.likedPlay)
                        .padding(.vertical, 3)
                }
                if !d.likedToys.isEmpty {
                    TagGroupView(title: "喜欢的道具", symbol: "sparkles", items: d.likedToys)
                        .padding(.vertical, 3)
                }
                if !d.aftercareNeeds.isEmpty {
                    TagGroupView(title: "事后需要", symbol: "hands.sparkles", items: d.aftercareNeeds, tint: Palette.status)
                        .padding(.vertical, 3)
                }
                if !habits.isEmpty {
                    HabitsView(habits: habits)
                        .padding(.vertical, 3)
                }
                if !d.sensitiveSpots.isEmpty { TextBlock(label: "敏感点", text: d.sensitiveSpots) }
                if !d.contraception.isEmpty { TextBlock(label: "避孕约定", text: d.contraception) }
            } header: {
                Text("亲密档案")
            }
        }
    }

    private func cycleSection(_ d: GirlDetails) -> some View {
        let info = d.cycle
        return Section {
            if info.hasData {
                CycleCard(girl: girl, info: info)
                NavigationLink {
                    GirlCycleView(girl: girl)
                } label: {
                    Label("经期日历与记录", systemImage: "calendar")
                }
            } else {
                Button {
                    withAnimation(.snappy) { girl.update { $0.startPeriod(on: Date()) } }
                } label: {
                    Label("今天来例假了", systemImage: "drop.fill")
                }
                .tint(Palette.period)
                Button {
                    sheet = .period
                } label: {
                    Label("补记之前的经期", systemImage: "calendar.badge.plus")
                }
            }
        } header: {
            Text("生理期")
        } footer: {
            if !info.hasData {
                Text("记两三次之后就能预测下次经期和易孕期。")
            }
        }
    }

    @ViewBuilder
    private var todoSection: some View {
        let todos = herTodos
        if !todos.isEmpty {
            Section {
                ForEach(todos) { todo in
                    TodoRow(todo: todo) {
                        TodoActions.toggle(todo, girls: allGirls, context: context)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { editingTodo = todo }
                }
            } header: {
                HStack {
                    Text("待办")
                    Spacer()
                    Button {
                        sheet = .todo
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
    }

    private func timelineSection(_ d: GirlDetails) -> some View {
        let events = TimelineBuilder.events(for: girl, todos: allTodos)
        let recent = Array(events.prefix(4))
        return Section {
            ForEach(Array(recent.enumerated()), id: \.element.id) { index, event in
                TimelineRow(event: event, isFirst: index == 0, isLast: index == recent.count - 1)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
            }
            NavigationLink {
                GirlTimelineView(girl: girl)
            } label: {
                Text("查看完整时间线（\(events.count)）")
                    .font(.subheadline)
                    .foregroundStyle(.tint)
            }
        } header: {
            Text("时间线")
        }
    }

    private func datesSection(_ d: GirlDetails) -> some View {
        Section("重要日期") {
            if let bd = d.birthday {
                DateCountdownRow(title: "生日", symbol: "gift", date: bd, isBirthday: true)
            }
            ForEach(d.importantDates) { item in
                DateCountdownRow(title: item.title, symbol: item.remind ? "bell" : "calendar", date: item.date)
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
                GiftRow(gift: gift)
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
            ), onSetCover: { id in
                // 复制一份当头像，这样删相册里的照片不会影响头像
                guard let data = PhotoStore.shared.rawData(id) else { return }
                let newID = UUID().uuidString
                guard PhotoStore.shared.importRaw(data, id: newID) else { return }
                if let old = girl.avatarID { PhotoStore.shared.delete(old) }
                withAnimation(.snappy) { girl.avatarID = newID }
                Haptics.success()
            })
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

/// 羁绊等级：见得越多，等级越高
struct BondRow: View {
    let bond: BondLevel

    @State private var shown = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("羁绊")
                    .foregroundStyle(.secondary)
                Spacer()
                Text("Lv.\(bond.level)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Palette.gold)
                Text(bond.title)
                    .font(Typo.display(17))
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.12))
                    Capsule()
                        .fill(LinearGradient(colors: [Palette.gold.opacity(0.7), Palette.gold], startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(5, geo.size.width * (shown ? bond.progress : 0)))
                }
            }
            .frame(height: 5)
            if let next = bond.nextCount, let title = bond.nextTitle {
                Text("再见 \(next - bond.count) 次，升级为「\(title)」")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("已是最高羁绊")
                    .font(.caption)
                    .foregroundStyle(Palette.gold)
            }
        }
        .padding(.vertical, 4)
        .onAppear {
            withAnimation(.smooth(duration: 0.9).delay(0.2)) { shown = true }
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
                .statNumber()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

/// 她说过的话：金色引号 + 衬线正文
struct QuoteRow: View {
    let note: NoteItem

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\u{201C}")
                .font(.system(size: 30, weight: .bold, design: .serif))
                .foregroundStyle(Palette.gold.opacity(0.75))
                .frame(width: 14, height: 20, alignment: .top)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 4) {
                Text(note.text)
                    .font(Typo.display(16, weight: .regular))
                    .lineSpacing(3)
                    .textSelection(.enabled)
                Text(Fmt.date(note.date))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

/// 生日、纪念日：右边是还有几天
struct DateCountdownRow: View {
    let title: String
    let symbol: String
    let date: Date
    var isBirthday = false

    private var days: Int { Reminders.daysUntilNext(date) }

    /// 生日：这次满几岁；纪念日：第几周年
    private var detail: String {
        let years = (Fmt.age(date) ?? 0) + (days == 0 ? 0 : 1)
        if isBirthday { return "\(Fmt.shortDate(date)) · 将满 \(years) 岁" }
        return years > 0 ? "\(Fmt.date(date)) · \(years) 周年" : Fmt.date(date)
    }

    var body: some View {
        HStack(spacing: 12) {
            IconBadge(symbol: symbol, color: Palette.gold, size: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if days == 0 {
                Text("就是今天")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Palette.gold))
            } else {
                VStack(alignment: .trailing, spacing: 0) {
                    Text("\(days)")
                        .font(Typo.display(22, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(days <= 7 ? Palette.gold : Color.primary)
                    Text("天后")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

/// 礼物和红包
struct GiftRow: View {
    let gift: GiftItem

    private var title: String {
        if !gift.item.trimmed.isEmpty { return gift.item }
        return gift.occasion.isEmpty ? "礼物" : gift.occasion
    }

    var body: some View {
        HStack(spacing: 12) {
            IconBadge(symbol: gift.item.trimmed.isEmpty && gift.amount > 0 ? "yensign.circle" : "gift",
                      color: Palette.gift, size: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text([Fmt.date(gift.date), gift.item.trimmed.isEmpty ? "" : gift.occasion]
                    .filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if gift.amount > 0 {
                Text(Fmt.money(gift.amount))
                    .font(Typo.display(17, weight: .medium))
                    .monospacedDigit()
            }
        }
        .padding(.vertical, 2)
    }
}

/// 几项评分，进页面时从零涨上去
struct ScoreBarsView: View {
    let entries: [ScoreEntry]

    @State private var shown = false

    var body: some View {
        VStack(spacing: 2) {
            ForEach(entries) { item in
                ScoreBar(title: item.label, value: .constant(shown ? item.value : 0), editable: false)
            }
        }
        .onAppear {
            withAnimation(.smooth(duration: 0.8).delay(0.15)) { shown = true }
        }
    }
}

// MARK: - 小表单

struct NoteSheet: View {
    let title: String
    var girl: Girl?
    var prompt = "写点什么…"
    let onSave: (NoteItem) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var note = NoteItem()
    @FocusState private var focused: Bool

    private func daysBack(_ n: Int) -> Date {
        let today = Calendar.current.startOfDay(for: Date())
        return Calendar.current.date(byAdding: .day, value: -n, to: today) ?? today
    }

    var body: some View {
        ComposerShell(title: title, canSave: !note.text.trimmed.isEmpty,
                      onCancel: { dismiss() },
                      onSave: { onSave(note); dismiss() }) {
            if let girl {
                HStack(spacing: 10) {
                    AvatarView(photoID: girl.avatarID, name: girl.name, size: 30)
                    Text("关于「\(girl.name)」")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
            }
            HStack(spacing: 8) {
                ForEach(0..<3, id: \.self) { back in
                    let day = daysBack(back)
                    ChoiceChip(title: ["今天", "昨天", "前天"][back],
                               selected: Calendar.current.isDate(note.date, inSameDayAs: day)) {
                        note.date = day
                    }
                }
                Spacer(minLength: 0)
                DatePicker("日期", selection: $note.date, displayedComponents: .date)
                    .labelsHidden()
            }
            TextField(prompt, text: $note.text, axis: .vertical)
                .font(Typo.display(20, weight: .regular))
                .lineSpacing(5)
                .lineLimit(6...20)
                .focused($focused)
        }
        .composerSheet()
        .onAppear { focused = true }
    }
}

struct GiftSheet: View {
    let onSave: (GiftItem) -> Void

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var config = ConfigStore.shared
    @State private var gift = GiftItem()
    @State private var amountText = ""
    @FocusState private var amountFocused: Bool

    var body: some View {
        ComposerShell(title: "礼物与红包",
                      canSave: !(gift.item.trimmed.isEmpty && gift.occasion.isEmpty && gift.amount == 0),
                      onCancel: { dismiss() },
                      onSave: { onSave(gift); dismiss() }) {
            VStack(spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("¥")
                        .font(Typo.display(26, weight: .regular))
                        .foregroundStyle(.secondary)
                    TextField("0", text: $amountText)
                        .font(Typo.display(54, weight: .medium))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.center)
                        .fixedSize()
                        .focused($amountFocused)
                        .onChange(of: amountText) { _, t in
                            gift.amount = Double(t.replacingOccurrences(of: ",", with: ".")) ?? 0
                        }
                }
                Text("金额").font(.caption).foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)

            ChipRow {
                ForEach(["52", "66", "88", "131.4", "188", "520", "1314"], id: \.self) { v in
                    ChoiceChip(title: "¥" + v, selected: amountText == v) {
                        amountText = amountText == v ? "" : v
                    }
                }
            }

            TextField("送了什么", text: $gift.item)
                .composerField()

            VStack(alignment: .leading, spacing: 10) {
                ComposerLabel("场合")
                ChipRow {
                    ForEach(config.options(.giftOccasions), id: \.self) { o in
                        ChoiceChip(title: o, selected: gift.occasion == o) {
                            gift.occasion = gift.occasion == o ? "" : o
                        }
                    }
                }
            }

            HStack {
                ComposerLabel("日期")
                DatePicker("日期", selection: $gift.date, displayedComponents: .date)
                    .labelsHidden()
            }
        }
        .composerSheet(detents: [.large])
        .onAppear { amountFocused = true }
    }
}

struct ImportantDateSheet: View {
    let onSave: (ImportantDate) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var item = ImportantDate()

    private let suggestions = ["在一起纪念日", "第一次见面", "第一次约会", "她的生理期开始", "相识纪念"]

    var body: some View {
        ComposerShell(title: "纪念日", canSave: !item.title.trimmed.isEmpty,
                      onCancel: { dismiss() },
                      onSave: { onSave(item); dismiss() }) {
            TextField("纪念什么", text: $item.title)
                .font(Typo.display(24, weight: .medium))
            ChipRow {
                ForEach(suggestions, id: \.self) { s in
                    ChoiceChip(title: s, selected: item.title == s) { item.title = s }
                }
            }
            DatePicker("日期", selection: $item.date, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .tint(.accentColor)
            Toggle(isOn: $item.remind) {
                Label("每年提醒", systemImage: "bell")
            }
            .tint(.accentColor)
            .composerField()
        }
        .composerSheet(detents: [.large])
    }
}

/// 亲密度：大号数字 + 细进度条，进页面时从零涨上去
struct IntimacyMeter: View {
    let value: Int
    var tint: Color = .accentColor

    @State private var shown = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("亲密度")
                Spacer(minLength: 8)
                Text("\(shown ? value : 0)")
                    .font(Typo.display(22, weight: .semibold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text("/ 100")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.12))
                    Capsule()
                        .fill(LinearGradient(colors: [tint.opacity(0.55), tint], startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(6, geo.size.width * CGFloat(shown ? value : 0) / 100))
                }
            }
            .frame(height: 6)
        }
        .onAppear {
            withAnimation(.smooth(duration: 0.9).delay(0.15)) { shown = true }
        }
    }
}

/// 关系变化：一条竖线串起每次变化，标出每个阶段持续了多久
struct StatusHistoryView: View {
    let history: [StatusChange]

    private var items: [StatusChange] { history.sorted { $0.date > $1.date } }

    var body: some View {
        let list = items
        List {
            Section {
                ForEach(Array(list.enumerated()), id: \.element.id) { index, item in
                    let status = RelationStatus(rawValue: item.status) ?? .flirting
                    // 这一段一直持续到下一次变化（列表是倒序，下一次在前一行）
                    let until = index == 0 ? Date() : list[index - 1].date
                    let days = max(Fmt.days(from: item.date, to: until), 0)
                    HStack(alignment: .top, spacing: 12) {
                        VStack(spacing: 0) {
                            Rectangle()
                                .fill(index == 0 ? Color.clear : Color.secondary.opacity(0.2))
                                .frame(width: 2, height: 10)
                            Circle()
                                .fill(status.color)
                                .frame(width: 12, height: 12)
                                .overlay(Circle().stroke(Color(uiColor: .secondarySystemGroupedBackground), lineWidth: 2))
                            Rectangle()
                                .fill(index == list.count - 1 ? Color.clear : Color.secondary.opacity(0.2))
                                .frame(width: 2)
                        }
                        .frame(width: 14)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(status.title)
                                .font(Typo.display(17))
                                .foregroundStyle(status.color)
                            Text(Fmt.dateTime(item.date))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 8)
                        Spacer(minLength: 8)
                        Text(index == 0 ? "至今 \(days) 天" : "持续 \(days) 天")
                            .font(.footnote)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .padding(.top, 10)
                    }
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                    .listRowSeparator(.hidden)
                }
            }
        }
        .navigationTitle("状态变化")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 亲密档案：从记录里统计的习惯

/// 和她的记录里最常出现的体位、玩法、道具
struct IntimacyHabits {
    struct Entry: Identifiable {
        let name: String
        let count: Int
        var id: String { name }
    }

    let positions: [Entry]
    let play: [Entry]
    let toys: [Entry]

    init(encounters: [Encounter]) {
        var positionCount: [String: Int] = [:]
        var playCount: [String: Int] = [:]
        var toyCount: [String: Int] = [:]
        for e in encounters {
            let d = e.details
            for v in Set(d.positions) where !v.isEmpty { positionCount[v, default: 0] += 1 }
            for v in Set(d.play) where !v.isEmpty { playCount[v, default: 0] += 1 }
            for v in Set(d.toys) where !v.isEmpty { toyCount[v, default: 0] += 1 }
        }
        func top(_ counts: [String: Int]) -> [Entry] {
            counts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
                .prefix(4)
                .map { Entry(name: $0.key, count: $0.value) }
        }
        positions = top(positionCount)
        play = top(playCount)
        toys = top(toyCount)
    }

    var isEmpty: Bool { positions.isEmpty && play.isEmpty && toys.isEmpty }
}

struct HabitsView: View {
    let habits: IntimacyHabits

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "chart.bar")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                Text("记录里最常")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            row("体位", habits.positions)
            row("玩法", habits.play)
            row("道具", habits.toys)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func row(_ title: String, _ entries: [IntimacyHabits.Entry]) -> some View {
        if !entries.isEmpty {
            HStack(alignment: .top, spacing: 10) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(width: 30, alignment: .leading)
                    .padding(.top, 5)
                FlowLayout(spacing: 6) {
                    ForEach(entries) { entry in
                        HStack(spacing: 5) {
                            Text(entry.name)
                            Text("\(entry.count)")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        .font(.footnote)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color(uiColor: .tertiarySystemFill)))
                    }
                }
            }
        }
    }
}

