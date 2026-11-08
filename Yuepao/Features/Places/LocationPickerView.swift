import SwiftUI
import MapKit
import CoreLocation

struct PickedLocation {
    var coordinate: CLLocationCoordinate2D
    var name: String
    var address: String
    var city: String
    var district: String
}

enum LocationPermission {
    static let manager = CLLocationManager()

    static func requestIfNeeded() {
        if TestSupport.isUITesting { return }
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
    }
}

/// 拖动地图让中心针对准位置。坐标直接取自地图本身，
/// 所以国内（GCJ-02 底图）也不会出现几百米的偏移。
struct LocationPickerView: View {
    var initial: CLLocationCoordinate2D?
    var onPick: (PickedLocation) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var position: MapCameraPosition
    @State private var center: CLLocationCoordinate2D
    @State private var query = ""
    @State private var results: [MKMapItem] = []
    @State private var selectedItem: MKMapItem?
    @State private var resolving = false
    @FocusState private var searchFocused: Bool

    init(initial: CLLocationCoordinate2D?, onPick: @escaping (PickedLocation) -> Void) {
        self.initial = initial
        self.onPick = onPick
        if let initial {
            _position = State(initialValue: .region(MKCoordinateRegion(center: initial, latitudinalMeters: 1500, longitudinalMeters: 1500)))
            _center = State(initialValue: initial)
        } else {
            _position = State(initialValue: .userLocation(fallback: .region(MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 35, longitude: 105),
                span: MKCoordinateSpan(latitudeDelta: 30, longitudeDelta: 30)))))
            _center = State(initialValue: CLLocationCoordinate2D(latitude: 35, longitude: 105))
        }
    }

    var body: some View {
        ZStack {
            Map(position: $position) {
                UserAnnotation()
            }
            .mapControls {
                MapUserLocationButton()
                MapCompass()
                MapScaleView()
            }
            .onMapCameraChange(frequency: .onEnd) { context in
                center = context.region.center
            }

            Image(systemName: "mappin")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(.red)
                .shadow(radius: 2)
                .offset(y: -17)
                .allowsHitTesting(false)
        }
        .safeAreaInset(edge: .top) {
            searchPanel
        }
        .navigationTitle("选择位置")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if resolving {
                    ProgressView()
                } else {
                    Button("确定") { confirm() }
                }
            }
        }
        .onAppear { LocationPermission.requestIfNeeded() }
    }

    private var searchPanel: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("搜索地点、酒店、小区…", text: $query)
                    .focused($searchFocused)
                    .submitLabel(.search)
                    .onSubmit { search() }
                if !query.isEmpty {
                    Button {
                        query = ""
                        results = []
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                }
            }
            .padding(10)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal)
            .padding(.top, 8)

            if !results.isEmpty {
                List(results, id: \.self) { item in
                    Button {
                        select(item)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name ?? "未命名").foregroundStyle(.primary)
                            Text(Self.address(of: item.placemark))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .listStyle(.plain)
                .frame(maxHeight: 280)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal)
                .padding(.top, 6)
            } else if let selectedItem {
                Text("已选：\(selectedItem.name ?? "")")
                    .font(.footnote)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.top, 6)
            }
        }
        .padding(.bottom, 6)
    }

    private func search() {
        let text = query.trimmed
        guard !text.isEmpty else { return }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = text
        request.region = MKCoordinateRegion(center: center, latitudinalMeters: 80_000, longitudinalMeters: 80_000)
        Task {
            let response = try? await MKLocalSearch(request: request).start()
            results = response?.mapItems ?? []
        }
    }

    private func select(_ item: MKMapItem) {
        let coordinate = item.placemark.coordinate
        selectedItem = item
        results = []
        searchFocused = false
        center = coordinate
        position = .region(MKCoordinateRegion(center: coordinate, latitudinalMeters: 800, longitudinalMeters: 800))
    }

    private func confirm() {
        if let item = selectedItem, item.placemark.coordinate.distance(to: center) < 80 {
            let pm = item.placemark
            onPick(PickedLocation(
                coordinate: pm.coordinate,
                name: item.name ?? "",
                address: Self.address(of: pm),
                city: pm.locality ?? pm.administrativeArea ?? "",
                district: pm.subLocality ?? ""
            ))
            dismiss()
            return
        }
        let coordinate = center
        resolving = true
        Task {
            var picked = PickedLocation(coordinate: coordinate, name: "", address: "", city: "", district: "")
            let geocoder = CLGeocoder()
            let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            if let pm = try? await geocoder.reverseGeocodeLocation(location).first {
                picked.name = pm.name ?? ""
                picked.address = Self.address(of: pm)
                picked.city = pm.locality ?? pm.administrativeArea ?? ""
                picked.district = pm.subLocality ?? ""
            }
            resolving = false
            onPick(picked)
            dismiss()
        }
    }

    static func address(of pm: CLPlacemark) -> String {
        let parts = [pm.administrativeArea, pm.locality, pm.subLocality, pm.thoroughfare, pm.subThoroughfare]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
        var result: [String] = []
        for p in parts where result.last != p {
            result.append(p)
        }
        return result.joined()
    }
}
