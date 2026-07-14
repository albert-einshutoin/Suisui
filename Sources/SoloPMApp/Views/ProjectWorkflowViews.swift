import Foundation
import SoloPMCore
import SwiftUI
import UniformTypeIdentifiers

struct ProjectBoardSidebarDestinationRow: View {
    let destination: ProjectBoardSidebarDestination
    let count: Int

    var body: some View {
        Label {
            HStack(spacing: 8) {
                Text(LocalizedStringKey(destination.title))
                    .lineLimit(1)
                    // The destination name wins layout negotiation so the
                    // trailing count badge can never force it to truncate.
                    .layoutPriority(1)
                Spacer(minLength: 8)
                Text("\(count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        } icon: {
            Image(systemName: destination.systemImage)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(destination.accessibilityLabel(count: count))
        .accessibilityIdentifier("sidebar-destination-\(destination.accessibilityIdentifierSuffix)")
    }
}
