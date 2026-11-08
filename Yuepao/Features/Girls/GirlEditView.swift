import SwiftUI
import SwiftData
import PhotosUI
import CoreLocation

struct GirlDraft {
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

struct GirlEditView: View {
    let girl: Girl?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Girl.createdAt) private var allGirls: [Girl]
    @ObservedObject private var config = ConfigStore.shared

    @State private var draft: GirlDraft
    @State private var avatarItem: PhotosPickerItem?
    @State private var newPhotoIDs: [String] = []
    private let originalAvatar: String?

    init(girl: Girl?) {
        self.girl = girl
        _draft = State(initialValue: GirlDraft(girl))
        originalAvatar = girl?.avatarID
    }

    var body: some View {
        NavigationStack {
            Form {
                Group {
                    basicSection
                    bodySection
                    socialSection
                    contactSection
                    metSection
                }
                Group {
                    haremSection
                    connectionSection
                    preferenceSection
                    intimacySection
                    customSection
                    notesSection
                }
            }
            .navigationTitle(girl == nil ? "新建档案" : "编辑档案")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { cancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
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
                        draft.avatarID = id
                    }
                    avatarItem = nil
                }
            }
        }
        .interactiveDismissDisabled()
    }

    // MARK: Sections

    private var basicSection: some View {
        Section {
            HStack(spacing: 16) {
                AvatarView(photoID: draft.avatarID, name: draft.name.isEmpty ? "?" : draft.name, size: 64)
                VStack(alignment: .leading, spacing: 8) {
                    PhotosPicker(selection: $avatarItem, matching: .images) {
                        Text(draft.avatarID == nil ? "选择头像" : "更换头像")
                    }
                    .buttonStyle(.borderless)
                    if draft.avatarID != nil {
                        Button("移除头像", role: .destructive) { draft.avatarID = nil }
                            .buttonStyle(.borderless)
                            .font(.footnote)
                    }
                }
            }
            TextField("代号 / 昵称（必填）", text: $draft.name)
                .accessibilityIdentifier("girlName")
            TextField("真名（默认隐藏）", text: $draft.details.realName)
            OptionalDateRow(title: "生日", date: $draft.details.birthday)
            if let age = Fmt.age(draft.details.birthday) {
                LabeledContent("年龄 / 星座", value: "\(age) 岁 · \(Fmt.zodiac(draft.details.birthday) ?? "")")
            }
            TextField("MBTI", text: $draft.details.mbti)
                .textInputAutocapitalization(.characters)
            OptionMultiPicker(title: "性格", key: .personality, selection: $draft.details.personality)
            OptionMultiPicker(title: "标签", key: .tags, selection: $draft.details.tags)
        } header: {
            Text("基本信息")
        }
    }

    private var bodySection: some View {
        Section("身材外貌") {
            IntField(title: "身高", value: $draft.details.height, unit: "cm")
            IntField(title: "体重", value: $draft.details.weight, unit: "kg")
            OptionSinglePicker(title: "罩杯", key: .cups, selection: $draft.details.cup)
            HStack {
                Text("三围")
                Spacer()
                measurement("胸", $draft.details.bust)
                measurement("腰", $draft.details.waist)
                measurement("臀", $draft.details.hips)
            }
            OptionSinglePicker(title: "体型", key: .bodyTypes, selection: $draft.details.bodyType)
            TextField("外貌特征（发型、纹身、痣…）", text: $draft.details.appearance, axis: .vertical)
        }
    }

    private func measurement(_ label: String, _ value: Binding<Int?>) -> some View {
        TextField(label, text: Binding(
            get: { value.wrappedValue.map { String($0) } ?? "" },
            set: { text in value.wrappedValue = Int(text.filter { $0.isASCII && $0.isNumber }) }
        ))
        .keyboardType(.numberPad)
        .multilineTextAlignment(.center)
        .frame(width: 48)
        .textFieldStyle(.roundedBorder)
    }

    private var socialSection: some View {
        Section("社会信息") {
            TextField("职业 / 行业", text: $draft.details.occupation)
            OptionSinglePicker(title: "学历", key: .education, selection: $draft.details.education)
            TextField("学校", text: $draft.details.school)
            TextField("籍贯", text: $draft.details.hometown)
            OptionSinglePicker(title: "感情状况", key: .maritalStatus, selection: $draft.details.maritalStatus)
            NavigationLink {
                LocationPickerView(initial: draft.coordinate) { picked in
                    draft.latitude = picked.coordinate.latitude
                    draft.longitude = picked.coordinate.longitude
                    if !picked.city.isEmpty { draft.city = picked.city }
                    if !picked.district.isEmpty { draft.details.district = picked.district }
                }
            } label: {
                LabeledContent("常驻位置（地图用）") {
                    Text(draft.coordinate == nil ? "未设置" : "已设置").foregroundStyle(.secondary)
                }
            }
            if draft.coordinate != nil {
                Button("清除位置", role: .destructive) {
                    draft.latitude = nil
                    draft.longitude = nil
                }
            }
            TextField("城市", text: $draft.city)
            TextField("常驻区域（区 / 商圈）", text: $draft.details.district)
        }
    }

    private var contactSection: some View {
        Section {
            ForEach($draft.details.contacts) { $contact in
                HStack {
                    Menu {
                        ForEach(config.options(.contactTypes), id: \.self) { t in
                            Button(t) { contact.type = t }
                        }
                    } label: {
                        Text(contact.type).frame(minWidth: 60, alignment: .leading)
                    }
                    TextField("账号 / 号码", text: $contact.value)
                }
            }
            .onDelete { draft.details.contacts.remove(atOffsets: $0) }
            Button {
                draft.details.contacts.append(ContactItem(type: config.options(.contactTypes).first ?? "微信"))
            } label: {
                Label("添加联系方式", systemImage: "plus")
            }
        } header: {
            Text("联系方式")
        }
    }

    private var metSection: some View {
        Section("认识经过") {
            OptionSinglePicker(title: "认识渠道", key: .channels, selection: $draft.details.channel)
            OptionalDateRow(title: "认识日期", date: $draft.details.metDate)
            OptionalDateRow(title: "首次见面", date: $draft.details.firstDateDate)
            TextField("介绍人", text: $draft.details.introducer)
            TextField("怎么认识的", text: $draft.details.howWeMet, axis: .vertical)
        }
    }

    private var haremSection: some View {
        Section {
            Picker("位分", selection: $draft.rank) {
                Text("未设置").tag("")
                ForEach(rankOptions, id: \.self) { r in
                    Text(r).tag(r)
                }
            }
            Picker("关系状态", selection: $draft.status) {
                ForEach(RelationStatus.allCases) { s in
                    Text(s.title).tag(s)
                }
            }
            VStack(alignment: .leading) {
                LabeledContent("亲密度", value: "\(draft.details.intimacy)")
                Slider(value: Binding(
                    get: { Double(draft.details.intimacy) },
                    set: { draft.details.intimacy = Int($0) }
                ), in: 0...100, step: 1)
            }
            ScorePicker(title: "颜值", value: $draft.details.ratingLooks)
            ScorePicker(title: "身材", value: $draft.details.ratingBody)
            ScorePicker(title: "性格", value: $draft.details.ratingPersonality)
            ScorePicker(title: "床上表现", value: $draft.details.ratingSex)
            ScorePicker(title: "综合", value: $draft.details.ratingOverall)
            Picker("她知道你有别人吗", selection: $draft.details.awarenessLevel) {
                ForEach(Awareness.allCases) { a in
                    Text(a.title).tag(a)
                }
            }
            Picker("联系频率目标", selection: $draft.details.contactGoalDays) {
                ForEach(Choices.contactGoals, id: \.self) { d in
                    Text(d == 0 ? "不提醒" : "至少 \(d) 天一次").tag(d)
                }
            }
        } header: {
            Text("后宫属性")
        } footer: {
            Text("超过联系频率目标没见面 / 没联系，会出现在统计页的冷落名单里。")
        }
    }

    private var rankOptions: [String] {
        let opts = config.options(.ranks)
        return draft.rank.isEmpty || opts.contains(draft.rank) ? opts : opts + [draft.rank]
    }

    private var otherGirls: [Girl] {
        allGirls.filter { $0.id != girl?.id }
    }

    private var connectionSection: some View {
        Section {
            ForEach($draft.details.connections) { $conn in
                HStack {
                    Picker("", selection: $conn.girlID) {
                        Text("选择").tag(UUID?.none)
                        ForEach(otherGirls) { g in
                            Text(g.name).tag(UUID?.some(g.id))
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                    TextField("关系（闺蜜 / 同事…）", text: $conn.relation)
                }
            }
            .onDelete { draft.details.connections.remove(atOffsets: $0) }
            if !otherGirls.isEmpty {
                Button {
                    draft.details.connections.append(Connection())
                } label: {
                    Label("添加关联档案", systemImage: "plus")
                }
            }
        } header: {
            Text("社交圈交集")
        } footer: {
            Text("记下她和其他档案的关系，避免撞车。")
        }
    }

    private var preferenceSection: some View {
        Section("偏好与雷区") {
            TextField("爱吃", text: $draft.details.favoriteFood, axis: .vertical)
            TextField("忌口", text: $draft.details.dislikedFood, axis: .vertical)
            TextField("喜欢的饮品", text: $draft.details.drinks, axis: .vertical)
            TextField("爱好", text: $draft.details.hobbies, axis: .vertical)
            TextField("喜欢的礼物 / 品牌", text: $draft.details.giftPrefs, axis: .vertical)
            TextField("雷点 / 禁忌话题", text: $draft.details.taboos, axis: .vertical)
        }
    }

    private var intimacySection: some View {
        Section("亲密偏好") {
            OptionMultiPicker(title: "喜欢的体位", key: .positions, selection: $draft.details.likedPositions)
            OptionMultiPicker(title: "喜欢的玩法", key: .play, selection: $draft.details.likedPlay)
            TextField("敏感点", text: $draft.details.sensitiveSpots, axis: .vertical)
            TextField("边界 / 明确不接受的", text: $draft.details.boundaries, axis: .vertical)
            TextField("避孕约定", text: $draft.details.contraception, axis: .vertical)
            Stepper("经期一般持续 \(draft.details.periodLength) 天", value: $draft.details.periodLength, in: 2...10)
        }
    }

    @ViewBuilder
    private var customSection: some View {
        if !config.config.customFields.isEmpty {
            Section("自定义字段") {
                ForEach(config.config.customFields) { field in
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

    private var notesSection: some View {
        Section("备注") {
            TextField("其他想记的", text: $draft.details.notes, axis: .vertical)
                .lineLimit(3...10)
        }
    }

    // MARK: Actions

    private func cancel() {
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
        Reminders.rescheduleDates(girls: isNew ? allGirls + [target] : allGirls)
        dismiss()
    }
}

struct CustomFieldInput: View {
    let field: CustomFieldDef
    @Binding var value: String

    var body: some View {
        switch field.kind {
        case .text:
            TextField(field.name, text: $value, axis: .vertical)
        case .number:
            LabeledContent(field.name) {
                TextField("—", text: $value)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
            }
        case .rating:
            Picker(field.name, selection: $value) {
                Text("未评").tag("")
                ForEach(Array(1...10), id: \.self) { n in
                    Text("\(n) 分").tag("\(n)")
                }
            }
        case .choice:
            Picker(field.name, selection: $value) {
                Text("未选择").tag("")
                ForEach(field.options, id: \.self) { o in
                    Text(o).tag(o)
                }
                if !value.isEmpty && !field.options.contains(value) {
                    Text(value).tag(value)
                }
            }
        }
    }
}
