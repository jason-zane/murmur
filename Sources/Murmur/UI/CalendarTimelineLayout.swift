import Foundation

/// Allocate columns inside each connected overlap group, including the visible
/// footprint of short appointments. Unrelated meetings retain the full day width.
enum CalendarTimelineLayout {
    struct Interval: Equatable {
        let id: String
        let start: Double
        let end: Double
    }
    struct Placement: Equatable {
        let id: String
        let start: Double
        let end: Double
        let lane: Int
        let columns: Int
    }
    static func place(_ intervals: [Interval], minimumDuration: Double, dayLength: Double = 1440) -> [Placement] {
        let sorted = intervals.map {
            let start = max(0, min(dayLength, $0.start))
            return Interval(id: $0.id, start: start, end: min(dayLength, max($0.end, start + minimumDuration)))
        }.filter { $0.start < $0.end }.sorted {
            if $0.start != $1.start { return $0.start < $1.start }
            if $0.end != $1.end { return $0.end > $1.end }
            return $0.id < $1.id
        }
        var result: [Placement] = [], group: [(Interval, Int)] = [], laneEnds: [Double] = []
        var groupEnd = -Double.infinity
        func finishGroup() {
            result += group.map { Placement(id: $0.0.id, start: $0.0.start, end: $0.0.end, lane: $0.1, columns: laneEnds.count) }
            group.removeAll(); laneEnds.removeAll()
        }
        for interval in sorted {
            if interval.start >= groupEnd { finishGroup(); groupEnd = interval.end }
            let lane = laneEnds.firstIndex { $0 <= interval.start } ?? laneEnds.count
            if lane == laneEnds.count { laneEnds.append(interval.end) } else { laneEnds[lane] = interval.end }
            group.append((interval, lane)); groupEnd = max(groupEnd, interval.end)
        }
        finishGroup()
        return result
    }
}
