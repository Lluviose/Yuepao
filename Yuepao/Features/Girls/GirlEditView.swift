import SwiftUI
import SwiftData
import PhotosUI
import CoreLocation

struct GirlDraft: Equatable {
    var name = ""
    var status: RelationStatus = .flirting
    var rank = ""
    var city = ""
    var latitude: Double?
    var longitude: Double?
    var avatarID: String?
    var details = GirlDetails()

    init(_ girl: Girl?) {
        guard let girl else { return }
        name = girl.name
        status = girl.status
        rank = girl.rank
        city = girl.city
        latitude = girl.latitude
        longitude = girl.longitude
        avatarID = girl.avatarID
        details = girl.details
    }

    var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    func apply(to girl: Girl, isNew: Bool) {
        var d = details
        if isNew || girl.status != status {
            d.statusHistory.append(StatusChange(date: Date(), status: status.rawValue))
        }
        girl.name = name.trimmed
        girl.status = status
        girl.rank = rank
        girl.city = city.trimmed
        girl.latitude = latitude
        girl.longitude = longitude
        girl.avatarID = avatarID
        d.contacts = d.contacts.filter { !$0.value.trimmed.isEmpty }
        girl.details = d
    }
}

/// 新建 / 编辑档案：顶部是头像、代号、关系和位分，其余资料按类别折叠成卡片，收起时显示已填的摘要
struct GirlEditView: View {
    let girl: Girl?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Girl.createdAt) private var allGirls: [Girl]
    @ObservedObject private var config = ConfigStore.shared

    @State private var draft: GirlDraft
    @State private var avatarItem: PhotosPickerItem?
    @State private var newPhotoIDs: [String] = []
    @State private var confirmDiscard = false
    @FocusState private var nameFocused: Bool
    private let originalAvatar: String?
    private let initialDraft: GirlDraft

    init(girl: Girl?) {
        self.girl = girl
        let d = GirlDraft(girl)
        _draft = State(initialValue: d)
        initialDraft = d
        originalAvatar = girl?.avatarID
    }

    private var isNew: Bool { girl == nil }

    private var isDirty: Bool { draft != initialDraft || !newPhotoIDs.isEmpty }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    identityCard
                    basicCard
                    metCard
                    bodyCard
                    socialCard
                    contactCard
                    haremCard
                    circleCard
                    preferenceCard
                    intimacyCard
                    customCard
                    notesCard
                }
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .padding(.bottom, 36)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .formKeyboardHandling()
            .navigationTitle(isNew ? "新建档案" : "编辑档案")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { cancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .fontWeight(.semibold)
                        .disabled(draft.name.trimmed.isEmpty)
                        .accessibilityIdentifier("saveGirl")
                }
            }
            .onChange(of: avatarItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let id = PhotoStore.shared.save(data: data) {
                        newPhotoIDs.append(id)
                        withAnimation(.snappy(duration: 0.35)) { draft.avatarID = id }
                    }
                    avatarItem = nil
                }
            }
            .onAppear {
                guard isNew else { return }
                // 等弹窗动画结束再弹键盘
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { nameFocused = true }
            }
        }
        .interactiveDismissDisabled(isDirty)
        .confirmationDialog("放弃这次的修改？", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("放弃修改", role: .destructive) { discard() }
            Button("继续编辑", role: .cancel) {}
        }
    }

    // MARK: 头像、代号、关系、位分

    private var identityCard: some View {
        VStack(spacing: 18) {
            VStack(spacing: 10) {
                avatarPicker
                if draft.avatarID != nil {
                    Button("移除头像", role: .destructive) {
                        withAnimation(.snappy(duration: 0.3)) { draft.avatarID = nil }
                    }
                    .font(.caption)
                    .buttonStyle(.borderless)
                    .transition(.opacity)
                }
            }
            VStack(spacing: 8) {
                TextField("她的代号", text: $draft.name)
                    .font(Typo.display(28))
                    .multilineTextAlignment(.center)
                    .submitLabel(.done)
                    .focused($nameFocused)
                    .accessibilityIdentifier("girlName")
                Capsule()
                    .fill(nameFocused ? Color.accentColor : Color.secondary.opacity(0.25))
                    .frame(width: nameFocused ? 120 : 72, height: nameFocused ? 2 : 1)
                    .animation(.snappy(duration: 0.25), value: nameFocused)
                if isNew {
                    Text("代号会显示在列表和地图上，真名可以在「基本信息」里单独填")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                FieldLabel(title: "关系")
                StatusPicker(status: $draft.status)
            }
            VStack(alignment: .leading, spacing: 10) {
                FieldLabel(title: "位分")
                TagCloud(key: .ranks, selection: $draft.rank.asSingleSelection, tint: Palette.gold)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 24)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity)
        .background { identityBackground }
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    private var avatarPicker: some View {
        PhotosPicker(selection: $avatarItem, matching: .images) {
            AvatarView(photoID: draft.avatarID, name: draft.name.trimmed.isEmpty ? "?" : draft.name, size: 104)
                .overlay(Circle().stroke(Color.white.opacity(0.75), lineWidth: 3))
                .shadow(color: .black.opacity(0.16), radius: 16, y: 8)
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: draft.avatarID == nil ? "camera.fill" : "arrow.triangle.2.circlepath")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(Color.accentColor))
                        .overlay(Circle().stroke(Color(uiColor: .secondarySystemGroupedBackground), lineWidth: 3))
                        .offset(x: 2, y: 2)
                }
                .id(draft.avatarID ?? "none")
                .transition(.scale(scale: 0.9).combined(with: .opacity))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(draft.avatarID == nil ? "选择头像" : "更换头像")
        .accessibilityIdentifier("pickAvatar")
    }

    /// 有头像时用模糊的照片做底；没有时用代号对应的色调，边输入边变
    private var identityBackground: some View {
        let card = Color(uiColor: .secondarySystemGroupedBackground)
        return ZStack {
            card
            if let id = draft.avatarID, let image = PhotoStore.shared.thumbnail(id, size: 240) {
                Color.clear
                    .overlay {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .blur(radius: 40)
                            .opacity(0.45)
                    }
                    .clipped()
            } else {
                Palette.avatarGradient(for: draft.name.trimmed.isEmpty ? "?" : draft.name)
                    .opacity(0.3)
                    .animation(.smooth(duration: 0.6), value: draft.name)
            }
            LinearGradient(colors: [.clear, card.opacity(0.96)],
                           startPoint: UnitPoint(x: 0.5, y: 0.2), endPoint: UnitPoint(x: 0.5, y: 0.62))
        }
    }

    // MARK: 基本信息

    private var basicSummary: String {
        let d = draft.details
        let age = Fmt.age(d.birthday).map { "\($0) 岁" }
        return FoldCardSummary.join([age, Fmt.zodiac(d.birthday), d.mbti,
                                     d.personality.prefix(3).joined(separator: "、")])
    }

    private var basicCard: some View {
        FoldCard("基本信息", symbol: "person.text.rectangle", summary: basicSummary,
                 expanded: isNew, identifier: "fold-basic") {
            CardField(title: "真名", text: $draft.details.realName, prompt: "只有你看得到，默认打码")
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                DateFieldRow(title: "生日", date: $draft.details.birthday, yearsAgo: 24)
                if let age = Fmt.age(draft.details.birthday) {
                    Text("\(age) 岁 · \(Fmt.zodiac(draft.details.birthday) ?? "")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .transition(.opacity)
                }
            }
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                FieldLabel(title: "MBTI")
                MBTIPicker(mbti: $draft.details.mbti)
            }
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                FieldLabel(title: "性格")
                TagCloud(key: .personality, selection: $draft.details.personality)
            }
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                FieldLabel(title: "标签")
                TagCloud(key: .tags, selection: $draft.details.tags, tint: Palette.gold)
            }
        }
    }

    // MARK: 认识经过

    private var metSummary: String {
        let d = draft.details
        return FoldCardSummary.join([d.channel, d.metDate.map { "认识于 " + Fmt.date($0) },
                                     d.introducer.trimmed.isEmpty ? nil : "\(d.introducer)介绍"])
    }

    private var metCard: some View {
        FoldCard("认识经过", symbol: "bubble.left.and.bubble.right", summary: metSummary,
                 expanded: isNew, identifier: "fold-met") {
            VStack(alignment: .leading, spacing: 10) {
                FieldLabel(title: "认识渠道")
                TagCloud(key: .channels, selection: $draft.details.channel.asSingleSelection)
            }
            Divider()
            DateFieldRow(title: "认识日期", date: $draft.details.metDate)
            Divider()
            DateFieldRow(title: "首次见面", date: $draft.details.firstDateDate)
            Divider()
            CardField(title: "介绍人", text: $draft.details.introducer)
            Divider()
            CardField(title: "怎么认识的", text: $draft.details.howWeMet,
                      prompt: "第一次聊了什么、怎么约出来的…", multiline: true)
        }
    }

    // MARK: 身材外貌

    private var bodySummary: String {
        let d = draft.details
        let hasMeasures = d.bust != nil || d.waist != nil || d.hips != nil
        let measures = hasMeasures
            ? [d.bust, d.waist, d.hips].map { v in v.map { "\($0)" } ?? "?" }.joined(separator: "-")
            : nil
        return FoldCardSummary.join([d.height.map { "\($0) cm" }, d.weight.map { "\($0) kg" },
                                     d.cup.isEmpty ? nil : "\(d.cup) 罩杯", measures, d.bodyType])
    }

    private var bodyCard: some View {
        FoldCard("身材外貌", symbol: "figure.stand", summary: bodySummary, identifier: "fold-body") {
            HStack(spacing: 10) {
                NumberTile(title: "身高", value: $draft.details.height, unit: "cm")
                NumberTile(title: "体重", value: $draft.details.weight, unit: "kg")
            }
            HStack(spacing: 10) {
                NumberTile(title: "胸围", value: $draft.details.bust, unit: "cm", size: 20)
                NumberTile(title: "腰围", value: $draft.details.waist, unit: "cm", size: 20)
                NumberTile(title: "臀围", value: $draft.details.hips, unit: "cm", size: 20)
            }
            VStack(alignment: .leading, spacing: 10) {
                FieldLabel(title: "罩杯")
                TagCloud(key: .cups, selection: $draft.details.cup.asSingleSelection)
            }
            VStack(alignment: .leading, spacing: 10) {
                FieldLabel(title: "体型")
                TagCloud(key: .bodyTypes, selection: $draft.details.bodyType.asSingleSelection)
            }
            Divider()
            CardField(title: "外貌特征", text: $draft.details.appearance,
                      prompt: "发型、纹身、痣、穿衣风格…", multiline: true)
        }
    }

    // MARK: 社会信息

    private var socialSummary: String {
        let d = draft.details
        let place = [draft.city, d.district].map(\.trimmed).filter { !$0.isEmpty }.joined(separator: " ")
        return FoldCardSummary.join([d.occupation, d.education, place, d.maritalStatus])
    }

    private var socialCard: some View {
        FoldCard("社会信息", symbol: "briefcase", summary: socialSummary, identifier: "fold-social") {
            Group {
                CardField(title: "职业 / 行业", text: $draft.details.occupation)
                Divider()
                VStack(alignment: .leading, spacing: 10) {
                    FieldLabel(title: "学历")
                    TagCloud(key: .education, selection: $draft.details.education.asSingleSelection)
                }
                Divider()
                CardField(title: "学校", text: $draft.details.school)
                Divider()
                CardField(title: "籍贯", text: $draft.details.hometown)
                Divider()
            }
            Group {
                VStack(alignment: .leading, spacing: 10) {
                    FieldLabel(title: "感情状况")
                    TagCloud(key: .maritalStatus, selection: $draft.details.maritalStatus.asSingleSelection)
                }
                Divider()
                CardField(title: "城市", text: $draft.city)
                Divider()
                CardField(title: "常驻区域", text: $draft.details.district, prompt: "区 / 商圈")
                Divider()
                locationRow
            }
        }
    }

    private var locationRow: some View {
        HStack(spacing: 10) {
            NavigationLink {
                LocationPickerView(initial: draft.coordinate) { picked in
                    draft.latitude = picked.coordinate.latitude
                    draft.longitude = picked.coordinate.longitude
                    if !picked.city.isEmpty { draft.city = picked.city }
                    if !picked.district.isEmpty { draft.details.district = picked.district }
                }
            } label: {
                HStack(spacing: 12) {
                    IconBadge(symbol: "mappin.and.ellipse", color: .accentColor, size: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("常驻位置")
                            .foregroundStyle(.primary)
                        Text(draft.coordinate == nil ? "设置后她会出现在地图上" : "已设置")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if draft.coordinate != nil {
                removeButton {
                    withAnimation(.snappy) {
                        draft.latitude = nil
                        draft.longitude = nil
                    }
                }
            }
        }
    }

    // MARK: 联系方式

    private var contactCard: some View {
        let types = draft.details.contacts.filter { !$0.value.trimmed.isEmpty }.map(\.type)
        return FoldCard("联系方式", symbol: "phone",
                        summary: types.isEmpty ? FoldCardSummary.empty : types.joined(separator: "、"),
                        identifier: "fold-contacts") {
            ForEach($draft.details.contacts) { $contact in
                HStack(spacing: 10) {
                    Menu {
                        ForEach(config.options(.contactTypes), id: \.self) { t in
                            Button(t) { contact.type = t }
                        }
                    } label: {
                        menuPill(contact.type)
                    }
                    TextField("账号 / 号码", text: $contact.value)
                    removeButton { removeContact(contact.id) }
                }
            }
            addRowButton("添加联系方式") {
                draft.details.contacts.append(ContactItem(type: config.options(.contactTypes).first ?? "微信"))
            }
        }
    }

    // MARK: 后宫属性

    private var haremSummary: String {
        let d = draft.details
        return FoldCardSummary.join(["亲密度 \(d.intimacy)",
                                     d.ratingOverall > 0 ? "综合 \(d.ratingOverall) 分" : nil,
                                     d.awarenessLevel == .unset ? nil : d.awarenessLevel.title])
    }

    private var intimacyBinding: Binding<Double> {
        Binding(get: { Double(draft.details.intimacy) }, set: { draft.details.intimacy = Int($0) })
    }

    private var haremCard: some View {
        FoldCard("后宫属性", symbol: "crown", summary: haremSummary, tint: Palette.gold, identifier: "fold-harem") {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("亲密度")
                    Spacer(minLength: 8)
                    Text("\(draft.details.intimacy)")
                        .font(Typo.display(22, weight: .semibold))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text("/ 100")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                Slider(value: intimacyBinding, in: 0...100, step: 1)
                    .tint(draft.status.color)
            }
            Divider()
            VStack(spacing: 2) {
                ScoreBar(title: "颜值", value: $draft.details.ratingLooks)
                ScoreBar(title: "身材", value: $draft.details.ratingBody)
                ScoreBar(title: "性格", value: $draft.details.ratingPersonality)
                ScoreBar(title: "床上表现", value: $draft.details.ratingSex)
                ScoreBar(title: "综合", value: $draft.details.ratingOverall)
            }
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                FieldLabel(title: "她知道你有别人吗")
                FlowLayout(spacing: 8) {
                    ForEach(Awareness.allCases.filter { $0 != .unset }) { a in
                        ChoiceChip(title: a.title, selected: draft.details.awarenessLevel == a) {
                            draft.details.awarenessLevel = draft.details.awarenessLevel == a ? .unset : a
                        }
                    }
                }
            }
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                FieldLabel(title: "联系频率目标")
                ScrollChips {
                    ForEach(Choices.contactGoals, id: \.self) { days in
                        ChoiceChip(title: days == 0 ? "不提醒" : "\(days) 天", selected: draft.details.contactGoalDays == days) {
                            draft.details.contactGoalDays = days
                        }
                    }
                }
                Text("超过这么多天没见面、没联系，会出现在统计页的冷落名单里。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: 社交圈交集

    private var otherGirls: [Girl] {
        allGirls.filter { $0.id != girl?.id }
    }

    private var circleCard: some View {
        let count = draft.details.connections.filter { $0.girlID != nil }.count
        return FoldCard("社交圈交集", symbol: "person.2",
                        summary: count == 0 ? FoldCardSummary.empty : "和 \(count) 位档案里的人认识",
                        identifier: "fold-circle") {
            ForEach($draft.details.connections) { $conn in
                HStack(spacing: 10) {
                    Menu {
                        Button("不选") { conn.girlID = nil }
                        ForEach(otherGirls) { g in
                            Button(g.name) { conn.girlID = g.id }
                        }
                    } label: {
                        menuPill(otherGirls.first { $0.id == conn.girlID }?.name ?? "选择")
                    }
                    TextField("关系：闺蜜、同事…", text: $conn.relation)
                    removeButton { removeConnection(conn.id) }
                }
            }
            if otherGirls.isEmpty {
                Text("还没有别的档案。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                addRowButton("添加关联档案") {
                    draft.details.connections.append(Connection())
                }
            }
            Text("记下她和其他档案的关系，避免撞车。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: 偏好与雷区

    private var preferenceSummary: String {
        let d = draft.details
        return FoldCardSummary.join([d.favoriteFood, d.hobbies, d.drinks, d.taboos.isEmpty ? nil : "有雷点"])
    }

    private var preferenceCard: some View {
        FoldCard("偏好与雷区", symbol: "heart.text.square", summary: preferenceSummary, identifier: "fold-preference") {
            Group {
                CardField(title: "爱吃", text: $draft.details.favoriteFood, prompt: "日料、火锅…", multiline: true)
                Divider()
                CardField(title: "忌口", text: $draft.details.dislikedFood, multiline: true)
                Divider()
                CardField(title: "喜欢的饮品", text: $draft.details.drinks, multiline: true)
                Divider()
            }
            Group {
                CardField(title: "爱好", text: $draft.details.hobbies, multiline: true)
                Divider()
                CardField(title: "喜欢的礼物 / 品牌", text: $draft.details.giftPrefs, multiline: true)
                Divider()
                CardField(title: "雷点 / 禁忌话题", text: $draft.details.taboos, multiline: true)
            }
        }
    }

    // MARK: 亲密偏好

    private var intimacySummary: String {
        let d = draft.details
        return FoldCardSummary.join([d.traits.prefix(3).joined(separator: "、"),
                                     d.safeWord.trimmed.isEmpty ? nil : "已约定安全词",
                                     d.likedPositions.prefix(2).joined(separator: "、")])
    }

    private var intimacyCard: some View {
        FoldCard("亲密偏好", symbol: "flame", summary: intimacySummary, identifier: "fold-intimacy") {
            VStack(spacing: 0) {
                TagDisclosure(title: "特质 / 性癖", symbol: "tag", key: .traits,
                              selection: $draft.details.traits, tint: Palette.gold)
                RowDivider()
                TagDisclosure(title: "喜欢的体位", symbol: "square.grid.2x2", key: .positions,
                              selection: $draft.details.likedPositions)
                RowDivider()
                TagDisclosure(title: "喜欢的玩法", symbol: "wand.and.stars", key: .play,
                              selection: $draft.details.likedPlay)
                RowDivider()
                TagDisclosure(title: "喜欢的道具", symbol: "sparkles", key: .toys,
                              selection: $draft.details.likedToys)
                RowDivider()
                TagDisclosure(title: "事后需要", symbol: "hands.sparkles", key: .aftercare,
                              selection: $draft.details.aftercareNeeds, tint: Palette.status)
            }
            Divider()
            Group {
                CardField(title: "安全词", text: $draft.details.safeWord, prompt: "约定好叫停的词")
                Divider()
                CardField(title: "底线 / 明确不接受的", text: $draft.details.boundaries, multiline: true)
                Divider()
                CardField(title: "敏感点", text: $draft.details.sensitiveSpots, multiline: true)
                Divider()
                CardField(title: "避孕约定", text: $draft.details.contraception, multiline: true)
                Divider()
            }
            Stepper("经期一般持续 \(draft.details.periodLength) 天", value: $draft.details.periodLength, in: 2...10)
            Text("玩得重一点之前先约好安全词，听到就停。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: 自定义字段、备注

    @ViewBuilder
    private var customCard: some View {
        let fields = config.config.customFields
        if !fields.isEmpty {
            let filled = fields.filter { !(draft.details.customValues[$0.id.uuidString] ?? "").isEmpty }.count
            FoldCard("自定义字段", symbol: "slider.horizontal.3",
                     summary: filled == 0 ? FoldCardSummary.empty : "已填 \(filled) / \(fields.count)",
                     identifier: "fold-custom") {
                ForEach(Array(fields.enumerated()), id: \.element.id) { index, field in
                    if index > 0 { Divider() }
                    CustomFieldInput(field: field, value: customBinding(field.id.uuidString))
                }
            }
        }
    }

    private func customBinding(_ key: String) -> Binding<String> {
        Binding(
            get: { draft.details.customValues[key] ?? "" },
            set: { draft.details.customValues[key] = $0.isEmpty ? nil : $0 }
        )
    }

    private var notesCard: some View {
        let notes = draft.details.notes.trimmed
        return FoldCard("备注", symbol: "note.text", summary: notes.isEmpty ? FoldCardSummary.empty : notes,
                        identifier: "fold-notes") {
            TextField("其他想记的", text: $draft.details.notes, axis: .vertical)
                .lineLimit(3...12)
        }
    }

    // MARK: 小部件

    private func menuPill(_ text: String) -> some View {
        HStack(spacing: 3) {
            Text(text)
                .lineLimit(1)
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .font(.subheadline.weight(.medium))
        .foregroundStyle(.primary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Capsule().fill(Color(uiColor: .tertiarySystemFill)))
    }

    private func removeButton(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "minus.circle.fill")
                .font(.system(size: 18))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("删除")
    }

    private func addRowButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.snappy) { action() }
        } label: {
            Label(title, systemImage: "plus")
                .font(.subheadline.weight(.medium))
        }
        .buttonStyle(.borderless)
    }

    /// 先收起键盘再删，避免输入框还绑着这一行
    private func removeContact(_ id: UUID) {
        hideKeyboard()
        DispatchQueue.main.async {
            withAnimation(.snappy) { draft.details.contacts.removeAll { $0.id == id } }
        }
    }

    private func removeConnection(_ id: UUID) {
        hideKeyboard()
        DispatchQueue.main.async {
            withAnimation(.snappy) { draft.details.connections.removeAll { $0.id == id } }
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
        PhotoStore.shared.delete(newPhotoIDs)
        dismiss()
    }

    private func save() {
        let isNew = girl == nil
        let target: Girl
        if let girl {
            target = girl
        } else {
            target = Girl()
            context.insert(target)
        }
        draft.apply(to: target, isNew: isNew)

        // 清理没用上的新头像，以及被替换掉的旧头像
        let unused = newPhotoIDs.filter { $0 != draft.avatarID }
        var toDelete = unused
        if let old = originalAvatar, old != draft.avatarID { toDelete.append(old) }
        PhotoStore.shared.delete(toDelete)

        try? context.save()
        Haptics.success()
        AchievementCenter.shared.refresh(context: context)
        Reminders.rescheduleDates(girls: isNew ? allGirls + [target] : allGirls)
        dismiss()
    }
}

/// 自定义字段的输入，放在卡片里用
struct CustomFieldInput: View {
    let field: CustomFieldDef
    @Binding var value: String

    private var choices: [String] {
        field.options + (value.isEmpty || field.options.contains(value) ? [] : [value])
    }

    var body: some View {
        switch field.kind {
        case .text:
            CardField(title: field.name, text: $value, multiline: true)
        case .number:
            HStack(spacing: 12) {
                Text(field.name)
                Spacer(minLength: 12)
                TextField("—", text: $value)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
            }
        case .rating:
            ScoreBar(title: field.name, value: Binding(
                get: { Int(value) ?? 0 },
                set: { value = $0 == 0 ? "" : "\($0)" }
            ))
        case .choice:
            VStack(alignment: .leading, spacing: 10) {
                FieldLabel(title: field.name)
                FlowLayout(spacing: 8) {
                    ForEach(choices, id: \.self) { option in
                        ChoiceChip(title: option, selected: value == option) {
                            value = value == option ? "" : option
                        }
                    }
                }
            }
        }
    }
}
