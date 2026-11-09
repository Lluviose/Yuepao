import SwiftUI
import SwiftData
import MapKit

// MARK: - 编辑地点

struct PlaceEditView: View {
    let place: Place?
    var onSave: ((Place) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @State private var name: String
    @State private var type: PlaceType
    @State private var latitude: Double?
    @State private var longitude: Double?
    @State private var city: String
    @State private var district: String
    @State private var address: String
    @State private var note: String
    @State private var rating: Int

    /// `preset`：从地图上长按选的位置，新建时预先填好
    init(place: Place?, preset: PickedLocation? = nil, onSave: ((Place) -> Void)? = nil) {
        self.place = place
        self.onSave = onSave
        _name = State(initialValue: place?.name ?? preset?.name ?? "")
        _type = State(initialValue: place?.type ?? .hotel)
        _latitude = State(initialValue: place?.latitude ?? preset?.coordinate.latitude)
        _longitude = State(initialValue: place?.longitude ?? preset?.coordinate.longitude)
        _city = State(initialValue: place?.city ?? preset?.city ?? "")
        _district = State(initialValue: place?.district ?? preset?.district ?? "")
        _address = State(initialValue: place?.address ?? preset?.address ?? "")
        _note = State(initialValue: place?.note ?? "")
        _rating = State(initialValue: place?.rating ?? 0)
    }

    private var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    RecordCard {
                        TextField("名称，比如 xx 酒店、她家", text: $name)
                            .font(Typo.display(24))
                            .accessibilityIdentifier("placeName")
                        typeGrid
                    }

                    RecordCard("位置") {
                        NavigationLink {
                            LocationPickerView(initial: coordinate) { picked in
                                latitude = picked.coordinate.latitude
                                longitude = picked.coordinate.longitude
                                if name.trimmed.isEmpty { name = picked.name }
                                if !picked.city.isEmpty { city = picked.city }
                                if !picked.district.isEmpty { district = picked.district }
                                if !picked.address.isEmpty { address = picked.address }
                            }
                        } label: {
                            HStack(spacing: 12) {
                                IconBadge(symbol: "mappin.and.ellipse", color: .accentColor, size: 32)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("地图选点")
                                        .foregroundStyle(.primary)
                                    Text(coordinate == nil ? "选好后会出现在地图上" : "已设置，点这里调整")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 8)
                                Image(systemName: "chevron.right")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if let coordinate {
                            MiniMap(coordinate: coordinate, height: 150)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        CardField(title: "城市", text: $city)
                        Divider()
                        CardField(title: "区", text: $district)
                        Divider()
                        CardField(title: "地址", text: $address, multiline: true)
                    }

                    RecordCard("评价") {
                        HStack {
                            Text("评分")
                            Spacer(minLength: 8)
                            StarPicker(value: $rating, identifier: "placeRating")
                        }
                        Divider()
                        TextField("备注：价格、房型、隔音、方不方便…", text: $note, axis: .vertical)
                            .lineLimit(2...6)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .padding(.bottom, 36)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .formKeyboardHandling()
            .navigationTitle(place == nil ? "新建地点" : "编辑地点")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    /// 地点类型：一格一个，选中的描边
    private var typeGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
            ForEach(PlaceType.allCases) { t in
                let on = type == t
                Button {
                    withAnimation(.snappy(duration: 0.22)) { type = t }
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: t.symbol)
                            .font(.system(size: 18))
                            .symbolRenderingMode(.hierarchical)
                            .frame(height: 22)
                        Text(t.title)
                            .font(.caption.weight(on ? .semibold : .regular))
                    }
                    .foregroundStyle(on ? Color.accentColor : Color.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(on ? Color.accentColor.opacity(0.12) : Color(uiColor: .tertiarySystemFill).opacity(0.7)))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(on ? Color.accentColor.opacity(0.5) : Color.clear, lineWidth: 1))
                    .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.chip)
                .accessibilityLabel(t.title)
                .accessibilityAddTraits(on ? .isSelected : [])
                .accessibilityIdentifier("placeType-\(t.rawValue)")
            }
        }
        .sensoryFeedback(.selection, trigger: type)
    }

    private func save() {
        let target: Place
        if let place {
            target = place
        } else {
            target = Place()
            context.insert(target)
        }
        target.name = name.trimmed
        target.type = type
        target.latitude = latitude
        target.longitude = longitude
        target.city = city.trimmed
        target.district = district.trimmed
        target.address = address.trimmed
        target.note = note
        target.rating = rating
        try? context.save()
        Haptics.success()
        onSave?(target)
        dismiss()
    }
}

struct MiniMap: View {
    let coordinate: CLLocationCoordinate2D
    var height: CGFloat = 140

    var body: some View {
        Map(initialPosition: .region(MKCoordinateRegion(center: coordinate, latitudinalMeters: 1200, longitudinalMeters: 1200)),
            interactionModes: []) {
            Marker("", coordinate: coordinate)
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        .id("\(coordinate.latitude),\(coordinate.longitude)")
    }
}

// MARK: - 选择地点（给记录用）

struct PlaceSelectView: View {
    @Binding var selection: Place?

    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Place.createdAt, order: .reverse) private var places: [Place]
    @State private var search = ""
    @State private var creating = false

    private var sorted: [Place] {
        let list = places.sorted { ($0.lastUsed ?? $0.createdAt) > ($1.lastUsed ?? $1.createdAt) }
        let q = search.trimmed
        guard !q.isEmpty else { return list }
        return list.filter { $0.name.contains(q) || $0.city.contains(q) || $0.district.contains(q) || $0.address.contains(q) }
    }

    var body: some View {
        List {
            Section {
                Button {
                    creating = true
                } label: {
                    Label("新建地点", systemImage: "plus.circle.fill")
                }
                Button {
                    selection = nil
                    dismiss()
                } label: {
                    HStack {
                        Text("不设置地点").foregroundStyle(.primary)
                        Spacer()
                        if selection == nil { Image(systemName: "checkmark").foregroundStyle(.tint) }
                    }
                }
            }

            if !sorted.isEmpty {
                Section("常用地点") {
                    ForEach(sorted) { place in
                        Button {
                            selection = place
                            dismiss()
                        } label: {
                            HStack {
                                PlaceRow(place: place)
                                if selection?.id == place.id {
                                    Image(systemName: "checkmark").foregroundStyle(.tint)
                                }
                            }
                        }
                        .tint(.primary)
                    }
                }
            }
        }
        .searchable(text: $search, prompt: "搜索地点")
        .navigationTitle("选择地点")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $creating) {
            PlaceEditView(place: nil) { newPlace in
                selection = newPlace
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { dismiss() }
            }
        }
    }
}

struct PlaceRow: View {
    let place: Place

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: place.type.symbol)
                .frame(width: 32, height: 32)
                .foregroundStyle(.tint)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text(place.displayName).foregroundStyle(.primary)
                Text([place.type.title, place.city, place.district].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(place.encounters.count) 次")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - 地点列表 / 详情

struct PlaceListView: View {
    @Query(sort: \Place.createdAt, order: .reverse, animation: .snappy) private var places: [Place]
    @Environment(\.modelContext) private var context
    @State private var creating = false
    @State private var pendingDelete: Place?

    private var sorted: [Place] {
        places.sorted { $0.encounters.count > $1.encounters.count }
    }

    var body: some View {
        List {
            ForEach(sorted) { place in
                NavigationLink {
                    PlaceDetailView(place: place)
                } label: {
                    PlaceRow(place: place)
                }
                .swipeActions {
                    Button("删除", role: .destructive) { pendingDelete = place }
                }
            }
        }
        .overlay {
            if places.isEmpty {
                ContentUnavailableView("还没有地点", systemImage: "mappin.slash", description: Text("记录约会时可以顺手新建地点"))
            }
        }
        .navigationTitle("地点")
        .toolbar {
            Button {
                creating = true
            } label: {
                Image(systemName: "plus")
            }
        }
        .sheet(isPresented: $creating) {
            PlaceEditView(place: nil)
        }
        .confirmationDialog("删除地点？", isPresented: Binding(
            get: { pendingDelete != nil },
            set: { if !$0 { pendingDelete = nil } }
        ), titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                if let p = pendingDelete {
                    context.delete(p)
                    try? context.save()
                }
                pendingDelete = nil
            }
        } message: {
            Text("相关记录会保留，只是不再关联这个地点。")
        }
    }
}

struct PlaceDetailView: View {
    let place: Place

    @State private var editing = false
    @State private var openGirl: Girl?

    /// 在这里见过的人和次数
    private func visitors(_ encounters: [Encounter]) -> [(girl: Girl, count: Int)] {
        var counts: [UUID: (girl: Girl, count: Int)] = [:]
        for e in encounters {
            for g in e.girls {
                counts[g.id, default: (girl: g, count: 0)].count += 1
            }
        }
        return counts.values.sorted { $0.count != $1.count ? $0.count > $1.count : $0.girl.name < $1.girl.name }
    }

    var body: some View {
        let encounters = place.encounters.sorted { $0.date > $1.date }
        let people = visitors(encounters)
        List {
            Section {
                VStack(alignment: .leading, spacing: 16) {
                    if let coordinate = place.coordinate {
                        MiniMap(coordinate: coordinate, height: 170)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    HStack(spacing: 12) {
                        IconBadge(symbol: place.type.symbol, color: .accentColor, size: 44)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(place.displayName)
                                .font(Typo.display(22))
                            Text([place.type.title, place.city, place.district].filter { !$0.isEmpty }.joined(separator: " · "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    MetricStrip(items: [
                        MetricItem(label: "次数", value: "\(encounters.count)"),
                        MetricItem(label: "见过", value: "\(people.count)", unit: "人"),
                        MetricItem(label: "上次", value: place.lastUsed.map { Fmt.daysAgo($0) } ?? "—"),
                        MetricItem(label: "评分", value: place.rating > 0 ? "\(place.rating)" : "—",
                                   unit: place.rating > 0 ? "星" : "")
                    ])
                }
                .padding(.vertical, 6)
            }

            if !place.address.isEmpty || !place.note.isEmpty {
                Section {
                    if !place.address.isEmpty { TextBlock(label: "地址", text: place.address) }
                    if !place.note.isEmpty { TextBlock(label: "备注", text: place.note) }
                }
            }

            if !people.isEmpty {
                Section("在这里见过") {
                    FlowLayout(spacing: 8) {
                        ForEach(people, id: \.girl.id) { item in
                            Button {
                                openGirl = item.girl
                            } label: {
                                HStack(spacing: 7) {
                                    AvatarView(photoID: item.girl.avatarID, name: item.girl.name, size: 26)
                                    Text(item.girl.name)
                                        .font(.subheadline)
                                    Text("\(item.count)")
                                        .font(.caption.weight(.semibold))
                                        .monospacedDigit()
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.leading, 4)
                                .padding(.trailing, 12)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(Color(uiColor: .tertiarySystemFill)))
                                .contentShape(Capsule())
                            }
                            .buttonStyle(.chip)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            if !encounters.isEmpty {
                Section("在这里的记录") {
                    ForEach(encounters) { e in
                        NavigationLink {
                            EncounterDetailView(encounter: e)
                        } label: {
                            EncounterRow(encounter: e, showPlace: false)
                        }
                    }
                }
            }
        }
        .navigationTitle(place.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $openGirl) { girl in
            GirlDetailView(girl: girl)
        }
        .toolbar {
            Button("编辑") { editing = true }
        }
        .sheet(isPresented: $editing) {
            PlaceEditView(place: place)
        }
    }
}
