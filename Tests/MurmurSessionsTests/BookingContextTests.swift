import Foundation
import MurmurSessions
import Testing

struct BookingContextTests {
    @Test func bookingAnswersAreLabelledAsWrittenBeforeTheMeeting() {
        var session = MeetingSession(id: "booked", title: "Intro call: Jo and Ada", startedAt: Date(), engine: "Apple Speech")
        session.booking = BookingContext(eventType: "Intro call", guestName: "Ada", guestEmail: "ada@example.invalid", answers: [
            .init(question: "What would you like to cover?", answer: "Pricing for a team of 12"),
            .init(question: "Company", answer: "  "),
        ])
        let source = MeetingNotes.source(session: session, bullets: [], segments: [])
        #expect(source.contains("Booked by: Ada (Intro call)"))
        #expect(source.contains("written before the meeting, not said in it"))
        #expect(source.contains("- What would you like to cover?: Pricing for a team of 12"))
        #expect(!source.contains("Company"))
    }

    @Test func manifestsWithoutBookingStillDecodeAndBookingRoundTrips() throws {
        var session = MeetingSession(id: "booked", title: "Intro", startedAt: Date(timeIntervalSince1970: 1_800_000_000), engine: "Apple Speech")
        let earlier = try JSONEncoder().encode(session)
        #expect(!String(decoding: earlier, as: UTF8.self).contains("booking"))
        #expect(try JSONDecoder().decode(MeetingSession.self, from: earlier).booking == nil)
        session.booking = BookingContext(eventType: "Intro call", guestName: "Ada", answers: [.init(question: "Topic", answer: "Pricing")])
        let decoded = try JSONDecoder().decode(MeetingSession.self, from: try JSONEncoder().encode(session))
        #expect(decoded.booking == session.booking)
    }
}
