import UIKit
import MapKit

// MARK: - Annotations

final class PersonAnnotation: NSObject, MKAnnotation {
    let coordinate: CLLocationCoordinate2D
    var item: MapPerson
    var title: String? { item.name }

    init(_ item: MapPerson) {
        self.item = item
        self.coordinate = item.coordinate
    }
}

final class SpotAnnotation: NSObject, MKAnnotation {
    let coordinate: CLLocationCoordinate2D
    var item: MapSpot
    var title: String? { item.name }

    init(_ item: MapSpot) {
        self.item = item
        self.coordinate = item.coordinate
    }
}

/// 长按放下的待新建地点
final class DraftAnnotation: NSObject, MKAnnotation {
    let coordinate: CLLocationCoordinate2D
    var title: String? { "新地点" }

    init(_ coordinate: CLLocationCoordinate2D) {
        self.coordinate = coordinate
    }
}

// MARK: - Annotation views

/// 所有自绘标记的基类：深浅色切换时重画，选中时轻轻弹一下
class MarkerView: MKAnnotationView {
    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        collisionMode = .circle
        displayPriority = .required
        canShowCallout = false
        isAccessibilityElement = true
        accessibilityTraits = .button
        registerForTraitChanges([UITraitUserInterfaceStyle.self], action: #selector(styleDidChange))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func styleDidChange() {
        configure()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        transform = .identity
    }

    override func prepareForDisplay() {
        super.prepareForDisplay()
        configure()
    }

    /// 子类在这里画图
    func configure() {}

    override func setSelected(_ selected: Bool, animated: Bool) {
        let changed = selected != isSelected
        super.setSelected(selected, animated: animated)
        guard changed else { return }
        configure()
        if selected { pop() }
    }

    func pop() {
        transform = CGAffineTransform(scaleX: 0.84, y: 0.84)
        UIView.animate(withDuration: 0.5, delay: 0, usingSpringWithDamping: 0.5, initialSpringVelocity: 0.8,
                       options: [.allowUserInteraction, .beginFromCurrentState]) {
            self.transform = .identity
        }
    }

    /// 数字变化时跳一下（回放时用）
    func pulse() {
        UIView.animate(withDuration: 0.12, delay: 0, options: [.allowUserInteraction, .beginFromCurrentState]) {
            self.transform = CGAffineTransform(scaleX: 1.22, y: 1.22)
        } completion: { _ in
            UIView.animate(withDuration: 0.45, delay: 0, usingSpringWithDamping: 0.5, initialSpringVelocity: 0.6,
                           options: [.allowUserInteraction, .beginFromCurrentState]) {
                self.transform = .identity
            }
        }
    }
}

final class PersonPinView: MarkerView {
    static let reuseID = "person"

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        clusteringIdentifier = "person"
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func prepareForDisplay() {
        clusteringIdentifier = "person"
        super.prepareForDisplay()
    }

    override func configure() {
        guard let a = annotation as? PersonAnnotation else { return }
        let marker = MarkerRenderer.person(a.item, selected: isSelected, traits: traitCollection)
        image = marker.image
        centerOffset = marker.offset
        accessibilityLabel = a.item.name
        accessibilityIdentifier = "pin-\(a.item.name)"
    }
}

final class SpotPinView: MarkerView {
    static let reuseID = "spot"

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        clusteringIdentifier = "spot"
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func prepareForDisplay() {
        clusteringIdentifier = "spot"
        super.prepareForDisplay()
    }

    override func configure() {
        guard let a = annotation as? SpotAnnotation else { return }
        let marker = MarkerRenderer.spot(a.item, selected: isSelected, traits: traitCollection)
        image = marker.image
        centerOffset = marker.offset
        accessibilityLabel = "\(a.item.name)，\(a.item.count) 次"
        accessibilityIdentifier = "spot-\(a.item.name)"
    }
}

final class ClusterMarkerView: MarkerView {
    static let reuseID = "cluster"

    override func configure() {
        guard let cluster = annotation as? MKClusterAnnotation else { return }
        let members = cluster.memberAnnotations
        let people = members.compactMap { ($0 as? PersonAnnotation)?.item }
        if !people.isEmpty {
            let marker = MarkerRenderer.personCluster(people, traits: traitCollection)
            image = marker.image
            centerOffset = marker.offset
            accessibilityLabel = "\(people.count) 人"
            accessibilityIdentifier = "cluster-people"
        } else {
            let spots = members.compactMap { ($0 as? SpotAnnotation)?.item }
            let marker = MarkerRenderer.spotCluster(spots, traits: traitCollection)
            image = marker.image
            centerOffset = marker.offset
            accessibilityLabel = "\(spots.count) 个地点"
            accessibilityIdentifier = "cluster-spots"
        }
    }
}

// MARK: - 绘制

struct RenderedMarker {
    let image: UIImage
    /// 让尖角正好落在坐标上
    let offset: CGPoint
}

enum MarkerRenderer {
    /// 标记的底色：浅色模式白，深色模式深灰
    static let surface = UIColor { trait in
        trait.userInterfaceStyle == .dark ? UIColor(white: 0.17, alpha: 1) : .white
    }

    private static let shadowColor = UIColor.black.withAlphaComponent(0.26).cgColor
    private static let pad: CGFloat = 8

    static func person(_ item: MapPerson, selected: Bool, traits: UITraitCollection) -> RenderedMarker {
        var result: RenderedMarker?
        traits.performAsCurrent {
            result = drawPerson(item, selected: selected)
        }
        return result ?? RenderedMarker(image: UIImage(), offset: .zero)
    }

    static func spot(_ item: MapSpot, selected: Bool, traits: UITraitCollection) -> RenderedMarker {
        var result: RenderedMarker?
        traits.performAsCurrent {
            result = drawSpot(item, selected: selected)
        }
        return result ?? RenderedMarker(image: UIImage(), offset: .zero)
    }

    static func personCluster(_ members: [MapPerson], traits: UITraitCollection) -> RenderedMarker {
        var result: RenderedMarker?
        traits.performAsCurrent {
            result = drawPersonCluster(members)
        }
        return result ?? RenderedMarker(image: UIImage(), offset: .zero)
    }

    static func spotCluster(_ members: [MapSpot], traits: UITraitCollection) -> RenderedMarker {
        var result: RenderedMarker?
        traits.performAsCurrent {
            result = drawSpotCluster(members)
        }
        return result ?? RenderedMarker(image: UIImage(), offset: .zero)
    }

    // MARK: 人：圆形头像 + 压在下沿的名牌 + 小尖角

    private static func drawPerson(_ item: MapPerson, selected: Bool) -> RenderedMarker {
        let d: CGFloat = selected ? 52 : 44
        let ring: CGFloat = selected ? 3 : 2.5
        let font = UIFont.systemFont(ofSize: 11, weight: .semibold)
        let name = item.name as NSString
        let nameWidth = ceil(name.size(withAttributes: [.font: font]).width)
        let dot: CGFloat = 6
        let tagH: CGFloat = 18
        let tagW = min(max(nameWidth + dot + 4 + 16, 44), 112)
        let overlap: CGFloat = 7
        let tailH: CGFloat = 6

        let width = max(d, tagW) + pad * 2
        let height = pad + d - overlap + tagH + tailH + pad
        let circle = CGRect(x: (width - d) / 2, y: pad, width: d, height: d)
        let tag = CGRect(x: (width - tagW) / 2, y: circle.maxY - overlap, width: tagW, height: tagH)
        let tip = CGPoint(x: width / 2, y: tag.maxY + tailH)

        let fill = selected ? Palette.wineUI : surface
        let textColor = selected ? UIColor.white : UIColor.label

        let image = UIGraphicsImageRenderer(size: CGSize(width: width, height: height)).image { ctx in
            let cg = ctx.cgContext
            withShadow(cg) {
                fill.setFill()
                UIBezierPath(ovalIn: circle).fill()
                UIBezierPath(roundedRect: tag, cornerRadius: tagH / 2).fill()
                tail(from: tag.maxY - 1, tip: tip).fill()
            }

            let inner = circle.insetBy(dx: ring, dy: ring)
            cg.saveGState()
            UIBezierPath(ovalIn: inner).addClip()
            drawAvatar(item.avatarID, name: item.name, in: inner)
            cg.restoreGState()

            // 名牌：状态色小圆点 + 名字
            let textWidth = min(nameWidth, tagW - 16 - dot - 4)
            let startX = tag.midX - (dot + 4 + textWidth) / 2
            (selected ? UIColor.white : item.tone).setFill()
            UIBezierPath(ovalIn: CGRect(x: startX, y: tag.midY - dot / 2, width: dot, height: dot)).fill()
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineBreakMode = .byTruncatingTail
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: textColor, .paragraphStyle: paragraph]
            let lineHeight = ceil(font.lineHeight)
            name.draw(in: CGRect(x: startX + dot + 4, y: tag.midY - lineHeight / 2, width: textWidth + 1, height: lineHeight),
                      withAttributes: attrs)
        }
        return RenderedMarker(image: image, offset: CGPoint(x: 0, y: height / 2 - tip.y))
    }

    // MARK: 地点：胶囊 = 类型图标 + 次数

    private static func drawSpot(_ item: MapSpot, selected: Bool) -> RenderedMarker {
        let h: CGFloat = selected ? 32 : 28
        let glyphColor = selected ? UIColor.white : Palette.wineUI
        let glyph = symbol(item.type.mapSymbol, size: selected ? 13 : 12, color: glyphColor)
        let font = serif(selected ? 16 : 15, weight: .semibold)
        let text = "\(item.count)" as NSString
        let textSize = text.size(withAttributes: [.font: font])
        let glyphW = glyph?.size.width ?? 0
        let w = max(10 + glyphW + 5 + ceil(textSize.width) + 11, h + 6)
        let size = CGSize(width: w + pad * 2, height: h + pad * 2)
        let pill = CGRect(x: pad, y: pad, width: w, height: h)

        let image = UIGraphicsImageRenderer(size: size).image { ctx in
            withShadow(ctx.cgContext) {
                (selected ? Palette.wineUI : surface).setFill()
                UIBezierPath(roundedRect: pill, cornerRadius: h / 2).fill()
            }
            if !selected {
                UIColor.separator.withAlphaComponent(0.35).setStroke()
                let border = UIBezierPath(roundedRect: pill.insetBy(dx: 0.25, dy: 0.25), cornerRadius: h / 2)
                border.lineWidth = 0.5
                border.stroke()
            }
            glyph?.draw(at: CGPoint(x: pill.minX + 10, y: pill.midY - (glyph?.size.height ?? 0) / 2))
            text.draw(at: CGPoint(x: pill.minX + 10 + glyphW + 5, y: pill.midY - textSize.height / 2),
                      withAttributes: [.font: font, .foregroundColor: selected ? UIColor.white : UIColor.label])
        }
        return RenderedMarker(image: image, offset: .zero)
    }

    // MARK: 人的聚合：叠在一起的头像 + 人数名牌

    private static func drawPersonCluster(_ members: [MapPerson]) -> RenderedMarker {
        let shown = Array(members.prefix(3))
        let d: CGFloat = 38
        let ring: CGFloat = 2.5
        let step: CGFloat = 23
        let stackW = d + step * CGFloat(max(shown.count - 1, 0))
        let font = UIFont.systemFont(ofSize: 11, weight: .semibold)
        let label = "\(members.count) 人" as NSString
        let labelW = ceil(label.size(withAttributes: [.font: font]).width)
        let tagH: CGFloat = 18
        let tagW = max(labelW + 18, 40)
        let overlap: CGFloat = 6
        let tailH: CGFloat = 6

        let width = max(stackW, tagW) + pad * 2
        let height = pad + d - overlap + tagH + tailH + pad
        let startX = (width - stackW) / 2
        let tag = CGRect(x: (width - tagW) / 2, y: pad + d - overlap, width: tagW, height: tagH)
        let tip = CGPoint(x: width / 2, y: tag.maxY + tailH)
        let circles = shown.indices.map { CGRect(x: startX + step * CGFloat($0), y: pad, width: d, height: d) }

        let image = UIGraphicsImageRenderer(size: CGSize(width: width, height: height)).image { ctx in
            let cg = ctx.cgContext
            withShadow(cg) {
                surface.setFill()
                for c in circles { UIBezierPath(ovalIn: c).fill() }
                UIBezierPath(roundedRect: tag, cornerRadius: tagH / 2).fill()
                tail(from: tag.maxY - 1, tip: tip).fill()
            }
            // 从右往左画，左边的压在上面
            for (index, member) in shown.enumerated().reversed() {
                let c = circles[index]
                surface.setFill()
                UIBezierPath(ovalIn: c).fill()
                let inner = c.insetBy(dx: ring, dy: ring)
                cg.saveGState()
                UIBezierPath(ovalIn: inner).addClip()
                drawAvatar(member.avatarID, name: member.name, in: inner)
                cg.restoreGState()
            }
            surface.setFill()
            UIBezierPath(roundedRect: tag, cornerRadius: tagH / 2).fill()
            let lineHeight = ceil(font.lineHeight)
            label.draw(at: CGPoint(x: tag.midX - labelW / 2, y: tag.midY - lineHeight / 2),
                       withAttributes: [.font: font, .foregroundColor: UIColor.label])
        }
        return RenderedMarker(image: image, offset: CGPoint(x: 0, y: height / 2 - tip.y))
    }

    // MARK: 地点的聚合：叠起来的胶囊 = 总次数 · 几处

    private static func drawSpotCluster(_ members: [MapSpot]) -> RenderedMarker {
        let h: CGFloat = 30
        let glyph = symbol("mappin.and.ellipse", size: 12, color: Palette.wineUI)
        let numberFont = serif(15, weight: .semibold)
        let smallFont = UIFont.systemFont(ofSize: 11, weight: .medium)
        let total = "\(members.reduce(0) { $0 + $1.count })" as NSString
        let places = " · \(members.count) 处" as NSString
        let totalSize = total.size(withAttributes: [.font: numberFont])
        let placesSize = places.size(withAttributes: [.font: smallFont])
        let glyphW = glyph?.size.width ?? 0
        let w = 10 + glyphW + 5 + ceil(totalSize.width) + ceil(placesSize.width) + 12
        let stackOffset: CGFloat = 4
        let size = CGSize(width: w + pad * 2, height: h + stackOffset + pad * 2)
        let pill = CGRect(x: pad, y: pad, width: w, height: h)
        let back = pill.insetBy(dx: 7, dy: 0).offsetBy(dx: 0, dy: stackOffset)

        let image = UIGraphicsImageRenderer(size: size).image { ctx in
            withShadow(ctx.cgContext) {
                surface.setFill()
                UIBezierPath(roundedRect: back, cornerRadius: h / 2).fill()
            }
            UIColor.separator.withAlphaComponent(0.3).setFill()
            UIBezierPath(roundedRect: back, cornerRadius: h / 2).fill()
            withShadow(ctx.cgContext) {
                surface.setFill()
                UIBezierPath(roundedRect: pill, cornerRadius: h / 2).fill()
            }
            UIColor.separator.withAlphaComponent(0.35).setStroke()
            let border = UIBezierPath(roundedRect: pill.insetBy(dx: 0.25, dy: 0.25), cornerRadius: h / 2)
            border.lineWidth = 0.5
            border.stroke()

            var x = pill.minX + 10
            glyph?.draw(at: CGPoint(x: x, y: pill.midY - (glyph?.size.height ?? 0) / 2))
            x += glyphW + 5
            total.draw(at: CGPoint(x: x, y: pill.midY - totalSize.height / 2),
                       withAttributes: [.font: numberFont, .foregroundColor: UIColor.label])
            x += ceil(totalSize.width)
            places.draw(at: CGPoint(x: x, y: pill.midY - placesSize.height / 2 + 0.5),
                        withAttributes: [.font: smallFont, .foregroundColor: UIColor.secondaryLabel])
        }
        return RenderedMarker(image: image, offset: CGPoint(x: 0, y: stackOffset / 2))
    }

    // MARK: 小工具

    private static func withShadow(_ cg: CGContext, _ draw: () -> Void) {
        cg.saveGState()
        cg.setShadow(offset: CGSize(width: 0, height: 2), blur: 6, color: shadowColor)
        cg.beginTransparencyLayer(auxiliaryInfo: nil)
        draw()
        cg.endTransparencyLayer()
        cg.restoreGState()
    }

    /// 顺时针画的小三角，和名牌连成一体
    private static func tail(from top: CGFloat, tip: CGPoint) -> UIBezierPath {
        let path = UIBezierPath()
        path.move(to: CGPoint(x: tip.x + 5.5, y: top))
        path.addLine(to: tip)
        path.addLine(to: CGPoint(x: tip.x - 5.5, y: top))
        path.close()
        return path
    }

    static func drawAvatar(_ avatarID: String?, name: String, in rect: CGRect) {
        if let avatarID, let photo = PhotoStore.shared.thumbnail(avatarID, size: 160) {
            let scale = max(rect.width / photo.size.width, rect.height / photo.size.height)
            let w = photo.size.width * scale
            let h = photo.size.height * scale
            photo.draw(in: CGRect(x: rect.midX - w / 2, y: rect.midY - h / 2, width: w, height: h))
            return
        }
        let (top, bottom) = Palette.avatarUIColors(for: name)
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                     colors: [top.cgColor, bottom.cgColor] as CFArray,
                                     locations: [0, 1]) {
            UIGraphicsGetCurrentContext()?.drawLinearGradient(
                gradient, start: CGPoint(x: rect.minX, y: rect.minY),
                end: CGPoint(x: rect.maxX, y: rect.maxY), options: [])
        }
        let initial = String(name.prefix(1)) as NSString
        let attrs: [NSAttributedString.Key: Any] = [
            .font: serif(rect.width * 0.44, weight: .medium),
            .foregroundColor: UIColor.white.withAlphaComponent(0.95)
        ]
        let s = initial.size(withAttributes: attrs)
        initial.draw(at: CGPoint(x: rect.midX - s.width / 2, y: rect.midY - s.height / 2), withAttributes: attrs)
    }

    static func serif(_ size: CGFloat, weight: UIFont.Weight) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        guard let descriptor = base.fontDescriptor.withDesign(.serif) else { return base }
        return UIFont(descriptor: descriptor, size: size)
    }

    static func symbol(_ name: String, size: CGFloat, color: UIColor) -> UIImage? {
        let config = UIImage.SymbolConfiguration(pointSize: size, weight: .semibold)
        let image = UIImage(systemName: name, withConfiguration: config) ?? UIImage(systemName: "mappin", withConfiguration: config)
        return image?.withTintColor(color, renderingMode: .alwaysOriginal)
    }
}

extension PlaceType {
    /// 地图标记上用的实心图标
    var mapSymbol: String {
        switch self {
        case .hotel: return "bed.double.fill"
        case .homestay: return "building.2.fill"
        case .herHome: return "house.fill"
        case .myHome: return "house.lodge.fill"
        case .car: return "car.fill"
        case .outdoor: return "tree.fill"
        case .other: return "mappin"
        }
    }
}
