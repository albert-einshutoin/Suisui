import Combine
import Foundation

public enum CommandPaletteSearchState: Equatable, Sendable {
    case idle
    case loading
    case loaded([CommandPaletteContentMatch])
    case failed(String)
}

/// Owns asynchronous local search; views render state and forward user intent.
@MainActor
public final class CommandPaletteSearchViewModel: ObservableObject {
    @Published public private(set) var state: CommandPaletteSearchState = .idle
    private let provider: CommandPaletteContentSearch?
    private var requestID = UUID()

    public init(provider: CommandPaletteContentSearch?) {
        self.provider = provider
    }

    public var matches: [CommandPaletteContentMatch] {
        guard case .loaded(let matches) = state else { return [] }
        return matches
    }

    public func reset() {
        requestID = UUID()
        state = .idle
    }

    public func search(query: String, debounceNanoseconds: UInt64 = 150_000_000) async {
        reset()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let provider, trimmed.count >= CommandPaletteComposer.minimumContentSearchQueryLength else { return }
        let currentRequestID = requestID
        state = .loading
        do {
            try await Task.sleep(nanoseconds: debounceNanoseconds)
            try Task.checkCancellation()
            let matches = try await Task.detached { try provider(trimmed) }.value
            guard !Task.isCancelled, requestID == currentRequestID else { return }
            state = .loaded(matches)
        } catch is CancellationError {
            if requestID == currentRequestID { state = .idle }
        } catch {
            guard !Task.isCancelled, requestID == currentRequestID else { return }
            state = .failed(LocalPathRedactor.redact(
                LocalWorkspaceFailureMessage.message(for: error, fallback: String(localized: "Content search failed. Try again."))
            ))
        }
    }
}
