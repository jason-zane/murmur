import SwiftUI

struct CalendarEventEditor: View {
    let event: CalendarEvent?
    let workspace: CalendarWorkspaceStore
    let onSaved: () -> Void
    let onClose: () -> Void
    @State private var title: String
    @State private var start: Date
    @State private var end: Date
    @State private var allDay: Bool
    @State private var source: String
    @State private var location: String
    @State private var description: String
    @State private var guests: String
    @State private var timeZone: String
    @State private var reminder = "keep"
    @State private var repeatFrequency = "None"
    @State private var removing = false
    @State private var busy = false
    @State private var error: String?
    init(event: CalendarEvent?, date: Date, workspace: CalendarWorkspaceStore, onSaved: @escaping () -> Void, onClose: @escaping () -> Void) {
        self.event = event; self.workspace = workspace; self.onSaved = onSaved; self.onClose = onClose
        _timeZone = State(initialValue: event?.timeZone ?? TimeZone.current.identifier)
        _title = State(initialValue: event?.title ?? "")
        _start = State(initialValue: event?.displayStart ?? date)
        _end = State(initialValue: event?.displayEnd ?? date.addingTimeInterval(3_600))
        _allDay = State(initialValue: event?.isAllDay ?? false)
        _source = State(initialValue: event?.calendarSourceID ?? workspace.calendars.first(where: { $0.can_write == true })?.id ?? CalendarService.shared.localSources.first(where: \.canWrite)?.id ?? "")
        _location = State(initialValue: event?.location ?? "")
        _description = State(initialValue: event?.eventDescription ?? "")
        _guests = State(initialValue: event?.attendees.compactMap(\.email).joined(separator: ", ") ?? "")
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.lg) {
                HStack {
                    Text(event == nil ? "New event" : "Edit event").font(DS.Font.title)
                    Spacer()
                    ActionButton(title: "Cancel", emphasis: .quiet, action: onClose).disabled(busy)
                }
                if let error { InlineNotice(text: error, tone: .warning) }
                TextField("Title", text: $title).textFieldStyle(.roundedBorder)
                Picker("Calendar", selection: $source) {
                    Text("Choose a calendar").tag("")
                    ForEach(workspace.calendars.filter { $0.can_write == true }) { calendar in Text(calendar.name).tag(calendar.id) }
                    ForEach(CalendarService.shared.localSources.filter(\.canWrite)) { calendar in Text(calendar.account + " · " + calendar.name).tag(calendar.id) }
                }.disabled(event != nil)
                ToggleRow(title: "All day", isOn: $allDay).onChange(of: allDay) { _, value in
                    if value { start = Calendar.current.startOfDay(for: start); end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? end }
                }
                DatePicker("Starts", selection: $start, displayedComponents: allDay ? [.date] : [.date, .hourAndMinute]).environment(\.timeZone, allDay ? .current : TimeZone(identifier: timeZone) ?? .current)
                DatePicker(allDay ? "Ends before" : "Ends", selection: $end, displayedComponents: allDay ? [.date] : [.date, .hourAndMinute]).environment(\.timeZone, allDay ? .current : TimeZone(identifier: timeZone) ?? .current)
                if !allDay {
                    Picker("Time zone", selection: $timeZone) { ForEach(Array(Set(TimeZone.knownTimeZoneIdentifiers + [timeZone])).sorted(), id: \.self) { Text($0).tag($0) } }
                }
                Picker("Reminder", selection: $reminder) {
                    Text("Keep existing reminders").tag("keep")
                    if workspace.calendars.contains(where: { $0.id == source }) { Text("Calendar defaults").tag("default") }
                    Text("No reminder").tag("none"); Text("At the start").tag("0")
                    Text("10 minutes before").tag("10"); Text("30 minutes before").tag("30")
                    Text("1 hour before").tag("60"); Text("1 day before").tag("1440")
                }
                Text("Times in " + timeZone + ". All-day end dates are exclusive.").font(DS.Font.caption).foregroundStyle(DS.Color.textSecondary)
                if event == nil { Picker("Repeat", selection: $repeatFrequency) { ForEach(["None", "Daily", "Weekly", "Monthly"], id: \.self) { Text($0).tag($0) } } }
                if workspace.calendars.contains(where: { $0.id == source }) {
                    TextField("Guest email addresses, separated by commas", text: $guests).textFieldStyle(.roundedBorder)
                    Text("Google sends invitations and updates to guests. Changes to repeating events apply to this occurrence.").font(DS.Font.caption).foregroundStyle(DS.Color.textSecondary)
                } else {
                    Text("Manage guests in your calendar app. Changes to repeating events apply to this occurrence.").font(DS.Font.caption).foregroundStyle(DS.Color.textSecondary)
                }
                TextField("Location", text: $location).textFieldStyle(.roundedBorder)
                Text("Description").font(DS.Font.label)
                TextEditor(text: $description).frame(minHeight: DS.Layout.calendarMonthCellHeight)
                ActionButton(title: busy ? "Saving…" : "Save event", emphasis: .prominent) { Task { await save() } }
                    .disabled(busy || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || source.isEmpty)
                if event != nil { ActionButton(title: "Remove event…", emphasis: .quiet) { removing = true }.disabled(busy) }
            }.padding(DS.Space.xxl)
        }.frame(width: DS.Layout.meetingDetailWidth, height: DS.Layout.calendarTimelineHeight)
        .interactiveDismissDisabled(busy)
        .alert("Remove this event?", isPresented: $removing) {
            Button("Cancel", role: .cancel) { }
            Button("Remove") { Task { await remove() } }
        } message: { Text("For repeating events, only this occurrence is removed. Your calendar provider may notify guests.") }
    }
    private func remove() async {
        guard let event else { return }
        busy = true; defer { busy = false }
        do {
            if workspace.calendars.contains(where: { $0.id == event.calendarSourceID }) {
                guard let cloud = workspace.events.first(where: { $0.calendarIdentity == event.id }) else { throw CloudHTTPError(status: 409, message: "Reload this event before removing it.") }
                try await workspace.removeEvent(cloud)
            } else { try CalendarService.shared.removeEvent(event) }
            onSaved()
        } catch { self.error = error.localizedDescription }
    }
    private func save() async {
        guard end > start else { error = "Choose an end after the start."; return }
        busy = true; error = nil
        defer { busy = false }
        do {
            if let calendar = workspace.calendars.first(where: { $0.id == source }) {
                let cloud = event.flatMap { selected in workspace.events.first { $0.calendarIdentity == selected.id } }
                if event != nil && cloud == nil { throw CloudHTTPError(status: 409, message: "Reload this event before editing it.") }
                try await workspace.saveEvent(event: cloud, source: calendar, title: title, start: start, end: end, allDay: allDay, location: location, description: description, guests: guests, repeatFrequency: repeatFrequency, timeZone: timeZone, reminder: reminder)
            } else {
                try CalendarService.shared.saveEvent(id: event?.id, originalStart: event?.start, expectedModified: event?.lastModified, sourceID: source, title: title, start: start, end: end, allDay: allDay, location: location, description: description, repeatFrequency: repeatFrequency, timeZone: timeZone, reminder: reminder)
            }
            onSaved()
        } catch { self.error = error.localizedDescription }
    }
}
