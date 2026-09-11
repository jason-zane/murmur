import AppKit
import SwiftUI
import MurmurSessions

struct CalendarWorkspace: View {
    let store: SessionStore
    @State private var date = Calendar.current.startOfDay(for: Date())
    @State private var mode = "Agenda"
    @State private var events: [CalendarEvent] = []
    @State private var selected: CalendarEvent?
    @State private var query = ""
    @State private var error: String?
    private var days: [Date] {
        (0..<(mode == "Day" ? 1 : 7)).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: date) }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.xl) {
                if let error { InlineNotice(text: error, tone: .warning) }
                HStack {
                    VStack(alignment: .leading, spacing: DS.Space.sm) {
                        Text("Calendar").font(DS.Font.title)
                        Text("Prepare, meet and follow through.").font(DS.Font.body).foregroundStyle(DS.Color.textSecondary)
                    }
                    Spacer()
                    Segmented(options: [("Agenda", "Agenda"), ("Day", "Day"), ("Week", "Week")], selection: $mode)
                }
                HStack(spacing: DS.Space.md) {
                    Button { shift(-1) } label: { Image(systemName: "chevron.left") }.help("Previous period")
                    ActionButton(title: "Today", emphasis: .normal) { date = Calendar.current.startOfDay(for: Date()) }
                    Button { shift(1) } label: { Image(systemName: "chevron.right") }.help("Next period")
                    DatePicker("Date", selection: $date, displayedComponents: .date).labelsHidden()
                    Spacer()
                    SearchField(text: $query, placeholder: "Search meetings")
                }
                if mode == "Week" {
                    ScrollView(.horizontal) {
                        HStack(alignment: .top, spacing: DS.Space.md) {
                            ForEach(days, id: \.self) { day in dayColumn(day).frame(width: DS.Layout.calendarDayWidth) }
                        }
                    }
                } else {
                    ForEach(days, id: \.self) { day in dayColumn(day) }
                }
                Text("Times in \(TimeZone.current.identifier). Calendars on this Mac remain available offline.")
                    .font(DS.Font.caption).foregroundStyle(DS.Color.textSecondary)
            }.padding(DS.Space.xxl)
        }
        .onAppear { reload(); MeetingSchedule.shared.refresh() }
        .onChange(of: date) { _, _ in reload() }
        .onChange(of: mode) { _, _ in reload() }
        .onReceive(NotificationCenter.default.publisher(for: .murmurNotesChanged)) { _ in reload() }
        .task {
            while !Task.isCancelled {
                do { try await Task.sleep(for: DS.Timing.refresh) } catch { return }
                reload()
            }
        }
        .sheet(item: $selected) { event in
            VStack(alignment: .leading, spacing: DS.Space.lg) {
                HStack {
                    Text(event.booking == nil ? "Calendar meeting" : "Booked meeting").font(DS.Font.label).foregroundStyle(DS.Color.textSecondary)
                    Spacer()
                    ActionButton(title: "Done", emphasis: .quiet) { selected = nil }
                }
                Text(event.title).font(DS.Font.title)
                Readout(event.start.formatted(.dateTime.weekday().day().month().hour().minute()), color: DS.Color.textSecondary)
                Text(event.attendees.map(\.name).joined(separator: ", ")).font(DS.Font.body)
                if let booking = event.booking {
                    Text("Notes template: \(booking.template ?? "Meeting")").font(DS.Font.caption)
                    Text("Guest answers").font(DS.Font.headline)
                    ForEach(booking.answers, id: \.question) { answer in
                        VStack(alignment: .leading, spacing: DS.Space.xs) {
                            Text(answer.question).font(DS.Font.bodyEmphasis)
                            Text(answer.answer).font(DS.Font.body).foregroundStyle(DS.Color.textSecondary)
                        }
                    }
                    ActionButton(title: "Manage booking and messages", emphasis: .normal) {
                        selected = nil
                        NotificationCenter.default.post(name: .murmurShowPage, object: MainPage.booking)
                    }
                }
                HStack(spacing: DS.Space.md) {
                    if event.conferenceURL != nil {
                        ActionButton(title: "Join meeting", systemImage: "arrow.up.right", emphasis: .prominent) { MeetingSchedule.shared.join(event) }
                    }
                    if let note = store.listSessions().first(where: { $0.calendarEventID == event.id }) {
                        ActionButton(title: "Open note", emphasis: .normal) {
                            selected = nil
                            NotificationCenter.default.post(name: .murmurShowSession, object: note.id)
                        }
                    } else {
                        ActionButton(title: "Prepare a note", emphasis: .normal) { prepare(event) }
                    }
                }
            }.padding(DS.Space.xxl).frame(width: DS.Layout.meetingDetailWidth)
        }
    }
    private func dayColumn(_ day: Date) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            Text(day.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                .font(DS.Font.headline).foregroundStyle(DS.Color.textSecondary)
            let matching = events.filter { Calendar.current.isDate($0.start, inSameDayAs: day) && (query.isEmpty || $0.title.localizedCaseInsensitiveContains(query)) }
            if matching.isEmpty { Text("No meetings").font(DS.Font.body).foregroundStyle(DS.Color.textTertiary).padding(.vertical, DS.Space.lg) }
            ForEach(matching, id: \.occurrenceID) { event in
                Button { selected = event } label: {
                    HStack(spacing: DS.Space.md) {
                        RoundedRectangle(cornerRadius: DS.Radius.sm).fill(DS.Color.accent).frame(width: DS.Layout.calendarAccent)
                        VStack(alignment: .leading, spacing: DS.Space.sm) {
                            Readout(event.start.formatted(.dateTime.hour().minute()) + "–" + event.end.formatted(.dateTime.hour().minute()), color: DS.Color.textSecondary)
                            Text(event.title).font(DS.Font.bodyEmphasis).foregroundStyle(DS.Color.text)
                            Text(event.booking.map { $0.guest_name + " · Booked" } ?? event.attendees.map(\.name).prefix(2).joined(separator: ", "))
                                .font(DS.Font.caption).foregroundStyle(DS.Color.textSecondary)
                        }
                        Spacer(minLength: DS.Space.zero)
                    }.padding(DS.Space.lg)
                        .background(DS.Color.window, in: .rect(cornerRadius: DS.Radius.md))
                }.buttonStyle(.plain)
            }
            Divider()
        }
    }
    private func prepare(_ event: CalendarEvent) {
        do {
            let note = try store.createNote(title: event.title)
            try store.update(id: note.id) { value in
                value.calendarEventID = event.id
                value.attendees = event.attendees
                if let booking = event.booking {
                    value.summaryTemplate = booking.template
                    value.booking = BookingContext(eventType: booking.event_type, guestName: booking.guest_name,
                        guestEmail: booking.guest_email, answers: booking.answers.map { .init(question: $0.question, answer: $0.answer) }, bookingID: booking.id)
                }
            }
            selected = nil
            NotificationCenter.default.post(name: .murmurShowSession, object: note.id)
        } catch { self.error = error.localizedDescription; selected = nil }
    }
    private func shift(_ direction: Int) {
        date = Calendar.current.date(byAdding: .day, value: direction * (mode == "Day" ? 1 : 7), to: date) ?? date
    }
    private func reload() {
        guard let end = Calendar.current.date(byAdding: .day, value: mode == "Day" ? 1 : 7, to: date) else { return }
        events = CalendarService.shared.events(from: Calendar.current.startOfDay(for: date), to: end)
    }
}

struct ConnectionsWorkspace: View {
    @State private var tab = "Account"
    var body: some View {
        VStack(spacing: DS.Space.zero) {
            Segmented(options: [("Account", "Account & this Mac"), ("Cloud", "Calendars, email & apps")], selection: $tab)
                .padding(DS.Space.xl)
            if tab == "Cloud" { CloudWorkspace(path: "/connections") }
            else {
                ScrollView {
                    VStack(alignment: .leading, spacing: DS.Space.xl) {
                        Text("Connections").font(DS.Font.title)
                        ConnectionsSettings()
                    }.padding(DS.Space.xxl)
                }
            }
        }
    }
}

extension Notification.Name {
    static let murmurShowPage = Notification.Name("com.jasonhunt.murmur.showPage")
}
