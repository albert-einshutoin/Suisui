import CoreGraphics
import Foundation
import SuisuiCore

enum ScheduleTimelineGeometry {
    struct OverlapPosition: Equatable {
        let lane: Int
        let groupSize: Int
    }

    static func blockFrame(
        startMinute: Int,
        durationMinutes: Int,
        dayIndex: Int,
        dayCount: Int,
        overlapLane: Int,
        overlapGroupSize: Int,
        gridWidth: CGFloat,
        timeAxisWidth: CGFloat,
        hourHeight: CGFloat
    ) -> CGRect {
        let safeDayCount = max(dayCount, 1)
        let dayWidth = max(0, gridWidth - timeAxisWidth) / CGFloat(safeDayCount)
        let safeGroupSize = max(overlapGroupSize, 1)
        let laneWidth = dayWidth / CGFloat(safeGroupSize)
        let lane = min(max(overlapLane, 0), safeGroupSize - 1)
        let clampedStart = min(max(startMinute, 0), 24 * 60)
        let clampedDuration = min(max(durationMinutes, 15), 24 * 60 - clampedStart)

        return CGRect(
            x: timeAxisWidth + CGFloat(dayIndex) * dayWidth + CGFloat(lane) * laneWidth + 2,
            y: CGFloat(clampedStart) / 60 * hourHeight,
            width: max(1, laneWidth - 4),
            height: max(18, CGFloat(clampedDuration) / 60 * hourHeight)
        )
    }

    static func snappedMinute(at y: CGFloat, hourHeight: CGFloat) -> Int {
        let rawMinute = y / max(hourHeight, 1) * 60
        let snapped = Int((rawMinute / 15).rounded()) * 15
        return min(max(snapped, 0), 24 * 60)
    }

    static func snappedDelta(for translation: CGFloat, hourHeight: CGFloat) -> Int {
        let minutes = snappedMinute(at: abs(translation), hourHeight: hourHeight)
        return translation < 0 ? -minutes : minutes
    }

    static func matchesSearch(_ query: String, values: [String]) -> Bool {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty || values.contains { $0.localizedCaseInsensitiveContains(query) }
    }

    static func allDayEvent(
        _ event: ExternalScheduleEvent,
        occursOn dateKey: String,
        fallback interval: Range<Date>
    ) -> Bool {
        if let startDateKey = event.allDayStartDateKey,
           let endDateKey = event.allDayEndDateKey {
            return startDateKey <= dateKey && dateKey < endDateKey
        }
        return event.endAt > interval.lowerBound && event.startAt < interval.upperBound
    }

    static func eventOccurs(
        _ event: ExternalScheduleEvent,
        on dateKey: String,
        during interval: Range<Date>
    ) -> Bool {
        if event.isAllDay {
            return allDayEvent(event, occursOn: dateKey, fallback: interval)
        }
        return event.endAt > interval.lowerBound && event.startAt < interval.upperBound
    }

    static func overlapPositions(for intervals: [DateInterval]) -> [OverlapPosition] {
        var positions: [OverlapPosition] = []
        for (itemIndex, interval) in intervals.enumerated() {
            let overlappingIndices = intervals.indices.prefix(itemIndex).filter {
                interval.start < intervals[$0].end && intervals[$0].start < interval.end
            }
            let usedLanes = Set(overlappingIndices.map { positions[$0].lane })
            let lane = (0...).first { !usedLanes.contains($0) } ?? 0
            let groupSize = max(1, overlappingIndices.count + 1)
            for index in overlappingIndices {
                positions[index] = OverlapPosition(
                    lane: positions[index].lane,
                    groupSize: max(positions[index].groupSize, groupSize)
                )
            }
            positions.append(OverlapPosition(lane: lane, groupSize: groupSize))
        }
        return positions
    }
}
