import SwiftUI
import MapKit

struct HospitalsView: View {
    @EnvironmentObject private var languageManager: LanguageManager
    @ObservedObject private var emergencyNumbers = EmergencyNumberService.shared
    @StateObject private var locator = HospitalLocatorService()
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var showEmergencyCallConfirm = false

    var body: some View {
        ZStack {
            BubbleBackground().ignoresSafeArea()
            hospitalList
        }
        .navigationTitle(languageManager.text("hospitals_title"))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    locator.requestLocationAndSearch()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
        }
        .onAppear {
            locator.requestLocationAndSearch()
        }
        .onChange(of: locator.nearestHospital?.id) { _, _ in
            updateCamera()
        }
        .emergencyCallConfirmation(
            isPresented: $showEmergencyCallConfirm,
            number: emergencyNumbers.emergencyNumber,
            languageManager: languageManager
        )
    }

    private var mapSection: some View {
        Map(position: $cameraPosition) {
            if let user = locator.userLocation {
                Annotation(languageManager.text("hospitals_you"), coordinate: user.coordinate) {
                    Image(systemName: "location.fill")
                        .padding(8)
                        .background(.blue, in: Circle())
                        .foregroundStyle(.white)
                }
            }

            ForEach(locator.hospitals.prefix(10)) { hospital in
                Annotation(hospital.name, coordinate: CLLocationCoordinate2D(
                    latitude: hospital.latitude,
                    longitude: hospital.longitude
                )) {
                    Image(systemName: "cross.case.fill")
                        .padding(8)
                        .background(hospital.id == locator.nearestHospital?.id ? Color.red : Color.orange, in: Circle())
                        .foregroundStyle(.white)
                }
            }
        }
        .frame(height: 280)
        .overlay(alignment: .top) {
            if locator.isLoading {
                ProgressView(languageManager.text("hospitals_finding"))
                    .padding(10)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.top, 12)
            }
        }
    }

    private var hospitalList: some View {
        List {
            Section {
                mapSection
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            Section {
                Button {
                    showEmergencyCallConfirm = true
                } label: {
                    Label(
                        languageManager.textFormat("hospitals_call_emergency", emergencyNumbers.emergencyNumber),
                        systemImage: "phone.fill"
                    )
                    .foregroundStyle(.red)
                    .font(.headline)
                }
            }

            if let nearest = locator.nearestHospital {
                Section(languageManager.text("hospitals_nearest")) {
                    HospitalRow(
                        hospital: nearest,
                        isNearest: true,
                        nearestBadge: languageManager.text("hospitals_nearest_badge")
                    ) {
                        locator.openInMaps(nearest)
                    }
                }
            }

            Section("\(languageManager.text("hospitals_all_nearby")) (\(locator.hospitals.count))") {
                if let error = locator.errorMessage {
                    Text(error).foregroundStyle(.red).font(.footnote)
                }

                ForEach(locator.hospitals) { hospital in
                    HospitalRow(
                        hospital: hospital,
                        isNearest: hospital.id == locator.nearestHospital?.id,
                        nearestBadge: languageManager.text("hospitals_nearest_badge")
                    ) {
                        locator.openInMaps(hospital)
                    }
                }
            }

            Section {
                Text(languageManager.text("hospitals_footer"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .listStyle(.insetGrouped)
    }

    private func updateCamera() {
        if let nearest = locator.nearestHospital {
            cameraPosition = .region(MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: nearest.latitude, longitude: nearest.longitude),
                span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)
            ))
        }
    }
}

struct HospitalRow: View {
    let hospital: HospitalPlace
    let isNearest: Bool
    let nearestBadge: String
    let onNavigate: () -> Void

    var body: some View {
        Button(action: onNavigate) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(hospital.name)
                            .font(.headline)
                            .foregroundStyle(.primary)
                        if isNearest {
                            Text(nearestBadge)
                                .font(.caption2.bold())
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.red.opacity(0.15), in: Capsule())
                                .foregroundStyle(.red)
                        }
                    }
                    Text(hospital.address)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    if let details = hospital.detailText, !details.isEmpty {
                        Text(details)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(4)
                    }
                }
                Spacer()
                VStack(alignment: .trailing) {
                    Text(hospital.distanceText)
                        .font(.subheadline.bold())
                    Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                        .foregroundStyle(.blue)
                }
            }
        }
    }
}
