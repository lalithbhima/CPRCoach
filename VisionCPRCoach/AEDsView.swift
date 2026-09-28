import SwiftUI
import MapKit

struct AEDsView: View {
    @EnvironmentObject private var languageManager: LanguageManager
    @ObservedObject private var emergencyNumbers = EmergencyNumberService.shared
    @StateObject private var locator = AEDLocatorService()
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var showEmergencyCallConfirm = false

    var body: some View {
        ZStack {
            BubbleBackground().ignoresSafeArea()
            aedList
        }
        .navigationTitle(languageManager.text("aeds_title"))
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
        .onChange(of: locator.nearestAED?.id) { _, _ in
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

            ForEach(locator.aeds.prefix(10)) { aed in
                Annotation(aed.name, coordinate: CLLocationCoordinate2D(
                    latitude: aed.latitude,
                    longitude: aed.longitude
                )) {
                    Image(systemName: "bolt.heart.fill")
                        .padding(8)
                        .background(aed.id == locator.nearestAED?.id ? Color.green : Color.teal, in: Circle())
                        .foregroundStyle(.white)
                }
            }
        }
        .frame(height: 280)
        .overlay(alignment: .top) {
            if locator.isLoading {
                ProgressView(languageManager.text("aeds_loading"))
                    .padding(10)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.top, 12)
            }
        }
    }

    private var aedList: some View {
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

            if let nearest = locator.nearestAED {
                Section(languageManager.text("aeds_nearest")) {
                    HospitalRow(
                        hospital: nearest,
                        isNearest: true,
                        nearestBadge: languageManager.text("aeds_nearest_badge")
                    ) {
                        locator.openInMaps(nearest)
                    }
                }
            }

            Section("\(languageManager.text("aeds_all_nearby")) (\(locator.aeds.count))") {
                if let error = locator.errorMessage {
                    Text(error).foregroundStyle(.red).font(.footnote)
                }

                ForEach(locator.aeds) { aed in
                    HospitalRow(
                        hospital: aed,
                        isNearest: aed.id == locator.nearestAED?.id,
                        nearestBadge: languageManager.text("aeds_nearest_badge")
                    ) {
                        locator.openInMaps(aed)
                    }
                }
            }

            Section {
                Text(
                    languageManager.textFormat(
                        "aeds_database_footer",
                        locator.totalStationsInDatabase,
                        locator.aeds.count
                    )
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
        .listStyle(.insetGrouped)
    }

    private func updateCamera() {
        if let nearest = locator.nearestAED {
            cameraPosition = .region(MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: nearest.latitude, longitude: nearest.longitude),
                span: MKCoordinateSpan(latitudeDelta: 0.06, longitudeDelta: 0.06)
            ))
        }
    }
}
