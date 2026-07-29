import SuisuiCore
import SwiftUI

/// The understanding surface intentionally renders only typed presentation
/// data. It is never a provider-output viewer and it offers a Queue handoff,
/// not a second execution route.
struct VoiceTaskConversationUnderstandingView: View {
    let presentation: VoiceTaskConversationWorkspacePresentation
    let isCompact: Bool
    let onOpenAssistantQueue: () -> Void

    var body: some View {
        Group {
            if isCompact {
                DisclosureGroup("Understanding") {
                    understandingContent
                        .padding(.top, SuisuiSpacing.sm)
                }
            } else {
                VStack(alignment: .leading, spacing: SuisuiSpacing.md) {
                    Label("Understanding", systemImage: "text.magnifyingglass")
                        .font(.headline)
                    understandingContent
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .soloCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("voice-conversation-understanding")
    }

    @ViewBuilder
    private var understandingContent: some View {
        if let target = presentation.resolvedTarget {
            VStack(alignment: .leading, spacing: SuisuiSpacing.xs) {
                Label("Resolved target", systemImage: "scope")
                    .font(.subheadline.weight(.semibold))
                Text(verbatim: target.title)
                    .font(.body)
                Text(verbatim: target.reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("voice-conversation-resolved-target")
            .accessibilityLabel("Resolved target")
            .accessibilityValue("\(presentation.resolvedTarget?.title ?? ""). \(presentation.resolutionReason)")
        }

        if let proposal = presentation.proposal {
            VStack(alignment: .leading, spacing: SuisuiSpacing.xs) {
                Label(
                    proposal.requiresApproval ? "Proposal needs approval" : "Proposal",
                    systemImage: proposal.requiresApproval ? "checkmark.shield" : "list.bullet.clipboard"
                )
                .font(.subheadline.weight(.semibold))

                Text(verbatim: proposal.summary)
                    .fixedSize(horizontal: false, vertical: true)

                ForEach(Array(proposal.actionTitles.enumerated()), id: \.offset) { _, title in
                    Label(title, systemImage: "arrow.right.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("voice-conversation-proposal")
        }

        if !presentation.factCandidates.isEmpty {
            VStack(alignment: .leading, spacing: SuisuiSpacing.xs) {
                Label("Fact candidates", systemImage: "lightbulb")
                    .font(.subheadline.weight(.semibold))
                ForEach(presentation.factCandidates) { fact in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: fact.preview)
                            .font(.caption)
                        Text("\(fact.stateLabel) · \(fact.sourceLabel)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Fact candidate")
                    .accessibilityValue("\(fact.preview). \(fact.stateLabel). \(fact.sourceLabel)")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("voice-conversation-fact-candidates")
        }

        if let handoff = presentation.queueHandoff {
            VStack(alignment: .leading, spacing: SuisuiSpacing.xs) {
                Label("Assistant Queue handoff", systemImage: "tray.full")
                    .font(.subheadline.weight(.semibold))
                Text(verbatim: handoff.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Status: \(handoff.stateLabel)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button(action: onOpenAssistantQueue) {
                    Label("Open Assistant Queue", systemImage: "arrow.right.square")
                }
                .accessibilityHint("Opens the focused item for the existing approval flow. It does not execute this work.")
                .accessibilityIdentifier(
                    "voice-conversation-open-assistant-queue"
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("voice-conversation-queue-handoff")
        }
    }
}

private extension VoiceTaskConversationWorkspacePresentation {
    var resolutionReason: String {
        resolvedTarget?.reason ?? ""
    }
}
