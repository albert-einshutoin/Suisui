import Combine
import Foundation
import SuisuiCore
#if canImport(CoreLocation)
import CoreLocation
#endif
#if canImport(WeatherKit)
import WeatherKit
#endif

public struct TodayWeatherCoordinate: Equatable, Sendable {
    public let latitude: Double
    public let longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

public struct TodayWeatherValue: Equatable, Sendable {
    public let temperatureCelsius: Int
    public let location: String
    public let updatedAt: Date

    public init(temperatureCelsius: Int, location: String, updatedAt: Date) {
        self.temperatureCelsius = temperatureCelsius
        self.location = location
        self.updatedAt = updatedAt
    }
}

public protocol TodayWeatherProviding: Sendable {
    func weather(for coordinate: TodayWeatherCoordinate) async throws -> TodayWeatherValue
}

public protocol TodayLocationProviding: Sendable {
    func currentCoordinate() async throws -> TodayWeatherCoordinate
}

public enum TodayWeatherModelError: Error, Equatable, Sendable {
    case unavailable
    case permissionDenied
}

@MainActor
public final class TodayWeatherModel: ObservableObject {
    @Published public private(set) var state: TodayWeatherState

    private let preferenceProvider: @MainActor () -> WeatherLocationPreference
    private let weatherProvider: any TodayWeatherProviding
    private let locationProvider: any TodayLocationProviding
    private var hasAttemptedRefresh = false
    private var cachedEntry: (key: String, value: TodayWeatherValue)?

    public init(
        initialState: TodayWeatherState = .notConfigured,
        preferenceProvider: @escaping @MainActor () -> WeatherLocationPreference,
        weatherProvider: any TodayWeatherProviding,
        locationProvider: any TodayLocationProviding
    ) {
        self.state = initialState
        self.preferenceProvider = preferenceProvider
        self.weatherProvider = weatherProvider
        self.locationProvider = locationProvider
    }

    public func refreshIfNeeded() async {
        guard !hasAttemptedRefresh else { return }
        hasAttemptedRefresh = true
        await refresh()
    }

    public func refresh() async {
        let preference = preferenceProvider().normalized
        let cacheKey = preference.sessionCacheKey
        switch preference {
        case .unset:
            state = .notConfigured
            return
        case .currentLocation:
            state = .permissionPending
        case .manual:
            break
        }

        // Keep the cache in the view model rather than UserDefaults: a weather
        // value can make a location inferable, so the privacy contract must not
        // turn a convenience refresh into a location history.
        if let cachedEntry, cachedEntry.key == cacheKey {
            state = .available(
                temperatureCelsius: cachedEntry.value.temperatureCelsius,
                location: cachedEntry.value.location,
                updatedAt: cachedEntry.value.updatedAt
            )
        }
        state = .loading
        do {
            let coordinate: TodayWeatherCoordinate
            let locationLabel: String
            switch preference {
            case .currentLocation:
                coordinate = try await locationProvider.currentCoordinate()
                locationLabel = "Current location"
            case let .manual(cityLabel, latitude, longitude):
                coordinate = TodayWeatherCoordinate(latitude: latitude, longitude: longitude)
                locationLabel = cityLabel
            case .unset:
                state = .notConfigured
                return
            }
            let value = try await weatherProvider.weather(for: coordinate)
            let displayLocation = value.location.isEmpty ? locationLabel : value.location
            let cacheValue = TodayWeatherValue(
                temperatureCelsius: value.temperatureCelsius,
                location: displayLocation,
                updatedAt: value.updatedAt
            )
            cachedEntry = (cacheKey, cacheValue)
            state = .available(
                temperatureCelsius: cacheValue.temperatureCelsius,
                location: cacheValue.location,
                updatedAt: cacheValue.updatedAt
            )
        } catch TodayWeatherModelError.permissionDenied {
            state = .permissionPending
        } catch {
            if let cachedEntry, cachedEntry.key == cacheKey {
                state = .available(
                    temperatureCelsius: cachedEntry.value.temperatureCelsius,
                    location: cachedEntry.value.location,
                    updatedAt: cachedEntry.value.updatedAt
                )
            } else {
                state = .failed
            }
        }
    }
}

public struct UnavailableTodayWeatherProvider: TodayWeatherProviding {
    public init() {}

    public func weather(for coordinate: TodayWeatherCoordinate) async throws -> TodayWeatherValue {
        throw TodayWeatherModelError.unavailable
    }
}

public struct UnavailableTodayLocationProvider: TodayLocationProviding {
    public init() {}

    public func currentCoordinate() async throws -> TodayWeatherCoordinate {
        throw TodayWeatherModelError.permissionDenied
    }
}

#if canImport(WeatherKit) && canImport(CoreLocation)
public struct WeatherKitTodayProvider: TodayWeatherProviding {
    private let service: WeatherService
    private let clock: @Sendable () -> Date

    public init(service: WeatherService = .shared, clock: @escaping @Sendable () -> Date = Date.init) {
        self.service = service
        self.clock = clock
    }

    public func weather(for coordinate: TodayWeatherCoordinate) async throws -> TodayWeatherValue {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let weather = try await service.weather(for: location)
        let celsius = weather.currentWeather.temperature.converted(to: .celsius).value
        return TodayWeatherValue(
            temperatureCelsius: Int(celsius.rounded()),
            location: "",
            updatedAt: clock()
        )
    }
}

public final class CoreLocationTodayProvider: NSObject, CLLocationManagerDelegate, TodayLocationProviding, @unchecked Sendable {
    private let manager: CLLocationManager
    private var continuation: CheckedContinuation<TodayWeatherCoordinate, Error>?

    public override init() {
        manager = CLLocationManager()
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    public func currentCoordinate() async throws -> TodayWeatherCoordinate {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            switch manager.authorizationStatus {
            case .authorized, .authorizedAlways:
                manager.requestLocation()
            case .notDetermined:
                manager.requestWhenInUseAuthorization()
            default:
                continuation.resume(throwing: TodayWeatherModelError.permissionDenied)
                self.continuation = nil
            }
        }
    }

    public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard manager.authorizationStatus == .authorized
            || manager.authorizationStatus == .authorizedAlways,
              continuation != nil else { return }
        manager.requestLocation()
    }

    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.first, let continuation else { return }
        self.continuation = nil
        continuation.resume(returning: TodayWeatherCoordinate(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude))
    }

    public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(throwing: error)
    }
}
#endif
