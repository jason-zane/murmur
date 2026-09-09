import Testing
@testable import MurmurSessions

@Suite struct SummaryTimestampTests {
    @Test func rejectsTheInventedExampleTimeSeenInALiveShortMeeting() {
        let summary = "## Summary\nA short conversation. [12:34]\n\n- A real question. [0:40]"
        #expect(MeetingNotes.retainingSourceTimestamps(in: summary, times: [0.9359, 2.1959, 39.6359])
            == "## Summary\nA short conversation.\n\n- A real question. [0:40]")
    }

    @Test func preservesExactSourceTimesAndUnicodeText() {
        let summary = "Café opens. [0:13]\nBudget agreed. [1:01:01]\n[Useful notes](https://example.com)"
        #expect(MeetingNotes.retainingSourceTimestamps(in: summary, times: [12.6, 3_661]) == summary)
    }

    @Test func noSourceTimesCannotProduceSourceLinks() {
        #expect(MeetingNotes.retainingSourceTimestamps(in: "Decision [1:00].", times: []) == "Decision.")
    }
}
