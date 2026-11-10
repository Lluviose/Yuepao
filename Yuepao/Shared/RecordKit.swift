import SwiftUI

/// 记录表单和记录详情共用的组件：卡片、可折叠的标签选择、计数格、强度条、防护选择块

// MARK: - 卡片

/// 圆角卡片：小标题 + 内容
struct RecordCard<Content: View, Trailing: View>: View {
    let title: String?
    let trailing: Trailing
    let content: Content

    init(_ title: String? = nil, @ViewBuilder trailing: () -> Trailing, @ViewBuilder content: () -> Content) {
        self.title = title
        self.trailing = trailing()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let title {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(title).eyebrow()
                    Spacer(minLength: 8)
                    trailing
                }
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(Palette.surface))
    }
}

extension RecordCard where Trailing == EmptyView {
    init(_ title: String? = nil, @ViewBuilder content: () -> Content) {
        self.init(title, trailing: { EmptyView() }, content: content)
    }
}

/// 卡片右上角的「全部 ›」
struct CardLinkLabel: View {
    let text: String

    var body: some View {
        HStack(spacing: 3) {
            Text(text)
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
        }
        .font(.footnote.weight(.medium))
        .foregroundStyle(.secondary)
        .contentShape(Rectangle())
    }
}

/// 卡片里的小字段名，右边可以带当前值
struct FieldLabel: View {
    let title: String
    var value: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            if let value {
                Text(value)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Color.accentColor)
                    .contentTransition(.opacity)
            }
        }
    }
}

/// 卡片里两行之间的分隔线，和行首图标对齐
struct RowDivider: View {
    var inset: CGFloat = 44

    var body: some View {
        Divider()
            .padding(.leading, inset)
            .padding(.vertical, 11)
    }
}

/// 卡片里横向滚动的一行
struct ScrollChips<Content: View>: View {
    var inset: CGFloat = 16
    var spacing: CGFloat = 8
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: spacing) {
                content()
            }
            .padding(.horizontal, inset)
            .padding(.vertical, 1)
        }
        .padding(.horizontal, -inset)
    }
}

// MARK: - 标签

/// 多选标签：选中后变成主题色的描边浅底，宽度不变，不会挤动别的标签
struct TagChip: View {
    let title: String
    let selected: Bool
    var tint: Color = .accentColor
    /// 她档案里写着喜欢的：前面带一颗小红心
    var marked = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if marked {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(Color.accentColor.opacity(selected ? 1 : 0.7))
                }
                Text(title)
            }
            .font(.subheadline)
            .lineLimit(1)
            .padding(.horizontal, 13)
            .padding(.vertical, 7)
            .foregroundStyle(selected ? tint : Color.primary.opacity(0.82))
            .background(Capsule().fill(selected ? tint.opacity(0.14) : Palette.fill))
            .overlay(Capsule().strokeBorder(selected ? tint.opacity(0.6) : Palette.hairline,
                                            lineWidth: selected ? 1 : 0.5))
            .contentShape(Capsule())
        }
        .buttonStyle(.chip)
        .sensoryFeedback(.selection, trigger: selected)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// 一组可多选的标签，直接在页面里点选；长列表按类别分组，末尾可以现场加新选项
struct TagCloud: View {
    let key: OptionKey
    @Binding var selection: [String]
    var tint: Color = .accentColor
    /// 标上小红心的选项（她喜欢的）
    var marked: Set<String> = []

    @ObservedObject private var config = ConfigStore.shared
    @State private var adding = false
    @State private var newName = ""

    private var options: [String] {
        let list = config.options(key)
        return list + selection.filter { !list.contains($0) }
    }

    var body: some View {
        let all = options
        VStack(alignment: .leading, spacing: 14) {
            if let groups = OptionGroups.groups(for: key, options: all) {
                ForEach(groups) { group in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(group.title)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        FlowLayout(spacing: 8) {
                            ForEach(group.items, id: \.self) { chip($0) }
                        }
                    }
                }
                addButton
            } else {
                FlowLayout(spacing: 8) {
                    ForEach(all, id: \.self) { chip($0) }
                    addButton
                }
            }
        }
        .alert("添加\(key.title)", isPresented: $adding) {
            TextField("名称", text: $newName)
            Button("添加") { add() }
            Button("取消", role: .cancel) { newName = "" }
        } message: {
            Text("会加进选项列表，以后都能选")
        }
    }

    private func chip(_ option: String) -> some View {
        TagChip(title: option, selected: selection.contains(option), tint: tint, marked: marked.contains(option)) {
            toggle(option)
        }
    }

    private var addButton: some View {
        Button {
            adding = true
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "plus")
                    .font(.caption.weight(.semibold))
                Text("自定义")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .overlay(Capsule().strokeBorder(Color.secondary.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
            .contentShape(Capsule())
        }
        .buttonStyle(.chip)
        .accessibilityIdentifier("addOption-\(key.rawValue)")
    }

    private func toggle(_ option: String) {
        withAnimation(.snappy(duration: 0.2)) {
            if let i = selection.firstIndex(of: option) {
                selection.remove(at: i)
            } else {
                selection.append(option)
            }
        }
    }

    private func add() {
        let value = newName.trimmed
        newName = ""
        guard !value.isEmpty else { return }
        config.addOption(value, to: key)
        if !selection.contains(value) {
            withAnimation(.snappy(duration: 0.2)) { selection.append(value) }
        }
    }
}

/// 可折叠的一行：收起时显示已选的内容，点开在原地多选
struct TagDisclosure: View {
    let title: String
    let symbol: String
    let key: OptionKey
    @Binding var selection: [String]
    var tint: Color = .accentColor
    var note: String?
    var identifier: String?
    var marked: Set<String> = []

    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.snappy(duration: 0.32)) { expanded.toggle() }
            } label: {
                HStack(spacing: 12) {
                    IconBadge(symbol: symbol, color: tint, size: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .foregroundStyle(.primary)
                        Text(selection.isEmpty ? "未选择" : selection.joined(separator: "、"))
                            .font(.caption)
                            .foregroundStyle(selection.isEmpty ? HierarchicalShapeStyle.tertiary : HierarchicalShapeStyle.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    if !selection.isEmpty {
                        Text("\(selection.count)")
                            .font(.caption.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(tint)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(tint.opacity(0.12)))
                            .contentTransition(.numericText())
                    }
                    Image(systemName: "chevron.down")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(identifier ?? "tags-\(key.rawValue)")

            if expanded {
                VStack(alignment: .leading, spacing: 12) {
                    TagCloud(key: key, selection: $selection, tint: tint, marked: marked)
                    if let note {
                        Text(note)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if !marked.isEmpty {
                        Label("带小红心的是她档案里写着喜欢的", systemImage: "heart.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 14)
                .transition(.opacity)
            }
        }
    }
}

/// 只读的一组标签（详情页用）
struct TagGroupView: View {
    let title: String
    let symbol: String
    let items: [String]
    var tint: Color?

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.caption)
                    .foregroundStyle(tint ?? Color.secondary)
                    .frame(width: 16)
                Text(title)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            FlowLayout(spacing: 6) {
                ForEach(items, id: \.self) { item in
                    Text(item)
                        .font(.footnote)
                        .foregroundStyle(tint ?? Color.primary.opacity(0.82))
                        .padding(.horizontal, 11)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(tint.map { $0.opacity(0.12) } ?? Palette.fill))
                        .overlay(Capsule().strokeBorder(tint.map { $0.opacity(0.35) } ?? Palette.hairline, lineWidth: 0.5))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - 单选胶囊

/// 一排单选胶囊，再点一次取消
struct PillChoice: View {
    let options: [String]
    @Binding var selection: String
    var identifier = "pill"

    var body: some View {
        HStack(spacing: 8) {
            ForEach(options, id: \.self) { option in
                ChoiceChip(title: option, selected: selection == option) {
                    selection = selection == option ? "" : option
                }
                .accessibilityIdentifier("\(identifier)-\(option)")
            }
        }
    }
}

// MARK: - 计数

/// 大号衬线数字 + 加减按钮
struct CounterTile: View {
    let title: String
    let value: String
    var caption: String?
    let canDecrement: Bool
    let canIncrement: Bool
    let identifier: String
    let onDecrement: () -> Void
    let onIncrement: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.footnote)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(value)
                    .font(Typo.display(38, weight: .medium))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .accessibilityIdentifier("\(identifier)-value")
                if let caption {
                    Text(caption)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            HStack(spacing: 8) {
                stepButton("minus", enabled: canDecrement, action: onDecrement)
                    .accessibilityLabel("\(title)减一")
                    .accessibilityIdentifier("\(identifier)-minus")
                stepButton("plus", enabled: canIncrement, action: onIncrement)
                    .accessibilityLabel("\(title)加一")
                    .accessibilityIdentifier("\(identifier)-plus")
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(Palette.fill.opacity(0.7)))
        .sensoryFeedback(.selection, trigger: value)
    }

    private func stepButton(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.snappy(duration: 0.25)) { action() }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(enabled ? Color.primary : Color.secondary.opacity(0.35))
                .frame(maxWidth: .infinity)
                .frame(height: 34)
                .background(Capsule().fill(Palette.surface))
                .overlay(Capsule().strokeBorder(Palette.hairline, lineWidth: 0.5))
                .contentShape(Capsule())
        }
        .buttonStyle(.chip)
        .disabled(!enabled)
        .buttonRepeatBehavior(.enabled)
    }
}

// MARK: - 强度

/// 四格强度条：越往右越高、越深
struct IntensityPicker: View {
    @Binding var value: Int

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            ForEach(Intensity.allCases) { level in
                let lit = value >= level.rawValue
                let current = value == level.rawValue
                Button {
                    withAnimation(.snappy(duration: 0.25)) { value = current ? 0 : level.rawValue }
                } label: {
                    VStack(spacing: 8) {
                        ZStack(alignment: .bottom) {
                            Color.clear.frame(height: 28)
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(barColor(level, lit: lit))
                                .frame(height: barHeight(level))
                        }
                        Text(level.title)
                            .font(.footnote.weight(current ? .semibold : .regular))
                            .foregroundStyle(current ? Color.accentColor : (lit ? Color.primary : Color.secondary))
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.chip)
                .accessibilityLabel("强度\(level.title)")
                .accessibilityAddTraits(current ? .isSelected : [])
                .accessibilityIdentifier("intensity-\(level.rawValue)")
            }
        }
        .sensoryFeedback(.selection, trigger: value)
    }

    private func barColor(_ level: Intensity, lit: Bool) -> Color {
        guard lit else { return Palette.fill }
        let strength = 0.3 + 0.7 * Double(level.rawValue) / 4
        return Color.accentColor.opacity(strength)
    }

    private func barHeight(_ level: Intensity) -> CGFloat {
        10 + CGFloat(level.rawValue) * 4.5
    }
}

/// 详情页里的小强度图标
struct IntensityGlyph: View {
    let value: Int
    var height: CGFloat = 12

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(1...4, id: \.self) { level in
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(level <= value ? Color.accentColor : Color.secondary.opacity(0.25))
                    .frame(width: 3, height: height * (0.4 + 0.15 * CGFloat(level)))
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - 防护

/// 一排五个选择块，再点一次回到「未记录」
struct ProtectionPicker: View {
    @Binding var value: Protection

    private let options: [Protection] = [.condom, .both, .pill, .withdrawal, .none]

    var body: some View {
        HStack(spacing: 7) {
            ForEach(options) { p in
                let on = value == p
                Button {
                    withAnimation(.snappy(duration: 0.22)) { value = on ? .unrecorded : p }
                } label: {
                    VStack(spacing: 7) {
                        Image(systemName: p.tileSymbol)
                            .font(.system(size: 18, weight: .regular))
                            .symbolRenderingMode(.hierarchical)
                            .frame(height: 22)
                        Text(p.shortTitle)
                            .font(.caption.weight(on ? .semibold : .regular))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .foregroundStyle(on ? p.color : Color.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(on ? p.color.opacity(0.13) : Palette.fill.opacity(0.7)))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(on ? p.color.opacity(0.55) : Color.clear, lineWidth: 1))
                    .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.chip)
                .accessibilityLabel(p.title)
                .accessibilityAddTraits(on ? .isSelected : [])
                .accessibilityIdentifier("protection-\(p.rawValue)")
            }
        }
        .sensoryFeedback(.selection, trigger: value)
    }
}

// MARK: - 评分

enum RatingWords {
    static func word(_ value: Int) -> String? {
        switch value {
        case 1: return "一般"
        case 2: return "还行"
        case 3: return "不错"
        case 4: return "很好"
        case 5: return "完美"
        default: return nil
        }
    }
}

/// 大号星级，再点一次同一颗清零
struct StarPicker: View {
    @Binding var value: Int
    var size: CGFloat = 22
    var identifier = "stars"

    var body: some View {
        HStack(spacing: 7) {
            ForEach(1...5, id: \.self) { i in
                Button {
                    withAnimation(.snappy(duration: 0.2)) { value = value == i ? 0 : i }
                } label: {
                    Image(systemName: i <= value ? "star.fill" : "star")
                        .font(.system(size: size, weight: .light))
                        .foregroundStyle(i <= value ? Palette.gold : Color.secondary.opacity(0.35))
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: size + 6, height: size + 6)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.chip)
                .accessibilityLabel("\(i) 星")
                .accessibilityIdentifier("\(identifier)-\(i)")
            }
        }
        .sensoryFeedback(.selection, trigger: value)
    }
}

// MARK: - 指标条

struct MetricItem: Identifiable {
    let label: String
    let value: String
    var unit: String = ""
    var id: String { label }
}

/// 一排大数字，中间用细线隔开
struct MetricStrip: View {
    let items: [MetricItem]
    /// 数字的字号
    var size: CGFloat = 24

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                if index > 0 {
                    Rectangle()
                        .fill(Palette.hairline)
                        .frame(width: 0.5, height: 36)
                }
                VStack(spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(item.value)
                            .font(Typo.display(size, weight: .medium))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        if !item.unit.isEmpty {
                            Text(item.unit)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text(item.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}

/// 详情页里带图标的一行
struct DetailLine: View {
    let symbol: String
    var tint: Color = .secondary
    let title: String
    var subtitle: String?

    var body: some View {
        HStack(spacing: 12) {
            IconBadge(symbol: symbol, color: tint, size: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .foregroundStyle(.primary)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
    }
}
