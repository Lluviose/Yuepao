import SwiftUI
import SwiftData

// MARK: - 周期环

/// 一圈代表一个周期：红色是经期，橙色是易孕期，白点是今天
struct CycleRing: View {
    let info: CycleInfo
    var size: CGFloat = 132

    @State private var progress: CGFloat = 0

    var body: some View {
        let current = info.current
        let length = CGFloat(max(current?.length ?? info.averageCycle, 1))
        let periodEnd = CGFloat(current?.periodLength ?? info.averagePeriodLength) / length
        let ov = CGFloat(current?.ovulationDay ?? (info.averageCycle - 13))
        let fertileStart = max(ov - 6, 0) / length
        let fertileEnd = min(ov + 1, length) / length
        let today = CGFloat((current?.day ?? 1) - 1) + 0.5
        let todayFraction = min(today / length, 1)
        let lineWidth = size * 0.1

        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.12), lineWidth: lineWidth)
            arc(0, periodEnd, Palette.period, lineWidth)
            arc(fertileStart, fertileEnd, Palette.fertile, lineWidth)

            // 今天
            Circle()
                .fill(.white)
                .frame(width: lineWidth * 0.9, height: lineWidth * 0.9)
                .shadow(color: .black.opacity(0.25), radius: 2)
                .offset(y: -size / 2)
                .rotationEffect(.degrees(Double(todayFraction * progress) * 360))

            VStack(spacing: 2) {
                if let current {
                    Text("第 \(current.day) 天")
                        .font(.system(size: size * 0.16, weight: .semibold, design: .rounded))
                        .contentTransition(.numericText())
                    if let phase = info.phase(on: Date()) {
                        Text(phase.title)
                            .font(.system(size: size * 0.1, weight: .medium))
                            .foregroundStyle(phase.color)
                    }
                } else {
                    Text("—").font(.title2)
                }
            }
        }
        .frame(width: size, height: size)
        .onAppear {
            withAnimation(.spring(duration: 0.9, bounce: 0.2).delay(0.1)) { progress = 1 }
        }
    }

    private func arc(_ from: CGFloat, _ to: CGFloat, _ color: Color, _ width: CGFloat) -> some View {
        Circle()
            .trim(from: from * progress, to: max(from, to) * progress)
            .stroke(color.gradient, style: StrokeStyle(lineWidth: width, lineCap: .round))
            .rotationEffect(.degrees(-90))
    }
}

/// 详情页里的周期卡片
struct CycleCard: View {
    let girl: Girl
    let info: CycleInfo

    @Environment(\.modelContext) private var context

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 18) {
                CycleRing(info: info, size: 116)
                VStack(alignment: .leading, spacing: 10) {
                    if info.isOngoing, let n = info.dayOfCycle(on: Date()) {
                        metric("经期中", "第 \(n) 天", Palette.period)
                    } else if let days = info.daysUntilNext, let next = info.nextStart {
                        metric("下次经期", days == 0 ? "今天" : "\(days) 天后", Palette.period,
                               detail: Fmt.shortDate(next))
                    }
                    if let window = info.nextFertileWindow {
                        metric("易孕期", "\(Fmt.shortDate(window.start)) - \(Fmt.shortDate(window.end))", Palette.fertile)
                    }
                    metric("平均周期", "\(info.averageCycle) 天 · 经期 \(info.averagePeriodLength) 天", .secondary)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 10) {
                if info.isOngoing {
                    pill("结束了", "checkmark", Palette.period) {
                        girl.update { $0.endPeriod(on: Date()) }
                    }
                } else {
                    pill("今天来了", "drop.fill", Palette.period) {
                        girl.update { $0.startPeriod(on: Date()) }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 6)
    }

    private func metric(_ title: String, _ value: String, _ color: Color, detail: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(value)
                    .font(.subheadline.weight(.semibold))
                    .fontDesign(.rounded)
                    .foregroundStyle(color == .secondary ? Color.primary : color)
                if let detail {
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func pill(_ title: String, _ symbol: String, _ color: Color, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.snappy) { action() }
        } label: {
            Label(title, systemImage: symbol)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .foregroundStyle(color)
                .background(color.opacity(0.12), in: Capsule())
        }
        .buttonStyle(.borderless)
        .sensoryFeedback(.success, trigger: girl.details.periodEntries.count)
    }
}

// MARK: - 她的周期页

struct GirlCycleView: View {
    let girl: Girl

    @State private var month = MonthCalendarView.calendar.date(
        from: MonthCalendarView.calendar.dateComponents([.year, .month], from: Date())) ?? Date()
    @State private var selection = Calendar.current.startOfDay(for: Date())
    @State private var editing: PeriodEntry?
    @State private var adding = false

    var body: some View {
        let d = girl.details
        let info = d.cycle
        let encounterDays = Set(girl.encounters.map { Calendar.current.startOfDay(for: $0.date) })
        List {
            if info.hasData {
                Section {
                    CycleCard(girl: girl, info: info)
                }
            }

            Section {
                MonthCalendarView(month: $month, selection: $selection) { day in
                    var dec = DayDecoration()
                    switch info.kind(on: day) {
                    case .period(let predicted): dec.band = predicted ? .predictedPeriod : .period
                    case .fertile: dec.band = .fertile
                    case .ovulation:
                        dec.band = .fertile
                        dec.ovulation = true
                    case .none: break
                    }
                    if encounterDays.contains(Calendar.current.startOfDay(for: day)) {
                        dec.dots.append(Palette.encounter)
                    }
                    return dec
                }
                .padding(.vertical, 6)
                HStack(spacing: 14) {
                    band(Palette.period.opacity(0.25), "经期")
                    band(Palette.period.opacity(0.08), "预测经期", dashed: true)
                    band(Palette.fertile.opacity(0.3), "易孕期")
                    HStack(spacing: 4) {
                        Circle().fill(Palette.encounter).frame(width: 6, height: 6)
                        Text("约会")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            } footer: {
                Text(selectionText(info))
            }

            Section {
                ForEach(d.periodEntries.reversed()) { entry in
                    Button {
                        editing = entry
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(Fmt.date(entry.start)).foregroundStyle(.primary)
                                Text(lengthText(entry, info: info)).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if let gap = gapAfter(entry, in: d.periodEntries) {
                                Text("周期 \(gap) 天").font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .onDelete { idx in
                    let reversed = Array(d.periodEntries.reversed())
                    let ids = Set(idx.map { reversed[$0].id })
                    girl.update { details in details.setPeriods(details.periodEntries.filter { !ids.contains($0.id) }) }
                }
                Button {
                    adding = true
                } label: {
                    Label("补记一次", systemImage: "plus")
                }
            } header: {
                Text("记录（\(d.periodEntries.count)）")
            } footer: {
                Text("预测基于最近 6 次记录的平均值，仅供参考，不能代替避孕措施。")
            }
        }
        .navigationTitle("\(girl.name) 的周期")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { entry in
            PeriodEditSheet(entry: entry) { updated in
                girl.update { details in
                    var list = details.periodEntries
                    if let i = list.firstIndex(where: { $0.id == updated.id }) { list[i] = updated }
                    details.setPeriods(list)
                }
            } onDelete: {
                girl.update { details in details.setPeriods(details.periodEntries.filter { $0.id != entry.id }) }
            }
        }
        .sheet(isPresented: $adding) {
            PeriodEditSheet(entry: PeriodEntry(start: Calendar.current.startOfDay(for: selection))) { new in
                girl.update { details in details.setPeriods(details.periodEntries + [new]) }
            }
        }
    }

    private func band(_ color: Color, _ text: String, dashed: Bool = false) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 3)
                .fill(color)
                .overlay {
                    if dashed {
                        RoundedRectangle(cornerRadius: 3)
                            .strokeBorder(Palette.period.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                    }
                }
                .frame(width: 12, height: 8)
            Text(text)
        }
    }

    private func selectionText(_ info: CycleInfo) -> String {
        var parts = [Fmt.date(selection)]
        if let n = info.dayOfCycle(on: selection) { parts.append("周期第 \(n) 天") }
        if let phase = info.phase(on: selection) { parts.append(phase.title) }
        return parts.joined(separator: " · ")
    }

    private func lengthText(_ entry: PeriodEntry, info: CycleInfo) -> String {
        guard let end = entry.end else {
            return info.isOngoing && entry.id == info.entries.last?.id ? "进行中" : "没记结束（按 \(info.averagePeriodLength) 天算）"
        }
        return "持续 \(Fmt.days(from: entry.start, to: end) + 1) 天"
    }

    private func gapAfter(_ entry: PeriodEntry, in list: [PeriodEntry]) -> Int? {
        guard let i = list.firstIndex(where: { $0.id == entry.id }), i + 1 < list.count else { return nil }
        return Fmt.days(from: entry.start, to: list[i + 1].start)
    }
}

struct PeriodEditSheet: View {
    let onSave: (PeriodEntry) -> Void
    var onDelete: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var entry: PeriodEntry
    @State private var hasEnd: Bool

    init(entry: PeriodEntry, onSave: @escaping (PeriodEntry) -> Void, onDelete: (() -> Void)? = nil) {
        self.onSave = onSave
        self.onDelete = onDelete
        _entry = State(initialValue: entry)
        _hasEnd = State(initialValue: entry.end != nil)
    }

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("开始", selection: $entry.start, in: ...Date(), displayedComponents: .date)
                Toggle("已结束", isOn: $hasEnd.animation(.snappy))
                if hasEnd {
                    DatePicker("最后一天", selection: Binding(
                        get: { entry.end ?? entry.start },
                        set: { entry.end = $0 }
                    ), in: entry.start...Date.distantFuture, displayedComponents: .date)
                }
                if let onDelete {
                    Section {
                        Button("删除这条记录", role: .destructive) {
                            onDelete()
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle("经期")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        var e = entry
                        e.start = Calendar.current.startOfDay(for: e.start)
                        e.end = hasEnd ? Calendar.current.startOfDay(for: max(e.end ?? e.start, e.start)) : nil
                        onSave(e)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
