import Foundation
import MurmurSessions

/// A debug build can preview an isolated notes directory without activating hotkeys,
/// reading calendars or starting meeting capture. Production launches never opt in.
enum PreviewEnvironment {
    static var root: URL? {
        #if DEBUG
        let environment = ProcessInfo.processInfo.environment
        if environment["MURMUR_UI_TESTING"] == "1",
           let path = environment["MURMUR_SESSIONS_DIR"], path.hasPrefix("/") {
            return URL(fileURLWithPath: path).deletingLastPathComponent()
        }
        #endif
        return nil
    }
    static var isActive: Bool { root != nil }

    /// `MURMUR_PREVIEW_OPEN` names something to raise on launch, so a preview can be
    /// captured without driving the UI: `settings[:tab]`, `onboarding`, or `session:<id>`.
    static var launchAction: String? {
        #if DEBUG
        guard isActive else { return nil }
        return ProcessInfo.processInfo.environment["MURMUR_PREVIEW_OPEN"]
        #else
        return nil
        #endif
    }

    /// The Settings tab named by `launchAction`, lower-cased; "" for the default tab.
    static var opensSettingsTab: String? {
        guard let value = launchAction, value.hasPrefix("settings") else { return nil }
        return value.split(separator: ":").dropFirst().first.map(String.init) ?? ""
    }

    /// A fortnight of example meetings around today, so the Home calendar has something to
    /// show without reading a real calendar. Empty outside preview launches.
    static func sampleEvents(from start: Date, to end: Date) -> [CalendarEvent] {
        guard isActive else { return [] }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let meet = URL(string: "https://meet.google.com/abc-defg-hij")!
        let zoom = URL(string: "https://zoom.us/j/123456789")!
        let samples: [(day: Int, hour: Int, minute: Int, title: String, url: URL?, people: [String])] = [
            (-9, 10, 0, "Roadmap review", meet, ["Sam Ito", "Priya Nair"]),
            (-7, 13, 0, "Customer call · Northwind", zoom, ["Marcus Lee"]),
            (-4, 10, 0, "Team standup", zoom, ["Sam Ito", "Priya Nair", "Marcus Lee"]),
            (-2, 17, 55, "Design review", zoom, ["Priya Nair"]),
            (-1, 7, 29, "15 Minute Meeting <> Sam Ito", meet, ["Sam Ito"]),
            (0, 14, 0, "Product sync", meet, ["Sam Ito", "Priya Nair"]),
            (0, 16, 30, "Design review", zoom, ["Priya Nair", "Marcus Lee"]),
            (3, 9, 30, "Interview · Priya's candidate", zoom, ["Priya Nair"]),
            (4, 11, 0, "Q3 planning", meet, ["Sam Ito", "Priya Nair", "Marcus Lee"]),
            (11, 10, 0, "Board prep", zoom, ["Lena Fischer"]),
        ]
        return samples.compactMap { sample in
            guard let day = calendar.date(byAdding: .day, value: sample.day, to: today) else { return nil }
            let startAt = day.addingTimeInterval(TimeInterval(sample.hour * 3_600 + sample.minute * 60))
            guard startAt >= start, startAt < end else { return nil }
            return CalendarEvent(
                id: "preview-\(sample.day)-\(sample.hour)\(sample.minute)", title: sample.title,
                start: startAt, end: startAt.addingTimeInterval(1_800),
                attendees: sample.people.map { Attendee(name: $0) },
                hasConference: sample.url != nil, conferenceURL: sample.url
            )
        }
    }
}
