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
            Form {
                Section {
                    TextField("名称（如：xx酒店 / 她家）", text: $name)
                    Picker("类型", selection: $type) {
                        ForEach(PlaceType.allCases) { t in
                            Label(t.title, systemImage: t.symbol).tag(t)
                        }
                    }
                }

                Section("位置") {
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
                        LabeledContent("地图选点") {
                            Text(coordinate == nil ? "未设置" : "已设置")
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let coordinate {
                        MiniMap(coordinate: coordinate)
                    }
                    TextField("城市", text: $city)
                    TextField("区", text: $district)
                    TextField("地址", text: $address, axis: .vertical)
                }

                Section("评价") {
                    LabeledContent("评分") { StarRating(value: $rating) }
                    TextField("备注（价格、房型、隔音、方便程度…）", text: $note, axis: .vertical)
                        .lineLimit(2...6)
                }
            }
            .formKeyboardHandling()
            .navigationTitle(place == nil ? "新建地点" : "编辑地点")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                }
            }
        }
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
    @Query(sort: \Place.createdAt, order: .reverse) private var places: [Place]
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

    var body: some View {
        List {
            if let coordinate = place.coordinate {
                Section {
                    MiniMap(coordinate: coordinate, height: 180)
                }
            }

            Section {
                InfoRow(label: "类型", value: place.type.title)
                if !place.city.isEmpty || !place.district.isEmpty {
                    InfoRow(label: "城市", value: [place.city, place.district].filter { !$0.isEmpty }.joined(separator: " "))
                }
                if !place.address.isEmpty { InfoRow(label: "地址", value: place.address) }
                if place.rating > 0 {
                    LabeledContent("评分") { StarDisplay(value: place.rating) }
                }
                InfoRow(label: "次数", value: "\(place.encounters.count) 次")
                if let last = place.lastUsed {
                    InfoRow(label: "上次", value: Fmt.daysAgo(last))
                }
                if !place.note.isEmpty { TextBlock(label: "备注", text: place.note) }
            }

            if !place.encounters.isEmpty {
                Section("在这里的记录") {
                    ForEach(place.encounters.sorted { $0.date > $1.date }) { e in
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
        .toolbar {
            Button("编辑") { editing = true }
        }
        .sheet(isPresented: $editing) {
            PlaceEditView(place: place)
        }
    }
}
