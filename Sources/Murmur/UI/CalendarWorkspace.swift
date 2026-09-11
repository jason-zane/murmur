import AppKit
import SwiftUI
import MurmurSessions

struct CalendarWorkspace: View {
    let store: SessionStore
    let onRecord: (CalendarEvent) -> Void
    let canRecord: Bool
    @State private var date = Calendar.current.startOfDay(for: Date())
    @State private var mode = "Agenda"
    @State private var events: [CalendarEvent] = []
    @State private var selected: CalendarEvent?
    @State private var query = ""
    @State private var choosingDate = false
    @State private var pickerMonth = HomeView.firstOfMonth(Date())
    @State private var error: String?
    private var days: [Date] {
        let calendar = Calendar.current
        var start = calendar.startOfDay(for: date)
        if mode == "Month" {
            let first = HomeView.firstOfMonth(date)
            let offset = (calendar.component(.weekday, from: first) + 5) % 7
            start = calendar.date(byAdding: .day, value: -offset, to: first) ?? first
        }
        return (0..<(mode == "Month" ? 42 : mode == "Day" ? 1 : 7)).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.xl) {
                if let error { InlineNotice(text: error, tone: .warning) }
                HStack {
                    VStack(alignment: .leading, spacing: DS.Space.sm) {
                        Text("Calendar").font(DS.Font.title)
                        Text("Your meetings, guest details and notes.").font(DS.Font.body).foregroundStyle(DS.Color.textSecondary)
                    }
                    Spacer()
                    Segmented(options: [("Agenda", "Agenda"), ("Day", "Day"), ("Week", "Week"), ("Month", "Month")], selection: $mode)
                        .frame(width: DS.Layout.calendarViewPickerWidth)
                }
                HStack(spacing: DS.Space.md) {
                    Button { shift(-1) } label: { Image(systemName: "chevron.left") }.help("Previous period")
                    ActionButton(title: "Today", emphasis: .normal) { date = Calendar.current.startOfDay(for: Date()) }
                    Button { shift(1) } label: { Image(systemName: "chevron.right") }.help("Next period")
                    Button { pickerMonth = HomeView.firstOfMonth(date); choosingDate.toggle() } label: {
                        Label(date.formatted(.dateTime.day().month(.wide).year()), systemImage: "calendar")
                    }
                    .popover(isPresented: $choosingDate) {
                        MonthCalendar(month: $pickerMonth, selected: $date, activity: MonthActivity())
                            .frame(width: DS.Layout.monthGridWidth)
                            .onChange(of: date) { _, _ in choosingDate = false }
                    }
                    Spacer()
                    SearchField(text: $query, placeholder: "Search meetings")
                        .frame(maxWidth: DS.Layout.calendarSearchWidth)
                }
                if mode == "Month" {
                    Text(date.formatted(.dateTime.month(.wide).year())).font(DS.Font.headline)
                    monthGrid
                } else if mode == "Week" {
                    ScrollView(.horizontal) {
                        HStack(alignment: .top, spacing: DS.Space.md) {
                            ForEach(days, id: \.self) { day in dayColumn(day).frame(width: DS.Layout.calendarDayWidth) }
                        }
                    }
                } else {
                    let visibleDays = mode == "Agenda" ? days.filter { day in
                        events.contains { event in Calendar.current.isDate(event.start, inSameDayAs: day) && (query.isEmpty || event.title.localizedCaseInsensitiveContains(query)) }
                    } : days
                    if visibleDays.isEmpty {
                        EmptyState(icon: "calendar", label: query.isEmpty ? "No meetings this week" : "No matching meetings", detail: query.isEmpty ? "Choose another date to see your meetings." : "Try a different search.")
                    }
                    ForEach(visibleDays, id: \.self) { day in dayColumn(day) }
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
                    ActionButton(title: "Record meeting", systemImage: "mic", emphasis: .prominent) {
                        selected = nil
                        onRecord(event)
                    }.disabled(!canRecord)
                    if event.conferenceURL != nil {
                        ActionButton(title: "Join meeting", systemImage: "arrow.up.right", emphasis: .normal) { MeetingSchedule.shared.join(event) }
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
                    HStack(alignment: .top, spacing: DS.Space.lg) {
                        if mode != "Week" {
                            Readout(event.start.formatted(.dateTime.hour().minute()) + "–" + event.end.formatted(.dateTime.hour().minute()), color: DS.Color.textSecondary)
                                .frame(width: DS.Layout.calendarTimeWidth, alignment: .leading)
                        }
                        VStack(alignment: .leading, spacing: DS.Space.xs) {
                            if mode == "Week" {
                                Readout(event.start.formatted(.dateTime.hour().minute()) + "–" + event.end.formatted(.dateTime.hour().minute()), color: DS.Color.textSecondary)
                            }
                            Text(event.title).font(DS.Font.bodyEmphasis).foregroundStyle(DS.Color.text)
                            let context = event.booking.map { $0.guest_name + " · Booked" } ?? event.attendees.map(\.name).prefix(2).joined(separator: ", ")
                            if !context.isEmpty {
                                Text(context).font(DS.Font.caption).foregroundStyle(DS.Color.textSecondary)
                            }
                        }
                        Spacer(minLength: DS.Space.zero)
                    }.padding(.vertical, DS.Space.md)
                        .contentShape(.rect)
                }.buttonStyle(.plain)
                Divider()
            }
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
    private var monthGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: DS.Space.zero), count: 7), spacing: DS.Space.zero) {
            ForEach(["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"], id: \.self) { day in
                Text(day).font(DS.Font.label).foregroundStyle(DS.Color.textSecondary).padding(.vertical, DS.Space.sm)
            }
            ForEach(days, id: \.self) { day in
                let matches = events.filter { Calendar.current.isDate($0.start, inSameDayAs: day) && (query.isEmpty || $0.title.localizedCaseInsensitiveContains(query)) }
                VStack(alignment: .leading, spacing: DS.Space.sm) {
                    Button { date = day; mode = "Day" } label: {
                        Readout(String(Calendar.current.component(.day, from: day)), color: Calendar.current.isDate(day, equalTo: date, toGranularity: .month) ? DS.Color.text : DS.Color.textSecondary)
                            .padding(DS.Space.xs)
                            .background(Calendar.current.isDateInToday(day) ? DS.Color.selection : .clear, in: .rect(cornerRadius: DS.Radius.sm))
                    }.buttonStyle(.plain).accessibilityLabel(day.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                    ForEach(Array(matches.prefix(DS.Layout.calendarMonthPreviewCount)), id: \.occurrenceID) { event in
                        Button { selected = event } label: {
                            HStack(spacing: DS.Space.xs) {
                                Readout(event.start.formatted(.dateTime.hour().minute()), color: DS.Color.textSecondary)
                                Text(event.title).font(DS.Font.caption).lineLimit(1)
                            }.frame(maxWidth: .infinity, alignment: .leading).contentShape(.rect)
                        }.buttonStyle(.plain).help(event.title)
                    }
                    if matches.count > DS.Layout.calendarMonthPreviewCount {
                        Button("+\(matches.count - DS.Layout.calendarMonthPreviewCount) more") { date = day; mode = "Day" }
                            .font(DS.Font.caption).buttonStyle(.plain)
                    }
                    Spacer(minLength: DS.Space.zero)
                }.padding(DS.Space.sm)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .frame(height: DS.Layout.calendarMonthCellHeight)
                    .overlay(Rectangle().strokeBorder(DS.Color.separator, lineWidth: DS.Stroke.hairline))
            }
        }
    }
    private func shift(_ direction: Int) {
        if mode == "Month" {
            date = Calendar.current.date(byAdding: .month, value: direction, to: HomeView.firstOfMonth(date)) ?? date
        } else {
            date = Calendar.current.date(byAdding: .day, value: direction * (mode == "Day" ? 1 : 7), to: date) ?? date
        }
    }
    private func reload() {
        guard let start = days.first, let last = days.last,
              let end = Calendar.current.date(byAdding: .day, value: 1, to: last) else { return }
        events = CalendarService.shared.events(from: start, to: end)
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
