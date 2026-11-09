import UIKit
import MapKit

// MARK: - 热力图

/// 覆盖全世界的一层，按约会次数画出发光的光斑；越常去越亮
final class HeatOverlay: NSObject, MKOverlay {
    let boundingMapRect: MKMapRect = .world
    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: 0, longitude: 0) }

    struct Sample {
        let point: MKMapPoint
        let weight: CGFloat
    }

    private let lock = NSLock()
    private var storage: [Sample] = []

    /// 绘制在后台线程进行，所以读写都加锁
    var samples: [Sample] {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storage
        }
        set {
            lock.lock()
            storage = newValue
            lock.unlock()
        }
    }

    init(points: [HeatPoint]) {
        super.init()
        update(points)
    }

    func update(_ points: [HeatPoint]) {
        samples = points.map {
            Sample(point: MKMapPoint(CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)),
                   weight: CGFloat(min(max($0.weight, 0), 1)))
        }
    }
}

final class HeatRenderer: MKOverlayRenderer {
    private let heat: HeatOverlay
    private let glow: CGGradient?
    private let core: CGGradient?

    init(heat: HeatOverlay) {
        self.heat = heat
        let space = CGColorSpaceCreateDeviceRGB()
        let wine = UIColor(red: 0.62, green: 0.18, blue: 0.29, alpha: 1)
        let rose = UIColor(red: 0.86, green: 0.40, blue: 0.43, alpha: 1)
        let gold = UIColor(red: 1.0, green: 0.86, blue: 0.62, alpha: 1)
        glow = CGGradient(colorsSpace: space,
                          colors: [rose.withAlphaComponent(0.62).cgColor,
                                   wine.withAlphaComponent(0.34).cgColor,
                                   wine.withAlphaComponent(0).cgColor] as CFArray,
                          locations: [0, 0.42, 1])
        core = CGGradient(colorsSpace: space,
                          colors: [gold.withAlphaComponent(0.95).cgColor,
                                   gold.withAlphaComponent(0.35).cgColor,
                                   gold.withAlphaComponent(0).cgColor] as CFArray,
                          locations: [0, 0.4, 1])
        super.init(overlay: heat)
    }

    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        guard let glow, let core else { return }
        // 光斑大小按屏幕上的点数算，缩小地图时会自然连成一片
        let maxRadius = 76 / zoomScale
        let area = mapRect.insetBy(dx: -maxRadius, dy: -maxRadius)
        let visible = heat.samples.filter { area.contains($0.point) }
        guard !visible.isEmpty else { return }

        context.saveGState()
        for s in visible {
            let center = point(for: s.point)
            let radius = (36 + 40 * s.weight) / zoomScale
            context.drawRadialGradient(glow, startCenter: center, startRadius: 0,
                                       endCenter: center, endRadius: radius, options: [])
        }
        for s in visible where s.weight > 0.2 {
            let center = point(for: s.point)
            let radius = (9 + 20 * s.weight) / zoomScale
            context.setAlpha(0.3 + 0.7 * s.weight)
            context.drawRadialGradient(core, startCenter: center, startRadius: 0,
                                       endCenter: center, endRadius: radius, options: [])
        }
        context.restoreGState()
    }
}

// MARK: - 关系弧线

/// 选中一个人时，从她连到一起去过的地点；选中地点时，连到在那里见过的人
final class ArcPolyline: MKPolyline {}

enum ArcBuilder {
    static func arc(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) -> ArcPolyline {
        let p0 = MKMapPoint(a)
        let p2 = MKMapPoint(b)
        let dx = p2.x - p0.x
        let dy = p2.y - p0.y
        let length = (dx * dx + dy * dy).squareRoot()
        // 垂直方向偏一点，统一往北（地图上方）拱起
        var nx = -dy / max(length, 1)
        var ny = dx / max(length, 1)
        if ny > 0 {
            nx = -nx
            ny = -ny
        }
        let bend = length * 0.2
        let control = MKMapPoint(x: (p0.x + p2.x) / 2 + nx * bend, y: (p0.y + p2.y) / 2 + ny * bend)
        let steps = 36
        var points: [MKMapPoint] = []
        points.reserveCapacity(steps + 1)
        for i in 0...steps {
            let t = Double(i) / Double(steps)
            let u = 1 - t
            points.append(MKMapPoint(x: u * u * p0.x + 2 * u * t * control.x + t * t * p2.x,
                                     y: u * u * p0.y + 2 * u * t * control.y + t * t * p2.y))
        }
        return ArcPolyline(points: points, count: points.count)
    }

    static func renderer(for arc: ArcPolyline) -> MKPolylineRenderer {
        let r = MKPolylineRenderer(polyline: arc)
        r.strokeColor = Palette.wineUI.withAlphaComponent(0.85)
        r.lineWidth = 2.5
        r.lineCap = .round
        r.lineJoin = .round
        r.lineDashPattern = [1, 6]
        return r
    }
}
