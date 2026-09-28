import Foundation
import CoreLocation
import MapKit
import UIKit

@MainActor
final class HospitalLocatorService: NSObject, ObservableObject {
    @Published var hospitals: [HospitalPlace] = []
    @Published var nearestHospital: HospitalPlace?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var userLocation: CLLocation?

    private let locationManager = CLLocationManager()
    private var pendingSearch = false
    private var locationRetryCount = 0

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func requestLocationAndSearch() {
        isLoading = true
        errorMessage = nil
        pendingSearch = true
        locationRetryCount = 0

        switch locationManager.authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            beginLocationUpdates()
        case .denied, .restricted:
            pendingSearch = false
            errorMessage = "Location access is required to find nearby hospitals."
            isLoading = false
        @unknown default:
            pendingSearch = false
            isLoading = false
        }
    }

    /// Continuous updates until first fix — more reliable than one-shot `requestLocation()`.
    private func beginLocationUpdates() {
        locationManager.stopUpdatingLocation()
        locationManager.startUpdatingLocation()
        scheduleLocationFallback()
    }

    private func scheduleLocationFallback() {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            guard pendingSearch, isLoading else { return }
            if locationRetryCount < 2 {
                locationRetryCount += 1
                locationManager.requestLocation()
            } else {
                pendingSearch = false
                isLoading = false
                errorMessage = "Could not determine your location. Tap refresh to try again."
            }
        }
    }

    private func stopLocationUpdates() {
        locationManager.stopUpdatingLocation()
    }

    func searchHospitals(near location: CLLocation) async {
        userLocation = location
        await EmergencyNumberService.shared.update(from: location)

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = "hospital emergency room"
        request.region = MKCoordinateRegion(
            center: location.coordinate,
            latitudinalMeters: 25_000,
            longitudinalMeters: 25_000
        )

        do {
            let search = MKLocalSearch(request: request)
            let response = try await search.start()

            let places = response.mapItems.compactMap { item -> HospitalPlace? in
                guard let name = item.name else { return nil }
                let coord = item.placemark.coordinate
                let address = [
                    item.placemark.subThoroughfare,
                    item.placemark.thoroughfare,
                    item.placemark.locality,
                    item.placemark.administrativeArea
                ].compactMap { $0 }.joined(separator: " ")

                let hospitalLocation = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
                let distance = location.distance(from: hospitalLocation)

                return HospitalPlace(
                    id: "\(name)-\(coord.latitude)-\(coord.longitude)",
                    name: name,
                    address: address.isEmpty ? "Address unavailable" : address,
                    latitude: coord.latitude,
                    longitude: coord.longitude,
                    distanceMeters: distance
                )
            }
            .sorted { ($0.distanceMeters ?? .infinity) < ($1.distanceMeters ?? .infinity) }

            hospitals = places
            nearestHospital = places.first
            isLoading = false
        } catch {
            errorMessage = "Could not find hospitals: \(error.localizedDescription)"
            isLoading = false
        }
    }

    func openInMaps(_ hospital: HospitalPlace) {
        let placemark = MKPlacemark(coordinate: CLLocationCoordinate2D(
            latitude: hospital.latitude,
            longitude: hospital.longitude
        ))
        let item = MKMapItem(placemark: placemark)
        item.name = hospital.name
        item.openInMaps(launchOptions: [
            MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving
        ])
    }

}

extension HospitalLocatorService: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            guard pendingSearch else { return }
            pendingSearch = false
            stopLocationUpdates()
            await searchHospitals(near: location)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            guard pendingSearch else { return }
            if locationRetryCount < 2 {
                locationRetryCount += 1
                manager.requestLocation()
                return
            }
            pendingSearch = false
            stopLocationUpdates()
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            switch manager.authorizationStatus {
            case .authorizedWhenInUse, .authorizedAlways:
                if pendingSearch {
                    beginLocationUpdates()
                }
            case .denied, .restricted:
                pendingSearch = false
                stopLocationUpdates()
                errorMessage = "Location access is required to find nearby hospitals."
                isLoading = false
            default:
                break
            }
        }
    }
}
