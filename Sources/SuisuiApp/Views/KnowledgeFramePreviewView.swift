import SwiftUI

struct KnowledgeFramePreview: Identifiable {
    let id: Int64
    let name: String
    let content: String
}

struct KnowledgeFramePreviewView: View {
    let preview: KnowledgeFramePreview
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(preview.name).font(.title2).textSelection(.enabled)
                Spacer()
                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("knowledge-preview-close")
            }
            Text("Local knowledge preview")
                .font(.caption).foregroundStyle(.secondary)
            Divider()
            ScrollView {
                Text(preview.content)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityIdentifier("knowledge-preview-content")
        }
        .padding(20)
        .frame(minWidth: 480, idealWidth: 620, minHeight: 320, idealHeight: 480)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("knowledge-preview")
    }
}
