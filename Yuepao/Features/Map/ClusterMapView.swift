import SwiftUI
import MapKit

struct MapGirlItem {
    let id: UUID
    let name: String
    let coordinate: CLLocationCoordinate2D
    let color: UIColor
    let avatarID: String?
}

struct MapPlaceItem {
    let id: UUID
    let name: String
    let coordinate: CLLocationCoordinate2D
    let count: Int
}

enum MapSelection: Identifiable {
    case girl(UUID)
    case place(UUID)
    case group(girls: [UUID], places: [UUID])

    var id: String {
        switch self {
        case .girl(let id): return "g-\(id)"
        case .place(let id): return "p-\(id)"
        case .group(let g, let p): return "grp-" + (g + p).map(\.uuidString).joined(separator: ",")
        }
    }
}

// MARK: - Annotations

final class GirlAnnotation: NSObject, MKAnnotation {
    let item: MapGirlItem
    var coordinate: CLLocationCoordinate2D { item.coordinate }
    var title: String? { item.name }

    init(_ item: MapGirlItem) {
        self.item = item
    }
}

final class PlaceAnnotation: NSObject, MKAnnotation {
    let item: MapPlaceItem
    var coordinate: CLLocationCoordinate2D { item.coordinate }
    var title: String? { item.name }

    init(_ item: MapPlaceItem) {
        self.item = item
    }
}

// MARK: - Annotation views

final class GirlAnnotationView: MKAnnotationView {
    static let reuseID = "girl"

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        clusteringIdentifier = "girl"
        collisionMode = .circle
        displayPriority = .required
        canShowCallout = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func prepareForDisplay() {
        super.prepareForDisplay()
        clusteringIdentifier = "girl"
        guard let a = annotation as? GirlAnnotation else { return }
        let avatar = a.item.avatarID.flatMap { PhotoStore.shared.thumbnail($0, size: 120) }
        image = MarkerRenderer.avatar(image: avatar, name: a.item.name, border: a.item.color)
        centerOffset = CGPoint(x: 0, y: 8)
    }
}

final class PlaceAnnotationView: MKAnnotationView {
    static let reuseID = "place"

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        clusteringIdentifier = "place"
        collisionMode = .circle
        displayPriority = .required
        canShowCallout = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func prepareForDisplay() {
        super.prepareForDisplay()
        clusteringIdentifier = "place"
        guard let a = annotation as? PlaceAnnotation else { return }
        image = MarkerRenderer.countBadge(count: a.item.count, suffix: "")
        // 往右上角偏一点，和同一位置的头像错开，像个角标
        centerOffset = MarkerRenderer.placeOffset
    }
}

final class CountClusterView: MKAnnotationView {
    static let reuseID = "cluster"

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        collisionMode = .circle
        displayPriority = .required
        canShowCallout = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func prepareForDisplay() {
        super.prepareForDisplay()
        guard let cluster = annotation as? MKClusterAnnotation else { return }
        let members = cluster.memberAnnotations
        if members.first is GirlAnnotation {
            image = MarkerRenderer.girlCluster(count: members.count)
            centerOffset = .zero
        } else {
            let total = members.compactMap { ($0 as? PlaceAnnotation)?.item.count }.reduce(0, +)
            image = MarkerRenderer.countBadge(count: total, suffix: "")
            centerOffset = MarkerRenderer.placeOffset
        }
    }
}

enum MarkerRenderer {
    static let placeOffset = CGPoint(x: 18, y: -18)

    static func avatar(image: UIImage?, name: String, border: UIColor) -> UIImage {
        let diameter: CGFloat = 44
        let labelHeight: CGFloat = 16
        let width: CGFloat = 72
        let size = CGSize(width: width, height: diameter + labelHeight)
        return UIGraphicsImageRenderer(size: size).image { _ in
            let circle = CGRect(x: (width - diameter) / 2, y: 0, width: diameter, height: diameter)
            let inner = circle.insetBy(dx: 3, dy: 3)

            border.setFill()
            UIBezierPath(ovalIn: circle).fill()

            UIGraphicsGetCurrentContext()?.saveGState()
            UIBezierPath(ovalIn: inner).addClip()
            if let image {
                let scale = max(inner.width / image.size.width, inner.height / image.size.height)
                let w = image.size.width * scale, h = image.size.height * scale
                image.draw(in: CGRect(x: inner.midX - w / 2, y: inner.midY - h / 2, width: w, height: h))
            } else {
                let (top, bottom) = Palette.avatarUIColors(for: name)
                if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                             colors: [top.cgColor, bottom.cgColor] as CFArray,
                                             locations: [0, 1]) {
                    UIGraphicsGetCurrentContext()?.drawLinearGradient(
                        gradient, start: CGPoint(x: inner.minX, y: inner.minY),
                        end: CGPoint(x: inner.maxX, y: inner.maxY), options: [])
                }
                let initial = String(name.prefix(1)) as NSString
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 18, weight: .semibold),
                    .foregroundColor: UIColor.white
                ]
                let s = initial.size(withAttributes: attrs)
                initial.draw(at: CGPoint(x: inner.midX - s.width / 2, y: inner.midY - s.height / 2), withAttributes: attrs)
            }
            UIGraphicsGetCurrentContext()?.restoreGState()

            let label = name as NSString
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            paragraph.lineBreakMode = .byTruncatingTail
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 11, weight: .semibold),
                .foregroundColor: UIColor.label,
                .strokeColor: UIColor.systemBackground,
                .strokeWidth: -3.0,
                .paragraphStyle: paragraph
            ]
            label.draw(in: CGRect(x: 0, y: diameter + 1, width: width, height: labelHeight), withAttributes: attrs)
        }
    }

    static func countBadge(count: Int, suffix: String) -> UIImage {
        let diameter = 30 + min(CGFloat(count), 20) * 1.4
        let intensity = min(CGFloat(count), 12) / 12
        let color = UIColor(red: 0.98, green: 0.55 - 0.35 * intensity, blue: 0.35 - 0.1 * intensity, alpha: 0.95)
        return circle(text: "\(count)\(suffix)", diameter: diameter, color: color)
    }

    static func girlCluster(count: Int) -> UIImage {
        circle(text: "\(count)人", diameter: 46, color: UIColor.systemPurple.withAlphaComponent(0.9))
    }

    private static func circle(text: String, diameter: CGFloat, color: UIColor) -> UIImage {
        let size = CGSize(width: diameter, height: diameter)
        return UIGraphicsImageRenderer(size: size).image { _ in
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: 1.5, dy: 1.5)
            color.setFill()
            let path = UIBezierPath(ovalIn: rect)
            path.fill()
            UIColor.white.setStroke()
            path.lineWidth = 2.5
            path.stroke()

            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: max(12, diameter * 0.36), weight: .bold),
                .foregroundColor: UIColor.white
            ]
            let s = (text as NSString).size(withAttributes: attrs)
            (text as NSString).draw(at: CGPoint(x: (size.width - s.width) / 2, y: (size.height - s.height) / 2), withAttributes: attrs)
        }
    }
}

// MARK: - Map view

struct ClusterMapView: UIViewRepresentable {
    var girls: [MapGirlItem]
    var places: [MapPlaceItem]
    /// 每次加 1 就执行一次「显示全部」/「定位到我」
    var fitRequest: Int = 0
    var locateRequest: Int = 0
    var onSelect: (MapSelection) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.showsUserLocation = true
        map.showsCompass = true
        map.register(GirlAnnotationView.self, forAnnotationViewWithReuseIdentifier: GirlAnnotationView.reuseID)
        map.register(PlaceAnnotationView.self, forAnnotationViewWithReuseIdentifier: PlaceAnnotationView.reuseID)
        map.register(CountClusterView.self, forAnnotationViewWithReuseIdentifier: CountClusterView.reuseID)
        map.setRegion(MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 35, longitude: 105),
                                         span: MKCoordinateSpan(latitudeDelta: 30, longitudeDelta: 30)), animated: false)
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.sync(map)
        context.coordinator.handleRequests(map)
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var parent: ClusterMapView
        private var signature = ""
        private var didFit = false
        private var lastFit = 0
        private var lastLocate = 0

        func handleRequests(_ map: MKMapView) {
            if parent.fitRequest != lastFit {
                lastFit = parent.fitRequest
                let all = map.annotations.filter { !($0 is MKUserLocation) }
                Coordinator.fit(map, to: all, animated: true)
            }
            if parent.locateRequest != lastLocate {
                lastLocate = parent.locateRequest
                if let location = map.userLocation.location {
                    let region = MKCoordinateRegion(center: location.coordinate, latitudinalMeters: 4000, longitudinalMeters: 4000)
                    map.setRegion(map.regionThatFits(region), animated: true)
                } else {
                    LocationPermission.requestIfNeeded()
                }
            }
        }

        init(parent: ClusterMapView) {
            self.parent = parent
        }

        func sync(_ map: MKMapView) {
            let girlSig = parent.girls.map { "\($0.id)|\($0.coordinate.latitude)|\($0.coordinate.longitude)|\($0.color.hashValue)|\($0.avatarID ?? "")|\($0.name)" }
            let placeSig = parent.places.map { "\($0.id)|\($0.coordinate.latitude)|\($0.coordinate.longitude)|\($0.count)" }
            let sig = (girlSig + ["#"] + placeSig).joined(separator: ";")
            guard sig != signature else { return }
            signature = sig

            let old = map.annotations.filter { !($0 is MKUserLocation) }
            map.removeAnnotations(old)
            let new: [MKAnnotation] = parent.girls.map { GirlAnnotation($0) } + parent.places.map { PlaceAnnotation($0) }
            map.addAnnotations(new)

            if !didFit, !new.isEmpty {
                didFit = true
                DispatchQueue.main.async {
                    Coordinator.fit(map, to: new, animated: false)
                }
            }
        }

        /// 让所有标注都可见，并避开顶部筛选栏和底部标签栏
        static func fit(_ map: MKMapView, to annotations: [MKAnnotation], animated: Bool) {
            guard let first = annotations.first else { return }
            var rect = MKMapRect.null
            for a in annotations {
                let p = MKMapPoint(a.coordinate)
                rect = rect.union(MKMapRect(x: p.x, y: p.y, width: 1, height: 1))
            }
            let minSide = 3000 * MKMapPointsPerMeterAtLatitude(first.coordinate.latitude)
            if rect.size.width < minSide || rect.size.height < minSide {
                rect = rect.insetBy(dx: -(max(minSide - rect.size.width, 0) / 2),
                                    dy: -(max(minSide - rect.size.height, 0) / 2))
            }
            map.setVisibleMapRect(rect, edgePadding: UIEdgeInsets(top: 60, left: 50, bottom: 150, right: 50), animated: animated)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation is MKUserLocation { return nil }
            if let cluster = annotation as? MKClusterAnnotation {
                return mapView.dequeueReusableAnnotationView(withIdentifier: CountClusterView.reuseID, for: cluster)
            }
            if annotation is GirlAnnotation {
                return mapView.dequeueReusableAnnotationView(withIdentifier: GirlAnnotationView.reuseID, for: annotation)
            }
            if annotation is PlaceAnnotation {
                return mapView.dequeueReusableAnnotationView(withIdentifier: PlaceAnnotationView.reuseID, for: annotation)
            }
            return nil
        }

        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            guard let annotation = view.annotation else { return }
            mapView.deselectAnnotation(annotation, animated: false)

            if let cluster = annotation as? MKClusterAnnotation {
                let members = cluster.memberAnnotations
                if spread(of: members) < 30 {
                    // 都在同一个点上，放大也分不开，直接列出来
                    let girls = members.compactMap { ($0 as? GirlAnnotation)?.item.id }
                    let places = members.compactMap { ($0 as? PlaceAnnotation)?.item.id }
                    parent.onSelect(.group(girls: girls, places: places))
                } else {
                    Coordinator.fit(mapView, to: members, animated: true)
                }
                return
            }
            if let g = annotation as? GirlAnnotation {
                parent.onSelect(.girl(g.item.id))
            } else if let p = annotation as? PlaceAnnotation {
                parent.onSelect(.place(p.item.id))
            }
        }

        /// 成员之间的最大距离（米）
        private func spread(of members: [MKAnnotation]) -> CLLocationDistance {
            guard let first = members.first else { return 0 }
            return members.map { $0.coordinate.distance(to: first.coordinate) }.max() ?? 0
        }
    }
}
