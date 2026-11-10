import SwiftUI
import SwiftData

/// 记一次 / 编辑记录：一页卡片，常用的直接点选，长列表折叠成一行、点开原地多选
struct EncounterEditView: View {
    let encounter: Encounter?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @ObservedObject private var config = ConfigStore.shared
    @Query(sort: \Girl.createdAt, order: .reverse) private var allGirls: [Girl]
    @Query(sort: \Place.createdAt, order: .reverse) private var allPlaces: [Place]

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
    /// 她的特质：在这里勾选，保存时写回她的档案
    @State private var traits: [UUID: [String]]
    @State private var originalTraits: [UUID: [String]]
    @State private var riskAlert = false
    @State private var confirmDiscard = false
    /// 没选对象就点了保存
    @State private var confirmNoOne = false
    /// 刚加的照片里最早的拍摄时间（和记录时间差得多时提示可以用它）
    @State private var photoDate: Date?
    /// 这次编辑里新加过的照片视频（包括加了又删掉的），取消或保存时清理没用上的文件
    @State private var sessionMedia: Set<String> = []
    /// 已经照着哪一条记录填过了（填过就不再提示）
    @State private var reusedFrom: UUID?

    private let originalPhotos: Set<String>
    private let initialSnapshot: Snapshot
    /// 打开后直接滚到哪一块（从记录详情点「补上」进来时）
    private let focus: String?

    /// 用来判断有没有改动
    struct Snapshot: Equatable {
        var date: Date
        var durationMinutes: Int
        var overnight: Bool
        var count: Int
        var protection: Protection
        var condomBroke: Bool
        var rating: Int
        var details: EncounterDetails
        var girlIDs: [UUID]
        var placeID: UUID?
        var traitChanges: [UUID: [String]]
    }

    private var snapshot: Snapshot {
        Snapshot(date: date, durationMinutes: durationMinutes, overnight: overnight, count: count,
                 protection: protection, condomBroke: condomBroke, rating: rating, details: details,
                 girlIDs: girls.map(\.id), placeID: place?.id, traitChanges: traitChanges)
    }

    private var isDirty: Bool { snapshot != initialSnapshot }

    /// 只算选中的人里真的改过的
    private var traitChanges: [UUID: [String]] {
        var result: [UUID: [String]] = [:]
        for g in girls {
            if let edited = traits[g.id], edited != (originalTraits[g.id] ?? []) {
                result[g.id] = edited
            }
        }
        return result
    }

    init(encounter: Encounter?, presetGirls: [Girl], presetDate: Date? = nil, presetPlace: Place? = nil,
         focus: String? = nil) {
        self.encounter = encounter
        self.focus = focus
        _durationMinutes = State(initialValue: encounter?.durationMinutes ?? 0)
        _overnight = State(initialValue: encounter?.overnight ?? false)
        _count = State(initialValue: encounter?.count ?? 1)
        _protection = State(initialValue: encounter?.protection ?? .unrecorded)
        _condomBroke = State(initialValue: encounter?.condomBroke ?? false)
        _rating = State(initialValue: encounter?.rating ?? 0)
        let d = encounter?.details ?? EncounterDetails()
        _details = State(initialValue: d)
        let initialGirls = encounter?.girls ?? presetGirls
        let initialPlace = encounter?.place ?? presetPlace
        _girls = State(initialValue: initialGirls)
        _place = State(initialValue: initialPlace)
        let storedTraits = Dictionary(initialGirls.map { ($0.id, $0.details.traits) }, uniquingKeysWith: { a, _ in a })
        _traits = State(initialValue: storedTraits)
        _originalTraits = State(initialValue: storedTraits)
        originalPhotos = Set(d.photoIDs)
        let initialDate = encounter?.date ?? Self.defaultDate(for: presetDate)
        _date = State(initialValue: initialDate)
        initialSnapshot = Snapshot(
            date: initialDate, durationMinutes: encounter?.durationMinutes ?? 0, overnight: encounter?.overnight ?? false,
            count: encounter?.count ?? 1, protection: encounter?.protection ?? .unrecorded,
            condomBroke: encounter?.condomBroke ?? false, rating: encounter?.rating ?? 0, details: d,
            girlIDs: initialGirls.map(\.id), placeID: initialPlace?.id, traitChanges: [:])
    }

    /// 从日历选了某天时：今天用现在的时间，其他日子默认晚上 9 点
    private static func defaultDate(for day: Date?) -> Date {
        guard let day, !Calendar.current.isDateInToday(day) else { return Date() }
        return Calendar.current.date(bySettingHour: 21, minute: 0, second: 0, of: day) ?? day
    }

    /// 选中对象在这天的周期提示
    private var cycleHints: [(text: String, color: Color)] {
        girls.compactMap { (girl: Girl) -> (text: String, color: Color)? in
            let info = girl.details.cycle
            guard info.hasData else { return nil }
            switch info.kind(on: date) {
            case .period(let predicted):
                return ("「\(girl.name)」这天\(predicted ? "可能" : "")在经期", Palette.period)
            case .fertile, .ovulation:
                return ("「\(girl.name)」这天在易孕期，注意避孕", Palette.fertile)
            case .none:
                return nil
            }
        }
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
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 14) {
                        whoCard.id("who")
                        placeCard.id("place")
                        timeCard.id("time")
                        processCard.id("process")
                        playCard.id("play")
                        safetyCard.id("safety")
                        feelingCard.id("feeling")
                        dateCard.id("date")
                        costCard.id("cost")
                        noteCard.id("note")
                        photoCard.id("photo")
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 36)
                }
                .safeAreaInset(edge: .top, spacing: 0) {
                    FormRail(items: railItems) { id in
                        jump(to: id, proxy: proxy)
                    }
                }
                .onAppear {
                    guard let focus else { return }
                    // 等弹窗动画结束再滚
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
                        jump(to: focus, proxy: proxy)
                    }
                }
            }
            .background(Palette.canvas)
            .formKeyboardHandling()
            .navigationTitle(encounter == nil ? "记一次" : "编辑记录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { cancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        if girls.isEmpty {
                            confirmNoOne = true
                        } else {
                            save()
                        }
                    }
                    .fontWeight(.semibold)
                    .accessibilityIdentifier("saveEncounter")
                }
            }
            .alert("这次有风险", isPresented: $riskAlert) {
                Button("知道了") { dismiss() }
            } message: {
                Text(riskMessage)
            }
            .confirmationDialog("放弃这次的修改？", isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button("放弃修改", role: .destructive) { discard() }
                Button("继续编辑", role: .cancel) {}
            }
            .confirmationDialog("还没选对象", isPresented: $confirmNoOne, titleVisibility: .visible) {
                Button("不选，直接保存") { save() }
                Button("回去选", role: .cancel) {}
            } message: {
                Text("没选对象的记录不会出现在任何人的档案和时间线里。")
            }
            .onChange(of: girls.map(\.id)) { _, _ in seedTraits() }
        }
        .interactiveDismissDisabled(isDirty)
    }

    // MARK: 分区索引

    private var railItems: [FormRailItem] {
        let d = details
        let feeling = rating > 0 || d.chemistry > 0 || !d.moods.isEmpty || !d.feedback.isEmpty || !d.aftercare.isEmpty
        return [
            FormRailItem(id: "who", title: "对象", filled: !girls.isEmpty),
            FormRailItem(id: "place", title: "地点", filled: place != nil),
            FormRailItem(id: "time", title: "时长", filled: durationMinutes > 0 || overnight),
            FormRailItem(id: "process", title: "过程", filled: d.intensity > 0 || d.herOrgasms >= 0 || !d.lead.isEmpty),
            FormRailItem(id: "play", title: "玩法", filled: !d.highlights.isEmpty),
            FormRailItem(id: "safety", title: "安全", filled: protection != .unrecorded),
            FormRailItem(id: "feeling", title: "感受", filled: feeling),
            FormRailItem(id: "date", title: "约会", filled: !d.activities.isEmpty || !d.initiator.isEmpty),
            FormRailItem(id: "cost", title: "花费", filled: d.totalCost > 0),
            FormRailItem(id: "note", title: "备注", filled: !d.notes.trimmed.isEmpty),
            FormRailItem(id: "photo", title: "照片", filled: !d.photoIDs.isEmpty)
        ]
    }

    private func jump(to id: String, proxy: ScrollViewProxy) {
        hideKeyboard()
        withAnimation(.snappy(duration: 0.35)) {
            proxy.scrollTo(id, anchor: .top)
        }
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

    // MARK: 对象

    /// 最近见过的人放在最前面，方便一点即选
    private var quickGirls: [Girl] {
        let current = allGirls.filter { $0.status.isCurrent }
        let recency = Dictionary(current.map { ($0.id, $0.lastEncounterDate ?? $0.createdAt) },
                                 uniquingKeysWith: { a, _ in a })
        var list = Array(current.sorted {
            (recency[$0.id] ?? .distantPast) > (recency[$1.id] ?? .distantPast)
        }.prefix(12))
        for g in girls where !list.contains(where: { $0.id == g.id }) {
            list.insert(g, at: 0)
        }
        return list
    }

    private func toggleGirl(_ g: Girl) {
        withAnimation(.snappy(duration: 0.25)) {
            if let i = girls.firstIndex(where: { $0.id == g.id }) {
                girls.remove(at: i)
            } else {
                girls.append(g)
            }
        }
    }

    /// 新选进来的人：把她档案里的特质带进来
    private func seedTraits() {
        for g in girls where traits[g.id] == nil {
            let stored = g.details.traits
            traits[g.id] = stored
            originalTraits[g.id] = stored
        }
    }

    private func traitBinding(_ girl: Girl) -> Binding<[String]> {
        Binding(
            get: { traits[girl.id] ?? [] },
            set: { traits[girl.id] = $0 }
        )
    }

    /// 新记录只选了一个人时，她上一次的记录
    private var lastWithHer: Encounter? {
        guard encounter == nil, girls.count == 1, let girl = girls.first else { return nil }
        return girl.encounters.max { $0.date < $1.date }
    }

    /// 上一次有没有值得照着填的：地点，或者体位、玩法、道具、穿着
    private func reusableSummary(_ last: Encounter) -> String? {
        var parts: [String] = []
        if let place = last.place { parts.append(place.displayName) }
        let tags = last.details.highlights
        if !tags.isEmpty { parts.append(EncounterRow.tagLine(tags)) }
        if parts.isEmpty { return nil }
        return ([Fmt.shortDate(last.date)] + parts).joined(separator: " · ")
    }

    /// 只照搬地点和玩法这两样习惯性的，而且只填还空着的。
    /// 时长、安全措施、次数、评分每次都不一样，照搬了反而会记错
    private func reuse(_ last: Encounter) {
        let d = last.details
        withAnimation(.snappy(duration: 0.3)) {
            if place == nil { place = last.place }
            if details.positions.isEmpty { details.positions = d.positions }
            if details.play.isEmpty { details.play = d.play }
            if details.toys.isEmpty { details.toys = d.toys }
            if details.outfits.isEmpty { details.outfits = d.outfits }
            reusedFrom = last.id
        }
        Haptics.light()
    }

    @ViewBuilder
    private var reuseRow: some View {
        if let last = lastWithHer, let summary = reusableSummary(last) {
            if reusedFrom == last.id {
                Label("已照上次的填了地点和玩法，改一改不一样的就行", systemImage: "checkmark.circle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            } else {
                Button {
                    reuse(last)
                } label: {
                    HStack(spacing: 10) {
                        IconBadge(symbol: "arrow.triangle.2.circlepath", color: .accentColor, size: 32)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("照上次的填")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(Color.primary)
                            Text(summary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 8)
                        Text("填入")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(Color.accentColor.opacity(0.1)))
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Palette.fill.opacity(0.6)))
                    .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.chip)
                .transition(.opacity)
                .accessibilityIdentifier("reuseLast")
            }
        }
    }

    private var whoCard: some View {
        RecordCard("对象", trailing: {
            NavigationLink {
                GirlMultiSelectView(selection: $girls)
            } label: {
                CardLinkLabel(text: girls.isEmpty ? "全部" : "已选 \(girls.count) 人")
            }
            .accessibilityIdentifier("pickGirls")
        }) {
            let quick = quickGirls
            if quick.isEmpty {
                NavigationLink {
                    GirlMultiSelectView(selection: $girls)
                } label: {
                    placeholderRow("选择对象，或新建一份档案", symbol: "person.crop.circle.badge.plus")
                }
                .buttonStyle(.plain)
            } else {
                ScrollChips(spacing: 14) {
                    ForEach(quick) { g in
                        QuickPickAvatar(girl: g, selected: girls.contains { $0.id == g.id }) {
                            toggleGirl(g)
                        }
                    }
                }
            }
            if let hint = bondHint {
                Label(hint.text, systemImage: hint.levelUp ? "sparkles" : "heart")
                    .font(.footnote.weight(hint.levelUp ? .medium : .regular))
                    .foregroundStyle(hint.levelUp ? Palette.gold : Color.secondary)
                    .transition(.opacity)
            }
            reuseRow
            let hints = cycleHints
            if !hints.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(hints, id: \.text) { hint in
                        Label(hint.text, systemImage: "drop.fill")
                            .font(.footnote)
                            .foregroundStyle(hint.color)
                    }
                }
                .transition(.opacity)
            }
            if !girls.isEmpty {
                VStack(spacing: 0) {
                    Divider().padding(.bottom, 12)
                    ForEach(Array(girls.enumerated()), id: \.element.id) { index, g in
                        if index > 0 { RowDivider() }
                        TagDisclosure(title: girls.count == 1 ? "她的特质" : "\(g.name)的特质",
                                      symbol: "tag", key: .traits, selection: traitBinding(g),
                                      tint: Palette.gold,
                                      note: "保存后同步到「\(g.name)」的档案",
                                      identifier: "traits-\(g.name)")
                    }
                }
                .transition(.opacity)
            }
        }
    }

    /// 新记录只选了一个人时：这是和她的第几次，这次之后羁绊会不会升级
    private var bondHint: (text: String, levelUp: Bool)? {
        guard encounter == nil, girls.count == 1, let girl = girls.first else { return nil }
        let n = girl.encounters.count + 1
        let before = BondLevel(count: n - 1)
        let after = BondLevel(count: n)
        if after.level > before.level {
            return ("和她的第 \(n) 次 · 保存后羁绊升到「\(after.title)」", true)
        }
        return ("和她的第 \(n) 次", false)
    }

    private func placeholderRow(_ text: String, symbol: String) -> some View {
        HStack(spacing: 12) {
            IconBadge(symbol: symbol, color: .accentColor, size: 32)
            Text(text)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }

    // MARK: 地点

    /// 只选了一个人时，和她去过的地方（去了几次）
    private var herPlaceCounts: [UUID: Int] {
        guard girls.count == 1, let girl = girls.first else { return [:] }
        var counts: [UUID: Int] = [:]
        for e in girl.encounters {
            if let p = e.place { counts[p.id, default: 0] += 1 }
        }
        return counts
    }

    /// 和她常去的排最前面，其余按最近用过的时间
    private var quickPlaces: [Place] {
        let counts = herPlaceCounts
        let sorted = allPlaces.sorted { a, b in
            let ca = counts[a.id] ?? 0, cb = counts[b.id] ?? 0
            if ca != cb { return ca > cb }
            return (a.lastUsed ?? a.createdAt) > (b.lastUsed ?? b.createdAt)
        }
        var list = Array(sorted.prefix(8))
        if let place, !list.contains(where: { $0.id == place.id }) {
            list.insert(place, at: 0)
        }
        return list
    }

    private var placeCard: some View {
        RecordCard("地点", trailing: {
            NavigationLink {
                PlaceSelectView(selection: $place)
            } label: {
                CardLinkLabel(text: "全部")
            }
            .accessibilityIdentifier("pickPlace")
        }) {
            let quick = quickPlaces
            if quick.isEmpty {
                NavigationLink {
                    PlaceSelectView(selection: $place)
                } label: {
                    placeholderRow("选择或新建地点", symbol: "mappin.and.ellipse")
                }
                .buttonStyle(.plain)
            } else {
                ScrollChips {
                    ForEach(quick) { p in
                        ChoiceChip(title: p.displayName, symbol: p.type.symbol, selected: place?.id == p.id) {
                            place = place?.id == p.id ? nil : p
                        }
                    }
                }
            }
            if let place {
                let line = [place.city, place.district, place.address].map(\.trimmed).filter { !$0.isEmpty }
                if !line.isEmpty {
                    Label(line.joined(separator: " · "), systemImage: "mappin")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .transition(.opacity)
                }
            } else if !herPlaceCounts.isEmpty {
                Text("和她去过的地方排在前面")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            }
        }
    }

    // MARK: 时间

    /// 「1.5 小时 · 到 23:00」
    private var durationLabel: String? {
        guard durationMinutes > 0 else { return nil }
        let end = date.addingTimeInterval(Double(durationMinutes) * 60)
        return Choices.durationTitle(durationMinutes) + " · 到 " + end.formatted(.dateTime.hour().minute())
    }

    private var timeCard: some View {
        RecordCard("时间") {
            HStack {
                Text("开始")
                Spacer(minLength: 8)
                DatePicker("开始时间", selection: $date)
                    .labelsHidden()
            }
            if encounter == nil {
                ScrollChips {
                    ForEach(TimePreset.allCases) { preset in
                        ChoiceChip(title: preset.title, symbol: preset.symbol, selected: preset.matches(date)) {
                            date = preset.date
                        }
                    }
                }
            }
            VStack(alignment: .leading, spacing: 9) {
                FieldLabel(title: "时长", value: durationLabel)
                ScrollViewReader { proxy in
                    ScrollChips {
                        ForEach(Choices.quickDurations, id: \.self) { m in
                            ChoiceChip(title: Choices.durationTitle(m), selected: durationMinutes == m) {
                                durationMinutes = durationMinutes == m ? 0 : m
                            }
                            .id(m)
                        }
                    }
                    .onAppear {
                        if Choices.quickDurations.contains(durationMinutes) {
                            proxy.scrollTo(durationMinutes, anchor: .center)
                        }
                    }
                }
            }
            Toggle(isOn: $overnight) {
                Label("过夜", systemImage: "moon")
            }
            .tint(.accentColor)
        }
    }

    // MARK: 过程

    private var orgasmText: String {
        switch details.herOrgasms {
        case ..<0: return "—"
        case 6...: return "6+"
        default: return "\(details.herOrgasms)"
        }
    }

    /// 「安全词：红灯」，多人时带上名字
    private var safeWords: String {
        let pairs = girls.compactMap { g -> (String, String)? in
            let word = g.details.safeWord.trimmed
            return word.isEmpty ? nil : (g.name, word)
        }
        guard !pairs.isEmpty else { return "" }
        if pairs.count == 1 { return "安全词：\(pairs[0].1)" }
        return "安全词：" + pairs.map { "\($0.0) \($0.1)" }.joined(separator: "，")
    }

    private var processCard: some View {
        RecordCard("过程") {
            HStack(spacing: 10) {
                CounterTile(title: "回合", value: "\(count)",
                            canDecrement: count > 0, canIncrement: count < 20, identifier: "rounds",
                            onDecrement: { count = max(count - 1, 0) },
                            onIncrement: { count = min(count + 1, 20) })
                CounterTile(title: "她高潮", value: orgasmText,
                            caption: details.herOrgasms < 0 ? "未记录" : (details.herOrgasms == 0 ? "没有" : "次"),
                            canDecrement: details.herOrgasms >= 0, canIncrement: details.herOrgasms < 6,
                            identifier: "orgasms",
                            onDecrement: { details.herOrgasms = max(details.herOrgasms - 1, -1) },
                            onIncrement: {
                                details.herOrgasms = details.herOrgasms < 0 ? 1 : min(details.herOrgasms + 1, 6)
                            })
            }
            VStack(alignment: .leading, spacing: 10) {
                FieldLabel(title: "强度", value: Intensity.title(details.intensity))
                IntensityPicker(value: $details.intensity)
                // 玩得重的时候，把她约好的安全词放在眼前
                if details.intensity >= Intensity.intense.rawValue {
                    let words = safeWords
                    if !words.isEmpty {
                        Label(words, systemImage: "lock.shield")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .transition(.opacity)
                    }
                }
            }
            .padding(.top, 2)
            VStack(alignment: .leading, spacing: 10) {
                FieldLabel(title: "谁主导")
                PillChoice(options: Choices.leads, selection: $details.lead, identifier: "lead")
            }
        }
    }

    // MARK: 玩法与道具

    /// 只选了一个人时，她档案里的偏好（用来给选项标小红心）
    private var herPreferences: GirlDetails? {
        girls.count == 1 ? girls.first?.details : nil
    }

    /// 她档案里写的底线，记玩法的时候放在眼前
    private var boundaryNotes: [(name: String, text: String)] {
        girls.compactMap { g -> (name: String, text: String)? in
            let text = g.details.boundaries.trimmed
            return text.isEmpty ? nil : (name: g.name, text: text)
        }
    }

    private var playCard: some View {
        let liked = herPreferences
        let limits = boundaryNotes
        return RecordCard("玩法与道具") {
            if !limits.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(limits, id: \.name) { item in
                        Label(girls.count == 1 ? "她的底线：\(item.text)" : "\(item.name)的底线：\(item.text)",
                              systemImage: "hand.raised")
                            .font(.footnote)
                            .foregroundStyle(Palette.period)
                    }
                }
            }
            VStack(spacing: 0) {
                TagDisclosure(title: "体位", symbol: "square.grid.2x2", key: .positions, selection: $details.positions,
                              marked: Set(liked?.likedPositions ?? []))
                RowDivider()
                TagDisclosure(title: "玩法", symbol: "wand.and.stars", key: .play, selection: $details.play,
                              marked: Set(liked?.likedPlay ?? []))
                RowDivider()
                TagDisclosure(title: "道具", symbol: "sparkles", key: .toys, selection: $details.toys,
                              marked: Set(liked?.likedToys ?? []))
                RowDivider()
                TagDisclosure(title: "穿着", symbol: "tshirt", key: .outfits, selection: $details.outfits)
            }
        }
    }

    // MARK: 安全

    private var safetyCard: some View {
        RecordCard("安全", trailing: {
            if protection != .unrecorded {
                Text(protection.title)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(protection.color)
                    .transition(.opacity)
            }
        }) {
            ProtectionPicker(value: $protection)
            if protection == .condom || protection == .both {
                Toggle("破套 / 中途摘了", isOn: $condomBroke)
                    .tint(Palette.fertile)
            }
            if pregnancyRisk {
                Toggle("已吃紧急避孕药", isOn: $details.pillTaken)
                    .tint(Palette.status)
            }
            if isRisky {
                Label("有风险：保存后会提醒你按时间做检测。", systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(Palette.fertile)
                    .transition(.opacity)
            }
        }
    }

    // MARK: 感受

    private var feelingCard: some View {
        RecordCard("感受") {
            ratingRow("满意度", value: $rating, identifier: "rating")
            ratingRow("化学反应", value: $details.chemistry, identifier: "chemistry")
            Divider()
            VStack(spacing: 0) {
                TagDisclosure(title: "氛围", symbol: "theatermasks", key: .moods, selection: $details.moods)
                RowDivider()
                TagDisclosure(title: "她的反馈", symbol: "text.bubble", key: .feedback, selection: $details.feedback)
                RowDivider()
                TagDisclosure(title: "事后照顾", symbol: "hands.sparkles", key: .aftercare, selection: $details.aftercare,
                              marked: Set(herPreferences?.aftercareNeeds ?? []))
            }
        }
    }

    private func ratingRow(_ title: String, value: Binding<Int>, identifier: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(RatingWords.word(value.wrappedValue) ?? "未评")
                    .font(.caption)
                    .foregroundStyle(value.wrappedValue > 0 ? Palette.gold : Color.secondary)
                    .contentTransition(.opacity)
            }
            Spacer(minLength: 8)
            StarPicker(value: value, identifier: identifier)
        }
    }

    // MARK: 约会

    private var dateCard: some View {
        RecordCard("约会") {
            TagDisclosure(title: "约会内容", symbol: "fork.knife", key: .activities, selection: $details.activities)
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                FieldLabel(title: "谁主动约的")
                PillChoice(options: Choices.initiatorChoices, selection: $details.initiator, identifier: "initiator")
            }
        }
    }

    // MARK: 花费

    private var costCard: some View {
        RecordCard("花费", trailing: {
            if details.totalCost > 0 {
                Text("合计 \(Fmt.money(details.totalCost))")
                    .font(.footnote.weight(.semibold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
        }) {
            if !details.expenses.isEmpty {
                VStack(spacing: 10) {
                    ForEach($details.expenses) { $item in
                        expenseRow($item)
                    }
                }
            }
            // 按类别直接加一笔，不用先加再去菜单里改类别
            let categories = config.options(.expenseCategories)
            if categories.isEmpty {
                Button {
                    withAnimation(.snappy) { details.expenses.append(ExpenseItem()) }
                } label: {
                    Label("添加一笔", systemImage: "plus")
                        .font(.subheadline.weight(.medium))
                }
                .buttonStyle(.borderless)
            } else {
                ScrollChips {
                    ForEach(categories, id: \.self) { category in
                        Button {
                            withAnimation(.snappy) {
                                details.expenses.append(ExpenseItem(category: category))
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "plus")
                                    .font(.caption2.weight(.semibold))
                                Text(category)
                            }
                            .font(.subheadline)
                            .foregroundStyle(Color.accentColor)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Capsule().fill(Color.accentColor.opacity(0.08)))
                            .contentShape(Capsule())
                        }
                        .buttonStyle(.chip)
                        .accessibilityLabel("加一笔\(category)")
                    }
                }
            }
        }
    }

    private func expenseRow(_ item: Binding<ExpenseItem>) -> some View {
        HStack(spacing: 10) {
            Menu {
                ForEach(config.options(.expenseCategories), id: \.self) { c in
                    Button(c) { item.wrappedValue.category = c }
                }
            } label: {
                HStack(spacing: 3) {
                    Text(item.wrappedValue.category)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(Palette.fill))
            }
            TextField("说明", text: item.note)
                .font(.subheadline)
            DecimalField(title: "¥ 0", value: item.amount)
                .font(.subheadline.monospacedDigit())
                .frame(width: 84)
            Button {
                removeExpense(item.wrappedValue.id)
            } label: {
                Image(systemName: "minus.circle.fill")
                    .font(.system(size: 18))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("删除这笔")
        }
    }

    /// 先收起键盘再删，避免输入框还绑着这一行
    private func removeExpense(_ id: UUID) {
        hideKeyboard()
        DispatchQueue.main.async {
            withAnimation(.snappy) { details.expenses.removeAll { $0.id == id } }
        }
    }

    // MARK: 备注和照片

    private var noteCard: some View {
        RecordCard("备注") {
            TextField("细节、对话、下次想试的…", text: $details.notes, axis: .vertical)
                .lineLimit(4...14)
        }
    }

    private var photoCard: some View {
        RecordCard("照片与视频", trailing: {
            Text("原画质")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
        }) {
            VStack(alignment: .leading, spacing: 12) {
                MediaGrid(ids: $details.photoIDs)
                if let photoDate, abs(photoDate.timeIntervalSince(date)) > 30 * 60 {
                    Button {
                        withAnimation(.snappy) { date = photoDate }
                        Haptics.light()
                    } label: {
                        Label("按拍摄时间填：\(Fmt.row(photoDate))", systemImage: "camera")
                            .font(.footnote.weight(.medium))
                    }
                    .buttonStyle(.borderless)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                    .accessibilityIdentifier("usePhotoDate")
                }
            }
        }
        .task(id: details.photoIDs) {
            // 只看这次新加的
            let ids = details.photoIDs.filter { !originalPhotos.contains($0) }
            sessionMedia.formUnion(ids)
            let earliest = await Task.detached(priority: .utility) { () -> Date? in
                ids.compactMap { MediaStore.shared.info($0)?.capturedAt }.min()
            }.value
            withAnimation(.snappy) { photoDate = earliest }
        }
    }

    // MARK: Actions

    private func cancel() {
        if isDirty {
            confirmDiscard = true
        } else {
            discard()
        }
    }

    private func discard() {
        let added = Set(details.photoIDs).subtracting(originalPhotos).union(sessionMedia)
        MediaStore.shared.delete(Array(added))
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

        // 在这里勾选的特质写回她的档案
        let changes = traitChanges
        for girl in girls {
            if let edited = changes[girl.id] {
                girl.update { $0.traits = edited }
            }
        }

        // 第一次发生关系：把"暧昧中"自动改成"在约"
        for girl in girls where girl.status == .flirting {
            girl.status = .active
            girl.update { $0.statusHistory.append(StatusChange(date: Date(), status: RelationStatus.active.rawValue)) }
        }

        let removed = originalPhotos.union(sessionMedia).subtracting(d.photoIDs)
        MediaStore.shared.delete(Array(removed))

        try? context.save()
        Haptics.success()
        AchievementCenter.shared.refresh(context: context)

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

/// 记录表单里一点即选的头像
struct QuickPickAvatar: View {
    let girl: Girl
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                AvatarView(photoID: girl.avatarID, name: girl.name, size: 46)
                    .overlay(alignment: .bottomTrailing) {
                        if selected {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 17))
                                .foregroundStyle(.white, Color.accentColor)
                                .background(Circle().fill(Color(uiColor: .systemBackground)).padding(1))
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .scaleEffect(selected ? 1.0 : 0.94)
                    .opacity(selected ? 1 : 0.75)
                Text(girl.name)
                    .font(.caption2.weight(selected ? .semibold : .regular))
                    .foregroundStyle(selected ? Color.primary : Color.secondary)
                    .lineLimit(1)
                    .frame(width: 54)
            }
        }
        .buttonStyle(.chip)
        .sensoryFeedback(.selection, trigger: selected)
        .accessibilityLabel(girl.name)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

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
        .paperBackground()
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
