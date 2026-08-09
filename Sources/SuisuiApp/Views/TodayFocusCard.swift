import SuisuiCore
import SwiftUI

struct TodayFocusCard: View {
    @ObservedObject var session: TodayFocusSessionStore
    let tasks: [TodayTaskRowSnapshot]
    let suggestedTaskID: Int64?
    let openInspector: (Int64) -> Void

    @State private var durationMinutes = 25
    @State private var showsReplacementConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: SuisuiSpacing.sm) {
            Label("Focus", systemImage: "target")
                .font(SuisuiTypography.sectionTitle)
            Text(timeLabel)
                .font(.title2.monospacedDigit().weight(.semibold))
            Text(stateLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
            if let taskTitle {
                Text(taskTitle)
                    .font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Picker("Duration", selection: $durationMinutes) {
                Text("25 min").tag(25)
                Text("50 min").tag(50)
                Text("90 min").tag(90)
            }
            .pickerStyle(.segmented)
            .disabled(session.record.state == .running || session.record.state == .paused)
            Stepper("Custom duration: \(durationMinutes) min", value: $durationMinutes, in: 1...240)
                .disabled(session.record.state == .running || session.record.state == .paused)
            controls
            if let taskID = session.record.taskID ?? suggestedTaskID {
                Button("Open task") {
                    openInspector(taskID)
                }
                .buttonStyle(.link)
                .accessibilityIdentifier("today-focus-open-task")
            }
        }
        .soloCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("today-focus-card")
        .accessibilityLabel(String(format: String(localized: "Focus: %@. %@ remaining."), stateLabel, timeLabel))
        .alert("Replace active Focus?", isPresented: $showsReplacementConfirmation) {
            Button("Replace", role: .destructive) {
                _ = session.start(taskID: suggestedTaskID, durationSeconds: durationMinutes * 60, replaceExisting: true)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Starting a new Focus ends the active local session. It does not change task status or Calendar.")
        }
        .task {
            _ = session.restore()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                session.tick()
            }
        }
    }

    @ViewBuilder
    private var controls: some View {
        switch session.record.state {
        case .idle, .completed:
            Button("Start Focus") { start() }
                .accessibilityIdentifier("today-focus-start")
        case .running:
            HStack {
                Button("Pause") { _ = session.pause() }
                    .accessibilityIdentifier("today-focus-pause")
                Button("End Focus") { _ = session.end() }
                    .accessibilityIdentifier("today-focus-end")
            }
        case .paused:
            HStack {
                Button("Resume") { _ = session.resume() }
                    .accessibilityIdentifier("today-focus-resume")
                Button("End Focus") { _ = session.end() }
                    .accessibilityIdentifier("today-focus-end")
            }
        }
    }

    private var taskTitle: String? {
        guard let taskID = session.record.taskID ?? suggestedTaskID else { return nil }
        return tasks.first(where: { $0.taskID == taskID })?.title
    }

    private var timeLabel: String {
        let remaining = max(0, session.record.durationSeconds - session.elapsedSeconds)
        return String(format: "%02d:%02d", remaining / 60, remaining % 60)
    }

    private var stateLabel: String {
        switch session.record.state {
        case .idle: String(localized: "Ready to focus")
        case .running: String(localized: "Focus in progress")
        case .paused: String(localized: "Focus paused")
        case .completed: String(localized: "Focus complete")
        }
    }

    private func start() {
        if case .failure(.requiresReplacement) = session.start(
            taskID: suggestedTaskID,
            durationSeconds: durationMinutes * 60
        ) {
            showsReplacementConfirmation = true
        }
    }
}
