import AppKit
import MurmurSessions
import SwiftUI

/// The empty-detail page: one day's meetings and notes beside a month you can page through.
/// Past meetings open the note that was recorded for them; upcoming ones join.
struct HomeView: View {
    let store: SessionStore
    let onRecord: () -> Void
    let onNewNote: () -> Void
    @State private var schedule = MeetingSchedule.shared
    @State private var settings = MeetingSettings.shared
    @State private var requesting = false
    @State private var audioGranted = SystemAudioCapture.isKnownGranted
    @State private var microphoneGranted = Permissions.hasMicrophone
    @State private var selectedDay = Calendar.current.startOfDay(for: Date())
    @State private var visibleMonth = HomeView.firstOfMonth(Date())
    @State private var activity = MonthActivity()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.xxl) {
                VStack(alignment: .leading, spacing: DS.Space.sm) {
                    Text("Home").font(DS.Font.title)
                    Text("Meetings and notes for your day.").font(DS.Font.body).foregroundStyle(DS.Color.textSecondary)
                }
                HStack(alignment: .top, spacing: DS.Space.xxl) {
                    day.frame(maxWidth: .infinity, alignment: .topLeading)
                    MonthCalendar(month: $visibleMonth, selected: $selectedDay, activity: activity)
                        .frame(width: DS.Layout.monthGridWidth)
                }
                if !microphoneGranted || !audioGranted { setup }
                Hint("Voice Notes offers to record when a call starts in Meet, Zoom or Teams. Change this in Settings ▸ Meetings.")
            }
            .padding(DS.Space.xxl)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .onAppear { schedule.refresh(); refreshPermissions(); reload() }
        .onChange(of: visibleMonth) { _, _ in reload() }
        .onReceive(NotificationCenter.default.publisher(for: .murmurNotesChanged)) { _ in reload() }
        .task {
            while !Task.isCancelled {
                do { try await Task.sleep(for: DS.Timing.refresh) } catch { return }
                refreshPermissions()
                reload()
            }
        }
    }

    // MARK: Day

    private var dayTitle: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(selectedDay) { return "Today" }
        if calendar.isDateInYesterday(selectedDay) { return "Yesterday" }
        if calendar.isDateInTomorrow(selectedDay) { return "Tomorrow" }
        return selectedDay.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }

    private var day: some View {
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            HStack {
                Text(dayTitle).font(DS.Font.headline)
                Spacer()
                if schedule.calendarGranted {
                    Label(settings.autoOpenMeetings ? "Links open automatically" : "Calendar connected", systemImage: "calendar")
                        .font(DS.Font.caption).foregroundStyle(DS.Color.textSecondary)
                }
            }
            if !settings.calendarEnabled {
                Text("Connect your calendar to see meetings here and open their links on time.")
                    .font(DS.Font.body).foregroundStyle(DS.Color.textSecondary)
                ActionButton(title: "Use my calendar", emphasis: .normal) { settings.calendarEnabled = true; connectCalendar() }
            } else if !schedule.calendarGranted && !PreviewEnvironment.isActive {
                connectCard
            }
            let entries = activity.entries(on: selectedDay)
            if entries.isEmpty {
                let today = Calendar.current.isDateInToday(selectedDay)
                EmptyState(
                    icon: "calendar",
                    label: today ? "Nothing scheduled today" : "Nothing on this day",
                    detail: today ? "Record a meeting or write a note any time." : "No meetings or notes."
                ) {
                    if today {
                        HStack(spacing: DS.Space.sm) {
                            ActionButton(title: "Record meeting", systemImage: "mic", emphasis: .normal, action: onRecord)
                            ActionButton(title: "New note", emphasis: .quiet, action: onNewNote)
                        }
                    }
                }
                .frame(maxHeight: DS.Layout.editorHeight)
            } else {
                VStack(spacing: DS.Space.zero) {
                    ForEach(entries) { entry in
                        DayRow(entry: entry, schedule: schedule) { id in
                            NotificationCenter.default.post(name: .murmurShowSession, object: id)
                        }
                        Divider()
                    }
                }
            }
            if let message = schedule.message {
                Text(message).font(DS.Font.caption).foregroundStyle(DS.Color.textSecondary)
            }
        }
    }

    private var connectCard: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            Image(systemName: "calendar.badge.clock").font(DS.Font.largeSymbol).foregroundStyle(DS.Color.accent)
            Text("Your next meeting, one step closer.").font(DS.Font.headline)
            Text("Connect the calendars on your Mac. Voice Notes can open meeting links a minute before they begin, then take notes when you enter the call.")
                .font(DS.Font.body).foregroundStyle(DS.Color.textSecondary).fixedSize(horizontal: false, vertical: true)
            ActionButton(title: requesting ? "Connecting…" : "Connect calendar", systemImage: "calendar.badge.plus", emphasis: .prominent) { connectCalendar() }
                .disabled(requesting)
            Text("Google Calendar, iCloud and Exchange work through Calendar on this Mac.")
                .font(DS.Font.caption).foregroundStyle(DS.Color.textTertiary)
        }
        .padding(DS.Space.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.Color.window, in: .rect(cornerRadius: DS.Radius.lg))
    }

    private var setup: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            Text("Before your first call").font(DS.Font.headline)
            if !microphoneGranted {
                PermissionRow(
                    title: "Microphone",
                    detail: "Your side of every call and dictation.",
                    isGranted: microphoneGranted,
                    grantTitle: "Allow…"
                ) {
                    Task {
                        microphoneGranted = await Permissions.requestMicrophone()
                        if !microphoneGranted { Permissions.openMicrophoneSettings() }
                    }
                }
            }
            if !audioGranted {
                PermissionRow(
                    title: "Audio recording",
                    detail: "The other side of the call — what your Mac is playing.",
                    isGranted: audioGranted,
                    grantTitle: "Allow…"
                ) {
                    Task { audioGranted = await SystemAudioCapture.requestPermission() }
                }
            }
        }
        .padding(DS.Space.lg)
        .background(DS.Color.window, in: .rect(cornerRadius: DS.Radius.md))
    }

    // MARK: Data

    /// Loads the visible month plus the leading and trailing days the grid shows.
    private func reload() {
        let calendar = Calendar.current
        guard let start = calendar.date(byAdding: .day, value: -7, to: visibleMonth),
              let end = calendar.date(byAdding: .day, value: 49, to: visibleMonth) else { return }
        let events = settings.calendarEnabled ? CalendarService.shared.events(from: start, to: end) : []
        let sessions = store.listSessions().filter { $0.startedAt >= start && $0.startedAt < end }
        let next = MonthActivity(
            events: Dictionary(grouping: events) { calendar.startOfDay(for: $0.start) },
            notes: Dictionary(grouping: sessions) { calendar.startOfDay(for: $0.startedAt) }
        )
        if next != activity { activity = next }
    }

    private func refreshPermissions() {
        microphoneGranted = Permissions.hasMicrophone
        audioGranted = SystemAudioCapture.isKnownGranted
    }

    private func connectCalendar() {
        if CalendarService.shared.isDenied { CalendarService.openSettings(); return }
        requesting = true
        Task { await schedule.requestCalendar(); requesting = false; reload() }
    }

    static func firstOfMonth(_ date: Date) -> Date {
        let calendar = Calendar.current
        return calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
    }
}

// MARK: - Model

/// What happened, or is due, on each day of the visible month.
private struct MonthActivity: Equatable {
    var events: [Date: [CalendarEvent]] = [:]
    var notes: [Date: [MeetingSession]] = [:]

    enum Mark { case meeting, note }

    func mark(on day: Date) -> Mark? {
        if events[day]?.isEmpty == false { return .meeting }
        if notes[day]?.isEmpty == false { return .note }
        return nil
    }

    /// The day's events, each paired with the note recorded for it, followed by notes that
    /// weren't tied to any event — a call that wasn't in the calendar, a personal note.
    func entries(on day: Date) -> [DayEntry] {
        let dayEvents = events[day] ?? []
        let dayNotes = notes[day] ?? []
        var linked: Set<String> = []
        var result: [DayEntry] = dayEvents.map { event in
            let note = dayNotes.first { $0.calendarEventID == event.id }
                ?? dayNotes.first { !$0.isNoteOnly && $0.title == event.title && abs($0.startedAt.timeIntervalSince(event.start)) < 30 * 60 }
            if let note { linked.insert(note.id) }
            return DayEntry(id: event.occurrenceID, time: event.start, event: event, note: note)
        }
        result += dayNotes.filter { !linked.contains($0.id) }.map { DayEntry(id: $0.id, time: $0.startedAt, event: nil, note: $0) }
        return result.sorted { $0.time < $1.time }
    }
}

private struct DayEntry: Identifiable {
    let id: String
    let time: Date
    let event: CalendarEvent?
    let note: MeetingSession?
}

// MARK: - Rows

private struct DayRow: View {
    let entry: DayEntry
    let schedule: MeetingSchedule
    let onOpen: (String) -> Void

    private var subtitle: String {
        if let event = entry.event {
            return event.conferenceURL.flatMap { MeetingLink.provider(for: $0) } ?? "Calendar meeting"
        }
        guard let note = entry.note else { return "" }
        if note.isNoteOnly { return "Note" }
        let app = note.app ?? "Meeting"
        return note.duration > 0 ? app + " · " + TimeFormat.clock(note.duration) : app
    }

    var body: some View {
        HStack(alignment: .center, spacing: DS.Space.md) {
            Readout(entry.time.formatted(.dateTime.hour().minute()), color: DS.Color.text)
                .frame(width: DS.Layout.transcriptTime, alignment: .leading)
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                Text(entry.event?.title ?? entry.note?.title ?? "").font(DS.Font.bodyEmphasis).lineLimit(2)
                Text(subtitle).font(DS.Font.caption).foregroundStyle(DS.Color.textSecondary)
            }
            Spacer(minLength: DS.Space.sm)
            trailing
        }
        .padding(.vertical, DS.Space.lg)
    }

    @ViewBuilder private var trailing: some View {
        if let note = entry.note {
            ActionButton(title: "Open note", systemImage: "doc.text", emphasis: .quiet) { onOpen(note.id) }
        } else if let event = entry.event, event.end > Date() {
            if event.conferenceURL != nil {
                ActionButton(title: "Join", systemImage: "arrow.up.right", emphasis: .normal) { schedule.join(event) }
                Menu {
                    Button("Skip automatic opening") { schedule.skip(event) }
                    Button("Open Calendar") { NSWorkspace.shared.open(URL(string: "ical://")!) }
                } label: { Image(systemName: "ellipsis").font(DS.Font.symbol) }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden)
                    .frame(width: DS.Layout.symbolColumn)
                    .help("Meeting options")
            }
        } else {
            Text("No notes").font(DS.Font.caption).foregroundStyle(DS.Color.textTertiary)
        }
    }
}

// MARK: - Month grid

private struct MonthCalendar: View {
    @Binding var month: Date
    @Binding var selected: Date
    let activity: MonthActivity
    private let calendar = Calendar.current

    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    private var days: [Date] {
        let weekday = calendar.component(.weekday, from: month)
        let offset = (weekday - calendar.firstWeekday + 7) % 7
        guard let gridStart = calendar.date(byAdding: .day, value: -offset, to: month) else { return [] }
        return (0..<42).compactMap { calendar.date(byAdding: .day, value: $0, to: gridStart) }
    }

    var body: some View {
        VStack(spacing: DS.Space.md) {
            HStack(spacing: DS.Space.xs) {
                Text(month.formatted(.dateTime.month(.wide).year())).font(DS.Font.headline)
                Spacer(minLength: DS.Space.sm)
                ActionButton(title: "Today", emphasis: .quiet) {
                    month = HomeView.firstOfMonth(Date())
                    selected = calendar.startOfDay(for: Date())
                }
                arrow("chevron.left", help: "Previous month", by: -1)
                arrow("chevron.right", help: "Next month", by: 1)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: DS.Space.xxs), count: 7), spacing: DS.Space.xxs) {
                ForEach(weekdaySymbols, id: \.self) { symbol in
                    Text(symbol).font(DS.Font.label).foregroundStyle(DS.Color.textTertiary)
                }
                ForEach(days, id: \.self) { day in
                    cell(day)
                }
            }
        }
        .padding(DS.Space.lg)
        .background(DS.Color.window, in: .rect(cornerRadius: DS.Radius.lg))
    }

    private func arrow(_ symbol: String, help: String, by months: Int) -> some View {
        Button {
            guard let next = calendar.date(byAdding: .month, value: months, to: month) else { return }
            month = next
        } label: {
            Image(systemName: symbol).font(DS.Font.smallSymbol).foregroundStyle(DS.Color.textSecondary)
                .frame(width: DS.Layout.symbolColumn, height: DS.Layout.symbolColumn)
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func cell(_ day: Date) -> some View {
        let isSelected = calendar.isDate(day, inSameDayAs: selected)
        let isToday = calendar.isDateInToday(day)
        let inMonth = calendar.isDate(day, equalTo: month, toGranularity: .month)
        let mark = activity.mark(on: day)
        return Button {
            selected = day
            if !inMonth { month = HomeView.firstOfMonth(day) }
        } label: {
            VStack(spacing: DS.Space.tight) {
                Text(String(calendar.component(.day, from: day))).font(DS.Font.readout)
                Circle()
                    .fill(isSelected ? DS.Color.window : mark == .meeting ? DS.Color.accent : DS.Color.textSecondary)
                    .frame(width: DS.Layout.calendarDot, height: DS.Layout.calendarDot)
                    .opacity(mark == nil ? 0 : 1)
            }
            .frame(maxWidth: .infinity)
            .frame(height: DS.Layout.calendarCell)
            .foregroundStyle(isSelected ? DS.Color.window : inMonth ? DS.Color.text : DS.Color.textTertiary)
            .background(isSelected ? DS.Color.accent : isToday ? DS.Color.accentSoft : .clear, in: .rect(cornerRadius: DS.Radius.sm))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(day.formatted(.dateTime.weekday(.wide).day().month(.wide)))
    }
}
