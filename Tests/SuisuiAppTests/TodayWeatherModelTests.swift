import Combine
import XCTest
@testable import Suisui
import SuisuiCore
#if canImport(CoreLocation)
import CoreLocation
#endif

final class TodayWeatherModelTests: XCTestCase {
    @MainActor
    func testManualCityLoadsWeatherWithoutRequestingLocation() async {
        let weather = RecordingWeatherProvider()
        let location = RecordingLocationProvider()
        let model = TodayWeatherModel(
            preferenceProvider: { .manual(cityLabel: "Tokyo", latitude: 35.6, longitude: 139.7) },
            weatherProvider: weather,
            locationProvider: location
        )

        await model.refresh()

        XCTAssertEqual(model.state, .available(temperatureCelsius: 23, location: "Tokyo", updatedAt: weather.updatedAt))
        XCTAssertEqual(weather.coordinates, [TodayWeatherCoordinate(latitude: 35.6, longitude: 139.7)])
        XCTAssertEqual(location.requestCount, 0)
    }

    @MainActor
    func testCurrentLocationDeniedIsDistinguishedFromPendingAuthorization() async {
        let model = TodayWeatherModel(
            preferenceProvider: { .currentLocation },
            weatherProvider: RecordingWeatherProvider(),
            locationProvider: RecordingLocationProvider(error: TodayWeatherModelError.permissionDenied)
        )

        await model.refresh()

        XCTAssertEqual(model.state, .permissionDenied)
    }

    @MainActor
    func testUnsetLocationDoesNotContactProviders() async {
        let weather = RecordingWeatherProvider()
        let location = RecordingLocationProvider()
        let model = TodayWeatherModel(
            preferenceProvider: { .unset },
            weatherProvider: weather,
            locationProvider: location
        )

        await model.refresh()

        XCTAssertEqual(model.state, .notConfigured)
        XCTAssertTrue(weather.coordinates.isEmpty)
        XCTAssertEqual(location.requestCount, 0)
    }

    @MainActor
    func testFailedRefreshRetainsSessionCacheWithoutPersistingLocationHistory() async {
        let weather = SequenceWeatherProvider(values: [
            .success(TodayWeatherValue(temperatureCelsius: 23, location: "Tokyo", updatedAt: Date(timeIntervalSince1970: 100))),
            .failure(TodayWeatherModelError.unavailable)
        ])
        let model = TodayWeatherModel(
            preferenceProvider: { .manual(cityLabel: "Tokyo", latitude: 35.6, longitude: 139.7) },
            weatherProvider: weather,
            locationProvider: RecordingLocationProvider()
        )

        await model.refresh()
        await model.refresh()

        XCTAssertEqual(model.state, .available(temperatureCelsius: 23, location: "Tokyo", updatedAt: Date(timeIntervalSince1970: 100)))
        XCTAssertEqual(weather.requestCount, 2)
    }

    @MainActor
    func testRefreshKeepsCachedWeatherVisibleWhileNewRequestIsPending() async {
        let weather = DeferredWeatherProvider()
        let model = TodayWeatherModel(
            preferenceProvider: { .manual(cityLabel: "Tokyo", latitude: 35.6, longitude: 139.7) },
            weatherProvider: weather,
            locationProvider: RecordingLocationProvider()
        )

        let first = Task { @MainActor in await model.refresh() }
        await weather.waitForRequestCount(1)
        await weather.resolveRequest(
            at: 0,
            with: TodayWeatherValue(temperatureCelsius: 23, location: "Tokyo", updatedAt: Date(timeIntervalSince1970: 100))
        )
        await first.value

        let second = Task { @MainActor in await model.refresh() }
        await weather.waitForRequestCount(2)
        XCTAssertEqual(
            model.state,
            .available(temperatureCelsius: 23, location: "Tokyo", updatedAt: Date(timeIntervalSince1970: 100))
        )

        await weather.resolveRequest(
            at: 0,
            with: TodayWeatherValue(temperatureCelsius: 24, location: "Tokyo", updatedAt: Date(timeIntervalSince1970: 200))
        )
        await second.value
    }

    @MainActor
    func testNewerWeatherRefreshKeepsItsLocationWhenOlderRequestFinishesLast() async throws {
        let weather = DeferredWeatherProvider()
        let preference = MutableWeatherPreference(
            .manual(cityLabel: "Tokyo", latitude: 35.6, longitude: 139.7)
        )
        let model = TodayWeatherModel(
            preferenceProvider: { preference.value },
            weatherProvider: weather,
            locationProvider: RecordingLocationProvider()
        )

        let olderRefresh = Task { @MainActor in await model.refresh() }
        await weather.waitForRequestCount(1)
        preference.value = .manual(cityLabel: "Osaka", latitude: 34.7, longitude: 135.5)
        let newerRefresh = Task { @MainActor in await model.refresh() }
        await weather.waitForRequestCount(2)

        await weather.resolveRequest(
            at: 1,
            with: TodayWeatherValue(
                temperatureCelsius: 24,
                location: "Osaka",
                updatedAt: Date(timeIntervalSince1970: 200)
            )
        )
        await weather.resolveRequest(
            at: 0,
            with: TodayWeatherValue(
                temperatureCelsius: 23,
                location: "Tokyo",
                updatedAt: Date(timeIntervalSince1970: 100)
            )
        )
        await olderRefresh.value
        await newerRefresh.value

        XCTAssertEqual(
            model.state,
            .available(
                temperatureCelsius: 24,
                location: "Osaka",
                updatedAt: Date(timeIntervalSince1970: 200)
            )
        )
    }

    @MainActor
    func testWeatherSettingsNotificationReloadsTodayWeather() async {
        let center = NotificationCenter()
        let weather = SequenceWeatherProvider(values: [
            .success(TodayWeatherValue(temperatureCelsius: 23, location: "Tokyo", updatedAt: Date(timeIntervalSince1970: 100))),
            .success(TodayWeatherValue(temperatureCelsius: 24, location: "Osaka", updatedAt: Date(timeIntervalSince1970: 200))),
        ])
        let preference = WeatherPreferenceBox(
            .manual(cityLabel: "Tokyo", latitude: 35.6, longitude: 139.7)
        )
        let model = TodayWeatherModel(
            preferenceProvider: { preference.value },
            weatherProvider: weather,
            locationProvider: RecordingLocationProvider()
        )
        let observer = AppRuntimeFactory.observeTodayWeatherSettingsChanges(
            for: model,
            notificationCenter: center
        )
        defer { center.removeObserver(observer) }
        await model.refresh()
        preference.value = .manual(cityLabel: "Osaka", latitude: 34.7, longitude: 135.5)
        let reloaded = expectation(description: "Weather state uses the saved location")
        let cancellable = model.$state.dropFirst().sink { state in
            if state == .available(
                temperatureCelsius: 24,
                location: "Osaka",
                updatedAt: Date(timeIntervalSince1970: 200)
            ) {
                reloaded.fulfill()
            }
        }

        center.post(name: .suisuiWeatherLocationDidChange, object: nil)

        await fulfillment(of: [reloaded], timeout: 1)
        withExtendedLifetime(cancellable) {}
        XCTAssertEqual(weather.requestCount, 2)
    }

#if canImport(CoreLocation)
    func testCoreLocationDeniedAndRestrictedMapToPermissionDenied() {
        XCTAssertEqual(CoreLocationTodayProvider.permissionError(for: .denied), .permissionDenied)
        XCTAssertEqual(CoreLocationTodayProvider.permissionError(for: .restricted), .permissionDenied)
        XCTAssertNil(CoreLocationTodayProvider.permissionError(for: .authorized))
    }

    func testCoreLocationCoordinatorRejectsConcurrentRequestAndResumesOriginal() async throws {
        let coordinator = CoreLocationRequestCoordinator()
        let requested = expectation(description: "first request started")
        let expected = TodayWeatherCoordinate(latitude: 35.6, longitude: 139.7)
        let first = Task {
            try await coordinator.currentCoordinate {
                requested.fulfill()
            }
        }

        await fulfillment(of: [requested], timeout: 1)
        do {
            _ = try await coordinator.currentCoordinate {}
            XCTFail("A second request must not replace the pending continuation")
        } catch let error as TodayWeatherModelError {
            XCTAssertEqual(error, .unavailable)
        }

        coordinator.finish(.success(expected))
        let result = try await first.value
        XCTAssertEqual(result, expected)
        XCTAssertFalse(coordinator.hasPendingRequest)
    }

    func testCoreLocationCoordinatorResumesPermissionDeniedRequest() async {
        let coordinator = CoreLocationRequestCoordinator()
        let requested = expectation(description: "request started")
        let waiting = Task {
            try await coordinator.currentCoordinate {
                requested.fulfill()
            }
        }

        await fulfillment(of: [requested], timeout: 1)
        coordinator.finish(.failure(TodayWeatherModelError.permissionDenied))

        do {
            _ = try await waiting.value
            XCTFail("A denied authorization result must resume the request")
        } catch let error as TodayWeatherModelError {
            XCTAssertEqual(error, .permissionDenied)
        } catch {
            XCTFail("Unexpected permission error: \(error)")
        }
        XCTAssertFalse(coordinator.hasPendingRequest)
    }

    func testCoreLocationCoordinatorCancellationReleasesPendingContinuation() async {
        let coordinator = CoreLocationRequestCoordinator()
        let requested = expectation(description: "request started")
        let waiting = Task {
            try await coordinator.currentCoordinate {
                requested.fulfill()
            }
        }

        await fulfillment(of: [requested], timeout: 1)
        waiting.cancel()

        do {
            _ = try await waiting.value
            XCTFail("Cancellation must resume the request continuation")
        } catch is CancellationError {
            // Expected: cancellation must not leave CoreLocation request waiters suspended.
        } catch {
            XCTFail("Unexpected cancellation error: \(error)")
        }
        XCTAssertFalse(coordinator.hasPendingRequest)
    }
#endif
}

@MainActor
private final class WeatherPreferenceBox {
    var value: WeatherLocationPreference

    init(_ value: WeatherLocationPreference) {
        self.value = value
    }
}

private final class RecordingWeatherProvider: TodayWeatherProviding, @unchecked Sendable {
    let updatedAt = Date(timeIntervalSince1970: 1_700_000_000)
    private(set) var coordinates: [TodayWeatherCoordinate] = []

    func weather(for coordinate: TodayWeatherCoordinate) async throws -> TodayWeatherValue {
        coordinates.append(coordinate)
        return TodayWeatherValue(temperatureCelsius: 23, location: "Tokyo", updatedAt: updatedAt)
    }
}

private final class SequenceWeatherProvider: TodayWeatherProviding, @unchecked Sendable {
    private let values: [Result<TodayWeatherValue, Error>]
    private(set) var requestCount = 0

    init(values: [Result<TodayWeatherValue, Error>]) {
        self.values = values
    }

    func weather(for coordinate: TodayWeatherCoordinate) async throws -> TodayWeatherValue {
        defer { requestCount += 1 }
        let result = values[min(requestCount, values.count - 1)]
        return try result.get()
    }
}

private actor DeferredWeatherProvider: TodayWeatherProviding {
    private var continuations: [CheckedContinuation<TodayWeatherValue, Error>] = []
    private var requestCount = 0

    func weather(for coordinate: TodayWeatherCoordinate) async throws -> TodayWeatherValue {
        requestCount += 1
        return try await withCheckedThrowingContinuation { continuation in
            continuations.append(continuation)
        }
    }

    func waitForRequestCount(_ expectedCount: Int) async {
        while requestCount < expectedCount {
            // A pure yield can keep this actor scheduled indefinitely and
            // starve the MainActor task that must enter `weather(for:)`.
            // Sleeping briefly gives the producer a scheduling opportunity
            // while keeping the helper deterministic and CPU-light.
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
    }

    func resolveRequest(at index: Int, with value: TodayWeatherValue) {
        continuations.remove(at: index).resume(returning: value)
    }
}

@MainActor
private final class MutableWeatherPreference {
    var value: WeatherLocationPreference

    init(_ value: WeatherLocationPreference) {
        self.value = value
    }
}

private final class RecordingLocationProvider: TodayLocationProviding, @unchecked Sendable {
    let error: Error?
    private(set) var requestCount = 0

    init(error: Error? = nil) {
        self.error = error
    }

    @MainActor
    func currentCoordinate() async throws -> TodayWeatherCoordinate {
        requestCount += 1
        if let error { throw error }
        return TodayWeatherCoordinate(latitude: 35.6, longitude: 139.7)
    }
}
