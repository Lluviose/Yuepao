import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Query private var girls: [Girl]
    @Query private var encounters: [Encounter]
    @Query private var places: [Place]

    @AppStorage("lockEnabled") private var lockEnabled = true
    @AppStorage("lockDelay") private var lockDelay: Double = 0
    @AppStorage("notificationsEnabled") private var notificationsEnabled = false
    @AppStorage("discreetNotifications") private var discreetNotifications = true
    @AppStorage("riskReminders") private var riskReminders = true
    @AppStorage("periodReminders") private var periodReminders = false
    @AppStorage("weeklyNudge") private var weeklyNudge = false
    @AppStorage("appearance") private var appearance = AppearanceMode.system.rawValue
    @Environment(\.dismiss) private var dismiss

    @State private var exportSheet = false
    @State private var exportDocument: BackupDocument?
    @State private var exporting = false
    @State private var importing = false
    @State private var importData: Data?
    @State private var importPassword = ""
    @State private var askImportPassword = false
    @State private var pendingRestore: BackupFile?
    @State private var message: String?
    @State private var confirmWipe = false
    @State private var confirmWipeAgain = false

    var body: some View {
        NavigationStack {
            Form {
                securitySection
                appearanceSection
                notificationSection
                customizeSection
                dataSection
                aboutSection
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .sheet(isPresented: $exportSheet) {
                BackupPasswordSheet { password in
                    makeBackup(password: password)
                }
            }
            .fileExporter(isPresented: $exporting, document: exportDocument, contentType: .data,
                          defaultFilename: BackupService.defaultFilename) { result in
                switch result {
                case .success: message = "备份已保存。请记住密码，忘了就打不开。"
                case .failure(let error): message = "保存失败：\(error.localizedDescription)"
                }
                exportDocument = nil
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.data, .item]) { result in
                handleImport(result)
            }
            .alert("输入备份密码", isPresented: $askImportPassword) {
                SecureField("密码", text: $importPassword)
                Button("取消", role: .cancel) {
                    importData = nil
                    importPassword = ""
                }
                Button("解密") { decryptImport() }
            }
            .alert("用备份覆盖当前数据？", isPresented: Binding(
                get: { pendingRestore != nil },
                set: { if !$0 { pendingRestore = nil } }
            )) {
                Button("取消", role: .cancel) { pendingRestore = nil }
                Button("覆盖恢复", role: .destructive) { restore() }
            } message: {
                Text(restoreSummary)
            }
            .alert("提示", isPresented: Binding(
                get: { message != nil },
                set: { if !$0 { message = nil } }
            )) {
                Button("好", role: .cancel) { message = nil }
            } message: {
                Text(message ?? "")
            }
            .confirmationDialog("清空全部数据？", isPresented: $confirmWipe, titleVisibility: .visible) {
                Button("清空", role: .destructive) { confirmWipeAgain = true }
            } message: {
                Text("所有档案、记录、地点、照片都会被删除，无法恢复。建议先导出备份。")
            }
            .alert("真的要清空吗？", isPresented: $confirmWipeAgain) {
                Button("取消", role: .cancel) {}
                Button("确认清空", role: .destructive) { wipe() }
            }
        }
    }

    // MARK: Sections

    private var securitySection: some View {
        Section {
            Toggle("打开时需要\(AppLock.biometryName)", isOn: $lockEnabled)
            if lockEnabled {
                Picker("离开后多久锁定", selection: $lockDelay) {
                    Text("立即").tag(0.0)
                    Text("1 分钟").tag(60.0)
                    Text("5 分钟").tag(300.0)
                    Text("15 分钟").tag(900.0)
                }
            }
        } header: {
            Text("隐私与安全")
        } footer: {
            if !AppLock.canAuthenticate {
                Text("这台设备没有设置锁屏密码，无法启用应用锁。").foregroundStyle(.red)
            } else {
                Text("切到后台时内容会被遮住。主屏幕上的名字和图标是「手账」。")
            }
        }
    }

    private var appearanceSection: some View {
        Section {
            Picker("外观", selection: $appearance) {
                ForEach(AppearanceMode.allCases) { m in
                    Text(m.title).tag(m.rawValue)
                }
            }
            NavigationLink {
                AppIconPicker()
            } label: {
                LabeledContent("App 图标") {
                    Text(AppIconChoice.current.title).foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("外观")
        }
    }

    private var notificationSection: some View {
        Section {
            Toggle("开启提醒", isOn: $notificationsEnabled)
                .onChange(of: notificationsEnabled) { _, on in
                    if on {
                        Task {
                            let granted = await Reminders.requestAuthorization()
                            if !granted {
                                notificationsEnabled = false
                                message = "通知权限被拒绝了，可以去系统设置里打开。"
                            } else {
                                Reminders.rescheduleDates(girls: girls)
                            }
                        }
                    } else {
                        Reminders.removeAll()
                    }
                }
            if notificationsEnabled {
                Toggle("隐藏通知内容", isOn: $discreetNotifications)
                    .onChange(of: discreetNotifications) { _, _ in Reminders.rescheduleDates(girls: girls) }
                Toggle("有风险时提醒做检测", isOn: $riskReminders)
                Toggle("经期提醒（预计前一天晚上）", isOn: $periodReminders)
                    .onChange(of: periodReminders) { _, _ in Reminders.rescheduleDates(girls: girls) }
                Toggle("每周目标提醒（周四晚上）", isOn: $weeklyNudge)
                    .onChange(of: weeklyNudge) { _, _ in AchievementCenter.shared.refresh(context: context) }
            }
        } header: {
            Text("提醒")
        } footer: {
            Text("生日 / 纪念日前一天晚上和当天早上提醒；待办按设定的时间提醒。隐藏内容后，锁屏上只显示「你有一条待办事项」。")
        }
    }

    private var customizeSection: some View {
        Section("自定义") {
            NavigationLink("选项管理（位分、渠道、体位…）") {
                OptionListsView()
            }
            NavigationLink("自定义档案字段") {
                CustomFieldsView()
            }
            NavigationLink("地点管理") {
                PlaceListView()
            }
            NavigationLink("性健康检测记录") {
                HealthTestListView()
            }
        }
    }

    private var dataSection: some View {
        Section {
            Button {
                exportSheet = true
            } label: {
                Label("导出加密备份", systemImage: "square.and.arrow.up")
            }
            Button {
                importing = true
            } label: {
                Label("从备份恢复", systemImage: "square.and.arrow.down")
            }
            Button(role: .destructive) {
                confirmWipe = true
            } label: {
                Label("清空全部数据", systemImage: "trash")
            }
        } header: {
            Text("数据")
        } footer: {
            Text("数据只保存在这台手机上，没有任何联网。删除 App 会丢失全部数据，请定期导出备份到「文件」或电脑。续签时保持覆盖安装即可保留数据。")
        }
    }

    private var aboutSection: some View {
        Section("关于") {
            LabeledContent("版本", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "-")
            LabeledContent("档案 / 记录 / 地点", value: "\(girls.count) / \(encounters.count) / \(places.count)")
            if let error = Persistence.loadError {
                Text("数据库打开失败，当前为临时模式：\(error)").foregroundStyle(.red).font(.footnote)
            }
        }
    }

    private var restoreSummary: String {
        guard let file = pendingRestore else { return "" }
        return "备份时间：\(Fmt.dateTime(file.exportedAt))\n包含 \(file.girls.count) 个档案、\(file.encounters.count) 条记录、\(file.todos?.count ?? 0) 条待办、\(file.places.count) 个地点、\(file.photos.count) 张照片。\n当前 App 里的数据会被全部替换。"
    }

    // MARK: Actions

    private func makeBackup(password: String) {
        do {
            let data = try BackupService.makeBackup(context: context, password: password)
            exportDocument = BackupDocument(data: data)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { exporting = true }
        } catch {
            message = "备份失败：\(error.localizedDescription)"
        }
    }

    private func handleImport(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            do {
                importData = try Data(contentsOf: url)
                importPassword = ""
                askImportPassword = true
            } catch {
                message = "读取文件失败：\(error.localizedDescription)"
            }
        case .failure(let error):
            message = "读取文件失败：\(error.localizedDescription)"
        }
    }

    private func decryptImport() {
        guard let data = importData else { return }
        let password = importPassword
        importData = nil
        importPassword = ""
        do {
            pendingRestore = try BackupService.readBackup(data, password: password)
        } catch {
            message = error.localizedDescription
        }
    }

    private func restore() {
        guard let file = pendingRestore else { return }
        pendingRestore = nil
        do {
            try BackupService.restore(file, context: context)
            let all = (try? context.fetch(FetchDescriptor<Girl>())) ?? []
            Reminders.rescheduleDates(girls: all)
            for todo in (try? context.fetch(FetchDescriptor<TodoItem>())) ?? [] {
                Reminders.scheduleTodo(todo, girlName: all.first { $0.id == todo.girlID }?.name)
            }
            message = "恢复完成"
        } catch {
            message = "恢复失败：\(error.localizedDescription)"
        }
    }

    private func wipe() {
        do {
            try BackupService.wipeAll(context: context)
            Reminders.removeAll()
            message = "已清空"
        } catch {
            message = "清空失败：\(error.localizedDescription)"
        }
    }
}

struct BackupPasswordSheet: View {
    let onConfirm: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var confirm = ""

    private var valid: Bool { password.count >= 4 && password == confirm }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("密码（至少 4 位）", text: $password)
                    SecureField("再输一次", text: $confirm)
                } footer: {
                    Text("备份文件用这个密码加密（AES-256）。忘记密码将无法恢复，App 也不会保存这个密码。")
                }
            }
            .navigationTitle("设置备份密码")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("导出") {
                        let pw = password
                        dismiss()
                        onConfirm(pw)
                    }
                    .disabled(!valid)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - 选项管理

struct OptionListsView: View {
    @ObservedObject private var config = ConfigStore.shared

    private static let groups: [(title: String, keys: [OptionKey])] = [
        ("档案", [.ranks, .channels, .personality, .tags, .bodyTypes, .cups, .maritalStatus, .education, .contactTypes]),
        ("亲密", [.traits, .positions, .play, .toys, .outfits, .aftercare]),
        ("记录", [.activities, .moods, .feedback, .expenseCategories]),
        ("其他", [.giftOccasions, .todoCategories])
    ]

    /// 以后加了新选项、还没归类的，放到最后
    private var ungrouped: [OptionKey] {
        let grouped = Set(Self.groups.flatMap(\.keys))
        return OptionKey.allCases.filter { !grouped.contains($0) }
    }

    var body: some View {
        List {
            ForEach(Self.groups, id: \.title) { group in
                Section(group.title) {
                    ForEach(group.keys) { key in row(key) }
                }
            }
            if !ungrouped.isEmpty {
                Section("更多") {
                    ForEach(ungrouped) { key in row(key) }
                }
            }
        }
        .navigationTitle("选项管理")
    }

    private func row(_ key: OptionKey) -> some View {
        NavigationLink {
            OptionEditView(key: key)
        } label: {
            LabeledContent(key.title, value: "\(config.options(key).count) 项")
        }
    }
}

struct OptionEditView: View {
    let key: OptionKey

    @ObservedObject private var config = ConfigStore.shared
    @State private var newValue = ""

    var body: some View {
        let options = config.options(key)
        List {
            Section {
                ForEach(options, id: \.self) { o in
                    Text(o)
                }
                .onDelete { idx in
                    var list = options
                    list.remove(atOffsets: idx)
                    config.setOptions(list, for: key)
                }
                .onMove { from, to in
                    var list = options
                    list.move(fromOffsets: from, toOffset: to)
                    config.setOptions(list, for: key)
                }
            } footer: {
                if key == .ranks {
                    Text("位分的顺序就是排序和地图配色的顺序，越靠上越高。")
                }
            }

            Section("添加") {
                HStack {
                    TextField("新选项", text: $newValue)
                    Button("添加") {
                        config.addOption(newValue, to: key)
                        newValue = ""
                    }
                    .disabled(newValue.trimmed.isEmpty)
                }
            }

            Section {
                Button("恢复默认选项", role: .destructive) {
                    config.setOptions(key.defaults, for: key)
                }
            }
        }
        .navigationTitle(key.title)
        .toolbar { EditButton() }
    }
}

// MARK: - 自定义字段

struct CustomFieldsView: View {
    @ObservedObject private var config = ConfigStore.shared
    @State private var editing: CustomFieldDef?

    var body: some View {
        List {
            Section {
                ForEach(config.config.customFields) { f in
                    Button {
                        editing = f
                    } label: {
                        LabeledContent(f.name, value: f.kind.title)
                    }
                    .tint(.primary)
                }
                .onDelete { config.config.customFields.remove(atOffsets: $0) }
                .onMove { config.config.customFields.move(fromOffsets: $0, toOffset: $1) }
            } footer: {
                Text("自定义字段会出现在每个档案的编辑页底部。删除字段不会删除已填的值。")
            }
            Section {
                Button {
                    editing = CustomFieldDef()
                } label: {
                    Label("添加字段", systemImage: "plus")
                }
            }
        }
        .navigationTitle("自定义字段")
        .toolbar { EditButton() }
        .sheet(item: $editing) { field in
            CustomFieldEditor(field: field) { updated in
                if let i = config.config.customFields.firstIndex(where: { $0.id == updated.id }) {
                    config.config.customFields[i] = updated
                } else {
                    config.config.customFields.append(updated)
                }
            }
        }
    }
}

struct CustomFieldEditor: View {
    let onSave: (CustomFieldDef) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var field: CustomFieldDef
    @State private var optionsText: String

    init(field: CustomFieldDef, onSave: @escaping (CustomFieldDef) -> Void) {
        self.onSave = onSave
        _field = State(initialValue: field)
        _optionsText = State(initialValue: field.options.joined(separator: "、"))
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("字段名", text: $field.name)
                Picker("类型", selection: $field.kind) {
                    ForEach(CustomFieldKind.allCases) { k in
                        Text(k.title).tag(k)
                    }
                }
                if field.kind == .choice {
                    Section {
                        TextField("选项，用顿号或逗号分开", text: $optionsText, axis: .vertical)
                    } footer: {
                        Text("例如：A、B、C")
                    }
                }
            }
            .navigationTitle("字段")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        var f = field
                        f.name = f.name.trimmed
                        f.options = optionsText
                            .split(whereSeparator: { "、,，;；\n".contains($0) })
                            .map { String($0).trimmed }
                            .filter { !$0.isEmpty }
                        onSave(f)
                        dismiss()
                    }
                    .disabled(field.name.trimmed.isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - App 图标

enum AppIconChoice: String, CaseIterable, Identifiable {
    case standard, dark, minimal, list

    var id: String { rawValue }

    /// 传给 setAlternateIconName 的名字，默认图标是 nil
    var iconName: String? {
        switch self {
        case .standard: return nil
        case .dark: return "AppIconDark"
        case .minimal: return "AppIconMinimal"
        case .list: return "AppIconList"
        }
    }

    var preview: String {
        switch self {
        case .standard: return "IconPreviewDefault"
        case .dark: return "IconPreviewDark"
        case .minimal: return "IconPreviewMinimal"
        case .list: return "IconPreviewList"
        }
    }

    var title: String {
        switch self {
        case .standard: return "酒红"
        case .dark: return "墨黑"
        case .minimal: return "象牙"
        case .list: return "夜蓝"
        }
    }

    @MainActor
    static var current: AppIconChoice {
        let name = UIApplication.shared.alternateIconName
        return allCases.first { $0.iconName == name } ?? .standard
    }
}

struct AppIconPicker: View {
    @State private var selected = AppIconChoice.current
    @State private var error: String?

    var body: some View {
        List {
            Section {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 20) {
                    ForEach(AppIconChoice.allCases) { choice in
                        Button {
                            apply(choice)
                        } label: {
                            VStack(spacing: 8) {
                                Image(choice.preview)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 76, height: 76)
                                    .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 17, style: .continuous)
                                            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                                    }
                                    .padding(4)
                                    .overlay {
                                        if selected == choice {
                                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                                .stroke(Color.accentColor, lineWidth: 3)
                                        }
                                    }
                                    .shadow(color: .black.opacity(0.1), radius: 6, y: 3)
                                Text(choice.title)
                                    .font(.footnote.weight(selected == choice ? .semibold : .regular))
                                    .foregroundStyle(selected == choice ? Color.accentColor : Color.primary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 10)
            } footer: {
                Text("主屏幕上的名字始终是「手账」。切换时系统会弹一个提示，属于正常现象。")
            }
        }
        .navigationTitle("App 图标")
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.selection, trigger: selected)
        .alert("无法切换图标", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("好", role: .cancel) {}
        } message: {
            Text(error ?? "")
        }
    }

    private func apply(_ choice: AppIconChoice) {
        guard choice != selected else { return }
        withAnimation(.snappy) { selected = choice }
        guard UIApplication.shared.supportsAlternateIcons else {
            error = "当前设备不支持更换图标"
            return
        }
        UIApplication.shared.setAlternateIconName(choice.iconName) { err in
            if let err {
                Task { @MainActor in
                    error = err.localizedDescription
                    selected = AppIconChoice.current
                }
            }
        }
    }
}
