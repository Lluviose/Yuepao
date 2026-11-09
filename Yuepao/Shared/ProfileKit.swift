import SwiftUI

/// 档案编辑和档案详情共用的组件：可折叠卡片、输入行、数字格、十格评分、MBTI、关系状态

// MARK: - 可折叠卡片

/// 收起时只显示标题和摘要，点开在原地展开内容
struct FoldCard<Content: View>: View {
    let title: String
    let symbol: String
    let summary: String
    var tint: Color
    var identifier: String?
    let content: () -> Content

    @State private var expanded: Bool

    init(_ title: String, symbol: String, summary: String, tint: Color = .accentColor,
         expanded: Bool = false, identifier: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.symbol = symbol
        self.summary = summary
        self.tint = tint
        self.identifier = identifier
        self.content = content
        _expanded = State(initialValue: expanded)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.snappy(duration: 0.34)) { expanded.toggle() }
            } label: {
                HStack(spacing: 12) {
                    IconBadge(symbol: symbol, color: tint, size: 34)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(Typo.display(17))
                            .foregroundStyle(.primary)
                        if !expanded {
                            Text(summary)
                                .font(.caption)
                                .foregroundStyle(summary == FoldCardSummary.empty
                                                 ? HierarchicalShapeStyle.tertiary : HierarchicalShapeStyle.secondary)
                                .lineLimit(1)
                                .transition(.opacity)
                        }
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.down")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(identifier ?? "fold-\(title)")

            if expanded {
                VStack(alignment: .leading, spacing: 14) {
                    content()
                }
                .padding(.top, 18)
                .transition(.opacity)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(Color(uiColor: .secondarySystemGroupedBackground)))
    }
}

enum FoldCardSummary {
    static let empty = "未填写"

    /// 把填了的几项用「·」连起来，一项都没有就是「未填写」
    static func join(_ parts: [String?]) -> String {
        let list = parts.compactMap { $0?.trimmed }.filter { !$0.isEmpty }
        return list.isEmpty ? empty : list.joined(separator: " · ")
    }
}

// MARK: - 输入

/// 卡片里的一行输入：左边名字，右边输入框；多行时名字在上
struct CardField: View {
    let title: String
    @Binding var text: String
    var prompt = "未填写"
    var multiline = false

    var body: some View {
        if multiline {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                TextField(prompt, text: $text, axis: .vertical)
                    .lineLimit(1...8)
            }
        } else {
            HStack(spacing: 12) {
                Text(title)
                Spacer(minLength: 12)
                TextField(prompt, text: $text)
                    .multilineTextAlignment(.trailing)
            }
        }
    }
}

/// 大号数字输入格：身高、体重、三围
struct NumberTile: View {
    let title: String
    @Binding var value: Int?
    var unit = ""
    var size: CGFloat = 26

    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                TextField("—", text: Binding(
                    get: { value.map { String($0) } ?? "" },
                    set: { text in value = Int(text.filter { $0.isASCII && $0.isNumber }.prefix(4)) }
                ))
                .keyboardType(.numberPad)
                .font(Typo.display(size, weight: .medium))
                .monospacedDigit()
                .fixedSize()
                .focused($focused)
                if !unit.isEmpty {
                    Text(unit)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color(uiColor: .tertiarySystemFill).opacity(focused ? 1 : 0.7)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(focused ? Color.accentColor.opacity(0.5) : Color.clear, lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture { focused = true }
        .animation(.snappy(duration: 0.2), value: focused)
    }
}

extension Binding where Value == String {
    /// 把单选的字符串当成最多一个元素的数组，好直接用多选的标签组件
    var asSingleSelection: Binding<[String]> {
        Binding<[String]>(
            get: { wrappedValue.isEmpty ? [] : [wrappedValue] },
            set: { wrappedValue = $0.last ?? "" }
        )
    }
}

// MARK: - 十格评分

/// 1-10 分：点第几格就是几分，再点一次清零。只读时用来展示
struct ScoreBar: View {
    let title: String
    @Binding var value: Int
    var tint: Color = Palette.gold
    var editable = true

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.subheadline)
                .lineLimit(1)
                .frame(width: 64, alignment: .leading)
            HStack(spacing: 3) {
                ForEach(1...10, id: \.self) { i in
                    segment(i)
                }
            }
            Text(value == 0 ? "—" : "\(value)")
                .font(Typo.display(17, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(value == 0 ? Color.secondary : tint)
                .frame(width: 26, alignment: .trailing)
                .contentTransition(.numericText())
        }
        .sensoryFeedback(.selection, trigger: editable ? value : 0)
        .accessibilityElement(children: editable ? .contain : .combine)
    }

    @ViewBuilder
    private func segment(_ i: Int) -> some View {
        let bar = Capsule()
            .fill(i <= value ? tint : Color(uiColor: .tertiarySystemFill))
            .frame(height: 8)
        if editable {
            Button {
                withAnimation(.snappy(duration: 0.2)) { value = value == i ? 0 : i }
            } label: {
                bar
                    .padding(.vertical, 9)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(title) \(i) 分")
        } else {
            bar
        }
    }
}

// MARK: - MBTI

/// 四个维度各选一边，拼出类型；没选的维度用「?」占位
struct MBTIPicker: View {
    @Binding var mbti: String

    private static let axes: [(String, String)] = [("E", "I"), ("S", "N"), ("T", "F"), ("J", "P")]

    static let nicknames: [String: String] = [
        "INTJ": "建筑师", "INTP": "逻辑学家", "ENTJ": "指挥官", "ENTP": "辩论家",
        "INFJ": "提倡者", "INFP": "调停者", "ENFJ": "主人公", "ENFP": "竞选者",
        "ISTJ": "物流师", "ISFJ": "守卫者", "ESTJ": "总经理", "ESFJ": "执政官",
        "ISTP": "鉴赏家", "ISFP": "探险家", "ESTP": "企业家", "ESFP": "表演者"
    ]

    private func letter(at index: Int) -> String? {
        let chars = Array(mbti.uppercased())
        guard index < chars.count else { return nil }
        let c = String(chars[index])
        let axis = Self.axes[index]
        return c == axis.0 || c == axis.1 ? c : nil
    }

    private func set(_ letter: String?, at index: Int) {
        var letters = (0..<4).map { self.letter(at: $0) }
        letters[index] = letter
        mbti = letters.allSatisfy { $0 == nil } ? "" : letters.map { $0 ?? "?" }.joined()
    }

    private var type: String { mbti.uppercased() }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            ForEach(0..<4, id: \.self) { index in
                let axis = Self.axes[index]
                let current = letter(at: index)
                VStack(spacing: 0) {
                    side(axis.0, selected: current == axis.0) { set(current == axis.0 ? nil : axis.0, at: index) }
                    side(axis.1, selected: current == axis.1) { set(current == axis.1 ? nil : axis.1, at: index) }
                }
                .background(Capsule().fill(Color(uiColor: .tertiarySystemFill).opacity(0.7)))
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(type.isEmpty ? "—" : type)
                    .font(Typo.display(24, weight: .semibold))
                    .foregroundStyle(type.isEmpty ? Color.secondary : Color.primary)
                    .contentTransition(.numericText())
                Text(Self.nicknames[type] ?? (type.isEmpty ? "点字母选择" : "还差几项"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .sensoryFeedback(.selection, trigger: mbti)
    }

    private func side(_ letter: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.snappy(duration: 0.22)) { action() }
        } label: {
            Text(letter)
                .font(.system(size: 15, weight: selected ? .bold : .regular, design: .serif))
                .foregroundStyle(selected ? Color.white : Color.secondary)
                .frame(width: 34, height: 32)
                .background {
                    if selected {
                        Capsule().fill(Color.accentColor)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.chip)
        .accessibilityLabel("MBTI \(letter)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - 关系状态

/// 一排关系状态，选中的底色会滑过去
struct StatusPicker: View {
    @Binding var status: RelationStatus

    @Namespace private var ns

    var body: some View {
        ScrollChips {
            ForEach(RelationStatus.allCases) { s in
                let on = status == s
                Button {
                    withAnimation(.snappy(duration: 0.3)) { status = s }
                } label: {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(s.color)
                            .frame(width: 7, height: 7)
                        Text(s.title)
                            .font(.subheadline.weight(on ? .semibold : .regular))
                            .foregroundStyle(on ? s.color : Color.primary.opacity(0.8))
                    }
                    .padding(.horizontal, 13)
                    .padding(.vertical, 8)
                    .background {
                        if on {
                            Capsule()
                                .fill(s.color.opacity(0.15))
                                .overlay(Capsule().strokeBorder(s.color.opacity(0.55), lineWidth: 1))
                                .matchedGeometryEffect(id: "status", in: ns)
                        } else {
                            Capsule().fill(Color(uiColor: .tertiarySystemFill))
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.chip)
                .accessibilityIdentifier("status-\(s.rawValue)")
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .sensoryFeedback(.selection, trigger: status)
    }
}

// MARK: - 可选日期

/// 卡片里的可选日期：没设时是「设置」按钮，设了以后是日期选择加清除
struct DateFieldRow: View {
    let title: String
    @Binding var date: Date?
    /// 第一次设置时默认往前推几年（生日用）
    var yearsAgo = 0

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
            Spacer(minLength: 8)
            if date != nil {
                DatePicker(title, selection: Binding(get: { date ?? Date() }, set: { date = $0 }),
                           displayedComponents: .date)
                    .labelsHidden()
                    .transition(.opacity)
                Button {
                    withAnimation(.snappy(duration: 0.25)) { date = nil }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("清除\(title)")
            } else {
                Button {
                    let today = Calendar.current.startOfDay(for: Date())
                    let initial = Calendar.current.date(byAdding: .year, value: -yearsAgo, to: today) ?? today
                    withAnimation(.snappy(duration: 0.25)) { date = initial }
                } label: {
                    Text("设置")
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color(uiColor: .tertiarySystemFill)))
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("设置\(title)")
            }
        }
    }
}
