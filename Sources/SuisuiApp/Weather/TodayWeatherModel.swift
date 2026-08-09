import Combine
import Foundation
import SuisuiCore
#if canImport(CoreLocation)
@preconcurrency import CoreLocation
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
    public let condition: String?
    public let highTemperatureCelsius: Int?
    public let lowTemperatureCelsius: Int?
    public let attributionURL: String?

    public init(
        temperatureCelsius: Int,
        location: String,
        updatedAt: Date,
        condition: String? = nil,
        highTemperatureCelsius: Int? = nil,
        lowTemperatureCelsius: Int? = nil,
        attributionURL: String? = nil
    ) {
        self.temperatureCelsius = temperatureCelsius
        self.location = location
        self.updatedAt = updatedAt
        self.condition = condition
        self.highTemperatureCelsius = highTemperatureCelsius
        self.lowTemperatureCelsius = lowTemperatureCelsius
        self.attributionURL = attributionURL
    }
}

public protocol TodayWeatherProviding: Sendable {
    func weather(for coordinate: TodayWeatherCoordinate) async throws -> TodayWeatherValue
}

@MainActor
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
    private var refreshGeneration = 0

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
        refreshGeneration += 1
        let generation = refreshGeneration
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
        let hasMatchingCache = cachedEntry?.key == cacheKey
        if let cachedEntry, cachedEntry.key == cacheKey {
            state = state(for: cachedEntry.value)
        }
        // Keep a cached reading visible while the refresh runs. Replacing it
        // with a loading placeholder creates a misleading blank/oscillating
        // header and discards the stale-data affordance.
        if !hasMatchingCache {
            state = .loading
        }
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
            guard isCurrentRefresh(generation) else { return }
            let value = try await weatherProvider.weather(for: coordinate)
            // Settings may start a newer refresh while location/weather awaits.
            // Only the newest request is allowed to publish a Today state.
            guard isCurrentRefresh(generation) else { return }
            let displayLocation = value.location.isEmpty ? locationLabel : value.location
            let cacheValue = TodayWeatherValue(
                temperatureCelsius: value.temperatureCelsius,
                location: displayLocation,
                updatedAt: value.updatedAt,
                condition: value.condition,
                highTemperatureCelsius: value.highTemperatureCelsius,
                lowTemperatureCelsius: value.lowTemperatureCelsius,
                attributionURL: value.attributionURL
            )
            cachedEntry = (cacheKey, cacheValue)
            state = state(for: cacheValue)
        } catch TodayWeatherModelError.permissionDenied {
            guard isCurrentRefresh(generation) else { return }
            state = .permissionDenied
        } catch {
            guard isCurrentRefresh(generation) else { return }
            if let cachedEntry, cachedEntry.key == cacheKey {
                state = state(for: cachedEntry.value)
            } else {
                state = .failed
            }
        }
    }

    private func isCurrentRefresh(_ generation: Int) -> Bool {
        refreshGeneration == generation
    }

    private func state(for value: TodayWeatherValue) -> TodayWeatherState {
        if value.condition != nil
            || value.highTemperatureCelsius != nil
            || value.lowTemperatureCelsius != nil
            || value.attributionURL != nil {
            return .availableDetails(
                temperatureCelsius: value.temperatureCelsius,
                location: value.location,
                updatedAt: value.updatedAt,
                condition: value.condition,
                highTemperatureCelsius: value.highTemperatureCelsius,
                lowTemperatureCelsius: value.lowTemperatureCelsius,
                attributionURL: value.attributionURL
            )
        }
        return .available(
            temperatureCelsius: value.temperatureCelsius,
            location: value.location,
            updatedAt: value.updatedAt
        )
    }
}

public struct UnavailableTodayWeatherProvider: TodayWeatherProviding {
    public init() {}

    public func weather(for coordinate: TodayWeatherCoordinate) async throws -> TodayWeatherValue {
        throw TodayWeatherModelError.unavailable
    }
}

@MainActor
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
        let todayForecast = weather.dailyForecast.first
        return TodayWeatherValue(
            temperatureCelsius: Int(celsius.rounded()),
            location: "",
            updatedAt: clock(),
            condition: weather.currentWeather.condition.description,
            highTemperatureCelsius: todayForecast.map {
                Int($0.highTemperature.converted(to: .celsius).value.rounded())
            },
            lowTemperatureCelsius: todayForecast.map {
                Int($0.lowTemperature.converted(to: .celsius).value.rounded())
            },
            attributionURL: "https://weatherkit.apple.com/legal-attribution.html"
        )
    }
}

/// Serializes the one-shot CoreLocation continuation. CLLocationManager can
/// deliver denial, failure, and cancellation on different turns, so reserving
/// the request before installing its continuation prevents a later caller
/// from orphaning the first waiter.
final class CoreLocationRequestCoordinator: @unchecked Sendable {
    private let lock = NSLock()
    private var isReserved = false
    private var wasCancelled = false
    private var continuation: CheckedContinuation<TodayWeatherCoordinate, Error>?

    var hasPendingRequest: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isReserved
    }

    func currentCoordinate(
        onRequest: @escaping @Sendable () -> Void
    ) async throws -> TodayWeatherCoordinate {
        try Task.checkCancellation()
        guard reserve() else { throw TodayWeatherModelError.unavailable }

        return try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                guard install(continuation) else {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                onRequest()
            }
        }, onCancel: {
            self.cancel()
        })
    }

    func finish(_ result: Result<TodayWeatherCoordinate, Error>) {
        let continuation = takeContinuation()
        continuation?.resume(with: result)
    }

    private func reserve() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !isReserved else { return false }
        isReserved = true
        wasCancelled = false
        return true
    }

    private func install(_ continuation: CheckedContinuation<TodayWeatherCoordinate, Error>) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard isReserved, !wasCancelled else {
            isReserved = false
            wasCancelled = false
            return false
        }
        self.continuation = continuation
        return true
    }

    private func cancel() {
        lock.lock()
        guard isReserved else {
            lock.unlock()
            return
        }
        wasCancelled = true
        let continuation = self.continuation
        self.continuation = nil
        if continuation != nil {
            isReserved = false
            wasCancelled = false
        }
        lock.unlock()
        continuation?.resume(throwing: CancellationError())
    }

    private func takeContinuation() -> CheckedContinuation<TodayWeatherCoordinate, Error>? {
        lock.lock()
        defer { lock.unlock() }
        guard isReserved, let continuation else { return nil }
        self.continuation = nil
        isReserved = false
        wasCancelled = false
        return continuation
    }
}

@MainActor
public final class CoreLocationTodayProvider: NSObject, CLLocationManagerDelegate, TodayLocationProviding {
    private let manager: CLLocationManager
    private let requestCoordinator = CoreLocationRequestCoordinator()

    public override init() {
        manager = CLLocationManager()
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    public func currentCoordinate() async throws -> TodayWeatherCoordinate {
        try await requestCoordinator.currentCoordinate { [weak self] in
            Task { @MainActor [weak self] in
                self?.requestCoordinate()
            }
        }
    }

    public func requestAuthorization() {
        guard manager.authorizationStatus == .notDetermined else { return }
        manager.requestWhenInUseAuthorization()
    }

    nonisolated static func permissionError(for authorizationStatus: CLAuthorizationStatus) -> TodayWeatherModelError? {
        switch authorizationStatus {
        case .denied, .restricted:
            .permissionDenied
        default:
            nil
        }
    }

    nonisolated public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        // Core Location invokes its delegate on a framework-managed queue. Hop
        // back to the provider's MainActor before touching CLLocationManager;
        // the request coordinator itself remains thread-safe and is only used
        // directly by the data callbacks below.
        Task { @MainActor [weak self] in
            self?.requestCoordinate()
        }
    }

    nonisolated public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        requestCoordinator.finish(.success(
            TodayWeatherCoordinate(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude
            )
        ))
    }

    nonisolated public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        requestCoordinator.finish(.failure(error))
    }

    private func requestCoordinate() {
        guard requestCoordinator.hasPendingRequest else { return }
        if let error = Self.permissionError(for: manager.authorizationStatus) {
            requestCoordinator.finish(.failure(error))
            return
        }
        switch manager.authorizationStatus {
        case .authorized, .authorizedAlways:
            manager.requestLocation()
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        default:
            requestCoordinator.finish(.failure(TodayWeatherModelError.permissionDenied))
        }
    }
}
#endif
