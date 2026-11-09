import SwiftUI

/// 解锁成就时的庆祝：奖章翻转入场 + 扫光 + 一圈金色微粒
struct CelebrationView: View {
    let result: AchievementResult
    let onDismiss: () -> Void

    @State private var appear = false
    @State private var burst = false

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(Color.black.opacity(0.25))
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }

            VStack(spacing: 16) {
                Text("成就解锁")
                    .eyebrow()
                    .opacity(appear ? 1 : 0)

                ZStack {
                    Circle()
                        .fill(RadialGradient(colors: [Palette.gold.opacity(0.45), .clear],
                                             center: .center, startRadius: 10, endRadius: 140))
                        .frame(width: 280, height: 280)
                        .scaleEffect(appear ? 1 : 0.3)
                        .opacity(appear ? 1 : 0)
                    ForEach(0..<14, id: \.self) { i in
                        Circle()
                            .fill(Palette.gold)
                            .frame(width: i % 3 == 0 ? 5 : 3, height: i % 3 == 0 ? 5 : 3)
                            .offset(y: burst ? -CGFloat(100 + (i % 4) * 14) : -30)
                            .rotationEffect(.degrees(Double(i) / 14 * 360))
                            .opacity(burst ? 0 : 0.9)
                    }
                    MedalView(symbol: result.def.symbol, tier: result.def.tier, unlocked: true, size: 132, shine: appear)
                        .scaleEffect(appear ? 1 : 0.4)
                        .rotation3DEffect(.degrees(appear ? 0 : 160), axis: (x: 0, y: 1, z: 0))
                }
                .frame(height: 200)

                VStack(spacing: 8) {
                    Text(result.def.title)
                        .font(Typo.display(30))
                    Text(result.def.detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    HStack(spacing: 6) {
                        Text(result.def.tier.title)
                        Text("·")
                        Text("+\(result.def.tier.points) 魅力值")
                    }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.gold)
                    .padding(.top, 2)
                }
                .opacity(appear ? 1 : 0)
                .offset(y: appear ? 0 : 12)

                Button {
                    onDismiss()
                } label: {
                    Text("收下")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: 180)
                        .padding(.vertical, 3)
                }
                .buttonStyle(.wine)
                .padding(.top, 8)
                .opacity(appear ? 1 : 0)
                .accessibilityIdentifier("dismissCelebration")
            }
            .padding(.vertical, 28)
            .padding(.horizontal, 24)
            .frame(maxWidth: 340)
            .background(
                RoundedRectangle(cornerRadius: 34, style: .continuous)
                    .fill(.regularMaterial)
                    .shadow(color: .black.opacity(0.2), radius: 30, y: 12)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 34, style: .continuous)
                    .stroke(Palette.gold.opacity(0.35), lineWidth: 0.8)
            )
            .scaleEffect(appear ? 1 : 0.92)
        }
        .onAppear {
            Haptics.success()
            withAnimation(.spring(duration: 0.8, bounce: 0.32)) { appear = true }
            withAnimation(.easeOut(duration: 1.1).delay(0.25)) { burst = true }
        }
    }
}
