import SwiftUI
import MapKit

// MARK: - 顶部：模式切换

struct MapModeSwitcher: View {
    @Binding var mode: MapMode
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 2) {
            ForEach(MapMode.allCases) { m in
                Button {
                    guard mode != m else { return }
                    withAnimation(.spring(response: 0.36, dampingFraction: 0.82)) { mode = m }
                } label: {
                    Text(m.title)
                        .font(.subheadline.weight(mode == m ? .semibold : .regular))
                        .foregroundStyle(mode == m ? Color.primary : Color.secondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background {
                            if mode == m {
                                Capsule()
                                    .fill(Color(uiColor: .tertiarySystemBackground))
                                    .shadow(color: Color.black.opacity(0.1), radius: 4, y: 1)
                                    .matchedGeometryEffect(id: "thumb", in: namespace)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("mapMode-\(m.rawValue)")
                .accessibilityAddTraits(mode == m ? .isSelected : [])
            }
        }
        .padding(4)
        .floatingGlass(Capsule())
        .sensoryFeedback(.selection, trigger: mode)
    }
}

/// 生效中的筛选条件，点一下清除
struct MapFilterToken: View {
    let title: String
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tint)
                Text(title)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.primary)
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .floatingGlass(Capsule(), interactive: true)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("清除筛选：\(title)")
    }
}

/// 右下角竖排的圆角按钮组
struct MapControlStack: View {
    struct Item: Identifiable {
        let symbol: String
        let label: String
        let id: String
        let action: () -> Void
    }

    let items: [Item]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                if index > 0 {
                    Rectangle()
                        .fill(Color.primary.opacity(0.1))
                        .frame(width: 22, height: 0.5)
                }
                Button {
                    Haptics.light()
                    item.action()
                } label: {
                    Image(systemName: item.symbol)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.primary)
                        .frame(width: 46, height: 46)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.label)
                .accessibilityIdentifier(item.id)
            }
        }
        .floatingGlass(RoundedRectangle(cornerRadius: 23, style: .continuous))
    }
}

// MARK: - 底部：统计条

struct MapSummaryStrip: View {
    let stats: MapStats
    let heatLegend: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                HStack(spacing: 0) {
                    cell(stats.people, "人")
                    divider
                    cell(stats.spots, "地点")
                    divider
                    cell(stats.encounters, "次")
                    divider
                    cell(stats.cities, "城市")
                }
                if heatLegend {
                    HStack(spacing: 8) {
                        Text("少").font(.caption2).foregroundStyle(.secondary)
                        Capsule()
                            .fill(LinearGradient(colors: [Color(red: 0.62, green: 0.18, blue: 0.29).opacity(0.35),
                                                          Color(red: 0.86, green: 0.40, blue: 0.43),
                                                          Color(red: 1.0, green: 0.86, blue: 0.62)],
                                                 startPoint: .leading, endPoint: .trailing))
                            .frame(height: 5)
                        Text("多").font(.caption2).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 6)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 10)
            .overlay(alignment: .topTrailing) {
                Image(systemName: "chevron.up")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.tertiary)
                    .padding(9)
            }
            .contentShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .floatingGlass(RoundedRectangle(cornerRadius: 26, style: .continuous), interactive: true)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("mapSummary")
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.1))
            .frame(width: 0.5, height: 26)
    }

    private func cell(_ value: Int, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(Typo.display(22, weight: .medium))
                .statNumber()
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - 底部：卡片

/// 卡片里的一个小指标：衬线数字 + 说明
private struct CardMetric: View {
    let value: String
    let caption: String
    var tint: Color?

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                if let tint {
                    Circle().fill(tint).frame(width: 6, height: 6)
                }
                Text(value)
                    .font(Typo.display(15, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Text(caption)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

private struct CardButton: View {
    let title: String
    let symbol: String
    var prominent = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .labelStyle(.titleAndIcon)
                .font(.footnote.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .foregroundStyle(prominent ? Color.white : Color.primary)
                .background(prominent ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color.primary.opacity(0.08)),
                            in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct GirlMapCard: View {
    let girl: Girl
    let distance: CLLocationDistance?
    let onOpen: () -> Void
    let onRecord: () -> Void

    var body: some View {
        let details = girl.details
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                AvatarView(photoID: girl.avatarID, name: girl.name, size: 48, ring: girl.status.color)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(girl.name)
                            .font(Typo.display(19))
                            .lineLimit(1)
                        if !girl.rank.isEmpty { Badge(text: girl.rank) }
                    }
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            HStack(alignment: .bottom, spacing: 18) {
                CardMetric(value: "\(girl.encounters.count) 次", caption: "一起")
                CardMetric(value: Fmt.daysAgo(girl.lastInteraction(details: details)), caption: "上次")
                cycleMetric(details)
                Spacer(minLength: 0)
                CardButton(title: "记一次", symbol: "plus", prominent: true, action: onRecord)
                    .accessibilityIdentifier("mapCardRecord")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .contentShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .floatingGlass(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .onTapGesture(perform: onOpen)
        .accessibilityIdentifier("mapCard-\(girl.name)")
    }

    private var subtitle: String {
        var parts = [girl.status.title]
        if !girl.city.isEmpty { parts.append(girl.city) }
        if let distance { parts.append("距你 " + MapFormat.distance(distance)) }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func cycleMetric(_ details: GirlDetails) -> some View {
        let cycle = details.cycle
        if cycle.hasData, let phase = cycle.phase(on: Date()) {
            if phase == .period, let day = cycle.dayOfCycle(on: Date()) {
                CardMetric(value: "第 \(day) 天", caption: "经期", tint: phase.color)
            } else {
                CardMetric(value: phase.title, caption: "周期", tint: phase.color)
            }
        } else {
            CardMetric(value: BondLevel(count: girl.encounters.count).title, caption: "羁绊")
        }
    }
}

struct PlaceMapCard: View {
    let place: Place
    let count: Int
    let distance: CLLocationDistance?
    let onOpen: () -> Void
    let onRecord: () -> Void
    let onNavigate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: place.type.symbol)
                    .font(.system(size: 19, weight: .regular))
                    .foregroundStyle(.tint)
                    .frame(width: 48, height: 48)
                    .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text(place.displayName)
                        .font(Typo.display(19))
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            HStack(alignment: .bottom, spacing: 16) {
                CardMetric(value: "\(count) 次", caption: "在这里")
                CardMetric(value: Fmt.daysAgo(place.lastUsed), caption: "上次")
                peopleStack
                Spacer(minLength: 0)
                Button(action: onNavigate) {
                    Image(systemName: "arrow.triangle.turn.up.right.diamond")
                        .font(.footnote.weight(.semibold))
                        .frame(width: 34, height: 34)
                        .background(Color.primary.opacity(0.08), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("导航")
                CardButton(title: "记一次", symbol: "plus", prominent: true, action: onRecord)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .contentShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .floatingGlass(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .onTapGesture(perform: onOpen)
        .accessibilityIdentifier("mapCard-\(place.displayName)")
    }

    private var subtitle: String {
        var parts = [place.type.title]
        let area = [place.city, place.district].filter { !$0.isEmpty }.joined(separator: " ")
        if !area.isEmpty { parts.append(area) }
        if let distance { parts.append("距你 " + MapFormat.distance(distance)) }
        return parts.joined(separator: " · ")
    }

    /// 在这里见过的人：叠起来的小头像
    private var peopleStack: some View {
        var seen = Set<UUID>()
        var people: [Girl] = []
        for e in place.encounters.sorted(by: { $0.date > $1.date }) {
            for g in e.girls where !seen.contains(g.id) {
                seen.insert(g.id)
                people.append(g)
            }
        }
        let shown = Array(people.prefix(3))
        return VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: -7) {
                ForEach(shown) { g in
                    AvatarView(photoID: g.avatarID, name: g.name, size: 20)
                        .overlay(Circle().stroke(Color(uiColor: .systemBackground), lineWidth: 1.5))
                }
                if shown.isEmpty {
                    Text("—").font(Typo.display(15, weight: .semibold))
                }
            }
            .frame(height: 20)
            Text(people.count > 3 ? "等 \(people.count) 人" : "和谁")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

/// 长按地图放下的新地点
struct DraftPlaceCard: View {
    let draft: DraftPin
    let onCancel: () -> Void
    let onCreate: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "mappin.and.ellipse")
                .font(.system(size: 19))
                .foregroundStyle(.tint)
                .frame(width: 48, height: 48)
                .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(draft.name.isEmpty ? "这里" : draft.name)
                    .font(Typo.display(18))
                    .lineLimit(1)
                Group {
                    if draft.resolved {
                        Text(draft.address.isEmpty ? "未知地址" : draft.address)
                    } else {
                        Text("正在获取地址…")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            Spacer(minLength: 0)
            Button(action: onCancel) {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.semibold))
                    .frame(width: 34, height: 34)
                    .background(Color.primary.opacity(0.08), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("取消")
            CardButton(title: "添加地点", symbol: "plus", prominent: true, action: onCreate)
                .accessibilityIdentifier("draftCreate")
        }
        .padding(16)
        .floatingGlass(RoundedRectangle(cornerRadius: 26, style: .continuous))
    }
}

// MARK: - 底部：足迹回放

struct PlaybackPanel: View {
    let playback: MapPlayback
    let stats: MapStats
    let onToggle: () -> Void
    let onSeek: (Double) -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("足迹回放").eyebrow()
                    Text(playback.dateTitle)
                        .font(Typo.display(26, weight: .medium))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
                Spacer()
                HStack(alignment: .firstTextBaseline, spacing: 14) {
                    total(stats.encounters, "次")
                    total(stats.spots, "处")
                    total(stats.people, "人")
                }
            }
            HStack(spacing: 12) {
                Button(action: onToggle) {
                    Image(systemName: playback.isFinished ? "arrow.counterclockwise" : (playback.playing ? "pause.fill" : "play.fill"))
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(Color.accentColor, in: Circle())
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("playbackToggle")
                Slider(value: Binding(get: { playback.progress }, set: { onSeek($0) }), in: 0...1)
                    .tint(Color.accentColor)
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.footnote.weight(.semibold))
                        .frame(width: 34, height: 34)
                        .background(Color.primary.opacity(0.08), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("结束回放")
                .accessibilityIdentifier("playbackClose")
            }
        }
        .padding(16)
        .floatingGlass(RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    private func total(_ value: Int, _ unit: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text("\(value)")
                .font(Typo.display(19, weight: .semibold))
                .statNumber()
            Text(unit)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

/// 地图上什么都没有时的提示
struct MapEmptyHint: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "map")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(.secondary)
            Text("地图上还没有内容")
                .font(Typo.display(18))
            Text("给档案设置常驻位置、给地点在地图上选点，\n她们和你们去过的地方就会出现在这里。长按地图也可以直接添加地点。")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(22)
        .frame(maxWidth: 320)
        .floatingGlass(RoundedRectangle(cornerRadius: 26, style: .continuous))
    }
}
