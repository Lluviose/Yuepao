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
    @State private var exportURL: URL?
    @State private var exporting = false
    @State private var importing = false
    @State private var importURL: URL?
    @State private var importPassword = ""
    @State private var askImportPassword = false
    @State private var pendingRestore: PendingRestore?
    @State private var message: String?
    @State private var confirmWipe = false
    @State private var confirmWipeAgain = false
    /// 正在打包 / 恢复时的提示和进度
    @State private var working: String?
    @State private var workProgress: Double = 0
    @State private var mediaUsage: MediaUsage?
    @State private var orphans: [String] = []
    @State private var orphanBytes: Int64 = 0
    @State private var confirmCleanup = false

    var body: some View {
        NavigationStack {
            Form {
                securitySection
                appearanceSection
                notificationSection
                customizeSection
                mediaSection
                dataSection
                aboutSection
            }
            .paperBackground()
            .tint(Color.accentColor)
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .sheet(isPresented: $exportSheet) {
                BackupPasswordSheet(usage: mediaUsage) { password, includeVideos in
                    makeBackup(password: password, includeVideos: includeVideos)
                }
            }
            .fileMover(isPresented: $exporting, file: exportURL) { result in
                switch result {
                case .success:
                    message = "备份已保存。请记住密码，忘了就打不开。"
                case .failure(let error):
                    if (error as? CocoaError)?.code != .userCancelled {
                        message = "保存失败：\(error.localizedDescription)"
                    }
                }
                if let exportURL { try? FileManager.default.removeItem(at: exportURL.deletingLastPathComponent()) }
                exportURL = nil
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.data, .item]) { result in
                handleImport(result)
            }
            .alert("输入备份密码", isPresented: $askImportPassword) {
                SecureField("密码", text: $importPassword)
                Button("取消", role: .cancel) {
                    importURL = nil
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
            .confirmationDialog("删除没用到的文件？", isPresented: $confirmCleanup, titleVisibility: .visible) {
                Button("删除 \(orphans.count) 个文件", role: .destructive) { cleanOrphans() }
            } message: {
                Text("这些照片视频没有被任何档案或记录用到（比如中途放弃的记录里加过的）。")
            }
            .overlay {
                if let working {
                    WorkingOverlay(title: working, progress: workProgress)
                        .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.2), value: working)
            .task { await loadUsage() }
        }
        .interactiveDismissDisabled(working != nil)
    }

    // MARK: Sections

    private var securitySection: some View {
        Section {
            Toggle(isOn: $lockEnabled) {
                SettingsLabel("打开时需要\(AppLock.biometryName)", symbol: AppLock.biometrySymbol, color: Palette.status)
            }
            if lockEnabled {
                Picker(selection: $lockDelay) {
                    Text("立即").tag(0.0)
                    Text("1 分钟").tag(60.0)
                    Text("5 分钟").tag(300.0)
                    Text("15 分钟").tag(900.0)
                } label: {
                    SettingsLabel("离开后多久锁定", symbol: "timer", color: Palette.todo)
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
            Picker(selection: $appearance) {
                ForEach(AppearanceMode.allCases) { m in
                    Text(m.title).tag(m.rawValue)
                }
            } label: {
                SettingsLabel("外观", symbol: "circle.lefthalf.filled", color: Palette.memo)
            }
            NavigationLink {
                AppIconPicker()
            } label: {
                LabeledContent {
                    Text(AppIconChoice.current.title).foregroundStyle(.secondary)
                } label: {
                    SettingsLabel("App 图标", symbol: "app.badge", color: Palette.wineBottom)
                }
            }
        } header: {
            Text("外观")
        }
    }

    private var notificationSection: some View {
        Section {
            Toggle(isOn: $notificationsEnabled) {
                SettingsLabel("开启提醒", symbol: "bell.fill", color: Palette.gold)
            }
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
                Toggle(isOn: $discreetNotifications) {
                    SettingsLabel("隐藏通知内容", symbol: "eye.slash.fill", color: Palette.memo)
                }
                .onChange(of: discreetNotifications) { _, _ in Reminders.rescheduleDates(girls: girls) }
                Toggle(isOn: $riskReminders) {
                    SettingsLabel("有风险时提醒做检测", symbol: "cross.case.fill", color: Palette.status)
                }
                Toggle(isOn: $periodReminders) {
                    SettingsLabel("经期提醒（预计前一天晚上）", symbol: "drop.fill", color: Palette.period)
                }
                .onChange(of: periodReminders) { _, _ in Reminders.rescheduleDates(girls: girls) }
                Toggle(isOn: $weeklyNudge) {
                    SettingsLabel("每周目标提醒（周四晚上）", symbol: "flame.fill", color: Palette.fertile)
                }
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
            NavigationLink {
                OptionListsView()
            } label: {
                SettingsLabel("选项管理（位分、渠道、体位…）", symbol: "slider.horizontal.3", color: Palette.wineBottom)
            }
            NavigationLink {
                CustomFieldsView()
            } label: {
                SettingsLabel("自定义档案字段", symbol: "text.badge.plus", color: Palette.gift)
            }
            NavigationLink {
                PlaceListView()
            } label: {
                SettingsLabel("地点管理", symbol: "mappin.and.ellipse", color: Palette.todo)
            }
            NavigationLink {
                HealthTestListView()
            } label: {
                SettingsLabel("性健康检测记录", symbol: "cross.case.fill", color: Palette.status)
            }
        }
    }

    private var mediaSection: some View {
        Section {
            if let usage = mediaUsage {
                LabeledContent("已保存", value: usage.count == 0 ? "无" : "\(usage.count) 项")
                if usage.count > 0 {
                    LabeledContent("照片 / 实况 / 视频", value: "\(usage.photos) / \(usage.lives) / \(usage.videos)")
                    LabeledContent("占用空间", value: Fmt.bytes(usage.bytes))
                }
                if !orphans.isEmpty {
                    Button {
                        confirmCleanup = true
                    } label: {
                        Label("清理 \(orphans.count) 个没用到的文件（\(Fmt.bytes(orphanBytes))）", systemImage: "sparkles")
                    }
                }
            } else {
                HStack {
                    Text("正在统计…").foregroundStyle(.secondary)
                    Spacer()
                    ProgressView()
                }
            }
        } header: {
            Text("照片与视频")
        } footer: {
            Text("照片、视频、实况都按原文件保存，不压缩、不转码；加密后只放在这台手机上，不进系统相册。更新前存的照片是压缩过的版本。")
        }
    }

    private var dataSection: some View {
        Section {
            Button {
                exportSheet = true
            } label: {
                SettingsLabel("导出加密备份", symbol: "square.and.arrow.up", color: Palette.gold)
            }
            Button {
                importing = true
            } label: {
                SettingsLabel("从备份恢复", symbol: "square.and.arrow.down", color: Palette.todo)
            }
            Button(role: .destructive) {
                confirmWipe = true
            } label: {
                SettingsLabel("清空全部数据", symbol: "trash.fill", color: Palette.period)
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
        guard let file = pendingRestore?.file else { return "" }
        return "备份时间：\(Fmt.dateTime(file.exportedAt))\n包含 \(file.girls.count) 个档案、\(file.encounters.count) 条记录、\(file.todos?.count ?? 0) 条待办、\(file.places.count) 个地点、\(file.mediaTotal) 个照片视频。\n当前 App 里的数据会被全部替换。"
    }

    // MARK: Actions

    private func makeBackup(password: String, includeVideos: Bool) {
        do {
            var manifest = try BackupService.makeManifest(context: context)
            var ids = Array(BackupService.referencedMediaIDs(context: context)).sorted()
            if !includeVideos {
                let videos = Set(ids.filter { MediaStore.shared.kind($0) == .video })
                ids.removeAll { videos.contains($0) }
                manifest = manifest.removingMedia(videos)
            }
            manifest.mediaCount = ids.count
            let file = manifest
            let mediaIDs = ids
            let filename = BackupService.defaultFilename
            let report = reportProgress
            startWork("正在打包备份…")
            Task {
                do {
                    let url = try await Task.detached(priority: .userInitiated) {
                        try BackupArchive.write(manifest: file, mediaIDs: mediaIDs, password: password,
                                                filename: filename, progress: report)
                    }.value
                    working = nil
                    exportURL = url
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { exporting = true }
                } catch {
                    working = nil
                    message = "备份失败：\(error.localizedDescription)"
                }
            }
        } catch {
            message = "备份失败：\(error.localizedDescription)"
        }
    }

    private func handleImport(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            importURL = url
            importPassword = ""
            askImportPassword = true
        case .failure(let error):
            message = "读取文件失败：\(error.localizedDescription)"
        }
    }

    private func decryptImport() {
        guard let url = importURL else { return }
        let password = importPassword
        importPassword = ""
        startWork("正在解密…")
        Task {
            do {
                let pending = try await Task.detached(priority: .userInitiated) { () throws -> PendingRestore in
                    let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    return try BackupArchive.readPending(url: url, password: password)
                }.value
                working = nil
                pendingRestore = pending
            } catch {
                working = nil
                importURL = nil
                message = error.localizedDescription
            }
        }
    }

    private func restore() {
        guard let pending = pendingRestore else { return }
        pendingRestore = nil
        let url = importURL
        let report = reportProgress
        startWork("正在恢复照片和视频…")
        Task {
            do {
                // 先把照片视频读到暂存目录，全部成功再替换，中途失败不影响现在的数据
                try await Task.detached(priority: .userInitiated) { () throws -> Void in
                    let access = url?.startAccessingSecurityScopedResource() ?? false
                    defer { if access { url?.stopAccessingSecurityScopedResource() } }
                    try BackupArchive.stageMedia(for: pending, progress: report)
                }.value
                try BackupService.replaceAll(with: pending.file, context: context)
                let all = (try? context.fetch(FetchDescriptor<Girl>())) ?? []
                Reminders.rescheduleDates(girls: all)
                for todo in (try? context.fetch(FetchDescriptor<TodoItem>())) ?? [] {
                    Reminders.scheduleTodo(todo, girlName: all.first { $0.id == todo.girlID }?.name)
                }
                working = nil
                importURL = nil
                message = "恢复完成"
                await loadUsage()
            } catch {
                MediaStore.shared.discardStaging()
                working = nil
                importURL = nil
                message = "恢复失败：\(error.localizedDescription)"
            }
        }
    }

    private func startWork(_ title: String) {
        workProgress = 0
        working = title
    }

    /// 后台线程里报进度
    private var reportProgress: @Sendable (Double) -> Void {
        { value in
            Task { @MainActor in workProgress = value }
        }
    }

    private func loadUsage() async {
        let referenced = BackupService.referencedMediaIDs(context: context)
        let result = await Task.detached(priority: .utility) { () -> (MediaUsage, [String], Int64) in
            let store = MediaStore.shared
            let all = store.allIDs()
            let used = all.filter { referenced.contains($0) }
            let unused = all.filter { !referenced.contains($0) }
            let unusedBytes = unused.reduce(Int64(0)) { $0 + store.diskSize($1) }
            return (store.usage(of: used), unused, unusedBytes)
        }.value
        mediaUsage = result.0
        orphans = result.1
        orphanBytes = result.2
    }

    private func cleanOrphans() {
        // 再核对一遍，确保只删没被引用的
        let referenced = BackupService.referencedMediaIDs(context: context)
        MediaStore.shared.delete(orphans.filter { !referenced.contains($0) })
        orphans = []
        orphanBytes = 0
        Task { await loadUsage() }
    }

    private func wipe() {
        do {
            try BackupService.wipeAll(context: context)
            Reminders.removeAll()
            Task { await loadUsage() }
            message = "已清空"
        } catch {
            message = "清空失败：\(error.localizedDescription)"
        }
    }
}

struct BackupPasswordSheet: View {
    var usage: MediaUsage?
    let onConfirm: (String, Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var confirm = ""
    @State private var includeVideos = true

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
                if let usage, usage.count > 0 {
                    Section {
                        LabeledContent("照片与实况", value: Fmt.bytes(max(usage.bytes - usage.videoBytes, 0)))
                        if usage.videos > 0 {
                            Toggle(isOn: $includeVideos) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("包含视频")
                                    Text("\(usage.videos) 个 · \(Fmt.bytes(usage.videoBytes))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    } footer: {
                        Text("照片视频都是原文件，备份大小约为 \(Fmt.bytes(includeVideos ? usage.bytes : usage.bytes - usage.videoBytes))。")
                    }
                }
            }
            .paperBackground()
            .navigationTitle("设置备份密码")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("导出") {
                        let pw = password
                        let videos = includeVideos
                        dismiss()
                        onConfirm(pw, videos)
                    }
                    .disabled(!valid)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// 打包 / 恢复时盖在页面上的进度
private struct WorkingOverlay: View {
    let title: String
    let progress: Double

    var body: some View {
        ZStack {
            Color.black.opacity(0.25).ignoresSafeArea()
            VStack(spacing: 14) {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .tint(Palette.gold)
                    .frame(width: 190)
                Text(title)
                    .font(.subheadline.weight(.medium))
                Text("\(Int((progress * 100).rounded()))%")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 22)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(.regularMaterial))
        }
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
        .paperBackground()
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
        .paperBackground()
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
        .paperBackground()
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
            .paperBackground()
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
        .paperBackground()
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

// MARK: - 设置行

/// 设置行前面的小图标：圆角方块底 + 白色图形
struct SettingsIcon: View {
    let symbol: String
    let color: Color

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Color.white)
            .frame(width: 29, height: 29)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(color.gradient))
    }
}

/// 设置行的标题：图标 + 文字
struct SettingsLabel: View {
    let title: String
    let symbol: String
    let color: Color

    init(_ title: String, symbol: String, color: Color) {
        self.title = title
        self.symbol = symbol
        self.color = color
    }

    var body: some View {
        Label {
            Text(title)
        } icon: {
            SettingsIcon(symbol: symbol, color: color)
        }
    }
}
