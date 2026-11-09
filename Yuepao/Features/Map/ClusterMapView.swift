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
        map.register(ClusterMarkerView.self, forAnnotationViewWithReuseIdentifier: ClusterMarkerView.reuseID)
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

        private var people: [UUID: PersonAnnotation] = [:]
        private var spots: [UUID: SpotAnnotation] = [:]
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
        /// 数据刚变过：这段时间里新出现的标记做入场动画
        private var animateUntil: CFTimeInterval = 0
        /// 这一轮新加的标记（只有它们和包含它们的聚合做入场动画）
        private var freshKeys = Set<ObjectIdentifier>()
        private var reclusterScheduled = false
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
            syncAnnotations(map)
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

        private func syncAnnotations(_ map: MKMapView) {
            var toRemove: [MKAnnotation] = []
            var toAdd: [MKAnnotation] = []
            var pulsed: [MKAnnotation] = []
            var appeared: [MKAnnotation] = []
            var visualsChanged = false

            let newPeople = Dictionary(parent.content.people.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            for (id, annotation) in people where newPeople[id] == nil {
                toRemove.append(annotation)
                people[id] = nil
            }
            for item in parent.content.people {
                if let existing = people[item.id] {
                    guard existing.item != item else { continue }
                    if existing.item.latitude != item.latitude || existing.item.longitude != item.longitude {
                        toRemove.append(existing)
                        let fresh = PersonAnnotation(item)
                        people[item.id] = fresh
                        toAdd.append(fresh)
                    } else {
                        let activated = item.active && !existing.item.active
                        existing.item = item
                        (map.view(for: existing) as? MarkerView)?.configure()
                        if activated { appeared.append(existing) }
                        visualsChanged = true
                    }
                } else {
                    let fresh = PersonAnnotation(item)
                    people[item.id] = fresh
                    toAdd.append(fresh)
                }
            }

            let newSpots = Dictionary(parent.content.spots.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            for (id, annotation) in spots where newSpots[id] == nil {
                toRemove.append(annotation)
                spots[id] = nil
            }
            for item in parent.content.spots {
                if let existing = spots[item.id] {
                    guard existing.item != item else { continue }
                    if existing.item.latitude != item.latitude || existing.item.longitude != item.longitude {
                        toRemove.append(existing)
                        let fresh = SpotAnnotation(item)
                        spots[item.id] = fresh
                        toAdd.append(fresh)
                    } else {
                        let activated = item.active && !existing.item.active
                        let grew = item.count > existing.item.count
                        existing.item = item
                        (map.view(for: existing) as? MarkerView)?.configure()
                        if activated {
                            appeared.append(existing)
                        } else if grew {
                            pulsed.append(existing)
                        }
                        visualsChanged = true
                    }
                } else {
                    let fresh = SpotAnnotation(item)
                    spots[item.id] = fresh
                    toAdd.append(fresh)
                }
            }

            if !toRemove.isEmpty { map.removeAnnotations(toRemove) }
            if !toAdd.isEmpty {
                animateUntil = CACurrentMediaTime() + 0.8
                freshKeys = Set(toAdd.map { ObjectIdentifier($0) })
                map.addAnnotations(toAdd)
                if didInitialFit { scheduleRecluster(map) }
            }
            if visualsChanged { refreshClusters(pulse: pulsed + appeared) }
            for a in pulsed {
                (map.view(for: a) as? MarkerView)?.pulse()
            }
            for a in appeared {
                guard let view = map.view(for: a) as? MarkerView else { continue }
                view.appear(delay: 0, alpha: view.alpha)
            }

            if !didInitialFit, !toAdd.isEmpty || !parent.content.heat.isEmpty {
                didInitialFit = true
                DispatchQueue.main.async { [weak self] in
                    self?.fitAll(animated: false)
                }
            }
        }

        /// MapKit 只在镜头变化时重新计算聚合，后加进来的标记不会和已有的合并。
        /// 等新标记的视图建好后，把镜头缩放千分之一（肉眼看不出），让它重新算一遍。
        private func scheduleRecluster(_ map: MKMapView) {
            guard !reclusterScheduled else { return }
            reclusterScheduled = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self, weak map] in
                guard let self, let map else { return }
                self.reclusterScheduled = false
                let rect = map.visibleMapRect
                map.setVisibleMapRect(rect.insetBy(dx: -rect.size.width * 0.0005, dy: -rect.size.height * 0.0005),
                                      animated: false)
            }
        }

        /// 聚合标记的图不会自己更新，成员数字变了要手动重画
        private func refreshClusters(pulse: [MKAnnotation]) {
            for view in markerViews.allObjects {
                guard let cluster = view.annotation as? MKClusterAnnotation else { continue }
                view.configure()
                if pulse.contains(where: { p in cluster.memberAnnotations.contains { $0 === p } }) {
                    view.pulse()
                }
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
            if let c = annotation as? MKClusterAnnotation { return c.memberAnnotations.contains { isRelated($0) } }
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
            // 头像标记在坐标上方，顶部多留一点
            let padding = UIEdgeInsets(top: insets.top + 72, left: 48, bottom: insets.bottom + 28, right: 48)
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
            let onScreen = map.visibleMapRect.contains(MKMapPoint(coordinate))
            if map.view(for: annotation) == nil && onScreen {
                // 藏在聚合里：拉近一些让它单独露出来
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
            case let cluster as MKClusterAnnotation:
                view = mapView.dequeueReusableAnnotationView(withIdentifier: ClusterMarkerView.reuseID, for: cluster)
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
                guard let marker = view as? MarkerView, let annotation = view.annotation else { continue }
                let isFresh: Bool
                if let cluster = annotation as? MKClusterAnnotation {
                    isFresh = cluster.memberAnnotations.contains { freshKeys.contains(ObjectIdentifier($0)) }
                } else {
                    isFresh = freshKeys.contains(ObjectIdentifier(annotation))
                }
                guard isFresh else { continue }
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
            if let cluster = annotation as? MKClusterAnnotation {
                mapView.deselectAnnotation(cluster, animated: false)
                let members = cluster.memberAnnotations
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

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            guard let pending = pendingSelect else { return }
            pendingSelect = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self, weak mapView] in
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
