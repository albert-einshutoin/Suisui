import Foundation

public enum TodayWorkloadDiagnostic: Equatable, Sendable {
    case unparseableBlock(id: String)
}

public struct TodayWorkloadSnapshot: Equatable, Sendable {
    public let plannedTaskCount: Int
    public let scheduledMinutes: Int
    public let focusTaskBlockMinutes: Int
    public let plannedMinutes: Int
    public let capacityMinutes: Int
    public let ratio: Double
    public let isOverCapacity: Bool
    public let diagnostics: [TodayWorkloadDiagnostic]

    public init(
        scheduledMinutes: Int,
        focusTaskBlockMinutes: Int,
        capacityMinutes: Int,
        plannedTaskCount: Int = 0,
        diagnostics: [TodayWorkloadDiagnostic] = []
    ) {
        self.plannedTaskCount = plannedTaskCount
        self.scheduledMinutes = scheduledMinutes
        self.focusTaskBlockMinutes = focusTaskBlockMinutes
        plannedMinutes = scheduledMinutes + focusTaskBlockMinutes
        self.capacityMinutes = capacityMinutes
        ratio = Double(plannedMinutes) / Double(capacityMinutes)
        isOverCapacity = plannedMinutes > capacityMinutes
        self.diagnostics = diagnostics
    }

    public init(
        plannedTaskCount: Int,
        dailyCapacityMinutes: Int
    ) {
        self.init(
            scheduledMinutes: 0,
            focusTaskBlockMinutes: 0,
            capacityMinutes: AppSettings.normalizedDailyWorkCapacityMinutes(dailyCapacityMinutes),
            plannedTaskCount: plannedTaskCount
        )
    }

    public var dailyCapacityMinutes: Int { capacityMinutes }
}

public enum TodayWorkloadSnapshotBuilder {
    public static func make(
        timeBlocks: [TodayTimeBlock],
        focusTaskID: Int64?,
        capacityMinutes: Int,
        plannedTaskCount: Int = 0
    ) -> TodayWorkloadSnapshot {
        let formatter = ISO8601DateFormatter()
        var scheduledMinutes = 0
        var focusTaskBlockMinutes = 0
        var diagnostics: [TodayWorkloadDiagnostic] = []

        for block in timeBlocks {
            guard let startAt = block.startAt,
                  let endAt = block.endAt,
                  let start = formatter.date(from: startAt),
                  let end = formatter.date(from: endAt) else {
                diagnostics.append(.unparseableBlock(id: block.id))
                continue
            }
            let minutes = Int(end.timeIntervalSince(start) / 60)
            guard minutes > 0 else {
                diagnostics.append(.unparseableBlock(id: block.id))
                continue
            }
            if block.task.id == focusTaskID {
                focusTaskBlockMinutes += minutes
            } else {
                scheduledMinutes += minutes
            }
        }

        return TodayWorkloadSnapshot(
            scheduledMinutes: scheduledMinutes,
            focusTaskBlockMinutes: focusTaskBlockMinutes,
            capacityMinutes: AppSettings.normalizedDailyWorkCapacityMinutes(capacityMinutes),
            plannedTaskCount: plannedTaskCount,
            diagnostics: diagnostics
        )
    }
}
