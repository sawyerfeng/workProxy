import CoreLocation
import Foundation
import WorkProxyCore

struct PlaceCandidate: Identifiable, Equatable {
    let id = UUID()
    let label: String
    let address: String?
    let latitude: Double
    let longitude: Double
}

@MainActor
final class LocationService: NSObject, ObservableObject, LocationRequesting,
                             CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<LocationResult, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var lastFix: LocationFix?

    @Published private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        authorizationStatus = manager.authorizationStatus
    }

    var isAuthorized: Bool {
        switch authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse: return true
        default: return false
        }
    }

    func requestAuthorization() {
        guard manager.authorizationStatus == .notDetermined else { return }
        manager.requestWhenInUseAuthorization()
    }

    func requestLocation(timeout: Duration) async -> LocationResult {
        requestAuthorization()
        switch manager.authorizationStatus {
        case .denied, .restricted:
            return .unavailable(.denied)
        case .authorizedAlways, .authorizedWhenInUse:
            break
        default:
            // 首次授权请求已发出；本轮按不可用降级，下一次网络事件再读取。
            return .unavailable(.unknown)
        }
        guard CLLocationManager.locationServicesEnabled() else {
            return .unavailable(.servicesDisabled)
        }
        if let lastFix, lastFix.isUsable(at: Date()) {
            return .fix(lastFix)
        }
        // 上一次请求还没结束就被新网络事件取代时，先释放旧的 continuation。
        if continuation != nil {
            finish(.unavailable(.unknown))
        }
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            manager.requestLocation()
            timeoutTask = Task { [weak self] in
                do { try await Task.sleep(for: timeout) } catch { return }
                self?.finish(.unavailable(.timeout))
            }
        }
    }

    func searchAddress(_ query: String) async throws -> [PlaceCandidate] {
        let placemarks = try await CLGeocoder().geocodeAddressString(query)
        return placemarks.compactMap { placemark in
            guard let location = placemark.location else { return nil }
            let address = [placemark.thoroughfare, placemark.locality,
                           placemark.administrativeArea]
                .compactMap { $0 }
                .joined(separator: " ")
            return PlaceCandidate(
                label: placemark.name ?? placemark.locality ?? query,
                address: address.isEmpty ? nil : address,
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude
            )
        }
    }

    private func finish(_ result: LocationResult) {
        timeoutTask?.cancel()
        timeoutTask = nil
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(returning: result)
    }

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        let fix = LocationFix(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            horizontalAccuracy: location.horizontalAccuracy,
            timestamp: location.timestamp
        )
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.lastFix = fix
            self.finish(fix.isUsable(at: Date()) ? .fix(fix) : .unavailable(.lowAccuracy))
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didFailWithError error: Error) {
        Task { @MainActor [weak self] in
            self?.finish(.unavailable(.unknown))
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.authorizationStatus = status
            if status == .denied || status == .restricted {
                self.finish(.unavailable(.denied))
            }
        }
    }
}
