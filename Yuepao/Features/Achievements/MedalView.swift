import SwiftUI

/// 金属奖章：铜 / 银 / 金 / 黑金。没解锁时是压印的灰色，外圈显示进度。
struct MedalView: View {
    let symbol: String
    let tier: AchievementTier
    var unlocked: Bool
    var secret = false
    var progress: Double = 0
    var size: CGFloat = 64
    var shine = false

    @State private var sweep: CGFloat = -1.2

    private var palette: (light: Color, mid: Color, dark: Color, glyph: Color, rim: [Color]) {
        switch tier {
        case .bronze:
            return (Color(red: 0.91, green: 0.70, blue: 0.52), Color(red: 0.72, green: 0.46, blue: 0.28),
                    Color(red: 0.47, green: 0.28, blue: 0.15), Color(red: 0.36, green: 0.20, blue: 0.10),
                    [Color(red: 0.98, green: 0.82, blue: 0.66), Color(red: 0.55, green: 0.33, blue: 0.18),
                     Color(red: 0.93, green: 0.73, blue: 0.55), Color(red: 0.50, green: 0.30, blue: 0.16),
                     Color(red: 0.98, green: 0.82, blue: 0.66)])
        case .silver:
            return (Color(red: 0.96, green: 0.97, blue: 0.98), Color(red: 0.78, green: 0.80, blue: 0.84),
                    Color(red: 0.55, green: 0.58, blue: 0.63), Color(red: 0.32, green: 0.35, blue: 0.40),
                    [Color.white, Color(red: 0.60, green: 0.63, blue: 0.68), Color(red: 0.92, green: 0.93, blue: 0.95),
                     Color(red: 0.56, green: 0.59, blue: 0.64), Color.white])
        case .gold:
            return (Color(red: 0.98, green: 0.90, blue: 0.66), Color(red: 0.85, green: 0.69, blue: 0.38),
                    Color(red: 0.60, green: 0.45, blue: 0.20), Color(red: 0.44, green: 0.31, blue: 0.10),
                    [Color(red: 1.0, green: 0.95, blue: 0.78), Color(red: 0.68, green: 0.51, blue: 0.22),
                     Color(red: 0.97, green: 0.86, blue: 0.58), Color(red: 0.62, green: 0.46, blue: 0.20),
                     Color(red: 1.0, green: 0.95, blue: 0.78)])
        case .platinum:
            return (Color(red: 0.30, green: 0.29, blue: 0.33), Color(red: 0.16, green: 0.15, blue: 0.18),
                    Color(red: 0.07, green: 0.07, blue: 0.09), Color(red: 0.93, green: 0.82, blue: 0.56),
                    [Color(red: 0.95, green: 0.85, blue: 0.60), Color(red: 0.45, green: 0.36, blue: 0.20),
                     Color(red: 0.90, green: 0.78, blue: 0.50), Color(red: 0.40, green: 0.32, blue: 0.18),
                     Color(red: 0.95, green: 0.85, blue: 0.60)])
        }
    }

    var body: some View {
        ZStack {
            if unlocked {
                unlockedMedal
            } else {
                lockedMedal
            }
        }
        .frame(width: size, height: size)
        .onAppear {
            guard shine else { return }
            sweep = -1.2
            withAnimation(.easeInOut(duration: 1.4).delay(0.35)) { sweep = 1.2 }
        }
    }

    private var unlockedMedal: some View {
        let p = palette
        return ZStack {
            // 金属面
            Circle()
                .fill(LinearGradient(colors: [p.light, p.mid, p.dark], startPoint: .topLeading, endPoint: .bottomTrailing))
            // 外圈金属光泽
            Circle()
                .strokeBorder(AngularGradient(colors: p.rim, center: .center), lineWidth: size * 0.075)
            // 压印的内圈
            Circle()
                .inset(by: size * 0.15)
                .stroke(Color.black.opacity(0.18), lineWidth: max(1, size * 0.018))
                .offset(y: size * 0.006)
            Circle()
                .inset(by: size * 0.15)
                .stroke(Color.white.opacity(0.35), lineWidth: max(0.5, size * 0.01))
            // 浮雕图形
            Image(systemName: symbol)
                .font(.system(size: size * 0.34, weight: .semibold))
                .foregroundStyle(p.glyph.opacity(0.92))
                .shadow(color: .white.opacity(tier == .platinum ? 0 : 0.45), radius: 0, x: 0, y: size * 0.012)
                .shadow(color: .black.opacity(0.25), radius: size * 0.01, x: 0, y: -size * 0.006)
            // 顶部高光
            Circle()
                .fill(LinearGradient(colors: [.white.opacity(0.42), .white.opacity(0)], startPoint: .top, endPoint: .center))
                .padding(size * 0.04)
                .blendMode(.softLight)
            // 扫光
            if shine {
                LinearGradient(colors: [.clear, .white.opacity(0.55), .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: size * 0.35)
                    .rotationEffect(.degrees(25))
                    .offset(x: sweep * size)
                    .blendMode(.plusLighter)
                    .mask(Circle())
            }
        }
        .compositingGroup()
        .shadow(color: p.dark.opacity(0.35), radius: size * 0.08, y: size * 0.05)
    }

    private var lockedMedal: some View {
        ZStack {
            Circle()
                .fill(Color(uiColor: .tertiarySystemFill))
            Circle()
                .inset(by: size * 0.06)
                .stroke(Color.secondary.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [2.5, 3]))
            if progress > 0 {
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(Palette.gold, style: StrokeStyle(lineWidth: max(2, size * 0.04), lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(max(1, size * 0.02))
            }
            Image(systemName: secret ? "questionmark" : symbol)
                .font(.system(size: size * 0.32, weight: .regular))
                .foregroundStyle(Color.secondary.opacity(0.45))
        }
    }
}
