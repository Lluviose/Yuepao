import SwiftUI
import SwiftData

enum WishKind: String, CaseIterable, Identifiable {
    case play = "玩法", place = "地点", experience = "体验", other = "其他"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .play: return "wand.and.stars"
        case .place: return "mappin.and.ellipse"
        case .experience: return "sparkles"
        case .other: return "star"
        }
    }
}

/// 心愿清单：想和她一起做的事
struct WishListView: View {
    @Query(sort: \WishItem.createdAt, order: .reverse) private var wishes: [WishItem]
    @Query private var girls: [Girl]
    @Environment(\.modelContext) private var context

    @State private var creating = false
    @State private var editing: WishItem?

    private var open: [WishItem] { wishes.filter { !$0.isDone } }
    private var done: [WishItem] {
        wishes.filter(\.isDone).sorted { ($0.doneAt ?? $0.createdAt) > ($1.doneAt ?? $1.createdAt) }
    }

    var body: some View {
        List {
            Section {
                header
                    .listRowBackground(LeatherBackground(cornerRadius: 0))
            }

            if !open.isEmpty {
                Section("想做的") {
                    ForEach(open) { wish in
                        row(wish)
                    }
                }
            }
            if !done.isEmpty {
                Section("已实现") {
                    ForEach(done) { wish in
                        row(wish)
                    }
                }
            }
        }
        .listSectionSpacing(.compact)
        .overlay {
            if wishes.isEmpty {
                ContentUnavailableView {
                    Label("还没有心愿", systemImage: "star")
                } description: {
                    Text("想去的酒店、想试的玩法、想和她一起做的事，都可以写下来")
                } actions: {
                    Button("写一个") { creating = true }
                        .buttonStyle(.borderedProminent)
                }
                .padding(.top, 120)
            }
        }
        .navigationTitle("心愿清单")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button {
                creating = true
            } label: {
                Image(systemName: "plus")
            }
            .accessibilityIdentifier("addWish")
        }
        .sheet(isPresented: $creating) {
            WishComposer(wish: nil)
        }
        .sheet(item: $editing) { wish in
            WishComposer(wish: wish)
        }
    }

    private var header: some View {
        let total = wishes.count
        let achieved = done.count
        return VStack(spacing: 10) {
            Image(systemName: "star.circle")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(Palette.gold)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(achieved)")
                    .font(Typo.display(44, weight: .medium))
                    .contentTransition(.numericText())
                Text("/ \(total) 已实现")
                    .font(.subheadline)
                    .foregroundStyle(Color.white.opacity(0.7))
            }
            .foregroundStyle(.white)
            ProgressView(value: Double(achieved), total: Double(max(total, 1)))
                .tint(Palette.gold)
                .frame(maxWidth: 220)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
    }

    private func row(_ wish: WishItem) -> some View {
        HStack(spacing: 14) {
            Button {
                toggle(wish)
            } label: {
                Image(systemName: wish.isDone ? "star.fill" : "star")
                    .font(.title3)
                    .foregroundStyle(wish.isDone ? Palette.gold : Color.secondary)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.borderless)
            .sensoryFeedback(.success, trigger: wish.isDone) { _, isDone in isDone }

            VStack(alignment: .leading, spacing: 4) {
                Text(wish.title)
                    .font(Typo.display(17, weight: .regular))
                    .foregroundStyle(Color.primary)
                HStack(spacing: 6) {
                    if let kind = WishKind(rawValue: wish.kind) {
                        Label(kind.rawValue, systemImage: kind.symbol)
                    }
                    if let name = girls.first(where: { $0.id == wish.girlID })?.name {
                        Text("· 和\(name)")
                    }
                    if wish.isDone, let at = wish.doneAt {
                        Text("· \(Fmt.date(at)) 实现")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                if !wish.note.isEmpty {
                    Text(wish.note)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture { editing = wish }
        .swipeActions {
            Button(role: .destructive) {
                withAnimation(.snappy) { context.delete(wish) }
                try? context.save()
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
    }

    private func toggle(_ wish: WishItem) {
        withAnimation(.snappy) {
            wish.isDone.toggle()
            wish.doneAt = wish.isDone ? Date() : nil
        }
        try? context.save()
        AchievementCenter.shared.refresh(context: context)
    }
}

struct WishComposer: View {
    let wish: WishItem?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Girl.createdAt, order: .reverse) private var girls: [Girl]

    @State private var title: String
    @State private var kind: String
    @State private var note: String
    @State private var girlID: UUID?
    @FocusState private var focused: Bool

    private let suggestions = ["海边酒店", "温泉之夜", "一起洗澡", "制服", "情侣套房", "一起旅行", "跨年夜", "看着镜子", "早安约会"]

    init(wish: WishItem?) {
        self.wish = wish
        _title = State(initialValue: wish?.title ?? "")
        _kind = State(initialValue: wish?.kind ?? WishKind.experience.rawValue)
        _note = State(initialValue: wish?.note ?? "")
        _girlID = State(initialValue: wish?.girlID)
    }

    private var currentGirls: [Girl] {
        girls.filter { $0.status.isCurrent }
    }

    var body: some View {
        ComposerShell(title: wish == nil ? "新心愿" : "编辑心愿", canSave: !title.trimmed.isEmpty,
                      saveIdentifier: "saveWish",
                      onCancel: { dismiss() }, onSave: save) {
            TextField("想做什么", text: $title, axis: .vertical)
                .font(Typo.display(24, weight: .medium))
                .focused($focused)
                .accessibilityIdentifier("wishTitle")
            if title.isEmpty {
                ChipRow {
                    ForEach(suggestions, id: \.self) { s in
                        ChoiceChip(title: s, selected: false) { title = s }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                ComposerLabel("类型")
                ChipRow {
                    ForEach(WishKind.allCases) { k in
                        ChoiceChip(title: k.rawValue, symbol: k.symbol, selected: kind == k.rawValue) {
                            kind = k.rawValue
                        }
                    }
                }
            }

            if !currentGirls.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    ComposerLabel("想和谁")
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 14) {
                            ForEach(currentGirls) { g in
                                QuickPickAvatar(girl: g, selected: girlID == g.id) {
                                    withAnimation(.snappy(duration: 0.22)) {
                                        girlID = girlID == g.id ? nil : g.id
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                    .padding(.horizontal, -20)
                }
            }

            TextField("备注（在哪、需要准备什么…）", text: $note, axis: .vertical)
                .lineLimit(2...6)
                .composerField()
        }
        .composerSheet(detents: [.large])
        .onAppear { if wish == nil { focused = true } }
    }

    private func save() {
        let target: WishItem
        if let wish {
            target = wish
        } else {
            target = WishItem()
            context.insert(target)
        }
        target.title = title.trimmed
        target.kind = kind
        target.note = note.trimmed
        target.girlID = girlID
        try? context.save()
        AchievementCenter.shared.refresh(context: context)
        dismiss()
    }
}
