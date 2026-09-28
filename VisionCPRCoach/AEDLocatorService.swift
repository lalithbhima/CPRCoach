import Foundation
import CoreLocation
import MapKit
import UIKit

@MainActor
final class AEDLocatorService: NSObject, ObservableObject {
    @Published var aeds: [HospitalPlace] = []
    @Published var nearestAED: HospitalPlace?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var userLocation: CLLocation?

    @Published var totalStationsInDatabase: Int = 0

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
            errorMessage = LanguageManager.shared.text("aeds_location_denied")
            isLoading = false
        @unknown default:
            pendingSearch = false
            isLoading = false
        }
    }

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
                errorMessage = LanguageManager.shared.text("aeds_location_failed")
            }
        }
    }

    private func stopLocationUpdates() {
        locationManager.stopUpdatingLocation()
    }

    func searchAEDs(near location: CLLocation) async {
        userLocation = location
        await EmergencyNumberService.shared.update(from: location)

        do {
            try await AEDGeoJSONStore.shared.ensureLoaded()
            totalStationsInDatabase = await AEDGeoJSONStore.shared.stationCount
            let places = await AEDGeoJSONStore.shared.placesNear(location).map(localizePlaceIfNeeded)

            if places.isEmpty {
                errorMessage = LanguageManager.shared.text("aeds_none_nearby")
            } else {
                errorMessage = nil
            }

            aeds = places
            nearestAED = places.first
            isLoading = false
        } catch let error as AEDGeoJSONError {
            switch error {
            case .fileNotFound:
                errorMessage = LanguageManager.shared.text("aeds_file_missing")
            case .invalidFormat:
                errorMessage = LanguageManager.shared.text("aeds_file_invalid")
            }
            isLoading = false
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }

    private func localizePlaceIfNeeded(_ place: HospitalPlace) -> HospitalPlace {
        guard place.address.isEmpty else { return place }
        return HospitalPlace(
            id: place.id,
            name: place.name,
            address: LanguageManager.shared.text("aeds_address_unavailable"),
            latitude: place.latitude,
            longitude: place.longitude,
            distanceMeters: place.distanceMeters,
            detailText: place.detailText
        )
    }

    func openInMaps(_ place: HospitalPlace) {
        let placemark = MKPlacemark(coordinate: CLLocationCoordinate2D(
            latitude: place.latitude,
            longitude: place.longitude
        ))
        let item = MKMapItem(placemark: placemark)
        item.name = place.name
        item.openInMaps(launchOptions: [
            MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking
        ])
    }
}

extension AEDLocatorService: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            guard pendingSearch else { return }
            pendingSearch = false
            stopLocationUpdates()
            await searchAEDs(near: location)
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
                errorMessage = LanguageManager.shared.text("aeds_location_denied")
                isLoading = false
            default:
                break
            }
        }
    }
}
