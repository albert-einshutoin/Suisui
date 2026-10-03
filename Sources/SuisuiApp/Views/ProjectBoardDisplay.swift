import SuisuiCore
import SwiftUI

enum ProjectBoardDisplayMode: String, CaseIterable, Identifiable {
    case overview
    case board
    case list

    var id: String { rawValue }

    var label: String {
        switch self {
        case .overview:
            "Overview"
        case .board:
            "Board"
        case .list:
            "List"
        }
    }

    var systemImage: String {
        switch self {
        case .overview:
            "rectangle.grid.2x2"
        case .board:
            "rectangle.3.group"
        case .list:
            "list.bullet"
        }
    }
}

extension ProjectTaskPriority {
    var color: Color {
        switch self {
        case .low:
            .secondary
        case .medium:
            .orange
        case .high:
            .red
        }
    }
}

extension ProjectTaskStatus {
    var tint: Color {
        switch self {
        case .backlog:
            .secondary
        case .planned:
            .blue
        case .inProgress:
            .purple
        case .blocked:
            .orange
        case .done:
            .green
        }
    }

    var systemImage: String {
        switch self {
        case .backlog:
            "tray"
        case .planned:
            "calendar.badge.clock"
        case .inProgress:
            "arrow.triangle.2.circlepath"
        case .blocked:
            "exclamationmark.octagon"
        case .done:
            "checkmark.circle"
        }
    }

    var previousStatus: ProjectTaskStatus? {
        guard let index = Self.allCases.firstIndex(of: self), index > Self.allCases.startIndex else {
            return nil
        }
        return Self.allCases[Self.allCases.index(before: index)]
    }

    var nextStatus: ProjectTaskStatus? {
        guard let index = Self.allCases.firstIndex(of: self) else {
            return nil
        }
        let nextIndex = Self.allCases.index(after: index)
        guard nextIndex < Self.allCases.endIndex else {
            return nil
        }
        return Self.allCases[nextIndex]
    }
}

extension ProjectPortfolioHealth {
    var tint: Color {
        switch self {
        case .onTrack:
            .green
        case .attention:
            .orange
        case .atRisk:
            .red
        case .completed:
            .blue
        }
    }

    var systemImage: String {
        switch self {
        case .onTrack:
            "checkmark.seal"
        case .attention:
            "exclamationmark.circle"
        case .atRisk:
            "exclamationmark.triangle"
        case .completed:
            "checkmark.circle"
        }
    }
}

extension ArtifactCreatedState {
    var label: String {
        switch self {
        case .expected:
            "Expected"
        case .created:
            "Created"
        case .missing:
            "Missing"
        }
    }

    var systemImage: String {
        switch self {
        case .expected:
            "doc.badge.clock"
        case .created:
            "doc.text.fill"
        case .missing:
            "doc.badge.exclamationmark"
        }
    }

    var tint: Color {
        switch self {
        case .expected:
            .blue
        case .created:
            .green
        case .missing:
            .orange
        }
    }
}

extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
