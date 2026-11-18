import SwiftUI

/// 表单里展示四个可直接点的选项，完整词库与表单使用同一份草稿。
struct JournalOptionPicker: View {
    let title: String
    let key: OptionKey
    @Binding var selection: [String]

    @ObservedObject private var config = ConfigStore.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var page = 0
    @State private var browsing = false
    @State private var query = ""

    private var groups: [JournalOptions.Group] {
        JournalOptions.catalog(for: key, configured: config.options(key), selected: selection)
    }

    var body: some View {
        let catalog = groups
        let words = JournalOptions.suggestions(from: catalog)
        let pageCount = max(1, (words.count + 3) / 4)
        let current = min(page, pageCount - 1)
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.headline)
                    .fontDesign(.serif)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button {
                    query = ""
                    browsing = true
                } label: {
                    HStack(spacing: 4) {
                        Text("全部")
                        Text("\(words.count)").monospacedDigit()
                        Image(systemName: "chevron.right").font(.caption2)
                    }
                    .font(.footnote.weight(.medium))
                    .frame(minHeight: 44)
                }
                .accessibilityLabel("全部\(title)选项")
                .accessibilityIdentifier("browse-\(key.rawValue)")
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8),
                                     count: typeSize.isAccessibilitySize ? 1 : 2), spacing: 8) {
                ForEach(words.dropFirst(current * 4).prefix(4), id: \.self) { word in
                    if let group = catalog.first(where: { $0.words.contains(word) }) {
                        tile(word, group: group)
                    }
                }
            }
            HStack {
                Text(selection.isEmpty ? "可多选" : "已选 \(selection.count) 项")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if pageCount > 1 {
                    Button {
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                            page = (current + 1) % pageCount
                        }
                    } label: {
                        Label("换一组", systemImage: "arrow.triangle.2.circlepath")
                            .font(.footnote.weight(.medium))
                            .frame(minHeight: 44)
                    }
                    .accessibilityLabel("换一组\(title)选项")
                    .accessibilityIdentifier("cycle-\(key.rawValue)")
                }
            }
            if !selection.isEmpty {
                ScrollChips(inset: 0) {
                    ForEach(Array(selection.enumerated()), id: \.offset) { _, word in
                        Button { toggle(word) } label: {
                            Label(word, systemImage: "xmark.circle.fill")
                                .font(.footnote)
                                .foregroundStyle(Color(uiColor: Palette.wineUI))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Palette.fill, in: Capsule())
                                .frame(minHeight: 44)
                        }
                        .buttonStyle(.chip)
                        .accessibilityLabel("移除\(word)")
                    }
                }
            }
        }
        .sheet(isPresented: $browsing) { library }
    }

    private func tile(_ word: String, group: JournalOptions.Group) -> some View {
        let on = selection.contains(word)
        let wine = Color(uiColor: Palette.wineUI)
        return Button { toggle(word) } label: {
            HStack(spacing: 7) {
                IconBadge(symbol: group.symbol, color: group.tint, size: 28)
                Text(word)
                    .font(.subheadline.weight(on ? .semibold : .regular))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .font(.caption)
                    .foregroundStyle(on ? wine : Color.secondary)
                    .contentTransition(.opacity)
            }
            .foregroundStyle(Color.primary)
            .padding(.horizontal, 9)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            .background((on ? wine.opacity(0.10) : group.tint.opacity(0.06)), in: RoundedRectangle(cornerRadius: 13))
            .overlay {
                RoundedRectangle(cornerRadius: 13)
                    .strokeBorder(on ? wine.opacity(0.65) : Palette.hairline)
            }
        }
        .buttonStyle(.chip)
        .accessibilityLabel(word)
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityIdentifier("tile-\(key.rawValue)-\(word)")
        .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.97)))
    }

    private var library: some View {
        let term = query.trimmed
        let catalog = groups
        return NavigationStack {
            List {
                ForEach(catalog) { group in
                    let matches = group.words.filter { term.isEmpty || $0.localizedCaseInsensitiveContains(term) }
                    if !matches.isEmpty {
                        Section {
                            ForEach(matches, id: \.self) { word in
                                let on = selection.contains(word)
                                Button { toggle(word) } label: {
                                    HStack {
                                        Text(word).foregroundStyle(.primary)
                                        Spacer()
                                        Image(systemName: on ? "checkmark.circle.fill" : "circle")
                                            .foregroundStyle(on ? Color(uiColor: Palette.wineUI) : Color.secondary)
                                    }
                                    .contentShape(Rectangle())
                                }
                                .accessibilityLabel(word)
                                .accessibilityAddTraits(on ? .isSelected : [])
                                .accessibilityIdentifier("option-\(key.rawValue)-\(word)")
                            }
                        } header: {
                            Label(group.title, systemImage: group.symbol)
                        }
                    }
                }
                if !term.isEmpty && !catalog.contains(where: { $0.words.contains(term) }) {
                    Button {
                        config.addOption(term, to: key)
                        toggle(term)
                        query = ""
                    } label: {
                        Label("将「\(term)」加入词库并选用", systemImage: "plus.circle")
                    }
                }
            }
            .paperBackground()
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "搜索或添加自定义选项")
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                HStack {
                    Text("已选 \(selection.count) 项")
                        .font(.subheadline)
                        .monospacedDigit()
                    Spacer()
                    Button("完成") { browsing = false }
                        .buttonStyle(.wine)
                        .accessibilityIdentifier("done-\(key.rawValue)")
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(.regularMaterial)
            }
        }
        .presentationDragIndicator(.visible)
    }

    private func toggle(_ word: String) {
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.18)) {
            if selection.contains(word) {
                selection.removeAll { $0 == word }
            } else {
                selection.append(word)
            }
        }
        Haptics.light()
    }
}
