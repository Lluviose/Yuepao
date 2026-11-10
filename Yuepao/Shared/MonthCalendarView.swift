import SwiftUI

/// 日历格子上的装饰
struct DayDecoration {
    enum Band {
        case period, predictedPeriod, fertile
    }

    var dots: [Color] = []
    var band: Band?
    var ovulation = false
}

/// 月历：左右滑动切换月份，选中态平滑移动
struct MonthCalendarView: View {
    @Binding var month: Date
    @Binding var selection: Date
    let decoration: (Date) -> DayDecoration

    @Namespace private var namespace
    @State private var forward = true

    static var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2
        cal.locale = Fmt.locale
        cal.timeZone = .current
        return cal
    }

    private var cal: Calendar { Self.calendar }

    private var days: [Date?] {
        guard let range = cal.range(of: .day, in: .month, for: month) else { return [] }
        let first = startOfMonth(month)
        let lead = (cal.component(.weekday, from: first) + 5) % 7
        var result: [Date?] = Array(repeating: nil, count: lead)
        for d in range {
            result.append(cal.date(byAdding: .day, value: d - 1, to: first))
        }
        while result.count % 7 != 0 { result.append(nil) }
        return result
    }

    func startOfMonth(_ date: Date) -> Date {
        cal.date(from: cal.dateComponents([.year, .month], from: date)) ?? date
    }

    var body: some View {
        VStack(spacing: 10) {
            header
            weekdayRow
            grid
                .id(startOfMonth(month))
                .transition(.asymmetric(
                    insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                    removal: .opacity
                ))
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 24)
                .onEnded { value in
                    guard abs(value.translation.width) > abs(value.translation.height) else { return }
                    if value.translation.width < -40 { shift(1) }
                    if value.translation.width > 40 { shift(-1) }
                }
        )
        .clipped()
    }

    private var header: some View {
        HStack(spacing: 14) {
            Text(Fmt.month(month))
                .font(Typo.display(20))
                .contentTransition(.numericText())
            Spacer()
            if !cal.isDate(month, equalTo: Date(), toGranularity: .month) || !cal.isDateInToday(selection) {
                Button("今天") {
                    let today = cal.startOfDay(for: Date())
                    forward = today > month
                    withAnimation(.snappy) {
                        month = startOfMonth(today)
                        selection = today
                    }
                }
                .font(.subheadline.weight(.medium))
                .buttonStyle(.borderless)
                .transition(.opacity.combined(with: .scale))
            }
            Button { shift(-1) } label: {
                Image(systemName: "chevron.left").font(.body.weight(.semibold))
            }
            .buttonStyle(.borderless)
            Button { shift(1) } label: {
                Image(systemName: "chevron.right").font(.body.weight(.semibold))
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 4)
    }

    private var weekdayRow: some View {
        HStack(spacing: 0) {
            ForEach(["一", "二", "三", "四", "五", "六", "日"], id: \.self) { w in
                Text(w)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(w == "六" || w == "日" ? HierarchicalShapeStyle.tertiary : HierarchicalShapeStyle.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var grid: some View {
        let items = days
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 4) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, date in
                if let date {
                    DayCell(
                        date: date,
                        isSelected: cal.isDate(date, inSameDayAs: selection),
                        isToday: cal.isDateInToday(date),
                        decoration: decoration(date),
                        namespace: namespace
                    )
                    .onTapGesture {
                        withAnimation(.snappy(duration: 0.28)) { selection = date }
                    }
                } else {
                    Color.clear.frame(height: 46)
                }
            }
        }
        .sensoryFeedback(.selection, trigger: selection)
    }

    private func shift(_ delta: Int) {
        guard let next = cal.date(byAdding: .month, value: delta, to: startOfMonth(month)) else { return }
        forward = delta > 0
        withAnimation(.snappy(duration: 0.32)) {
            month = next
            if !cal.isDate(selection, equalTo: next, toGranularity: .month) {
                selection = cal.isDate(next, equalTo: Date(), toGranularity: .month) ? cal.startOfDay(for: Date()) : next
            }
        }
    }
}

private struct DayCell: View {
    let date: Date
    let isSelected: Bool
    let isToday: Bool
    let decoration: DayDecoration
    let namespace: Namespace.ID

    var body: some View {
        VStack(spacing: 3) {
            ZStack {
                if isSelected {
                    Circle()
                        .fill(Palette.wineGradient)
                        .shadow(color: Palette.wineBottom.opacity(0.28), radius: 5, y: 2)
                        .matchedGeometryEffect(id: "selection", in: namespace)
                } else if isToday {
                    Circle().stroke(Color.accentColor.opacity(0.6), lineWidth: 1.5)
                }
                if decoration.ovulation && !isSelected {
                    Circle()
                        .strokeBorder(Palette.fertile, style: StrokeStyle(lineWidth: 1.5, dash: [2.5, 2.5]))
                }
                Text("\(Calendar.current.component(.day, from: date))")
                    .font(.system(size: 16, weight: isToday || isSelected ? .semibold : .regular, design: .serif))
                    .monospacedDigit()
                    .foregroundStyle(textColor)
            }
            .frame(width: 34, height: 34)

            HStack(spacing: 3) {
                ForEach(Array(decoration.dots.prefix(4).enumerated()), id: \.offset) { _, color in
                    Circle().fill(color).frame(width: 5, height: 5)
                }
            }
            .frame(height: 5)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 2)
        .background(bandBackground)
        .contentShape(Rectangle())
    }

    private var textColor: Color {
        if isSelected { return .white }
        if isToday { return .accentColor }
        return .primary
    }

    @ViewBuilder
    private var bandBackground: some View {
        switch decoration.band {
        case .some(.period):
            RoundedRectangle(cornerRadius: 10).fill(Palette.period.opacity(0.16))
        case .some(.predictedPeriod):
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Palette.period.opacity(0.45), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                .background(RoundedRectangle(cornerRadius: 10).fill(Palette.period.opacity(0.06)))
        case .some(.fertile):
            RoundedRectangle(cornerRadius: 10).fill(Palette.fertile.opacity(0.12))
        case .none:
            Color.clear
        }
    }
}
