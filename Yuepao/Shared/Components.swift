import SwiftUI
import PhotosUI

// MARK: - 头像

struct AvatarView: View {
    let photoID: String?
    let name: String
    var size: CGFloat = 44
    var ring: Color?

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        content
            .frame(width: size, height: size)
            .clipShape(Circle())
            .padding(ring == nil ? 0 : max(2, size / 22) + 1.5)
            .overlay {
                if let ring {
                    Circle().stroke(ring, lineWidth: max(2, size / 22))
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        if let photoID {
            AvatarPhoto(id: photoID, pixels: size * max(displayScale, 2)) { placeholder }
                .id(photoID)
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        ZStack {
            Circle().fill(Palette.avatarGradient(for: name))
            Text(String(name.prefix(1)))
                .font(.system(size: size * 0.4, weight: .medium, design: .serif))
                .foregroundStyle(Color.white.opacity(0.95))
        }
    }
}

/// 头像照片：先查缓存，没有再到后台解出缩略图，不卡列表
private struct AvatarPhoto<Placeholder: View>: View {
    let id: String
    let pixels: CGFloat
    let placeholder: Placeholder

    @State private var image: UIImage?

    init(id: String, pixels: CGFloat, @ViewBuilder placeholder: () -> Placeholder) {
        self.id = id
        self.pixels = pixels
        self.placeholder = placeholder()
        _image = State(initialValue: MediaStore.shared.cachedThumbnail(id, size: pixels))
    }

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .transition(.opacity)
            } else {
                placeholder
            }
        }
        .task(id: id) {
            guard image == nil else { return }
            let loaded = await MediaStore.shared.loadThumbnail(id, size: pixels)
            withAnimation(.easeOut(duration: 0.2)) { image = loaded }
        }
    }
}

// MARK: - 小标签

/// 小标签：中性底色 + 一个小色点，不用大面积彩色
struct Badge: View {
    let text: String
    var color: Color = .accentColor

    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 5, height: 5)
            Text(text)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Palette.fill, in: Capsule())
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: min(widest, maxWidth), height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

struct ChipsView: View {
    let items: [String]
    var color: Color = .accentColor

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(items, id: \.self) { item in
                Text(item)
                    .font(.footnote)
                    .foregroundStyle(Color.primary.opacity(0.8))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Palette.fill))
                    .overlay(Capsule().stroke(Palette.hairline, lineWidth: 0.5))
            }
        }
    }
}

// MARK: - 表单输入

struct DecimalField: View {
    let title: String
    @Binding var value: Double
    @State private var text = ""

    var body: some View {
        TextField(title, text: $text)
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.trailing)
            .onAppear { text = value == 0 ? "" : Self.format(value) }
            .onChange(of: text) { _, newValue in
                value = Double(newValue.replacingOccurrences(of: ",", with: ".")) ?? 0
            }
    }

    static func format(_ v: Double) -> String {
        v == v.rounded() && abs(v) < 1e12 ? String(Int(v)) : String(v)
    }
}

struct StarDisplay: View {
    let value: Int
    var max: Int = 5

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(1...max), id: \.self) { i in
                Image(systemName: i <= value ? "star.fill" : "star")
                    .font(.system(size: 9))
                    .foregroundStyle(i <= value ? Palette.gold : Color.secondary.opacity(0.3))
            }
        }
    }
}

// MARK: - 空状态 / 信息行

/// 空状态：两圈淡酒红的圆底托着图标，衬线标题，下面可以带一个主按钮
struct EmptyState: View {
    let symbol: String
    let title: String
    var message: String?
    var actionTitle: String?
    var action: (() -> Void)?

    /// 出现时外圈先铺开、图标弹一下，文字跟着浮上来
    @State private var shown = false

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.06))
                    .frame(width: 116, height: 116)
                    .scaleEffect(shown ? 1 : 0.7)
                Circle()
                    .fill(Color.accentColor.opacity(0.09))
                    .frame(width: 82, height: 82)
                    .scaleEffect(shown ? 1 : 0.8)
                Image(systemName: symbol)
                    .font(.system(size: 30, weight: .light))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.accentColor)
                    .scaleEffect(shown ? 1 : 0.6)
            }
            .opacity(shown ? 1 : 0)
            .accessibilityHidden(true)
            VStack(spacing: 6) {
                Text(title)
                    .font(Typo.display(21))
                if let message, !message.isEmpty {
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.wine)
                    .padding(.top, 4)
            }
        }
        .padding(.horizontal, 40)
        .frame(maxWidth: .infinity)
        .onAppear {
            withAnimation(.spring(duration: 0.6, bounce: 0.32)) { shown = true }
        }
    }
}

struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        LabeledContent(label) {
            Text(value).multilineTextAlignment(.trailing).textSelection(.enabled)
        }
    }
}

struct TextBlock: View {
    let label: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.subheadline).foregroundStyle(.secondary)
            Text(text).textSelection(.enabled)
        }
        .padding(.vertical, 2)
    }
}
