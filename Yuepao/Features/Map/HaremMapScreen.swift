import SwiftUI
import SwiftData
import MapKit

private enum MapSheet: Identifiable {
    case girl(UUID)
    case place(UUID)
    case record(girl: UUID?, place: UUID?)
    case newPlace(PickedLocation)
    case overview

    var id: String {
        switch self {
        case .girl(let id): return "g-\(id)"
        case .place(let id): return "p-\(id)"
        case .record(let g, let p): return "r-\(g?.uuidString ?? "")-\(p?.uuidString ?? "")"
        case .newPlace(let loc): return "n-\(loc.coordinate.latitude),\(loc.coordinate.longitude)"
        case .overview: return "overview"
        }
    }
}

struct HaremMapScreen: View {
    @Query private var girls: [Girl]
    @Query private var places: [Place]
    @Environment(\.modelContext) private var context
    @ObservedObject private var config = ConfigStore.shared
    @StateObject private var controller = MapController()

    @AppStorage("mapColorByRank") private var colorByRank = false
    @AppStorage("mapHideEnded") private var hideEnded = true
    @AppStorage("mapStyle") private var styleRaw = MapStyle.muted.rawValue
    @AppStorage("mapMode") private var modeRaw = MapMode.all.rawValue

    @State private var range: TimeRange = .all
    @State private var girlFilter: UUID?
    @State private var focus: MapFocus?
    @State private var cards: [MapFocus] = []
    @State private var scrolledCard: MapFocus?
    @State private var sheet: MapSheet?
    @State private var draft: DraftPin?
    @State private var userCoordinate: CLLocationCoordinate2D?
    @State private var playback: MapPlayback?
    @State private var playbackSnapshot: MapSnapshot?

    private var mode: MapMode { MapMode(rawValue: modeRaw) ?? .all }
    private var style: MapStyle { MapStyle(rawValue: styleRaw) ?? .muted }

    private var modeBinding: Binding<MapMode> {
        Binding(get: { mode }, set: { newValue in
            clearFocus()
            modeRaw = newValue.rawValue
        })
    }

    private var hasFilters: Bool { range != .all || girlFilter != nil }

    private var filterGirl: Girl? {
        girlFilter.flatMap { id in girls.first { $0.id == id } }
    }

    private var snapshot: MapSnapshot {
        MapSnapshot(girls: girls, places: places, range: range, girlFilter: girlFilter,
                    hideEnded: hideEnded, tone: tone(for:))
    }

    private func tone(for girl: Girl) -> UIColor {
        guard colorByRank else { return girl.status.uiColor }
        let palette: [UIColor] = [
            UIColor(red: 0.52, green: 0.17, blue: 0.27, alpha: 1),
            UIColor(red: 0.69, green: 0.30, blue: 0.39, alpha: 1),
            UIColor(red: 0.78, green: 0.60, blue: 0.38, alpha: 1),
            UIColor(red: 0.42, green: 0.53, blue: 0.45, alpha: 1),
            UIColor(red: 0.43, green: 0.52, blue: 0.60, alpha: 1),
            UIColor(red: 0.55, green: 0.47, blue: 0.60, alpha: 1)
        ]
        let index = config.rankIndex(girl.rank)
        return index == Int.max ? UIColor(white: 0.6, alpha: 1) : palette[min(index, palette.count - 1)]
    }

    /// 顶部浮层占的高度（状态栏以下）
    private var topChrome: CGFloat { hasFilters ? 98 : 58 }

    /// 底部浮层占的高度（标签栏以上）
    private var bottomChrome: CGFloat {
        if playback != nil { return 150 }
        if draft != nil { return 104 }
        if focus != nil { return ClusterMapView.cardChrome }
        return mode == .heat ? 108 : 86
    }

    var body: some View {
        let content: MapContent = {
            if let playback, let playbackSnapshot {
                return playbackSnapshot.content(mode: mode, until: playback.cutoff)
            }
            return snapshot.content(mode: mode)
        }()

        ZStack {
            ClusterMapView(
                content: content,
                focus: focus,
                draft: draft?.coordinate,
                style: style,
                chrome: UIEdgeInsets(top: topChrome, left: 0, bottom: bottomChrome, right: 0),
                controller: controller,
                onFocus: { f in show(f, among: content) },
                onCluster: { members in showGroup(members, among: content) },
                onTapEmpty: {
                    if draft != nil { cancelDraft() } else { clearFocus() }
                },
                onLongPress: { c in dropPin(at: c) },
                onUserLocation: { c in userCoordinate = c }
            )
            .ignoresSafeArea()

            if content.isEmpty && playback == nil && draft == nil {
                MapEmptyHint()
                    .padding(.horizontal, 30)
                    .transition(.opacity)
            }
        }
        .overlay(alignment: .top) {
            topBar
        }
        .overlay(alignment: .bottom) {
            bottomArea(content)
        }
        .overlay(alignment: .bottomTrailing) {
            if playback == nil {
                MapControlStack(items: [
                    .init(symbol: "location", label: "定位到我", id: "mapLocate") { controller.locateMe() },
                    .init(symbol: "arrow.up.left.and.arrow.down.right", label: "显示全部", id: "mapFit") { controller.fitAll() },
                    .init(symbol: "clock.arrow.circlepath", label: "足迹回放", id: "mapPlayback") { startPlayback() }
                ])
                .padding(.trailing, 16)
                .padding(.bottom, bottomChrome + 10)
                .transition(.opacity)
            }
        }
        .animation(.spring(response: 0.42, dampingFraction: 0.86), value: focus)
        .animation(.spring(response: 0.42, dampingFraction: 0.86), value: draft)
        .animation(.spring(response: 0.42, dampingFraction: 0.86), value: playback == nil)
        .animation(.spring(response: 0.36, dampingFraction: 0.86), value: hasFilters)
        .sheet(item: $sheet) { which in
            sheetContent(which)
        }
        .onChange(of: scrolledCard) { _, new in
            guard let new, new != focus else { return }
            focus = new
            controller.reveal(new)
        }
        .onChange(of: girlFilter) { _, _ in refitSoon() }
        .onChange(of: range) { _, _ in refitSoon() }
        .task(id: playback?.playing == true) {
            await runPlayback()
        }
        .onAppear { LocationPermission.requestIfNeeded() }
    }

    // MARK: 顶部

    private var topBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                MapModeSwitcher(mode: modeBinding)
                filterMenu
            }
            if hasFilters {
                HStack(spacing: 8) {
                    if range != .all {
                        MapFilterToken(title: range.title, symbol: "calendar") { range = .all }
                    }
                    if let g = filterGirl {
                        MapFilterToken(title: "只看\(g.name)", symbol: "person") { girlFilter = nil }
                    }
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
    }

    private var filterMenu: some View {
        Menu {
            Section("时间") {
                Picker("时间", selection: $range) {
                    ForEach(TimeRange.allCases) { r in
                        Text(r.title).tag(r)
                    }
                }
                .pickerStyle(.inline)
            }
            Section {
                Picker(selection: $girlFilter) {
                    Text("所有人").tag(UUID?.none)
                    ForEach(girls.sorted { $0.encounters.count > $1.encounters.count }) { g in
                        Text(g.name).tag(UUID?.some(g.id))
                    }
                } label: {
                    Label("只看某人", systemImage: "person")
                }
                .pickerStyle(.menu)
            }
            Section("显示") {
                Picker(selection: $styleRaw) {
                    ForEach(MapStyle.allCases) { s in
                        Label(s.title, systemImage: s.symbol).tag(s.rawValue)
                    }
                } label: {
                    Label("底图", systemImage: "map")
                }
                .pickerStyle(.menu)
                Picker(selection: $colorByRank) {
                    Text("按关系状态").tag(false)
                    Text("按位分").tag(true)
                } label: {
                    Label("名牌圆点颜色", systemImage: "circle.lefthalf.filled")
                }
                .pickerStyle(.menu)
                Toggle(isOn: $hideEnded) {
                    Label("隐藏断联和拉黑", systemImage: "eye.slash")
                }
            }
        } label: {
            Image(systemName: "line.3.horizontal.decrease")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 44, height: 44)
                .floatingGlass(Circle(), interactive: true)
                .overlay(alignment: .topTrailing) {
                    if hasFilters {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 9, height: 9)
                            .offset(x: -2, y: 2)
                    }
                }
        }
        .accessibilityLabel("筛选和显示")
        .accessibilityIdentifier("mapFilter")
    }

    // MARK: 底部

    @ViewBuilder
    private func bottomArea(_ content: MapContent) -> some View {
        Group {
            if let playback {
                PlaybackPanel(playback: playback, stats: content.stats,
                              onToggle: togglePlayback,
                              onSeek: { seek(to: $0) },
                              onClose: stopPlayback)
                    .padding(.horizontal, 16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if let draft {
                DraftPlaceCard(draft: draft, onCancel: cancelDraft) {
                    sheet = .newPlace(draft.picked)
                }
                .padding(.horizontal, 16)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if focus != nil, !cards.isEmpty {
                carousel
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                MapSummaryStrip(stats: content.stats, heatLegend: mode == .heat) {
                    sheet = .overview
                }
                .padding(.horizontal, 16)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(.bottom, 8)
    }

    private var carousel: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 10) {
                ForEach(cards, id: \.self) { f in
                    card(for: f)
                        .containerRelativeFrame(.horizontal) { width, _ in width - 52 }
                }
            }
            .scrollTargetLayout()
        }
        .contentMargins(.horizontal, 20, for: .scrollContent)
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $scrolledCard)
        .frame(height: 132)
    }

    @ViewBuilder
    private func card(for f: MapFocus) -> some View {
        switch f {
        case .girl(let id):
            if let g = girls.first(where: { $0.id == id }) {
                GirlMapCard(girl: g, distance: distance(to: g.coordinate),
                            onOpen: { sheet = .girl(id) },
                            onRecord: { sheet = .record(girl: id, place: nil) })
            }
        case .place(let id):
            if let p = places.first(where: { $0.id == id }) {
                PlaceMapCard(place: p, count: visitCount(p), distance: distance(to: p.coordinate),
                             onOpen: { sheet = .place(id) },
                             onRecord: { sheet = .record(girl: girlFilter, place: id) },
                             onNavigate: { navigate(to: p) })
            }
        }
    }

    // MARK: 弹窗

    @ViewBuilder
    private func sheetContent(_ which: MapSheet) -> some View {
        switch which {
        case .girl(let id):
            if let g = girls.first(where: { $0.id == id }) {
                NavigationStack { GirlDetailView(girl: g) }
            }
        case .place(let id):
            if let p = places.first(where: { $0.id == id }) {
                NavigationStack { PlaceDetailView(place: p) }
                    .presentationDetents([.medium, .large])
            }
        case .record(let girlID, let placeID):
            EncounterEditView(encounter: nil,
                              presetGirls: girls.filter { $0.id == girlID },
                              presetPlace: places.first { $0.id == placeID })
        case .newPlace(let picked):
            PlaceEditView(place: nil, preset: picked) { saved in
                draft = nil
                if saved.coordinate != nil {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        if mode == .harem || mode == .heat { modeRaw = MapMode.all.rawValue }
                    }
                }
            }
        case .overview:
            MapOverviewView(girls: girls, places: places, range: range, girlFilter: girlFilter, hideEnded: hideEnded,
                            onFly: { coords in
                                clearFocus()
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { controller.fly(to: coords) }
                            },
                            onFocusPlace: { id in focusPlaceFromOverview(id) })
                .composerSheet()
        }
    }

    // MARK: 选中

    private func show(_ f: MapFocus, among content: MapContent) {
        guard playback == nil, f != focus else { return }
        draft = nil
        if focus != nil, cards.contains(f) {
            // 卡片已经展开：直接滑到它，不打乱顺序
            focus = f
            withAnimation(.snappy) { scrolledCard = f }
            return
        }
        cards = ordered(content, from: content.coordinate(of: f), first: [f])
        focus = f
        scrolledCard = f
    }

    private func showGroup(_ members: [MapFocus], among content: MapContent) {
        guard playback == nil, let first = members.first else { return }
        draft = nil
        cards = ordered(content, from: content.coordinate(of: first), first: members)
        focus = first
        scrolledCard = first
    }

    /// 底部卡片的顺序：先放点中的，其余按离它的远近排
    private func ordered(_ content: MapContent, from origin: CLLocationCoordinate2D?, first: [MapFocus]) -> [MapFocus] {
        let rest = content.focuses.filter { !first.contains($0) }
        guard let origin else { return first + rest }
        let sorted = rest.sorted {
            (content.coordinate(of: $0)?.distance(to: origin) ?? .greatestFiniteMagnitude)
                < (content.coordinate(of: $1)?.distance(to: origin) ?? .greatestFiniteMagnitude)
        }
        return first + sorted
    }

    private func clearFocus() {
        guard focus != nil else { return }
        focus = nil
        scrolledCard = nil
    }

    private func focusPlaceFromOverview(_ id: UUID) {
        clearFocus()
        if !mode.showsSpots { modeRaw = MapMode.all.rawValue }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            let content = snapshot.content(mode: mode)
            guard content.spots.contains(where: { $0.id == id }) else { return }
            show(.place(id), among: content)
            controller.reveal(.place(id))
        }
    }

    private func refitSoon() {
        if playback != nil { stopPlayback() }
        clearFocus()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { controller.fitAll() }
    }

    // MARK: 长按新建地点

    private func dropPin(at coordinate: CLLocationCoordinate2D) {
        guard playback == nil else { return }
        clearFocus()
        draft = DraftPin(latitude: coordinate.latitude, longitude: coordinate.longitude)
        Task {
            let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            let placemark = try? await CLGeocoder().reverseGeocodeLocation(location).first
            guard var current = draft,
                  current.latitude == coordinate.latitude, current.longitude == coordinate.longitude else { return }
            if let pm = placemark {
                current.name = pm.name ?? ""
                current.address = LocationPickerView.address(of: pm)
                current.city = pm.locality ?? pm.administrativeArea ?? ""
                current.district = pm.subLocality ?? ""
            }
            current.resolved = true
            draft = current
        }
    }

    private func cancelDraft() {
        draft = nil
    }

    // MARK: 回放

    private func startPlayback() {
        clearFocus()
        draft = nil
        let snap = snapshot
        guard let start = snap.firstDate else { return }
        controller.fitAll()
        playbackSnapshot = snap
        // 起点往前留一点，让第一个标记也有“出现”的过程
        let begin = start.addingTimeInterval(-86_400 * 2)
        playback = MapPlayback(start: begin, end: Date(), progress: 0, playing: true)
    }

    private func togglePlayback() {
        guard var p = playback else { return }
        if p.isFinished {
            p.progress = 0
            p.playing = true
        } else {
            p.playing.toggle()
        }
        playback = p
    }

    private func seek(to progress: Double) {
        guard var p = playback else { return }
        p.progress = min(max(progress, 0), 1)
        p.playing = false
        playback = p
    }

    private func stopPlayback() {
        playback = nil
        playbackSnapshot = nil
    }

    /// 整段历史大约 12 秒放完
    private func runPlayback() async {
        guard playback?.playing == true else { return }
        let step = 0.05
        let duration = 12.0
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(Int(step * 1000)))
            guard var p = playback, p.playing else { return }
            p.progress = min(p.progress + step / duration, 1)
            if p.progress >= 1 {
                p.playing = false
                Haptics.success()
            }
            playback = p
        }
    }

    // MARK: 小工具

    private func distance(to coordinate: CLLocationCoordinate2D?) -> CLLocationDistance? {
        guard let userCoordinate, let coordinate else { return nil }
        return userCoordinate.distance(to: coordinate)
    }

    private func visitCount(_ place: Place) -> Int {
        place.encounters.filter { e in
            range.contains(e.date) && (girlFilter == nil || e.girls.contains { $0.id == girlFilter })
        }.count
    }

    private func navigate(to place: Place) {
        guard let c = place.coordinate else { return }
        let item = MKMapItem(placemark: MKPlacemark(coordinate: c))
        item.name = place.displayName
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDefault])
    }
}
