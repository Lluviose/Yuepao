import SwiftUI
import UIKit
import AVFoundation
import PhotosUI
import Observation

struct MediaViewerTarget: Identifiable, Hashable {
    let id: String
}

@MainActor
enum Presentation {
    /// 不带系统转场地改状态：查看器自己做淡入淡出
    static func instant(_ change: () -> Void) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction, change)
    }
}

/// 查看器里会频繁变化的状态单独放，避免下拉时整页重绘
@Observable
final class ViewerState {
    /// 下拉关闭的进度 0...1
    var pull: CGFloat = 0
    var zoomed = false
    /// 当前页的视频播放器（底部的进度条用）
    var activePlayer: AVPlayer?
}

/// 全屏查看照片、实况、视频。
/// 双指 / 双击放大，单击隐藏按钮，上下拖动关闭；实况长按或点「实况」播放；视频直接播放原文件。
struct MediaViewer: View {
    var onDelete: ((String) -> Void)?
    var onSetAvatar: ((String) -> Void)?
    /// 每一项的标题（比如「和小美 · 3月2日」）。不提供时显示拍摄时间
    var caption: ((String) -> String?)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var items: [String]
    @State private var current: String
    @State private var state = ViewerState()
    @State private var appeared = false
    @State private var chromeHidden = false
    @State private var infos: [String: MediaInfo] = [:]
    @State private var liveTrigger = 0
    @State private var confirmDelete = false
    @State private var sharing: ShareFile?
    @State private var busy = false
    @State private var toast: String?

    init(ids: [String], startID: String,
         onDelete: ((String) -> Void)? = nil,
         onSetAvatar: ((String) -> Void)? = nil,
         caption: ((String) -> String?)? = nil) {
        var seen = Set<String>()
        let unique = ids.filter { seen.insert($0).inserted }
        _items = State(initialValue: unique)
        _current = State(initialValue: unique.contains(startID) ? startID : (unique.first ?? startID))
        self.onDelete = onDelete
        self.onSetAvatar = onSetAvatar
        self.caption = caption
    }

    var body: some View {
        let currentIndex = items.firstIndex(of: current) ?? 0
        ZStack {
            ViewerBackdrop(state: state, visible: appeared)

            PullScale(state: state) {
                TabView(selection: $current) {
                    ForEach(Array(items.enumerated()), id: \.element) { offset, id in
                        MediaPage(id: id,
                                  isCurrent: id == current,
                                  isNear: abs(offset - currentIndex) <= 1,
                                  liveTrigger: id == current ? liveTrigger : 0,
                                  state: state,
                                  onTap: toggleChrome,
                                  onDismiss: close)
                            .tag(id)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
            .ignoresSafeArea()
            .opacity(appeared ? 1 : 0)
            .scaleEffect(appeared ? 1 : 0.94)

            ChromeFade(state: state, hidden: chromeHidden || !appeared) {
                VStack(spacing: 12) {
                    topBar(index: currentIndex)
                    Spacer(minLength: 0)
                    if let player = state.activePlayer {
                        VideoControls(player: player)
                            .id(ObjectIdentifier(player))
                            .padding(.horizontal, 16)
                            .transition(.opacity)
                    }
                    bottomBar
                }
                // 亮的照片、视频上也看得清按钮和文字
                .background(alignment: .top) {
                    LinearGradient(colors: [Color.black.opacity(0.5), Color.black.opacity(0)],
                                   startPoint: .top, endPoint: .bottom)
                        .frame(height: 150)
                        .ignoresSafeArea(edges: .top)
                        .allowsHitTesting(false)
                }
                .background(alignment: .bottom) {
                    LinearGradient(colors: [Color.black.opacity(0), Color.black.opacity(0.45)],
                                   startPoint: .top, endPoint: .bottom)
                        .frame(height: 190)
                        .ignoresSafeArea(edges: .bottom)
                        .allowsHitTesting(false)
                }
            }
        }
        .overlay(alignment: .bottom) {
            if let toast {
                Text(toast)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .floatingGlass(Capsule())
                    .padding(.bottom, 84)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .statusBarHidden(chromeHidden || !appeared)
        .persistentSystemOverlays(chromeHidden ? .hidden : .automatic)
        .environment(\.colorScheme, .dark)
        .presentationBackground(.clear)
        .onAppear {
            withAnimation(.smooth(duration: 0.28)) { appeared = true }
        }
        .onDisappear {
            state.activePlayer?.pause()
            MediaStore.shared.purgePlayback()
        }
        .onChange(of: scenePhase) { _, phase in
            // 切到多任务界面或后台时先停下，别在外面放出声音
            if phase != .active { state.activePlayer?.pause() }
        }
        .task { await loadInfos() }
        .sheet(item: $sharing) { file in
            ShareSheet(items: [file.url])
                .presentationDetents([.medium, .large])
                .ignoresSafeArea()
        }
        .confirmationDialog(deleteTitle, isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("删除", role: .destructive) { deleteCurrent() }
        } message: {
            Text("会从这台手机上彻底删除，无法恢复。")
        }
    }

    // MARK: 顶部 / 底部

    private func topBar(index: Int) -> some View {
        HStack(spacing: 12) {
            ViewerButton(symbol: "xmark", label: "关闭", action: close)
                .accessibilityIdentifier("closeViewer")
            Spacer(minLength: 0)
            VStack(spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(subtitle(index: index))
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(Color.white.opacity(0.7))
                    .lineLimit(1)
            }
            .foregroundStyle(Color.white)
            .multilineTextAlignment(.center)
            .contentTransition(.opacity)
            Spacer(minLength: 0)
            Color.clear.frame(width: 44, height: 44)
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
    }

    private var bottomBar: some View {
        HStack(spacing: 10) {
            if currentInfo?.kind == .live {
                Button {
                    liveTrigger += 1
                } label: {
                    Label("实况", systemImage: "livephoto")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 15)
                        .frame(height: 44)
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .floatingGlass(Capsule(), interactive: true)
                .accessibilityIdentifier("viewerLive")
                .transition(.opacity)
            }
            Spacer(minLength: 0)
            if onSetAvatar != nil {
                ViewerButton(symbol: "person.crop.circle", label: "设为头像", action: setAvatar)
                    .accessibilityIdentifier("viewerAvatar")
            }
            ViewerButton(symbol: "square.and.arrow.up", label: "分享", busy: busy, action: share)
                .accessibilityIdentifier("viewerShare")
            ViewerButton(symbol: "square.and.arrow.down", label: "存到系统相册", action: save)
                .accessibilityIdentifier("viewerSave")
            if onDelete != nil {
                ViewerButton(symbol: "trash", label: "删除") { confirmDelete = true }
                    .accessibilityIdentifier("viewerDelete")
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 6)
        .animation(.snappy, value: currentInfo?.kind)
    }

    private var currentInfo: MediaInfo? { infos[current] }

    private var title: String {
        if let text = caption?(current), !text.isEmpty { return text }
        if let date = currentInfo?.capturedAt { return Fmt.dateTime(date) }
        return currentInfo?.kind.title ?? "照片"
    }

    private func subtitle(index: Int) -> String {
        var parts = ["\(index + 1) / \(items.count)"]
        if let summary = currentInfo?.summary, !summary.isEmpty { parts.append(summary) }
        return parts.joined(separator: " · ")
    }

    private var deleteTitle: String {
        switch currentInfo?.kind {
        case .video?: return "删除这个视频？"
        case .live?: return "删除这张实况照片？"
        default: return "删除这张照片？"
        }
    }

    // MARK: 操作

    private func toggleChrome() {
        withAnimation(.easeOut(duration: 0.2)) { chromeHidden.toggle() }
    }

    private func close() {
        guard appeared else { return }
        state.activePlayer?.pause()
        withAnimation(.easeIn(duration: 0.2)) { appeared = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            Presentation.instant { dismiss() }
        }
    }

    private func share() {
        guard !busy else { return }
        let id = current
        busy = true
        Task {
            let url = try? await Task.detached(priority: .userInitiated) {
                try MediaExporter.shareURL(id)
            }.value
            busy = false
            if let url {
                sharing = ShareFile(url: url)
            } else {
                showToast("文件读取失败")
            }
        }
    }

    private func save() {
        let id = current
        Task {
            do {
                try await MediaExporter.saveToLibrary(id)
                Haptics.success()
                showToast("已存到系统相册")
            } catch {
                showToast(error.localizedDescription)
            }
        }
    }

    private func setAvatar() {
        onSetAvatar?(current)
        Haptics.success()
        showToast("已设为头像")
    }

    private func deleteCurrent() {
        guard let index = items.firstIndex(of: current) else { return }
        let id = current
        onDelete?(id)
        var remaining = items
        remaining.remove(at: index)
        if remaining.isEmpty {
            close()
            return
        }
        withAnimation(.snappy) {
            items = remaining
            current = remaining[min(index, remaining.count - 1)]
        }
    }

    private func showToast(_ text: String) {
        withAnimation(.snappy) { toast = text }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            if toast == text {
                withAnimation(.easeOut(duration: 0.25)) { toast = nil }
            }
        }
    }

    private func loadInfos() async {
        let ids = items
        let loaded = await Task.detached(priority: .userInitiated) { () -> [String: MediaInfo] in
            var map: [String: MediaInfo] = [:]
            for id in ids {
                if let info = MediaStore.shared.info(id) { map[id] = info }
            }
            return map
        }.value
        infos = loaded
    }
}

// MARK: - 一页

private struct MediaPage: View {
    let id: String
    let isCurrent: Bool
    let isNear: Bool
    let liveTrigger: Int
    let state: ViewerState
    let onTap: () -> Void
    let onDismiss: () -> Void

    @State private var info: MediaInfo?
    @State private var preview: UIImage?
    @State private var full: UIImage?
    @State private var livePhoto: PHLivePhoto?
    @State private var liveCommand = LiveCommand()
    @State private var player: AVPlayer?
    /// 实况配不上对时，用它直接播放配对的视频
    @State private var pairPlayer: AVPlayer?
    @State private var showingPair = false
    @State private var progress: Double?
    @State private var failed = false
    @State private var active = false

    init(id: String, isCurrent: Bool, isNear: Bool, liveTrigger: Int, state: ViewerState,
         onTap: @escaping () -> Void, onDismiss: @escaping () -> Void) {
        self.id = id
        self.isCurrent = isCurrent
        self.isNear = isNear
        self.liveTrigger = liveTrigger
        self.state = state
        self.onTap = onTap
        self.onDismiss = onDismiss
        _preview = State(initialValue: MediaStore.shared.cachedThumbnail(id, size: MediaStore.thumbPixels))
    }

    private var kind: MediaKind { info?.kind ?? .photo }

    private var aspect: CGSize {
        if let info, info.width > 0, info.height > 0 {
            return CGSize(width: info.width, height: info.height)
        }
        if let preview, preview.size.width > 0, preview.size.height > 0 { return preview.size }
        return CGSize(width: 1, height: 1)
    }

    var body: some View {
        ZStack {
            ZoomableMedia(image: full ?? preview,
                          livePhoto: livePhoto,
                          player: kind == .video ? player : (showingPair ? pairPlayer : nil),
                          aspect: aspect,
                          pixelWidth: CGFloat(info?.width ?? 0),
                          liveCommand: liveCommand,
                          onTap: onTap,
                          onZoom: { state.zoomed = $0 },
                          onPull: { state.pull = $0 },
                          onDismiss: onDismiss)

            if let progress, kind == .video, player == nil {
                LoadingRing(progress: progress)
                    .allowsHitTesting(false)
            }
            if failed {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.title2)
                    Text("文件读取失败")
                        .font(.footnote)
                }
                .foregroundStyle(Color.white.opacity(0.7))
                .allowsHitTesting(false)
            }
        }
        .task(id: isNear) { await refresh() }
        .onAppear {
            active = isCurrent
        }
        .onChange(of: isCurrent) { _, value in
            active = value
            if value {
                if let player {
                    state.activePlayer = player
                    autoplay(player)
                }
                hintLive()
            } else {
                player?.pause()
                pairPlayer?.pause()
                showingPair = false
                if let player, state.activePlayer === player { state.activePlayer = nil }
            }
        }
        .onChange(of: liveTrigger) { _, _ in playLive() }
        .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)) { note in
            guard let item = note.object as? AVPlayerItem, let pairPlayer, item === pairPlayer.currentItem else { return }
            withAnimation(.easeOut(duration: 0.25)) { showingPair = false }
        }
        .onDisappear {
            player?.pause()
            pairPlayer?.pause()
        }
    }

    private func refresh() async {
        let id = self.id
        if info == nil {
            info = await Task.detached(priority: .userInitiated) { MediaStore.shared.info(id) }.value
        }
        if preview == nil {
            let thumb = await MediaStore.shared.loadThumbnail(id, size: MediaStore.thumbPixels)
            if !Task.isCancelled { preview = thumb }
        }
        guard !Task.isCancelled else { return }
        guard isNear else {
            release()
            return
        }
        switch kind {
        case .photo:
            await loadFull()
        case .live:
            await loadFull()
            await loadLive()
        case .video:
            await loadVideo()
        }
    }

    /// 离当前页远了就把原图、播放器放掉，省内存
    private func release() {
        full = nil
        livePhoto = nil
        player?.pause()
        if let player, state.activePlayer === player { state.activePlayer = nil }
        player = nil
        pairPlayer?.pause()
        pairPlayer = nil
        showingPair = false
    }

    private func loadFull() async {
        guard full == nil else { return }
        let id = self.id
        let image = await Task.detached(priority: .userInitiated) {
            MediaStore.shared.displayImage(id, maxPixels: 6000)
        }.value
        guard !Task.isCancelled else { return }
        full = image
        if image == nil && preview == nil { failed = true }
    }

    private func loadLive() async {
        guard livePhoto == nil, pairPlayer == nil else { return }
        let id = self.id
        let files = try? await Task.detached(priority: .userInitiated) { () throws -> [URL] in
            let photo = try MediaStore.shared.plainFile(id)
            let video = try MediaStore.shared.plainFile(id, part: .pair)
            return [photo, video]
        }.value
        guard let files, !Task.isCancelled else { return }
        if let live = await LivePhotoLoader.load(files, placeholder: full ?? preview) {
            guard !Task.isCancelled else { return }
            livePhoto = live
            if active { hintLive() }
        } else if !Task.isCancelled {
            pairPlayer = AVPlayer(url: files[1])
        }
    }

    private func loadVideo() async {
        guard player == nil else { return }
        let id = self.id
        progress = 0
        let report: @Sendable (Double) -> Void = { value in
            Task { @MainActor in
                if player == nil { progress = value }
            }
        }
        let url = try? await Task.detached(priority: .userInitiated) { () throws -> URL in
            try MediaStore.shared.plainFile(id, progress: report)
        }.value
        guard !Task.isCancelled else { return }
        progress = nil
        guard let url else {
            failed = true
            return
        }
        let newPlayer = AVPlayer(url: url)
        newPlayer.actionAtItemEnd = .pause
        player = newPlayer
        if active {
            state.activePlayer = newPlayer
            newPlayer.play()
        }
    }

    /// 翻到视频页就播放，跟系统相册一样；上次已经播完的从头开始
    private func autoplay(_ player: AVPlayer) {
        if let item = player.currentItem, item.duration.isNumeric,
           CMTimeCompare(item.currentTime(), item.duration) >= 0 {
            player.seek(to: .zero)
        }
        player.play()
    }

    /// 翻到实况照片时轻轻动一下，跟系统相册一样
    private func hintLive() {
        guard kind == .live, livePhoto != nil else { return }
        liveCommand = LiveCommand(count: liveCommand.count + 1, full: false)
    }

    private func playLive() {
        if livePhoto != nil {
            liveCommand = LiveCommand(count: liveCommand.count + 1, full: true)
        } else if let pairPlayer {
            pairPlayer.seek(to: .zero)
            pairPlayer.play()
            withAnimation(.easeOut(duration: 0.2)) { showingPair = true }
        }
    }
}

enum LivePhotoLoader {
    /// 用解密出来的照片 + 配对视频拼成实况。配对信息不全时返回 nil
    @MainActor
    static func load(_ files: [URL], placeholder: UIImage?) async -> PHLivePhoto? {
        await withCheckedContinuation { (continuation: CheckedContinuation<PHLivePhoto?, Never>) in
            var resumed = false
            _ = PHLivePhoto.request(withResourceFileURLs: files, placeholderImage: placeholder,
                                    targetSize: .zero, contentMode: .aspectFit) { photo, info in
                guard !resumed else { return }
                let degraded = (info[PHLivePhotoInfoIsDegradedKey] as? Bool) ?? false
                let cancelled = (info[PHLivePhotoInfoCancelledKey] as? Bool) ?? false
                if photo == nil || !degraded || cancelled || info[PHLivePhotoInfoErrorKey] != nil {
                    resumed = true
                    continuation.resume(returning: cancelled ? nil : photo)
                }
            }
        }
    }
}

struct LiveCommand: Equatable {
    var count = 0
    var full = true
}

// MARK: - 视频控制条

private struct VideoControls: View {
    let player: AVPlayer

    @State private var time: Double = 0
    @State private var duration: Double = 0
    @State private var playing = false
    @State private var scrubbing = false
    @State private var muted = false
    @State private var token: Any?

    var body: some View {
        HStack(spacing: 10) {
            Button(action: toggle) {
                Image(systemName: playing ? "pause.fill" : "play.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 34, height: 38)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(playing ? "暂停" : "播放")
            .accessibilityIdentifier("videoPlayPause")

            Text(Fmt.clock(time))
                .font(.caption.weight(.medium))
                .monospacedDigit()
                .frame(minWidth: 36, alignment: .leading)

            Slider(value: $time, in: 0...max(duration, 0.1), onEditingChanged: { editing in
                scrubbing = editing
                if !editing { seek(to: time, precise: true) }
            })
            .tint(Color.white)

            Text("-" + Fmt.clock(max(duration - time, 0)))
                .font(.caption.weight(.medium))
                .monospacedDigit()
                .frame(minWidth: 42, alignment: .trailing)

            Button {
                muted.toggle()
                player.isMuted = muted
            } label: {
                Image(systemName: muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 28, height: 38)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(muted ? "打开声音" : "静音")
        }
        .foregroundStyle(Color.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 3)
        .floatingGlass(Capsule())
        .onChange(of: time) { _, value in
            if scrubbing { seek(to: value, precise: false) }
        }
        .onAppear(perform: attach)
        .onDisappear(perform: detach)
    }

    private func attach() {
        muted = player.isMuted
        playing = player.timeControlStatus != .paused
        if let item = player.currentItem {
            let now = item.currentTime().seconds
            if now.isFinite { time = now }
            // 还没开始播时也先把总时长显示出来
            Task {
                if let total = try? await item.asset.load(.duration), total.seconds.isFinite, total.seconds > 0 {
                    duration = total.seconds
                }
            }
        }
        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
        token = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { now in
            if !scrubbing, now.seconds.isFinite { time = now.seconds }
            if let total = player.currentItem?.duration.seconds, total.isFinite, total > 0 { duration = total }
            playing = player.timeControlStatus != .paused
        }
    }

    private func detach() {
        if let token { player.removeTimeObserver(token) }
        token = nil
    }

    private func toggle() {
        if player.timeControlStatus == .paused {
            if duration > 0, time >= duration - 0.15 { player.seek(to: .zero) }
            player.play()
            playing = true
        } else {
            player.pause()
            playing = false
        }
    }

    private func seek(to seconds: Double, precise: Bool) {
        let target = CMTime(seconds: seconds, preferredTimescale: 600)
        let tolerance = precise ? CMTime.zero : CMTime(seconds: 0.2, preferredTimescale: 600)
        player.seek(to: target, toleranceBefore: tolerance, toleranceAfter: tolerance)
    }
}

// MARK: - 小部件

private struct ViewerButton: View {
    let symbol: String
    let label: String
    var busy = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                if busy {
                    ProgressView().tint(Color.white)
                } else {
                    Image(systemName: symbol)
                        .font(.system(size: 16, weight: .medium))
                }
            }
            .foregroundStyle(Color.white)
            .frame(width: 44, height: 44)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .floatingGlass(Circle(), interactive: true)
        .accessibilityLabel(label)
    }
}

/// 解密大视频时的进度
private struct LoadingRing: View {
    let progress: Double

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.2), lineWidth: 3)
            Circle()
                .trim(from: 0, to: max(0.02, progress))
                .stroke(Color.white, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.15), value: progress)
        }
        .frame(width: 34, height: 34)
        .padding(12)
        .floatingGlass(Circle())
    }
}

private struct ViewerBackdrop: View {
    let state: ViewerState
    let visible: Bool

    var body: some View {
        Color.black
            .opacity(visible ? 1 - Double(state.pull) * 0.85 : 0)
            .ignoresSafeArea()
    }
}

private struct PullScale<Content: View>: View {
    let state: ViewerState
    @ViewBuilder var content: Content

    var body: some View {
        content.scaleEffect(1 - state.pull * 0.1)
    }
}

private struct ChromeFade<Content: View>: View {
    let state: ViewerState
    let hidden: Bool
    @ViewBuilder var content: Content

    var body: some View {
        let visible = !hidden && state.pull < 0.02
        content
            .opacity(visible ? 1 : 0)
            .allowsHitTesting(visible)
            .animation(.easeOut(duration: 0.18), value: visible)
    }
}

struct ShareFile: Identifiable {
    let id = UUID()
    let url: URL
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

// MARK: - UIKit：可缩放的画布

private struct ZoomableMedia: UIViewRepresentable {
    var image: UIImage?
    var livePhoto: PHLivePhoto?
    var player: AVPlayer?
    var aspect: CGSize
    var pixelWidth: CGFloat
    var liveCommand: LiveCommand
    var onTap: () -> Void
    var onZoom: (Bool) -> Void
    var onPull: (CGFloat) -> Void
    var onDismiss: () -> Void

    func makeUIView(context: Context) -> MediaZoomView {
        MediaZoomView(frame: .zero)
    }

    func updateUIView(_ view: MediaZoomView, context: Context) {
        view.onTap = onTap
        view.onZoom = onZoom
        view.onPull = onPull
        view.onDismiss = onDismiss
        view.pixelWidth = pixelWidth
        view.aspect = aspect
        view.setImage(image)
        view.setLivePhoto(livePhoto)
        view.setPlayer(player)
        if liveCommand.count != context.coordinator.liveCount {
            context.coordinator.liveCount = liveCommand.count
            view.playLive(full: liveCommand.full)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    static func dismantleUIView(_ view: MediaZoomView, coordinator: Coordinator) {
        view.setPlayer(nil)
    }

    final class Coordinator {
        var liveCount = 0
    }
}

/// 播放器画面
final class PlayerSurface: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }

    var playerLayer: AVPlayerLayer {
        // layerClass 已经指定为 AVPlayerLayer
        layer as! AVPlayerLayer
    }
}

/// 一个能双指缩放的画布：里面依次叠照片、实况、视频。
/// 没放大时上下拖动会回弹，拖得够远或够快就关闭查看器
final class MediaZoomView: UIScrollView, UIScrollViewDelegate {
    var onTap: (() -> Void)?
    var onZoom: ((Bool) -> Void)?
    var onPull: ((CGFloat) -> Void)?
    var onDismiss: (() -> Void)?

    var pixelWidth: CGFloat = 0 {
        didSet {
            if pixelWidth != oldValue { updateZoomLimits() }
        }
    }

    var aspect = CGSize(width: 1, height: 1) {
        didSet {
            guard aspect.width > 0, aspect.height > 0 else {
                aspect = oldValue
                return
            }
            let ratio = aspect.width / aspect.height
            let oldRatio = oldValue.width / max(oldValue.height, 0.001)
            if abs(ratio - oldRatio) > 0.001 {
                laidOutSize = .zero
                setNeedsLayout()
            }
        }
    }

    private let canvas = UIView()
    private let imageView = UIImageView()
    private var liveView: PHLivePhotoView?
    private var playerView: PlayerSurface?
    private var laidOutSize = CGSize.zero
    private var zoomedIn = false
    private var dismissing = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        delegate = self
        backgroundColor = .clear
        showsVerticalScrollIndicator = false
        showsHorizontalScrollIndicator = false
        contentInsetAdjustmentBehavior = .never
        decelerationRate = .fast
        alwaysBounceVertical = true
        bouncesZoom = true
        minimumZoomScale = 1
        maximumZoomScale = 3

        canvas.clipsToBounds = true
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.frame = canvas.bounds
        imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        canvas.addSubview(imageView)
        addSubview(canvas)

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)
        let singleTap = UITapGestureRecognizer(target: self, action: #selector(handleSingleTap))
        singleTap.require(toFail: doubleTap)
        addGestureRecognizer(singleTap)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0, bounds.height > 0, bounds.size != laidOutSize else { return }
        laidOutSize = bounds.size
        zoomScale = 1
        let fitted = AVMakeRect(aspectRatio: aspect, insideRect: CGRect(origin: .zero, size: bounds.size)).size
        canvas.frame = CGRect(x: 0, y: 0, width: fitted.width.rounded(), height: fitted.height.rounded())
        contentSize = canvas.frame.size
        updateZoomLimits()
        centerCanvas()
        contentOffset = CGPoint(x: -contentInset.left, y: -contentInset.top)
    }

    private func centerCanvas() {
        let size = canvas.frame.size
        let x = max((bounds.width - size.width) / 2, 0)
        let y = max((bounds.height - size.height) / 2, 0)
        let inset = UIEdgeInsets(top: y, left: x, bottom: y, right: x)
        if contentInset != inset { contentInset = inset }
    }

    private func updateZoomLimits() {
        let width = canvas.bounds.width
        guard width > 0 else { return }
        let scale = max(traitCollection.displayScale, 1)
        let native = pixelWidth > 0 ? pixelWidth / (width * scale) : 1
        maximumZoomScale = min(max(3, native * 2), 12)
    }

    // MARK: 内容

    func setImage(_ image: UIImage?) {
        guard imageView.image !== image else { return }
        if imageView.image == nil || image == nil {
            imageView.image = image
        } else {
            UIView.transition(with: imageView, duration: 0.2, options: [.transitionCrossDissolve, .allowUserInteraction]) {
                self.imageView.image = image
            }
        }
    }

    func setLivePhoto(_ livePhoto: PHLivePhoto?) {
        guard let livePhoto else {
            liveView?.removeFromSuperview()
            liveView = nil
            return
        }
        let view: PHLivePhotoView
        if let liveView {
            view = liveView
        } else {
            view = PHLivePhotoView(frame: canvas.bounds)
            view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            view.contentMode = .scaleAspectFill
            view.clipsToBounds = true
            canvas.insertSubview(view, aboveSubview: imageView)
            liveView = view
        }
        if view.livePhoto !== livePhoto { view.livePhoto = livePhoto }
    }

    func setPlayer(_ player: AVPlayer?) {
        guard let player else {
            playerView?.playerLayer.player = nil
            playerView?.removeFromSuperview()
            playerView = nil
            return
        }
        let view: PlayerSurface
        if let playerView {
            view = playerView
        } else {
            view = PlayerSurface(frame: canvas.bounds)
            view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            view.playerLayer.videoGravity = .resizeAspectFill
            view.isUserInteractionEnabled = false
            canvas.addSubview(view)
            playerView = view
        }
        if view.playerLayer.player !== player { view.playerLayer.player = player }
    }

    func playLive(full: Bool) {
        liveView?.startPlayback(with: full ? .full : .hint)
    }

    // MARK: 手势

    @objc private func handleSingleTap() {
        onTap?()
    }

    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        if zoomScale > minimumZoomScale + 0.01 {
            setZoomScale(minimumZoomScale, animated: true)
        } else {
            let point = gesture.location(in: canvas)
            let scale = min(maximumZoomScale, 2.5)
            let size = CGSize(width: bounds.width / scale, height: bounds.height / scale)
            zoom(to: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2,
                            width: size.width, height: size.height), animated: true)
        }
    }

    // MARK: UIScrollViewDelegate

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        canvas
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        centerCanvas()
        let zoomed = zoomScale > minimumZoomScale + 0.01
        if zoomed != zoomedIn {
            zoomedIn = zoomed
            onZoom?(zoomed)
        }
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard !zoomedIn, !dismissing else { return }
        let pull = abs(contentOffset.y + contentInset.top)
        onPull?(min(pull / 280, 1))
    }

    func scrollViewWillEndDragging(_ scrollView: UIScrollView, withVelocity velocity: CGPoint,
                                   targetContentOffset: UnsafeMutablePointer<CGPoint>) {
        guard !zoomedIn, !dismissing else { return }
        let pull = abs(contentOffset.y + contentInset.top)
        if pull > 80 || (pull > 20 && abs(velocity.y) > 1.2) {
            dismissing = true
            onDismiss?()
        }
    }
}
