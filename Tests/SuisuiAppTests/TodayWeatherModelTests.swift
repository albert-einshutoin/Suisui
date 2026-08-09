import XCTest
@testable import Suisui
import SuisuiCore

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
    func testCurrentLocationDeniedBecomesPermissionPending() async {
        let model = TodayWeatherModel(
            preferenceProvider: { .currentLocation },
            weatherProvider: RecordingWeatherProvider(),
            locationProvider: RecordingLocationProvider(error: TodayWeatherModelError.permissionDenied)
        )

        await model.refresh()

        XCTAssertEqual(model.state, .permissionPending)
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

private final class RecordingLocationProvider: TodayLocationProviding, @unchecked Sendable {
    let error: Error?
    private(set) var requestCount = 0

    init(error: Error? = nil) {
        self.error = error
    }

    func currentCoordinate() async throws -> TodayWeatherCoordinate {
        requestCount += 1
        if let error { throw error }
        return TodayWeatherCoordinate(latitude: 35.6, longitude: 139.7)
    }
}
