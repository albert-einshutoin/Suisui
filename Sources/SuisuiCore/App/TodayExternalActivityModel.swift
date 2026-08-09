import Foundation

/// A provider-payload-free row that Today can render without reading a
/// connector. Its strings come only from the sanitized integration snapshot.
public struct TodayExternalActivitySummaryRow: Equatable, Identifiable, Sendable {
    public let id: String
    public let service: TodayIntegrationService
    public let title: String
    public let detail: String
    public let accessibilityLabel: String
}

/// Read-only Calendar and Slack activity summaries for the Today review area.
/// The model deliberately stores neither provider response bodies nor tokens.
public struct TodayExternalActivityModel: Equatable, Sendable {
    public let rows: [TodayExternalActivitySummaryRow]

    public static let empty = TodayExternalActivityModel(rows: [])
}

public enum TodayExternalActivityModelBuilder {
    public static func make(integrations: TodayIntegrationsSnapshot) -> TodayExternalActivityModel {
        TodayExternalActivityModel(
            rows: [
                summaryRow(id: "today-external-activity-calendar", snapshot: integrations.calendar),
                summaryRow(id: "today-external-activity-slack", snapshot: integrations.slack),
            ].compactMap { $0 }
        )
    }

    private static func summaryRow(
        id: String,
        snapshot: TodayIntegrationSnapshot
    ) -> TodayExternalActivitySummaryRow? {
        // Connection/readiness is not activity. Render a row only after a
        // successful read (or a stale prior read) has supplied a count/time;
        // this prevents the Review card from pretending that a provider
        // connection is an external update feed.
        switch snapshot.state {
        case .synced:
            break
        case let .failed(lastSyncedAt, _, _):
            guard lastSyncedAt != nil else { return nil }
        default:
            return nil
        }
        return TodayExternalActivitySummaryRow(
            id: id,
            service: snapshot.service,
            title: snapshot.title,
            detail: snapshot.detail,
            accessibilityLabel: snapshot.accessibilityLabel
        )
    }
}
