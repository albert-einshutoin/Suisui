import Foundation

/// Geometry-only window state. Content, credentials, transcripts, approval
/// tokens, and terminal state intentionally have no representation here.
public struct ProjectBoardWindowFrame: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public func sanitized(visibleFrames: [ProjectBoardWindowFrame]) -> ProjectBoardWindowFrame {
        guard let fallbackScreen = visibleFrames.first else {
            return Self.defaultFrame
        }

        let targetScreen = visibleFrames
            .map { ($0, intersectionArea(with: $0)) }
            .max { lhs, rhs in lhs.1 < rhs.1 }

        guard let targetScreen, targetScreen.1 > 0 else {
            return Self.defaultFrame.centered(in: fallbackScreen)
        }

        let screen = targetScreen.0
        let safeWidth = min(max(width, Self.minimumWidth), screen.width)
        let safeHeight = min(max(height, Self.minimumHeight), screen.height)
        let safeX = min(max(x, screen.x), screen.x + screen.width - safeWidth)
        let safeY = min(max(y, screen.y), screen.y + screen.height - safeHeight)
        return ProjectBoardWindowFrame(x: safeX, y: safeY, width: safeWidth, height: safeHeight)
    }

    public static let minimumWidth = 960.0
    public static let minimumHeight = 640.0
    public static let defaultFrame = ProjectBoardWindowFrame(x: 0, y: 0, width: 1_180, height: 760)

    private func intersectionArea(with other: ProjectBoardWindowFrame) -> Double {
        let intersectionWidth = max(0, min(x + width, other.x + other.width) - max(x, other.x))
        let intersectionHeight = max(0, min(y + height, other.y + other.height) - max(y, other.y))
        return intersectionWidth * intersectionHeight
    }

    private func centered(in screen: ProjectBoardWindowFrame) -> ProjectBoardWindowFrame {
        let safeWidth = min(width, screen.width)
        let safeHeight = min(height, screen.height)
        return ProjectBoardWindowFrame(
            x: screen.x + (screen.width - safeWidth) / 2,
            y: screen.y + (screen.height - safeHeight) / 2,
            width: safeWidth,
            height: safeHeight
        )
    }
}

public struct ProjectBoardWindowPresentationState: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public let version: Int
    public var frame: ProjectBoardWindowFrame

    public init(frame: ProjectBoardWindowFrame, version: Int = currentVersion) {
        self.version = version
        self.frame = frame
    }

    public static func decodeCurrent(from data: Data) -> ProjectBoardWindowPresentationState? {
        guard let state = try? JSONDecoder().decode(Self.self, from: data),
              state.version == currentVersion else {
            return nil
        }
        return state
    }
}
