import SwiftUI
import MapKit

/// SwiftUI 这边用来“遥控”地图：显示全部、定位、飞到某处、选中某个标记
@MainActor
final class MapController: ObservableObject {
    fileprivate weak var coordinator: ClusterMapView.Coordinator?

    func fitAll(animated: Bool = true) {
        coordinator?.fitAll(animated: animated)
    }

    func locateMe() {
        coordinator?.locateMe()
    }

    func fly(to coordinates: [CLLocationCoordinate2D]) {
        coordinator?.fly(to: coordinates)
    }

    /// 让某个标记出现在可见区域中间并选中（滑动底部卡片时用）
    func reveal(_ focus: MapFocus) {
        coordinator?.reveal(focus)
    }
}

struct ClusterMapView: UIViewRepresentable {
    /// 底部卡片展开时占的高度，选中标记时按它留出空间
    static let cardChrome: CGFloat = 168

    var content: MapContent
    var focus: MapFocus?
    var draft: CLLocationCoordinate2D?
    var style: MapStyle
    /// 顶部和底部浮层占掉的高度（安全区以外的部分）
    var chrome: UIEdgeInsets
    let controller: MapController
    var onFocus: (MapFocus) -> Void
    var onCluster: ([MapFocus]) -> Void
    var onTapEmpty: () -> Void
    var onLongPress: (CLLocationCoordinate2D) -> Void
    var onUserLocation: (CLLocationCoordinate2D) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.showsUserLocation = true
        map.showsCompass = false
        map.isRotateEnabled = false
        map.isPitchEnabled = false
        map.register(PersonPinView.self, forAnnotationViewWithReuseIdentifier: PersonPinView.reuseID)
        map.register(SpotPinView.self, forAnnotationViewWithReuseIdentifier: SpotPinView.reuseID)
        map.register(GroupMarkerView.self, forAnnotationViewWithReuseIdentifier: GroupMarkerView.reuseID)
        map.setRegion(MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 33, longitude: 112),
                                         span: MKCoordinateSpan(latitudeDelta: 26, longitudeDelta: 26)), animated: false)

        let longPress = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleLongPress(_:)))
        longPress.minimumPressDuration = 0.45
        longPress.delegate = context.coordinator
        map.addGestureRecognizer(longPress)

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        tap.cancelsTouchesInView = false
        tap.delegate = context.coordinator
        // 长按松手时不要再当成「点空白处」，否则刚放下的新地点会被马上取消
        tap.require(toFail: longPress)
        map.addGestureRecognizer(tap)

        context.coordinator.map = map
        controller.coordinator = context.coordinator
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        context.coordinator.parent = self
        controller.coordinator = context.coordinator
        context.coordinator.update(map)
    }

    final class Coordinator: NSObject, MKMapViewDelegate, UIGestureRecognizerDelegate {
        var parent: ClusterMapView
        weak var map: MKMapView?

        /// 全部人和地点的标记（包括回放中还没出现的），不一定都在地图上
        private var people: [UUID: PersonAnnotation] = [:]
        private var spots: [UUID: SpotAnnotation] = [:]
        /// 现在真正放在地图上的：单个标记，或者几个合成的一个
        private var displayed: [ObjectIdentifier: MKAnnotation] = [:]
        private var groups: [String: GroupAnnotation] = [:]
        /// 上次合并时的地图宽度（地图点），缩放明显变化时重新合并
        private var layoutWidth: Double = 0
        private var draftAnnotation: DraftAnnotation?
        private let markerViews = NSHashTable<MarkerView>.weakObjects()
        private var heatOverlay: HeatOverlay?
        private var heatSource: [HeatPoint] = []
        private var arcs: [ArcPolyline] = []
        private var appliedFocus: MapFocus?
        private var appliedLinks = Set<MapLink>()
        private var related = Set<UUID>()
        private var appliedStyle: MapStyle?
        private var appliedChrome: UIEdgeInsets?
        private var didInitialFit = false
        /// 刚加到地图上的标记：只有它们做入场动画
        private var freshKeys = Set<ObjectIdentifier>()
        private var animateUntil: CFTimeInterval = 0
        private var lastUserCoordinate: CLLocationCoordinate2D?
        private var pendingSelect: MKAnnotation?
        /// 由卡片滑动触发的选中，didSelect 时不再回传给 SwiftUI
        private var programmaticFocus: MapFocus?

        init(parent: ClusterMapView) {
            self.parent = parent
        }

        // MARK: 同步

        func update(_ map: MKMapView) {
            applyStyle(map)
            applyChrome(map)
            syncItems(map)
            syncHeat(map)
            syncDraft(map)
            applyFocus(map)
        }

        private func applyStyle(_ map: MKMapView) {
            guard parent.style != appliedStyle else { return }
            appliedStyle = parent.style
            map.preferredConfiguration = parent.style.makeConfiguration()
        }

        private func applyChrome(_ map: MKMapView) {
            guard parent.chrome != appliedChrome else { return }
            appliedChrome = parent.chrome
            // 把地图自带的法律信息挪到浮层上方
            map.layoutMargins = UIEdgeInsets(top: parent.chrome.top, left: 8, bottom: parent.chrome.bottom, right: 8)
        }

        /// 把 SwiftUI 传来的人和地点同步成标记对象；成员或位置变了就重新合并
        private func syncItems(_ map: MKMapView) {
            var needsLayout = false
            var visualsChanged = false
            var pulsed = Set<UUID>()

            let newPeople = Dictionary(parent.content.people.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            for id in Array(people.keys) where newPeople[id] == nil {
                people[id] = nil
                needsLayout = true
            }
            for item in parent.content.people {
                if let existing = people[item.id] {
                    guard existing.item != item else { continue }
                    if existing.item.latitude != item.latitude || existing.item.longitude != item.longitude {
                        people[item.id] = PersonAnnotation(item)
                        needsLayout = true
                    } else {
                        if existing.item.active != item.active { needsLayout = true }
                        existing.item = item
                        visualsChanged = true
                    }
                } else {
                    people[item.id] = PersonAnnotation(item)
                    needsLayout = true
                }
            }

            let newSpots = Dictionary(parent.content.spots.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            for id in Array(spots.keys) where newSpots[id] == nil {
                spots[id] = nil
                needsLayout = true
            }
            for item in parent.content.spots {
                if let existing = spots[item.id] {
                    guard existing.item != item else { continue }
                    if existing.item.latitude != item.latitude || existing.item.longitude != item.longitude {
                        spots[item.id] = SpotAnnotation(item)
                        needsLayout = true
                    } else {
                        if existing.item.active != item.active {
                            needsLayout = true
                        } else if item.count > existing.item.count {
                            pulsed.insert(item.id)
                        }
                        existing.item = item
                        visualsChanged = true
                    }
                } else {
                    spots[item.id] = SpotAnnotation(item)
                    needsLayout = true
                }
            }

            if needsLayout { relayout(map) }
            if visualsChanged { refreshVisibleMarkers(map, pulse: pulsed) }

            if !didInitialFit, !people.isEmpty || !spots.isEmpty || !parent.content.heat.isEmpty {
                didInitialFit = true
                DispatchQueue.main.async { [weak self] in
                    self?.fitAll(animated: false)
                }
            }
        }

        // MARK: 合并

        /// 按当前缩放，把屏幕上挨得太近的标记合成一个（人和人合，地点和地点合）。
        /// 不用 MapKit 自带的聚合：它在镜头变化、逐个加入标记时经常不重新合并。
        private func relayout(_ map: MKMapView) {
            guard map.bounds.width > 1, map.bounds.height > 1 else { return }
            layoutWidth = map.visibleMapRect.size.width
            var desired: [MKAnnotation] = []
            var nextGroups: [String: GroupAnnotation] = [:]

            let activePeople = people.values
                .filter { $0.item.active }
                .sorted { $0.item.id.uuidString < $1.item.id.uuidString }
            for cluster in clusters(of: activePeople, radius: 46, in: map) {
                if cluster.count == 1 {
                    desired.append(cluster[0])
                    continue
                }
                let key = "p:" + cluster.map(\.item.id.uuidString).sorted().joined(separator: ",")
                let group = groups[key] ?? GroupAnnotation(people: cluster, key: key)
                nextGroups[key] = group
                desired.append(group)
            }

            let activeSpots = spots.values
                .filter { $0.item.active }
                .sorted { ($0.item.count, $0.item.id.uuidString) > ($1.item.count, $1.item.id.uuidString) }
            for cluster in clusters(of: activeSpots, radius: 40, in: map) {
                if cluster.count == 1 {
                    desired.append(cluster[0])
                    continue
                }
                let key = "s:" + cluster.map(\.item.id.uuidString).sorted().joined(separator: ",")
                let group = groups[key] ?? GroupAnnotation(spots: cluster, key: key)
                nextGroups[key] = group
                desired.append(group)
            }

            groups = nextGroups
            let wanted = Set(desired.map { ObjectIdentifier($0) })
            let toRemove = displayed.filter { !wanted.contains($0.key) }.map(\.value)
            let toAdd = desired.filter { displayed[ObjectIdentifier($0)] == nil }
            displayed = Dictionary(desired.map { (ObjectIdentifier($0), $0) }, uniquingKeysWith: { a, _ in a })

            if !toRemove.isEmpty { map.removeAnnotations(toRemove) }
            if !toAdd.isEmpty {
                freshKeys = Set(toAdd.map { ObjectIdentifier($0) })
                animateUntil = CACurrentMediaTime() + 0.6
                map.addAnnotations(toAdd)
            }
            restoreFocusSelection(map)
        }

        /// 贪心合并：按顺序取一个还没归组的标记，把屏幕上离它 radius 以内的都并进来
        private func clusters<A: MKAnnotation>(of items: [A], radius: CGFloat, in map: MKMapView) -> [[A]] {
            let points = items.map { map.convert($0.coordinate, toPointTo: map) }
            var used = [Bool](repeating: false, count: items.count)
            var result: [[A]] = []
            for i in items.indices where !used[i] {
                used[i] = true
                var cluster = [items[i]]
                for j in items.indices where !used[j] {
                    let dx = points[i].x - points[j].x
                    let dy = points[i].y - points[j].y
                    if dx * dx + dy * dy < radius * radius {
                        used[j] = true
                        cluster.append(items[j])
                    }
                }
                result.append(cluster)
            }
            return result
        }

        /// 数字、头像等变了：重画地图上的标记；次数增加的跳一下
        private func refreshVisibleMarkers(_ map: MKMapView, pulse: Set<UUID>) {
            for annotation in displayed.values {
                guard let view = map.view(for: annotation) as? MarkerView else { continue }
                view.configure()
                let ids: [UUID]
                if let p = annotation as? PersonAnnotation {
                    ids = [p.item.id]
                } else if let s = annotation as? SpotAnnotation {
                    ids = [s.item.id]
                } else if let g = annotation as? GroupAnnotation {
                    ids = g.people.map { $0.item.id } + g.spots.map { $0.item.id }
                } else {
                    ids = []
                }
                if ids.contains(where: { pulse.contains($0) }) { view.pulse() }
            }
        }

        /// 重新合并后，选中的标记如果又单独露出来了，把选中状态补回去
        private func restoreFocusSelection(_ map: MKMapView) {
            guard let focus = appliedFocus, let annotation = annotation(for: focus),
                  displayed[ObjectIdentifier(annotation)] != nil,
                  !map.selectedAnnotations.contains(where: { $0 === annotation }) else { return }
            DispatchQueue.main.async { [weak self, weak map] in
                guard let self, let map, self.appliedFocus == focus, map.view(for: annotation) != nil else { return }
                self.programmaticFocus = focus
                map.selectAnnotation(annotation, animated: false)
            }
        }

        private func syncHeat(_ map: MKMapView) {
            guard parent.content.heat != heatSource else { return }
            heatSource = parent.content.heat
            if heatSource.isEmpty {
                if let old = heatOverlay { map.removeOverlay(old) }
                heatOverlay = nil
                return
            }
            if let overlay = heatOverlay {
                // 原地更新，避免整层闪一下
                overlay.update(heatSource)
                map.renderer(for: overlay)?.setNeedsDisplay()
            } else {
                let overlay = HeatOverlay(points: heatSource)
                heatOverlay = overlay
                map.addOverlay(overlay, level: .aboveRoads)
            }
        }

        private func syncDraft(_ map: MKMapView) {
            let current = draftAnnotation?.coordinate
            let wanted = parent.draft
            let same: Bool
            switch (current, wanted) {
            case (nil, nil): same = true
            case let (a?, b?): same = a.latitude == b.latitude && a.longitude == b.longitude
            default: same = false
            }
            guard !same else { return }
            if let old = draftAnnotation { map.removeAnnotation(old) }
            draftAnnotation = nil
            if let wanted {
                let pin = DraftAnnotation(wanted)
                draftAnnotation = pin
                map.addAnnotation(pin)
            }
        }

        // MARK: 选中后的弱化和连线

        private func applyFocus(_ map: MKMapView) {
            let links = Set(parent.content.links)
            guard parent.focus != appliedFocus || links != appliedLinks else { return }
            let focusChanged = parent.focus != appliedFocus
            appliedFocus = parent.focus
            appliedLinks = links

            switch parent.focus {
            case .girl(let id)?:
                related = Set(links.filter { $0.girl == id }.map(\.place)).union([id])
            case .place(let id)?:
                related = Set(links.filter { $0.place == id }.map(\.girl)).union([id])
            case nil:
                related = []
            }

            UIView.animate(withDuration: focusChanged ? 0.3 : 0) {
                for view in self.markerViews.allObjects {
                    guard let annotation = view.annotation else { continue }
                    view.alpha = self.isRelated(annotation) ? 1 : 0.3
                }
            }

            if !arcs.isEmpty { map.removeOverlays(arcs) }
            arcs = makeArcs()
            if !arcs.isEmpty { map.addOverlays(arcs, level: .aboveRoads) }

            if parent.focus == nil {
                for a in map.selectedAnnotations { map.deselectAnnotation(a, animated: true) }
            }
        }

        private func isRelated(_ annotation: MKAnnotation) -> Bool {
            guard appliedFocus != nil else { return true }
            if let p = annotation as? PersonAnnotation { return related.contains(p.item.id) }
            if let s = annotation as? SpotAnnotation { return related.contains(s.item.id) }
            if let g = annotation as? GroupAnnotation { return g.members.contains { isRelated($0) } }
            return true
        }

        private func makeArcs() -> [ArcPolyline] {
            switch appliedFocus {
            case .girl(let id)?:
                guard let from = people[id]?.coordinate else { return [] }
                return appliedLinks.filter { $0.girl == id }.compactMap { (link: MapLink) -> ArcPolyline? in
                    guard let to = spots[link.place]?.coordinate, from.distance(to: to) > 60 else { return nil }
                    return ArcBuilder.arc(from: from, to: to)
                }
            case .place(let id)?:
                guard let to = spots[id]?.coordinate else { return [] }
                return appliedLinks.filter { $0.place == id }.compactMap { (link: MapLink) -> ArcPolyline? in
                    guard let from = people[link.girl]?.coordinate, from.distance(to: to) > 60 else { return nil }
                    return ArcBuilder.arc(from: from, to: to)
                }
            case nil:
                return []
            }
        }

        // MARK: 相机

        /// 浮层以外真正能看到地图的区域；`focusing` 时按底部卡片的高度算
        private func visibleInsets(_ map: MKMapView, focusing: Bool = false) -> UIEdgeInsets {
            let safe = map.safeAreaInsets
            let bottom = focusing ? max(parent.chrome.bottom, ClusterMapView.cardChrome) : parent.chrome.bottom
            return UIEdgeInsets(top: safe.top + parent.chrome.top, left: 0, bottom: safe.bottom + bottom, right: 0)
        }

        func fitAll(animated: Bool) {
            guard let map else { return }
            let coords = people.values.map(\.coordinate) + spots.values.map(\.coordinate)
                + parent.content.heat.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
            fit(map, to: coords, animated: animated)
        }

        func fly(to coordinates: [CLLocationCoordinate2D]) {
            guard let map else { return }
            fit(map, to: coordinates, animated: true)
        }

        private func fit(_ map: MKMapView, to coordinates: [CLLocationCoordinate2D], animated: Bool) {
            guard let first = coordinates.first else { return }
            var rect = MKMapRect.null
            for c in coordinates {
                let p = MKMapPoint(c)
                rect = rect.union(MKMapRect(x: p.x, y: p.y, width: 1, height: 1))
            }
            let minSide = 2600 * MKMapPointsPerMeterAtLatitude(first.latitude)
            if rect.size.width < minSide || rect.size.height < minSide {
                rect = rect.insetBy(dx: -(max(minSide - rect.size.width, 0) / 2),
                                    dy: -(max(minSide - rect.size.height, 0) / 2))
            }
            let insets = visibleInsets(map)
            // 头像标记在坐标上方、地点胶囊在下方，上下都留一点
            let padding = UIEdgeInsets(top: insets.top + 72, left: 48, bottom: insets.bottom + 40, right: 48)
            map.setVisibleMapRect(rect, edgePadding: padding, animated: animated)
        }

        func locateMe() {
            guard let map else { return }
            guard let location = map.userLocation.location else {
                LocationPermission.requestIfNeeded()
                return
            }
            let insets = visibleInsets(map)
            let side = 3000 * MKMapPointsPerMeterAtLatitude(location.coordinate.latitude)
            let p = MKMapPoint(location.coordinate)
            map.setVisibleMapRect(MKMapRect(x: p.x - side / 2, y: p.y - side / 2, width: side, height: side),
                                  edgePadding: UIEdgeInsets(top: insets.top + 20, left: 30, bottom: insets.bottom + 20, right: 30),
                                  animated: true)
        }

        /// 把坐标移到可见区域正中，保持缩放
        private func center(_ coordinate: CLLocationCoordinate2D, in map: MKMapView) {
            let insets = visibleInsets(map, focusing: true)
            let p = map.convert(coordinate, toPointTo: map)
            let desired = CGPoint(x: map.bounds.midX,
                                  y: insets.top + (map.bounds.height - insets.top - insets.bottom) / 2 + 20)
            let target = CGPoint(x: map.bounds.midX + p.x - desired.x, y: map.bounds.midY + p.y - desired.y)
            map.setCenter(map.convert(target, toCoordinateFrom: map), animated: true)
        }

        /// 点中的标记如果被底部卡片挡住，就挪上来
        private func keepVisible(_ coordinate: CLLocationCoordinate2D, in map: MKMapView) {
            let insets = visibleInsets(map, focusing: true)
            let p = map.convert(coordinate, toPointTo: map)
            let top = insets.top + 70
            let bottom = map.bounds.height - insets.bottom - 24
            guard p.y < top || p.y > bottom || p.x < 36 || p.x > map.bounds.width - 36 else { return }
            center(coordinate, in: map)
        }

        func reveal(_ focus: MapFocus) {
            guard let map, let annotation = annotation(for: focus) else { return }
            programmaticFocus = focus
            let coordinate = annotation.coordinate
            if displayed[ObjectIdentifier(annotation)] == nil {
                // 合并在别的标记里：拉近到它能单独显示
                let meters = max(min(map.region.span.latitudeDelta * 111_000 * 0.3, 6000), 900)
                let side = meters * MKMapPointsPerMeterAtLatitude(coordinate.latitude)
                let p = MKMapPoint(coordinate)
                let insets = visibleInsets(map, focusing: true)
                map.setVisibleMapRect(MKMapRect(x: p.x - side / 2, y: p.y - side / 2, width: side, height: side),
                                      edgePadding: UIEdgeInsets(top: insets.top + 40, left: 30, bottom: insets.bottom + 10, right: 30),
                                      animated: true)
                pendingSelect = annotation
            } else {
                center(coordinate, in: map)
                select(annotation, in: map)
            }
        }

        private func select(_ annotation: MKAnnotation, in map: MKMapView) {
            if map.selectedAnnotations.contains(where: { $0 === annotation }) { return }
            map.selectAnnotation(annotation, animated: true)
        }

        private func annotation(for focus: MapFocus) -> MKAnnotation? {
            switch focus {
            case .girl(let id): return people[id]
            case .place(let id): return spots[id]
            }
        }

        private func focus(of annotation: MKAnnotation) -> MapFocus? {
            if let p = annotation as? PersonAnnotation { return .girl(p.item.id) }
            if let s = annotation as? SpotAnnotation { return .place(s.item.id) }
            return nil
        }

        // MARK: MKMapViewDelegate

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            let view: MKAnnotationView
            switch annotation {
            case is MKUserLocation:
                return nil
            case let group as GroupAnnotation:
                view = mapView.dequeueReusableAnnotationView(withIdentifier: GroupMarkerView.reuseID, for: group)
            case is PersonAnnotation:
                view = mapView.dequeueReusableAnnotationView(withIdentifier: PersonPinView.reuseID, for: annotation)
            case is SpotAnnotation:
                view = mapView.dequeueReusableAnnotationView(withIdentifier: SpotPinView.reuseID, for: annotation)
            case is DraftAnnotation:
                let marker = mapView.dequeueReusableAnnotationView(withIdentifier: "draft") as? MKMarkerAnnotationView
                    ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: "draft")
                marker.annotation = annotation
                marker.markerTintColor = Palette.wineUI
                marker.glyphImage = UIImage(systemName: "plus")
                marker.displayPriority = .required
                marker.animatesWhenAdded = true
                marker.canShowCallout = false
                return marker
            default:
                return nil
            }
            if let marker = view as? MarkerView {
                markerViews.add(marker)
                marker.alpha = isRelated(annotation) ? 1 : 0.3
            }
            return view
        }

        func mapView(_ mapView: MKMapView, didAdd views: [MKAnnotationView]) {
            guard CACurrentMediaTime() < animateUntil else { return }
            var order = 0
            for view in views {
                guard let marker = view as? MarkerView, let annotation = view.annotation,
                      freshKeys.contains(ObjectIdentifier(annotation)) else { continue }
                marker.appear(delay: min(Double(order) * 0.03, 0.3), alpha: marker.alpha)
                order += 1
            }
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let heat = overlay as? HeatOverlay { return HeatRenderer(heat: heat) }
            if let arc = overlay as? ArcPolyline { return ArcBuilder.renderer(for: arc) }
            return MKOverlayRenderer(overlay: overlay)
        }

        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            guard let annotation = view.annotation else { return }
            if annotation is MKUserLocation || annotation is DraftAnnotation {
                mapView.deselectAnnotation(annotation, animated: false)
                return
            }
            if let group = annotation as? GroupAnnotation {
                mapView.deselectAnnotation(group, animated: false)
                let members = group.members
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                if spread(of: members) > 40 && mapView.region.span.latitudeDelta > 0.004 {
                    fit(mapView, to: members.map { $0.coordinate }, animated: true)
                } else {
                    // 同一个位置放大也分不开：直接在底部卡片里一个个看
                    let focuses = members.compactMap { focus(of: $0) }
                    guard !focuses.isEmpty else { return }
                    DispatchQueue.main.async { self.parent.onCluster(focuses) }
                }
                return
            }
            guard let tapped = focus(of: annotation) else { return }
            // 是 SwiftUI 那边让选中的，不再回传
            if tapped == appliedFocus || tapped == programmaticFocus {
                programmaticFocus = nil
                return
            }
            programmaticFocus = nil
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            keepVisible(annotation.coordinate, in: mapView)
            DispatchQueue.main.async { self.parent.onFocus(tapped) }
        }

        /// 拖动缩放过程中，缩放变化够大就重新合并，标记会跟着分开或合拢
        func mapViewDidChangeVisibleRegion(_ mapView: MKMapView) {
            let width = mapView.visibleMapRect.size.width
            guard layoutWidth > 0, abs(width / layoutWidth - 1) > 0.15 else { return }
            relayout(mapView)
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            let width = mapView.visibleMapRect.size.width
            let hasItems = !people.isEmpty || !spots.isEmpty
            if layoutWidth == 0 || abs(width / layoutWidth - 1) > 0.01 || (displayed.isEmpty && hasItems) {
                relayout(mapView)
            }
            guard let pending = pendingSelect else { return }
            pendingSelect = nil
            guard displayed[ObjectIdentifier(pending)] != nil else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self, weak mapView] in
                guard let self, let mapView, mapView.view(for: pending) != nil else { return }
                self.select(pending, in: mapView)
            }
        }

        func mapView(_ mapView: MKMapView, didUpdate userLocation: MKUserLocation) {
            guard let coordinate = userLocation.location?.coordinate else { return }
            if let last = lastUserCoordinate, last.distance(to: coordinate) < 150 { return }
            lastUserCoordinate = coordinate
            DispatchQueue.main.async { self.parent.onUserLocation(coordinate) }
        }

        /// 成员之间的最大距离（米）
        private func spread(of members: [MKAnnotation]) -> CLLocationDistance {
            guard let first = members.first else { return 0 }
            return members.map { $0.coordinate.distance(to: first.coordinate) }.max() ?? 0
        }

        // MARK: 手势

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard gesture.state == .ended, let map else { return }
            let point = gesture.location(in: map)
            guard !hitsAnnotation(at: point, in: map) else { return }
            parent.onTapEmpty()
        }

        @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
            guard gesture.state == .began, let map else { return }
            let point = gesture.location(in: map)
            guard !hitsAnnotation(at: point, in: map) else { return }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            parent.onLongPress(map.convert(point, toCoordinateFrom: map))
        }

        private func hitsAnnotation(at point: CGPoint, in map: MKMapView) -> Bool {
            var view = map.hitTest(point, with: nil)
            while let v = view {
                if v is MKAnnotationView { return true }
                view = v.superview
            }
            return false
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }
    }
}
