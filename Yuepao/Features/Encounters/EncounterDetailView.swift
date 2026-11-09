import SwiftUI
import SwiftData

/// 一条记录的详情：顶部是她的头像和这次的概要，下面按卡片分组，没填的部分不显示
struct EncounterDetailView: View {
    let encounter: Encounter

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var editing = false
    @State private var repeating = false
    @State private var confirmDelete = false
    @State private var addingMedia = false

    var body: some View {
        let d = encounter.details
        ScrollView {
            VStack(spacing: 14) {
                hero(d)
                riskCards(d)
                metricsCard(d)
                photoCard(d)
                whereCard
                peopleCard
                playCard(d)
                safetyCard(d)
                feelingCard(d)
                dateCard(d)
                costCard(d)
                noteCard(d)
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 32)
        }
        .background(Palette.canvas)
        .navigationTitle(Fmt.shortDate(encounter.date))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button { editing = true } label: { Label("编辑", systemImage: "pencil") }
                    Button { repeating = true } label: { Label("再记一次", systemImage: "arrow.clockwise.heart") }
                    Divider()
                    Button(role: .destructive) { confirmDelete = true } label: { Label("删除", systemImage: "trash") }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityIdentifier("recordMenu")
            }
        }
        .sheet(isPresented: $editing) {
            EncounterEditView(encounter: encounter, presetGirls: [])
        }
        .sheet(isPresented: $repeating) {
            EncounterEditView(encounter: nil, presetGirls: encounter.girls, presetPlace: encounter.place)
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

    // MARK: 顶部

    private var weekday: String {
        encounter.date.formatted(Date.FormatStyle().weekday(.wide).locale(Fmt.locale))
    }

    private struct HeroTag: Identifiable {
        let symbol: String
        let text: String
        var id: String { text }
    }

    private func heroTags(_ d: EncounterDetails) -> [HeroTag] {
        var tags: [HeroTag] = []
        if encounter.girls.count == 1, let girl = encounter.girls.first {
            let n = ordinal(of: girl)
            tags.append(n == 1 ? HeroTag(symbol: "sparkles", text: "初次") : HeroTag(symbol: "heart", text: "第 \(n) 次"))
            // 和上一次隔了几天
            if let previous = girl.encounters.filter({ $0.date < encounter.date }).map(\.date).max() {
                let gap = Fmt.days(from: previous, to: encounter.date)
                tags.append(HeroTag(symbol: "clock.arrow.circlepath", text: gap == 0 ? "同一天第二次" : "隔 \(gap) 天"))
            }
        }
        if encounter.overnight { tags.append(HeroTag(symbol: "moon", text: "过夜")) }
        if let intensity = Intensity.title(d.intensity) { tags.append(HeroTag(symbol: "flame", text: intensity)) }
        return tags
    }

    private func hero(_ d: EncounterDetails) -> some View {
        VStack(spacing: 14) {
            if encounter.girls.isEmpty {
                IconBadge(symbol: "heart", color: .accentColor, size: 72)
            } else {
                HStack(spacing: -16) {
                    ForEach(Array(encounter.girls.prefix(4))) { g in
                        AvatarView(photoID: g.avatarID, name: g.name, size: 76)
                            .overlay(Circle().stroke(Color.white.opacity(0.75), lineWidth: 3))
                            .shadow(color: .black.opacity(0.16), radius: 14, y: 7)
                    }
                }
            }
            VStack(spacing: 6) {
                Text(encounter.girlNames)
                    .font(Typo.display(26))
                    .multilineTextAlignment(.center)
                Text(Fmt.dateTime(encounter.date) + " · " + weekday)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if encounter.rating > 0 {
                HStack(spacing: 5) {
                    ForEach(1...5, id: \.self) { i in
                        Image(systemName: i <= encounter.rating ? "star.fill" : "star")
                            .font(.system(size: 15, weight: .light))
                            .foregroundStyle(i <= encounter.rating ? Palette.gold : Color.secondary.opacity(0.3))
                    }
                }
            }
            let tags = heroTags(d)
            if !tags.isEmpty {
                HStack(spacing: 6) {
                    ForEach(tags) { tag in
                        Label(tag.text, systemImage: tag.symbol)
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(.ultraThinMaterial, in: Capsule())
                            .overlay(Capsule().strokeBorder(Palette.hairline, lineWidth: 0.5))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .padding(.horizontal, 16)
        .background { heroBackground }
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    /// 这次拍了照片就用第一张模糊后做底，没有就用她的头像，再没有用她的头像色调
    private var heroBackground: some View {
        let card = Palette.surface
        let first = encounter.girls.first
        let backdrop = encounter.details.photoIDs.first ?? first?.avatarID
        return ZStack {
            card
            if let id = backdrop, let image = MediaStore.shared.thumbnail(id, size: 192) {
                Color.clear
                    .overlay {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .blur(radius: 40)
                            .opacity(0.5)
                    }
                    .clipped()
            } else if let first {
                Palette.avatarGradient(for: first.name).opacity(0.3)
            } else {
                Color.accentColor.opacity(0.12)
            }
            LinearGradient(colors: [.clear, card.opacity(0.92)], startPoint: .center, endPoint: .bottom)
        }
    }

    // MARK: 风险

    @ViewBuilder
    private func riskCards(_ d: EncounterDetails) -> some View {
        let hours = Date().timeIntervalSince(encounter.date) / 3600
        if encounter.pregnancyRisk && !d.pillTaken && hours >= 0 && hours < 72 {
            RecordCard {
                Callout(symbol: "exclamationmark.triangle", tint: Palette.fertile,
                        title: "有怀孕风险",
                        message: "已经过去 \(Int(hours)) 小时。紧急避孕药 72 小时内有效，越早越好。")
                Button {
                    withAnimation(.snappy) { encounter.update { $0.pillTaken = true } }
                    Haptics.success()
                } label: {
                    Label("已处理（已吃药）", systemImage: "checkmark")
                        .font(.subheadline.weight(.medium))
                }
                .buttonStyle(.borderless)
            }
        }
        if encounter.stiRisk {
            let days = Fmt.days(from: encounter.date)
            if days <= 60 {
                RecordCard {
                    Callout(symbol: "cross.case", tint: Palette.fertile,
                            title: "有性病风险",
                            message: days < 14
                                ? "建议 \(14 - days) 天后做一次检测，6 周后做 HIV / 梅毒检测。"
                                : (days < 42 ? "可以去做检测了；HIV / 梅毒建议 \(42 - days) 天后再测一次。" : "已过窗口期，可以做 HIV / 梅毒检测。"))
                }
            }
        }
    }

    // MARK: 数字

    private func orgasmText(_ d: EncounterDetails) -> String {
        switch d.herOrgasms {
        case ..<0: return "—"
        case 6...: return "6+"
        default: return "\(d.herOrgasms)"
        }
    }

    private func metricsCard(_ d: EncounterDetails) -> some View {
        let duration = Choices.durationParts(encounter.durationMinutes)
        return RecordCard {
            MetricStrip(items: [
                MetricItem(label: "回合", value: "\(encounter.count)"),
                MetricItem(label: "她高潮", value: orgasmText(d)),
                MetricItem(label: "时长", value: duration.value, unit: duration.unit),
                MetricItem(label: "强度", value: Intensity.title(d.intensity) ?? "—")
            ])
            .padding(.vertical, 2)
        }
    }

    // MARK: 时间和地点

    private var whereCard: some View {
        RecordCard("时间与地点") {
            DetailLine(symbol: "calendar", tint: .accentColor,
                       title: Fmt.dateTime(encounter.date),
                       subtitle: weekday + (encounter.overnight ? " · 过夜" : ""))
            if let place = encounter.place {
                Divider().padding(.leading, 44)
                NavigationLink {
                    PlaceDetailView(place: place)
                } label: {
                    HStack(spacing: 8) {
                        DetailLine(symbol: place.type.symbol, tint: .accentColor, title: place.displayName,
                                   subtitle: [place.type.title, place.city, place.district]
                                       .filter { !$0.isEmpty }.joined(separator: " · "))
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: 对象

    @ViewBuilder
    private var peopleCard: some View {
        if !encounter.girls.isEmpty {
            RecordCard("对象") {
                VStack(spacing: 0) {
                    ForEach(Array(encounter.girls.enumerated()), id: \.element.id) { index, girl in
                        if index > 0 {
                            Divider()
                                .padding(.leading, 56)
                                .padding(.vertical, 10)
                        }
                        NavigationLink {
                            GirlDetailView(girl: girl)
                        } label: {
                            personRow(girl)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func personRow(_ girl: Girl) -> some View {
        let traits = girl.details.traits
        let fallback = [girl.rank, girl.status.title].filter { !$0.isEmpty }.joined(separator: " · ")
        return HStack(spacing: 12) {
            AvatarView(photoID: girl.avatarID, name: girl.name, size: 40, ring: girl.status.color)
            VStack(alignment: .leading, spacing: 3) {
                Text(girl.name)
                    .font(Typo.display(17))
                    .foregroundStyle(.primary)
                Text(traits.isEmpty ? fallback : traits.prefix(4).joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(traits.isEmpty ? Color.secondary : Palette.gold)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text("第 \(ordinal(of: girl)) 次")
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(.secondary)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }

    /// 这是和她的第几次
    private func ordinal(of girl: Girl) -> Int {
        girl.encounters.filter { $0.date <= encounter.date }.count
    }

    // MARK: 玩法与道具

    @ViewBuilder
    private func playCard(_ d: EncounterDetails) -> some View {
        if !d.positions.isEmpty || !d.play.isEmpty || !d.toys.isEmpty || !d.outfits.isEmpty || !d.lead.isEmpty {
            RecordCard("玩法与道具", trailing: {
                if !d.lead.isEmpty {
                    Text("\(d.lead)主导")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(Color.accentColor)
                }
            }) {
                if !d.positions.isEmpty { TagGroupView(title: "体位", symbol: "square.grid.2x2", items: d.positions) }
                if !d.play.isEmpty { TagGroupView(title: "玩法", symbol: "wand.and.stars", items: d.play) }
                if !d.toys.isEmpty { TagGroupView(title: "道具", symbol: "sparkles", items: d.toys) }
                if !d.outfits.isEmpty { TagGroupView(title: "穿着", symbol: "tshirt", items: d.outfits) }
            }
        }
    }

    // MARK: 安全

    private func safetyCard(_ d: EncounterDetails) -> some View {
        let p = encounter.protection
        var notes: [String] = []
        if encounter.condomBroke { notes.append("破套 / 中途摘了") }
        if encounter.pregnancyRisk { notes.append(d.pillTaken ? "已吃紧急避孕药" : "紧急避孕药未记录") }
        return RecordCard("安全") {
            DetailLine(symbol: p.tileSymbol, tint: p.color, title: p.title, subtitle: notes.joined(separator: " · "))
        }
    }

    // MARK: 感受

    @ViewBuilder
    private func feelingCard(_ d: EncounterDetails) -> some View {
        if encounter.rating > 0 || d.chemistry > 0 || !d.moods.isEmpty || !d.feedback.isEmpty || !d.aftercare.isEmpty {
            RecordCard("感受") {
                if encounter.rating > 0 { starRow("满意度", encounter.rating) }
                if d.chemistry > 0 { starRow("化学反应", d.chemistry) }
                if !d.moods.isEmpty { TagGroupView(title: "氛围", symbol: "theatermasks", items: d.moods) }
                if !d.feedback.isEmpty {
                    TagGroupView(title: "她的反馈", symbol: "text.bubble", items: d.feedback, tint: .accentColor)
                }
                if !d.aftercare.isEmpty {
                    TagGroupView(title: "事后照顾", symbol: "hands.sparkles", items: d.aftercare, tint: Palette.status)
                }
            }
        }
    }

    private func starRow(_ title: String, _ value: Int) -> some View {
        HStack(spacing: 8) {
            Text(title)
            Spacer(minLength: 8)
            if let word = RatingWords.word(value) {
                Text(word)
                    .font(.footnote)
                    .foregroundStyle(Palette.gold)
            }
            HStack(spacing: 3) {
                ForEach(1...5, id: \.self) { i in
                    Image(systemName: i <= value ? "star.fill" : "star")
                        .font(.system(size: 13, weight: .light))
                        .foregroundStyle(i <= value ? Palette.gold : Color.secondary.opacity(0.3))
                }
            }
        }
    }

    // MARK: 约会

    @ViewBuilder
    private func dateCard(_ d: EncounterDetails) -> some View {
        if !d.activities.isEmpty || !d.initiator.isEmpty {
            RecordCard("约会") {
                if !d.initiator.isEmpty {
                    HStack {
                        Text("谁主动约的")
                        Spacer(minLength: 8)
                        Text(d.initiator)
                            .foregroundStyle(.secondary)
                    }
                }
                if !d.activities.isEmpty {
                    TagGroupView(title: "约会内容", symbol: "fork.knife", items: d.activities)
                }
            }
        }
    }

    // MARK: 花费、备注、照片

    @ViewBuilder
    private func costCard(_ d: EncounterDetails) -> some View {
        if !d.expenses.isEmpty {
            RecordCard("花费", trailing: {
                Text("合计 \(Fmt.money(encounter.totalCost))")
                    .font(.footnote.weight(.semibold))
                    .monospacedDigit()
            }) {
                VStack(spacing: 10) {
                    ForEach(d.expenses) { item in
                        HStack(spacing: 8) {
                            Text(item.category)
                            if !item.note.isEmpty {
                                Text(item.note)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 8)
                            Text(Fmt.money(item.amount))
                                .monospacedDigit()
                        }
                        .font(.subheadline)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func noteCard(_ d: EncounterDetails) -> some View {
        if !d.notes.isEmpty {
            RecordCard("备注") {
                Text(d.notes)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// 照片和视频放在前面：一张大图 + 小图拼起来，点开全屏看原图、播视频、看实况
    private func photoCard(_ d: EncounterDetails) -> some View {
        RecordCard("照片与视频", trailing: {
            if !d.photoIDs.isEmpty {
                Button {
                    addingMedia = true
                } label: {
                    Label("添加", systemImage: "plus")
                        .font(.footnote.weight(.medium))
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("addMediaHeader")
            }
        }) {
            MediaGrid(ids: storedMediaBinding(
                get: { encounter.details.photoIDs },
                set: { ids in encounter.update { $0.photoIDs = ids } }
            ), style: .mosaic, pickerPresented: $addingMedia)
        }
    }
}
