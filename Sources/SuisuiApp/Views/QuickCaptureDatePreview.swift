import SuisuiCore
import SwiftUI

struct QuickCaptureDatePreview: View {
    @Binding var capture: QuickCaptureDraft
    let accessibilityPrefix: String

    var body: some View {
        if let dueDate = capture.dueDate {
            LabeledContent("Task title", value: capture.draft.title)
                .font(.caption)
                .lineLimit(2)
                .accessibilityIdentifier("\(accessibilityPrefix)-title-preview")
            HStack {
                DatePicker("Due date", selection: Binding(
                    get: { capture.dueDate ?? dueDate },
                    set: { capture.setDueDate($0) }
                ))
                .datePickerStyle(.compact)
                .accessibilityIdentifier("\(accessibilityPrefix)-due-date-preview")

                Button("Remove due date", systemImage: "xmark.circle") {
                    capture.removeInferredDueDate()
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .help("Remove due date")
                .accessibilityIdentifier("\(accessibilityPrefix)-remove-due-date")
            }
            .font(.caption)
        }
    }
}
