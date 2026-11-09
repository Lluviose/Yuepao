import SwiftUI
import PhotosUI

/// 照片墙。编辑页用网格（最后一格是添加）；详情页用拼图（三张以上时第一张占 2×2）。
/// 照片、视频、实况都按原文件导入，导入时逐张出现；点开是全屏查看器
struct MediaGrid: View {
    enum Style {
        case grid, mosaic
    }

    @Binding var ids: [String]
    var style: Style = .grid
    var columns = 4
    var onSetAvatar: ((String) -> Void)?
    /// 由外部按钮（比如卡片右上角的「添加」）打开选择器
    var pickerPresented: Binding<Bool>?

    @State private var showPicker = false
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var pending = 0
    @State private var finished = 0
    @State private var failures = 0
    @State private var viewing: MediaViewerTarget?
    @State private var saveError: String?

    private var pickerBinding: Binding<Bool> { pickerPresented ?? $showPicker }

    var body: some View {
        Group {
            switch style {
            case .grid: grid
            case .mosaic: mosaic
            }
        }
        .photosPicker(isPresented: pickerBinding, selection: $pickerItems, maxSelectionCount: 30,
                      selectionBehavior: .ordered, matching: MediaImporter.filter,
                      preferredItemEncoding: .current)
        .onChange(of: pickerItems) { _, items in importPicked(items) }
        .fullScreenCover(item: $viewing) { target in
            MediaViewer(ids: ids, startID: target.id,
                        onDelete: { id in remove(id) },
                        onSetAvatar: onSetAvatar)
        }
        .sensoryFeedback(.success, trigger: finished)
        .alert("有 \(failures) 项没能导入", isPresented: Binding(
            get: { failures > 0 },
            set: { if !$0 { failures = 0 } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text("可能是 iCloud 里的原件还没下载完，或者格式不支持。")
        }
        .alert("没能存到系统相册", isPresented: Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(saveError ?? "")
        }
    }

    // MARK: 网格

    private var grid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: columns), spacing: 4) {
            ForEach(Array(ids.enumerated()), id: \.element) { index, id in
                tile(id, index: index, pixels: 384)
                    .aspectRatio(1, contentMode: .fit)
            }
            ForEach(0..<pending, id: \.self) { _ in
                ImportingTile()
                    .aspectRatio(1, contentMode: .fit)
            }
            if pending == 0 {
                addTile
                    .aspectRatio(1, contentMode: .fit)
            }
        }
        .padding(.vertical, 2)
    }

    private var addTile: some View {
        Button {
            pickerBinding.wrappedValue = true
        } label: {
            VStack(spacing: 5) {
                Image(systemName: "plus")
                    .font(.system(size: 19, weight: .light))
                Text(ids.isEmpty ? "照片 / 视频" : "添加")
                    .font(.caption2)
            }
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Palette.fill))
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.chip)
        .accessibilityLabel("添加照片或视频")
        .accessibilityIdentifier("addMedia")
    }

    // MARK: 拼图

    @ViewBuilder
    private var mosaic: some View {
        if ids.isEmpty && pending == 0 {
            emptyAdd
        } else {
            MosaicLayout(spacing: 4) {
                ForEach(Array(ids.enumerated()), id: \.element) { index, id in
                    tile(id, index: index, pixels: index == 0 || ids.count <= 2 ? 720 : 384)
                }
                ForEach(0..<pending, id: \.self) { _ in
                    ImportingTile()
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private var emptyAdd: some View {
        Button {
            pickerBinding.wrappedValue = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "photo.badge.plus")
                    .font(.system(size: 20, weight: .light))
                    .foregroundStyle(Palette.gold)
                    .frame(width: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text("添加照片或视频")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.primary)
                    Text("原画质保存，实况也能动")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.chip)
        .accessibilityIdentifier("addMedia")
    }

    // MARK: 单格

    private func tile(_ id: String, index: Int, pixels: CGFloat) -> some View {
        Button {
            Presentation.instant { viewing = MediaViewerTarget(id: id) }
        } label: {
            MediaTile(id: id, pixels: pixels, cornerRadius: style == .grid ? 8 : 3)
        }
        .buttonStyle(.plain)
        .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contextMenu {
            if let onSetAvatar {
                Button {
                    onSetAvatar(id)
                } label: {
                    Label("设为头像", systemImage: "person.crop.circle")
                }
            }
            Button {
                save(id)
            } label: {
                Label("存到系统相册", systemImage: "square.and.arrow.down")
            }
            Button(role: .destructive) {
                remove(id)
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
        .accessibilityIdentifier("media-\(index)")
        .transition(.scale(scale: 0.85).combined(with: .opacity))
    }

    // MARK: 操作

    private func remove(_ id: String) {
        withAnimation(.snappy) { ids.removeAll { $0 == id } }
    }

    private func save(_ id: String) {
        Task {
            do {
                try await MediaExporter.saveToLibrary(id)
                Haptics.success()
            } catch {
                saveError = error.localizedDescription
            }
            MediaStore.shared.purgePlayback()
        }
    }

    /// 逐个导入，导好一张出现一张
    private func importPicked(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        pickerItems = []
        withAnimation(.snappy) { pending += items.count }
        Task {
            var failed = 0
            for item in items {
                let id = await MediaImporter.importItem(item)
                withAnimation(.snappy) {
                    pending = max(pending - 1, 0)
                    if let id { ids.append(id) }
                }
                if id == nil { failed += 1 }
            }
            finished += 1
            if failed > 0 { failures = failed }
        }
    }
}

/// 一格缩略图：视频标时长，实况标图标
struct MediaTile: View {
    let id: String
    var pixels: CGFloat = 384
    var cornerRadius: CGFloat = 8

    @State private var image: UIImage?
    @State private var info: MediaInfo?

    init(id: String, pixels: CGFloat = 384, cornerRadius: CGFloat = 8) {
        self.id = id
        self.pixels = pixels
        self.cornerRadius = cornerRadius
        _image = State(initialValue: MediaStore.shared.cachedThumbnail(id, size: pixels))
    }

    var body: some View {
        Palette.fill
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .transition(.opacity)
                }
            }
            .overlay { badge }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .task(id: id) { await load() }
    }

    @ViewBuilder
    private var badge: some View {
        switch info?.kind {
        case .video?:
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                HStack(spacing: 3) {
                    Spacer(minLength: 0)
                    Image(systemName: "play.fill")
                        .font(.system(size: 8, weight: .bold))
                    Text(Fmt.clock(info?.duration ?? 0))
                        .font(.system(size: 11, weight: .semibold))
                        .monospacedDigit()
                }
                .foregroundStyle(Color.white)
                .padding(.horizontal, 6)
                .padding(.top, 10)
                .padding(.bottom, 5)
                .background(LinearGradient(colors: [Color.black.opacity(0), Color.black.opacity(0.45)],
                                           startPoint: .top, endPoint: .bottom))
            }
        case .live?:
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    Image(systemName: "livephoto")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .shadow(color: Color.black.opacity(0.45), radius: 2)
                        .padding(6)
                    Spacer(minLength: 0)
                }
                Spacer(minLength: 0)
            }
        default:
            EmptyView()
        }
    }

    private func load() async {
        let id = self.id
        let pixels = self.pixels
        if info == nil {
            info = await Task.detached(priority: .utility) { MediaStore.shared.info(id) }.value
        }
        if image == nil {
            let loaded = await MediaStore.shared.loadThumbnail(id, size: pixels)
            withAnimation(.easeOut(duration: 0.2)) { image = loaded }
        }
    }
}

private struct ImportingTile: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Palette.fill)
            .overlay { ProgressView() }
    }
}

/// 拼图：1 张 4:3；2 张并排；3 张以上第一张 2×2，其余三列
struct MosaicLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 320
        let height = frames(count: subviews.count, width: width).map(\.maxY).max() ?? 0
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rects = frames(count: subviews.count, width: bounds.width)
        for (index, subview) in subviews.enumerated() where index < rects.count {
            let rect = rects[index]
            subview.place(at: CGPoint(x: bounds.minX + rect.minX, y: bounds.minY + rect.minY),
                          anchor: .topLeading,
                          proposal: ProposedViewSize(width: rect.width, height: rect.height))
        }
    }

    func frames(count: Int, width: CGFloat) -> [CGRect] {
        guard count > 0, width > 0 else { return [] }
        switch count {
        case 1:
            return [CGRect(x: 0, y: 0, width: width, height: (width * 0.75).rounded())]
        case 2:
            let side = (width - spacing) / 2
            return [CGRect(x: 0, y: 0, width: side, height: side),
                    CGRect(x: side + spacing, y: 0, width: side, height: side)]
        default:
            let cell = (width - spacing * 2) / 3
            let big = cell * 2 + spacing
            var rects = [CGRect(x: 0, y: 0, width: big, height: big),
                         CGRect(x: big + spacing, y: 0, width: cell, height: cell),
                         CGRect(x: big + spacing, y: cell + spacing, width: cell, height: cell)]
            for i in 3..<count {
                let row = CGFloat((i - 3) / 3)
                let col = CGFloat((i - 3) % 3)
                rects.append(CGRect(x: col * (cell + spacing), y: big + spacing + row * (cell + spacing),
                                    width: cell, height: cell))
            }
            return rects
        }
    }
}

/// 绑定到已保存模型上的照片列表：被移除的文件顺手删掉
func storedMediaBinding(get: @escaping () -> [String], set: @escaping ([String]) -> Void) -> Binding<[String]> {
    Binding(
        get: get,
        set: { newValue in
            let removed = Set(get()).subtracting(newValue)
            MediaStore.shared.delete(Array(removed))
            set(newValue)
        }
    )
}

extension Girl {
    /// 用相册里的一项做头像：另存一份 1200 像素的 JPEG，删掉原图不影响头像
    @MainActor
    func setAvatar(fromMedia id: String) async {
        let newID = await Task.detached(priority: .userInitiated) {
            MediaStore.shared.makeAvatar(from: id)
        }.value
        guard let newID else { return }
        let old = avatarID
        withAnimation(.snappy) { avatarID = newID }
        if let old { MediaStore.shared.delete(old) }
    }
}
