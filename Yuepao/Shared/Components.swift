import SwiftUI
import PhotosUI

// MARK: - 头像

struct AvatarView: View {
    let photoID: String?
    let name: String
    var size: CGFloat = 44
    var ring: Color?

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
        if let photoID, let image = PhotoStore.shared.thumbnail(photoID) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            ZStack {
                Circle().fill(Palette.avatarGradient(for: name))
                Text(String(name.prefix(1)))
                    .font(.system(size: size * 0.42, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
            }
        }
    }
}

// MARK: - 小标签

struct Badge: View {
    let text: String
    var color: Color = .accentColor

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundStyle(color)
            .background(color.opacity(0.14), in: Capsule())
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
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(color.opacity(0.12), in: Capsule())
            }
        }
    }
}

// MARK: - 表单输入

struct IntField: View {
    let title: String
    @Binding var value: Int?
    var unit: String = ""

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 4) {
                TextField("—", text: Binding(
                    get: { value.map { String($0) } ?? "" },
                    set: { text in value = Int(text.filter { $0.isASCII && $0.isNumber }) }
                ))
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                if !unit.isEmpty {
                    Text(unit).foregroundStyle(.secondary)
                }
            }
        }
    }
}

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

struct OptionalDateRow: View {
    let title: String
    @Binding var date: Date?
    var components: DatePickerComponents = .date

    var body: some View {
        if date != nil {
            HStack {
                DatePicker(title, selection: Binding(
                    get: { date ?? Date() },
                    set: { date = $0 }
                ), displayedComponents: components)
                Button {
                    date = nil
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
            }
        } else {
            Button {
                date = Date()
            } label: {
                LabeledContent(title) {
                    Text("未设置").foregroundStyle(.secondary)
                }
            }
            .tint(.primary)
        }
    }
}

/// 1-10 分（0 = 未评）
struct ScorePicker: View {
    let title: String
    @Binding var value: Int
    var max: Int = 10

    var body: some View {
        Picker(title, selection: $value) {
            Text("未评").tag(0)
            ForEach(Array(1...max), id: \.self) { n in
                Text("\(n) 分").tag(n)
            }
        }
    }
}

/// 星级（0 = 未评）
struct StarRating: View {
    @Binding var value: Int
    var max: Int = 5

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(1...max), id: \.self) { i in
                Button {
                    value = (value == i) ? 0 : i
                } label: {
                    Image(systemName: i <= value ? "star.fill" : "star")
                        .foregroundStyle(i <= value ? Color.orange : Color.secondary)
                }
                .buttonStyle(.borderless)
            }
        }
    }
}

struct StarDisplay: View {
    let value: Int
    var max: Int = 5

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(1...max), id: \.self) { i in
                Image(systemName: i <= value ? "star.fill" : "star")
                    .font(.caption2)
                    .foregroundStyle(i <= value ? Color.orange : Color.secondary.opacity(0.4))
            }
        }
    }
}

// MARK: - 选项选择（支持现场添加新选项）

struct OptionMultiPicker: View {
    let title: String
    let key: OptionKey
    @Binding var selection: [String]

    var body: some View {
        NavigationLink {
            OptionChoiceList(title: title, key: key, selection: $selection, multiple: true)
        } label: {
            LabeledContent(title) {
                Text(selection.isEmpty ? "未选择" : selection.joined(separator: "、"))
                    .lineLimit(1)
                    .foregroundStyle(selection.isEmpty ? HierarchicalShapeStyle.tertiary : HierarchicalShapeStyle.secondary)
            }
        }
    }
}

struct OptionSinglePicker: View {
    let title: String
    let key: OptionKey
    @Binding var selection: String

    var body: some View {
        NavigationLink {
            OptionChoiceList(title: title, key: key, selection: Binding(
                get: { selection.isEmpty ? [] : [selection] },
                set: { selection = $0.first ?? "" }
            ), multiple: false)
        } label: {
            LabeledContent(title) {
                Text(selection.isEmpty ? "未选择" : selection)
                    .foregroundStyle(selection.isEmpty ? HierarchicalShapeStyle.tertiary : HierarchicalShapeStyle.secondary)
            }
        }
    }
}

struct OptionChoiceList: View {
    let title: String
    let key: OptionKey
    @Binding var selection: [String]
    let multiple: Bool

    @ObservedObject private var config = ConfigStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var newOption = ""

    private var allOptions: [String] {
        let opts = config.options(key)
        return opts + selection.filter { !opts.contains($0) }
    }

    var body: some View {
        List {
            Section {
                ForEach(allOptions, id: \.self) { option in
                    Button {
                        toggle(option)
                    } label: {
                        HStack {
                            Text(option).foregroundStyle(.primary)
                            Spacer()
                            if selection.contains(option) {
                                Image(systemName: "checkmark").foregroundStyle(.tint)
                            }
                        }
                    }
                }
            } footer: {
                Text(multiple ? "可多选" : "单选，再点一次取消")
            }

            Section("添加新选项") {
                HStack {
                    TextField("输入后点添加", text: $newOption)
                    Button("添加") {
                        let v = newOption.trimmed
                        config.addOption(v, to: key)
                        if !selection.contains(v) {
                            if multiple { selection.append(v) } else { selection = [v] }
                        }
                        newOption = ""
                    }
                    .disabled(newOption.trimmed.isEmpty)
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func toggle(_ option: String) {
        if multiple {
            if let i = selection.firstIndex(of: option) {
                selection.remove(at: i)
            } else {
                selection.append(option)
            }
        } else {
            selection = selection == [option] ? [] : [option]
            dismiss()
        }
    }
}

// MARK: - 照片

struct PhotoGrid: View {
    @Binding var photoIDs: [String]
    var columns: Int = 4
    /// 提供时，长按照片可以「设为头像」
    var onSetCover: ((String) -> Void)?

    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var viewer: PhotoViewerTarget?
    @State private var importing = false

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: columns), spacing: 6) {
            ForEach(Array(photoIDs.enumerated()), id: \.element) { index, id in
                PhotoThumb(id: id)
                    .onTapGesture { viewer = PhotoViewerTarget(index: index) }
                    .contextMenu {
                        if let onSetCover {
                            Button {
                                onSetCover(id)
                            } label: {
                                Label("设为头像", systemImage: "person.crop.circle")
                            }
                        }
                        Button(role: .destructive) {
                            withAnimation(.snappy) { photoIDs.removeAll { $0 == id } }
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                    }
            }
            PhotosPicker(selection: $pickerItems, maxSelectionCount: 20, matching: .images) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.12))
                    if importing {
                        ProgressView()
                    } else {
                        Image(systemName: "plus").font(.title3).foregroundStyle(.secondary)
                    }
                }
                .aspectRatio(1, contentMode: .fit)
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
        .onChange(of: pickerItems) { _, items in
            guard !items.isEmpty else { return }
            importing = true
            Task {
                var added: [String] = []
                for item in items {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let id = PhotoStore.shared.save(data: data) {
                        added.append(id)
                    }
                }
                photoIDs.append(contentsOf: added)
                pickerItems = []
                importing = false
            }
        }
        .fullScreenCover(item: $viewer) { target in
            PhotoViewer(photoIDs: $photoIDs, startIndex: target.index)
        }
    }
}

struct PhotoViewerTarget: Identifiable {
    let index: Int
    var id: Int { index }
}

struct PhotoThumb: View {
    let id: String

    var body: some View {
        Color.secondary.opacity(0.12)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let image = PhotoStore.shared.thumbnail(id) {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    Image(systemName: "photo").foregroundStyle(.secondary)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
    }
}

/// 全屏看图。删除只从列表移除，真正删文件由调用方决定。
struct PhotoViewer: View {
    @Binding var photoIDs: [String]
    let startIndex: Int

    @Environment(\.dismiss) private var dismiss
    @State private var selection: Int
    @State private var confirmDelete = false

    init(photoIDs: Binding<[String]>, startIndex: Int) {
        _photoIDs = photoIDs
        self.startIndex = startIndex
        _selection = State(initialValue: startIndex)
    }

    var body: some View {
        NavigationStack {
            TabView(selection: $selection) {
                ForEach(Array(photoIDs.enumerated()), id: \.element) { index, id in
                    FullImage(id: id).tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .automatic))
            .background(Color.black)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .destructiveAction) {
                    Button(role: .destructive) {
                        confirmDelete = true
                    } label: {
                        Image(systemName: "trash")
                    }
                }
            }
            .toolbarBackground(.visible, for: .navigationBar)
            .confirmationDialog("删除这张照片？", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("删除", role: .destructive) { deleteCurrent() }
            }
        }
    }

    private func deleteCurrent() {
        guard photoIDs.indices.contains(selection) else { return }
        photoIDs.remove(at: selection)
        if photoIDs.isEmpty {
            dismiss()
        } else {
            selection = min(selection, photoIDs.count - 1)
        }
    }
}

private struct FullImage: View {
    let id: String
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Color.black
            if let image {
                Image(uiImage: image).resizable().scaledToFit()
            } else {
                ProgressView().tint(.white)
            }
        }
        .task(id: id) {
            image = PhotoStore.shared.image(id)
        }
    }
}

/// 绑定到已保存模型上的照片列表时用：被移除的照片顺手删掉文件
func livePhotoBinding(get: @escaping () -> [String], set: @escaping ([String]) -> Void) -> Binding<[String]> {
    Binding(
        get: get,
        set: { newValue in
            let removed = Set(get()).subtracting(newValue)
            PhotoStore.shared.delete(Array(removed))
            set(newValue)
        }
    )
}

// MARK: - 空状态 / 信息行

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
