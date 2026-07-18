import AppKit
import SwiftUI

@MainActor
struct LocalPathSelectionField: View {
    enum SelectionKind {
        case file
        case directory

        var canChooseFiles: Bool { self == .file }
        var canChooseDirectories: Bool { self == .directory }
    }

    let title: LocalizedStringKey
    @Binding var text: String
    let selectionKind: SelectionKind
    let accessibilityIdentifier: String
    var browseAccessibilityIdentifier: String? = nil
    var baseDirectoryURL: URL?
    var canCreateDirectories = false
    var selectedPath: (URL) -> String = { $0.path }
    var onSelection: (URL) -> Void = { _ in }

    var body: some View {
        HStack(spacing: 8) {
            TextField(title, text: $text)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier(accessibilityIdentifier)

            Button {
                presentOpenPanel()
            } label: {
                Label("Browse…", systemImage: selectionKind == .directory ? "folder" : "doc")
            }
            .accessibilityIdentifier(browseAccessibilityIdentifier ?? "\(accessibilityIdentifier)-browse")
            .accessibilityHint(selectionKind == .directory ? "Choose a folder in Finder." : "Choose a file in Finder.")
        }
    }

    private var initialDirectoryURL: URL? {
        let trimmedPath = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedPath.isEmpty == false else {
            return baseDirectoryURL
        }

        let candidateURL = trimmedPath.hasPrefix("/")
            ? URL(fileURLWithPath: trimmedPath)
            : baseDirectoryURL?.appendingPathComponent(trimmedPath)

        guard let candidateURL else {
            return baseDirectoryURL
        }
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: candidateURL.path, isDirectory: &isDirectory),
           isDirectory.boolValue {
            return candidateURL
        }
        return candidateURL.deletingLastPathComponent()
    }

    private func presentOpenPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = selectionKind.canChooseFiles
        panel.canChooseDirectories = selectionKind.canChooseDirectories
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = canCreateDirectories
        panel.directoryURL = initialDirectoryURL
        panel.prompt = String(localized: "Choose")
        panel.message = selectionKind == .directory
            ? String(localized: "Choose a folder or enter its path directly")
            : String(localized: "Choose a file or enter its path directly")
        panel.begin { response in
            guard response == .OK, let url = panel.url else {
                return
            }
            Task { @MainActor in
                text = selectedPath(url)
                onSelection(url)
            }
        }
    }
}
