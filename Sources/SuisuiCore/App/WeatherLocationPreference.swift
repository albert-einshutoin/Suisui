import Foundation

/// User-selected weather source. Precise current-location coordinates are
/// intentionally not persisted; only a manual city may carry a coarse center
/// coordinate required by the provider.
public enum WeatherLocationPreference: Codable, Equatable, Sendable {
    case unset
    case currentLocation
    case manual(cityLabel: String, latitude: Double, longitude: Double)

    private enum CodingKeys: String, CodingKey {
        case kind
        case cityLabel
        case latitude
        case longitude
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(String.self, forKey: .kind) {
        case "unset":
            self = .unset
        case "currentLocation":
            self = .currentLocation
        case "manual":
            self = .manual(
                cityLabel: try container.decode(String.self, forKey: .cityLabel),
                latitude: try container.decode(Double.self, forKey: .latitude),
                longitude: try container.decode(Double.self, forKey: .longitude)
            ).normalized
            guard case .manual = self else {
                throw DecodingError.dataCorruptedError(forKey: .kind, in: container, debugDescription: "Invalid manual weather location")
            }
        default:
            throw DecodingError.dataCorruptedError(forKey: .kind, in: container, debugDescription: "Unknown weather location kind")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch normalized {
        case .unset:
            try container.encode("unset", forKey: .kind)
        case .currentLocation:
            try container.encode("currentLocation", forKey: .kind)
        case let .manual(cityLabel, latitude, longitude):
            try container.encode("manual", forKey: .kind)
            try container.encode(cityLabel, forKey: .cityLabel)
            try container.encode(latitude, forKey: .latitude)
            try container.encode(longitude, forKey: .longitude)
        }
    }

    public var normalized: WeatherLocationPreference {
        switch self {
        case .unset, .currentLocation:
            return self
        case let .manual(cityLabel, latitude, longitude):
            let label = String(cityLabel.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
            guard !label.isEmpty,
                  latitude.isFinite,
                  longitude.isFinite,
                  (-90...90).contains(latitude),
                  (-180...180).contains(longitude) else {
                return .unset
            }
            return .manual(cityLabel: label, latitude: latitude, longitude: longitude)
        }
    }

    public var shouldAsk: Bool {
        if case .unset = normalized { return true }
        return false
    }

    public var displayLabel: String {
        switch normalized {
        case .unset:
            "Not configured"
        case .currentLocation:
            "Current location"
        case let .manual(cityLabel, _, _):
            cityLabel
        }
    }

    /// A process-local cache key. Coordinates are used only to avoid showing
    /// a previous city's value after the preference changes; this key is never
    /// persisted, logged, or exposed in the dashboard presentation model.
    public var sessionCacheKey: String {
        switch normalized {
        case .unset:
            "unset"
        case .currentLocation:
            "current-location"
        case let .manual(cityLabel, latitude, longitude):
            "manual|\(cityLabel)|\(latitude)|\(longitude)"
        }
    }
}
