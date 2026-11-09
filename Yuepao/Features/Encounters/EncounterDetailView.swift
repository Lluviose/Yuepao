import SwiftUI
import SwiftData

struct EncounterDetailView: View {
    let encounter: Encounter

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var editing = false
    @State private var confirmDelete = false

    var body: some View {
        let d = encounter.details
        List {
            hero(d)
            riskSection(d)

            Section("时间和地点") {
                InfoRow(label: "时间", value: Fmt.dateTime(encounter.date))
                if encounter.durationMinutes > 0 {
                    InfoRow(label: "时长", value: Choices.durationTitle(encounter.durationMinutes))
                }
                if encounter.overnight { InfoRow(label: "过夜", value: "是") }
                if let place = encounter.place {
                    NavigationLink {
                        PlaceDetailView(place: place)
                    } label: {
                        HStack {
                            Text("地点")
                            Spacer()
                            Image(systemName: place.type.symbol)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text(place.displayName)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            }

            if !encounter.girls.isEmpty {
                Section("对象") {
                    ForEach(encounter.girls) { girl in
                        NavigationLink {
                            GirlDetailView(girl: girl)
                        } label: {
                            HStack(spacing: 12) {
                                AvatarView(photoID: girl.avatarID, name: girl.name, size: 36, ring: girl.status.color)
                                Text(girl.name)
                                Spacer()
                                Text("第 \(ordinal(of: girl)) 次").foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            Section("过程") {
                InfoRow(label: "回合数", value: "\(encounter.count)")
                if d.herOrgasms >= 0 {
                    InfoRow(label: "她高潮", value: d.herOrgasms >= 6 ? "6 次以上" : "\(d.herOrgasms) 次")
                }
                if !d.initiator.isEmpty { InfoRow(label: "谁主动", value: d.initiator) }
                chips("约会内容", d.activities)
                chips("体位", d.positions)
                chips("玩法 / 道具", d.play)
            }

            Section("安全") {
                HStack {
                    Text("措施")
                    Spacer()
                    Image(systemName: encounter.protection.symbol)
                        .font(.subheadline)
                    Text(encounter.protection.title)
                }
                .foregroundStyle(encounter.protection.color)
                if encounter.condomBroke { InfoRow(label: "破套", value: "是") }
                if encounter.pregnancyRisk {
                    InfoRow(label: "紧急避孕药", value: d.pillTaken ? "已吃" : "未记录")
                }
            }

            if !d.expenses.isEmpty {
                Section {
                    ForEach(d.expenses) { item in
                        LabeledContent(item.note.isEmpty ? item.category : "\(item.category) · \(item.note)",
                                       value: Fmt.money(item.amount))
                    }
                } header: {
                    HStack {
                        Text("花费")
                        Spacer()
                        Text("合计 \(Fmt.money(encounter.totalCost))")
                    }
                }
            }

            if encounter.rating > 0 || d.chemistry > 0 || !d.moods.isEmpty {
                Section("评价") {
                    if encounter.rating > 0 {
                        LabeledContent("满意度") { StarDisplay(value: encounter.rating) }
                    }
                    if d.chemistry > 0 {
                        LabeledContent("化学反应") { StarDisplay(value: d.chemistry) }
                    }
                    chips("心情 / 氛围", d.moods)
                }
            }

            if !d.notes.isEmpty {
                Section("备注") {
                    Text(d.notes).textSelection(.enabled)
                }
            }

            Section("照片") {
                PhotoGrid(photoIDs: livePhotoBinding(
                    get: { encounter.details.photoIDs },
                    set: { ids in encounter.update { $0.photoIDs = ids } }
                ))
            }
        }
        .navigationTitle(Fmt.shortDate(encounter.date))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button { editing = true } label: { Label("编辑", systemImage: "pencil") }
                    Button(role: .destructive) { confirmDelete = true } label: { Label("删除", systemImage: "trash") }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $editing) {
            EncounterEditView(encounter: encounter, presetGirls: [])
        }
        .confirmationDialog("删除这条记录？", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                dismiss()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    EncounterActions.delete(encounter, context: context)
                }
            }
        }
    }

    private func hero(_ d: EncounterDetails) -> some View {
        Section {
            VStack(spacing: 12) {
                HStack(spacing: -12) {
                    ForEach(Array(encounter.girls.prefix(4))) { g in
                        AvatarView(photoID: g.avatarID, name: g.name, size: 64)
                            .overlay(Circle().stroke(Color(uiColor: .secondarySystemGroupedBackground), lineWidth: 3))
                    }
                }
                VStack(spacing: 4) {
                    Text(encounter.girlNames)
                        .font(.title3.weight(.bold))
                        .fontDesign(.rounded)
                    Text(Fmt.dateTime(encounter.date) + " " +
                         encounter.date.formatted(Date.FormatStyle().weekday(.wide).locale(Fmt.locale)))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 8) {
                    heroPill("×\(encounter.count) 回合", "flame.fill", .pink)
                    if encounter.durationMinutes > 0 {
                        heroPill(Choices.durationTitle(encounter.durationMinutes), "clock.fill", .indigo)
                    }
                    if encounter.protection != .unrecorded {
                        heroPill(encounter.protection.title, encounter.protection.symbol, encounter.protection.color)
                    }
                }
                if encounter.rating > 0 {
                    HStack(spacing: 4) {
                        ForEach(1...5, id: \.self) { i in
                            Image(systemName: i <= encounter.rating ? "star.fill" : "star")
                                .font(.subheadline)
                                .foregroundStyle(i <= encounter.rating ? Color.orange : Color.secondary.opacity(0.35))
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .listRowBackground(
                ZStack {
                    Color(uiColor: .secondarySystemGroupedBackground)
                    LinearGradient(colors: [Color.accentColor.opacity(0.14), .clear], startPoint: .top, endPoint: .bottom)
                }
            )
        }
    }

    private func heroPill(_ text: String, _ symbol: String, _ color: Color) -> some View {
        Label(text, systemImage: symbol)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .foregroundStyle(color)
            .background(color.opacity(0.12), in: Capsule())
    }

    @ViewBuilder
    private func chips(_ title: String, _ items: [String]) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.subheadline).foregroundStyle(.secondary)
                ChipsView(items: items)
            }
            .padding(.vertical, 2)
        }
    }

    /// 这是和她的第几次
    private func ordinal(of girl: Girl) -> Int {
        girl.encounters.filter { $0.date <= encounter.date }.count
    }

    @ViewBuilder
    private func riskSection(_ d: EncounterDetails) -> some View {
        let hours = Date().timeIntervalSince(encounter.date) / 3600
        if encounter.pregnancyRisk && !d.pillTaken && hours >= 0 && hours < 72 {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label("有怀孕风险", systemImage: "exclamationmark.triangle.fill")
                        .font(.headline)
                        .foregroundStyle(.orange)
                    Text("已经过去 \(Int(hours)) 小时。紧急避孕药 72 小时内有效，越早越好。")
                        .font(.subheadline)
                    Button("已处理（已吃药）") {
                        encounter.update { $0.pillTaken = true }
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.vertical, 4)
            }
        }
        if encounter.stiRisk {
            let days = Fmt.days(from: encounter.date)
            if days <= 60 {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("有性病风险", systemImage: "cross.case")
                            .font(.headline)
                            .foregroundStyle(.orange)
                        Text(days < 14
                             ? "建议 \(14 - days) 天后做一次检测，6 周后做 HIV / 梅毒检测。"
                             : (days < 42 ? "可以去做检测了；HIV / 梅毒建议 \(42 - days) 天后再测一次。" : "已过窗口期，可以做 HIV / 梅毒检测。"))
                            .font(.subheadline)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }
}
