import SwiftUI
import SwiftData

/// 邮票的齿孔边
struct StampShape: Shape {
    var hole: CGFloat = 4.5
    var spacing: CGFloat = 13

    func path(in rect: CGRect) -> Path {
        var path = Path(rect)
        func holes(from start: CGPoint, to end: CGPoint) {
            let length = hypot(end.x - start.x, end.y - start.y)
            let count = max(Int(length / spacing), 1)
            for i in 0...count {
                let t = CGFloat(i) / CGFloat(count)
                let center = CGPoint(x: start.x + (end.x - start.x) * t, y: start.y + (end.y - start.y) * t)
                path.addEllipse(in: CGRect(x: center.x - hole, y: center.y - hole, width: hole * 2, height: hole * 2))
            }
        }
        holes(from: CGPoint(x: rect.minX, y: rect.minY), to: CGPoint(x: rect.maxX, y: rect.minY))
        holes(from: CGPoint(x: rect.minX, y: rect.maxY), to: CGPoint(x: rect.maxX, y: rect.maxY))
        holes(from: CGPoint(x: rect.minX, y: rect.minY + spacing), to: CGPoint(x: rect.minX, y: rect.maxY - spacing))
        holes(from: CGPoint(x: rect.maxX, y: rect.minY + spacing), to: CGPoint(x: rect.maxX, y: rect.maxY - spacing))
        return path
    }
}

struct CityStamp: Identifiable {
    let city: String
    let count: Int
    let first: Date
    let places: Int
    let people: Int
    var id: String { city }
}

/// 城市印章：每座去过的城市一枚邮票
struct CityStampsView: View {
    @Query(sort: \Encounter.date) private var encounters: [Encounter]

    private static let paper = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.17, green: 0.16, blue: 0.15, alpha: 1)
            : UIColor(red: 0.99, green: 0.97, blue: 0.93, alpha: 1)
    })

    private var stamps: [CityStamp] {
        var byCity: [String: [Encounter]] = [:]
        for e in encounters {
            guard let city = e.place?.city.trimmed, !city.isEmpty else { continue }
            byCity[city, default: []].append(e)
        }
        return byCity.map { city, list in
            CityStamp(city: city, count: list.count, first: list.map(\.date).min() ?? Date(),
                      places: Set(list.compactMap { $0.place?.id }).count,
                      people: Set(list.flatMap { $0.girls.map(\.id) }).count)
        }
        .sorted { $0.first < $1.first }
    }

    var body: some View {
        let list = stamps
        ScrollView {
            VStack(spacing: 20) {
                VStack(spacing: 6) {
                    Text("\(list.count)")
                        .font(Typo.display(52, weight: .medium))
                    Text(list.isEmpty ? "还没有收集到城市" : "座城市 · \(list.reduce(0) { $0 + $1.count }) 次相遇")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 8)

                if list.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "seal")
                            .font(.system(size: 36, weight: .light))
                            .foregroundStyle(Palette.gold)
                        Text("给地点填上城市，每到一座新城市就会多一枚印章")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(40)
                } else {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 18), GridItem(.flexible(), spacing: 18)], spacing: 22) {
                        ForEach(Array(list.enumerated()), id: \.element.id) { index, stamp in
                            StampCard(stamp: stamp, index: index, paper: Self.paper)
                                .rotationEffect(.degrees(index % 3 == 0 ? -2.2 : (index % 3 == 1 ? 1.6 : -0.8)))
                        }
                        NextStampCard(paper: Self.paper)
                            .rotationEffect(.degrees(list.count % 2 == 0 ? 1.4 : -1.4))
                    }
                    .padding(.horizontal, 6)
                }
            }
            .padding(16)
        }
        .background(Palette.canvas)
        .navigationTitle("城市印章")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct StampCard: View {
    let stamp: CityStamp
    let index: Int
    let paper: Color

    var body: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top) {
                    Text("No.\(String(format: "%02d", index + 1))")
                        .font(.system(size: 10, weight: .semibold, design: .serif))
                        .foregroundStyle(Color.accentColor.opacity(0.8))
                    Spacer()
                    Text("\(stamp.count)次")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Text(stamp.city)
                    .font(Typo.display(26, weight: .semibold))
                    .foregroundStyle(Color.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text("\(stamp.places) 处地点 · \(stamp.people) 位")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(stamp.first.formatted(.dateTime.year().month(.twoDigits).day(.twoDigits)))
                    .font(.system(size: 10, design: .serif))
                    .foregroundStyle(.tertiary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
            .overlay(
                Rectangle()
                    .stroke(Color.accentColor.opacity(0.35), lineWidth: 1)
                    .padding(6)
            )

            // 邮戳
            Postmark(date: stamp.first)
                .frame(width: 66, height: 66)
                .rotationEffect(.degrees(-18))
                .offset(x: 34, y: 2)
                .opacity(0.55)
        }
        .padding(10)
        .background(paper)
        .clipShape(StampShape(), style: FillStyle(eoFill: true))
        .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
    }
}

private struct Postmark: View {
    let date: Date

    var body: some View {
        ZStack {
            Circle().stroke(Color.accentColor, lineWidth: 1.2)
            Circle().inset(by: 5).stroke(Color.accentColor, lineWidth: 0.6)
            VStack(spacing: 1) {
                Text(date.formatted(.dateTime.year()))
                    .font(.system(size: 9, weight: .bold, design: .serif))
                Text(date.formatted(.dateTime.month(.twoDigits).day(.twoDigits)))
                    .font(.system(size: 8, weight: .medium, design: .serif))
            }
            .foregroundStyle(Color.accentColor)
            VStack(spacing: 3) {
                ForEach(0..<3, id: \.self) { _ in
                    Capsule().fill(Color.accentColor).frame(width: 44, height: 0.8)
                }
            }
            .offset(x: 38)
        }
    }
}

private struct NextStampCard: View {
    let paper: Color

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "plus")
                .font(.system(size: 22, weight: .light))
            Text("下一站")
                .font(Typo.display(17))
            Text("新的城市，新的印章")
                .font(.caption2)
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, minHeight: 150)
        .padding(10)
        .background(
            Rectangle()
                .strokeBorder(Color.secondary.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                .padding(6)
        )
        .background(paper.opacity(0.5))
        .clipShape(StampShape(), style: FillStyle(eoFill: true))
    }
}
