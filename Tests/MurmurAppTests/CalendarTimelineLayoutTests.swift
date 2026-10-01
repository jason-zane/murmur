import Testing
@testable import Murmur

struct CalendarTimelineLayoutTests {
    @Test func unrelatedAfternoonMeetingUsesFullWidth() {
        let result = CalendarTimelineLayout.place([
            .init(id: "a", start: 540, end: 600), .init(id: "b", start: 570, end: 630),
            .init(id: "c", start: 1020, end: 1080)
        ], minimumDuration: 15)
        #expect(result.map(\.columns) == [2, 2, 1])
        #expect(result.last?.lane == 0)
    }
    @Test func chainKeepsAlignedColumnsAndReusesFreeLane() {
        let result = CalendarTimelineLayout.place([
            .init(id: "a", start: 0, end: 60), .init(id: "b", start: 30, end: 90), .init(id: "c", start: 60, end: 120)
        ], minimumDuration: 15)
        #expect(result.map(\.lane) == [0, 1, 0])
        #expect(result.allSatisfy { $0.columns == 2 })
    }
    @Test func visibleShortAppointmentsDoNotCoverEachOther() {
        let result = CalendarTimelineLayout.place([
            .init(id: "a", start: 540, end: 545), .init(id: "b", start: 545, end: 550)
        ], minimumDuration: 24)
        #expect(result.map(\.columns) == [2, 2])
        #expect(result.map(\.lane) == [0, 1])
    }
    @Test func equalStartsAreStableAndMidnightIsClipped() {
        let result = CalendarTimelineLayout.place([
            .init(id: "b", start: -60, end: 30), .init(id: "a", start: -20, end: 30),
            .init(id: "late", start: 1435, end: 1500)
        ], minimumDuration: 24)
        #expect(result.map(\.id) == ["a", "b", "late"])
        #expect(result.first?.start == 0)
        #expect(result.last?.end == 1440)
        #expect(result.last?.columns == 1)
    }
}
