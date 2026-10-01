import AppKit
import EventKit
import SwiftUI
import MurmurSessions

struct CalendarWorkspace: View {
    let store: SessionStore
    let onRecord: (CalendarEvent) -> Void
    let canRecord: Bool
    @State private var date = Calendar.current.startOfDay(for: Date())
    @AppStorage("workspace.calendar.view") private var mode = "Week"
    @State private var showingStatus = false
    @State private var events: [CalendarEvent] = []
    @State private var selected: CalendarEvent?
    @State private var query = ""
    @State private var choosingDate = false
    @State private var pickerMonth = HomeView.firstOfMonth(Date())
    @State private var error: String?
    @State private var calendarStore = CalendarWorkspaceStore()
    @State private var source = ""
    @State private var editing = false
    @State private var editEvent: CalendarEvent?
    private var days: [Date] {
        let calendar = Calendar.current
        var start = calendar.startOfDay(for: date)
        if mode == "Week" {
            start = calendar.date(byAdding: .day, value: -((calendar.component(.weekday, from: start) + 5) % 7), to: start) ?? start
        }
        if mode == "Month" {
            let first = HomeView.firstOfMonth(date)
            let offset = (calendar.component(.weekday, from: first) + 5) % 7
            start = calendar.date(byAdding: .day, value: -offset, to: first) ?? first
        }
        return (0..<(mode == "Month" ? 42 : mode == "Day" ? 1 : 7)).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.lg) {
                if let error { InlineNotice(text: error, tone: .warning) }
                HStack {
                    VStack(alignment: .leading, spacing: DS.Space.sm) {
                        Text("Calendar").font(DS.Font.title)
                    }
                    Spacer()
                    ActionButton(title: "New event", emphasis: .normal) { editEvent = nil; editing = true }.disabled(CalendarService.shared.localSources.isEmpty && !calendarStore.calendars.contains { $0.can_write == true })
                    Segmented(options: [("Agenda", "Agenda"), ("Day", "Day"), ("Week", "Week"), ("Month", "Month")], selection: $mode)
                        .frame(width: DS.Layout.calendarViewPickerWidth)
                }
                if !PreviewEnvironment.isActive && !CalendarService.shared.isAuthorized && !CloudSync.shared.calendarConnected {
                    InlineNotice(text: "Connect Google Calendar or allow the calendars on this Mac to see your events.", tone: .info) {
                        ActionButton(title: "Connect a calendar", emphasis: .normal) { NotificationCenter.default.post(name: .murmurShowPage, object: MainPage.connections) }
                    }
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
                    Button { showingStatus.toggle() } label: {
                        Label(calendarStore.needsAttention ? "Needs attention" : "Calendar status", systemImage: calendarStore.needsAttention ? "exclamationmark.triangle" : "info.circle")
                            .labelStyle(.titleAndIcon)
                            .font(DS.Font.caption)
                            .foregroundStyle(calendarStore.needsAttention ? DS.Color.warning : DS.Color.textSecondary)
                    }.buttonStyle(.plain).help("Calendar status and time zone")
                    .popover(isPresented: $showingStatus) {
                        VStack(alignment: .leading, spacing: DS.Space.sm) {
                            Text("Time zone: " + TimeZone.current.identifier).font(DS.Font.body)
                            if let message = calendarStore.message { Text(message).font(DS.Font.caption).foregroundStyle(DS.Color.textSecondary) }
                            else { Text(calendarStore.loading ? "Updating calendars…" : "Downloaded calendars are available offline.").font(DS.Font.caption).foregroundStyle(DS.Color.textSecondary) }
                            ActionButton(title: "Connected apps", emphasis: .quiet) { showingStatus = false; NotificationCenter.default.post(name: .murmurShowPage, object: MainPage.connections) }
                        }.padding(DS.Space.lg)
                    }
                    Menu("Calendars") {
                        Button("All calendars") { source = ""; reload() }
                        ForEach(calendarStore.calendars.filter(\.selected)) { calendar in
                            Button(calendar.name) { source = calendar.id; reload() }
                        }
                        Divider()
                        ForEach(CalendarService.shared.localSources) { calendar in
                            Toggle(calendar.account + " · " + calendar.name, isOn: Binding(get: { CalendarService.shared.isVisible(calendar.id) }, set: { CalendarService.shared.setVisible(calendar.id, visible: $0); reload() }))
                        }
                        Button("Manage connected accounts") { NotificationCenter.default.post(name: .murmurShowPage, object: MainPage.connections) }
                    }
                    Spacer()
                    SearchField(text: $query, placeholder: "Search meetings")
                        .frame(maxWidth: DS.Layout.calendarSearchWidth)
                }
                if mode == "Month" {
                    Text(date.formatted(.dateTime.month(.wide).year())).font(DS.Font.headline)
                    ScrollView { monthGrid }
                } else if mode == "Week" || mode == "Day" {
                    weekTimeline
                } else {
                    ScrollView {
                    VStack(alignment: .leading, spacing: DS.Space.lg) {
                    let visibleDays = mode == "Agenda" ? days.filter { day in
                        events.contains { event in event.displayStart < Calendar.current.date(byAdding: .day, value: 1, to: day)! && event.displayEnd > day && (query.isEmpty || event.title.localizedCaseInsensitiveContains(query)) }
                    } : days
                    if visibleDays.isEmpty {
                        EmptyState(icon: "calendar", label: query.isEmpty ? "No meetings this week" : "No matching meetings", detail: query.isEmpty ? "Choose another date to see your meetings." : "Try a different search.")
                    }
                    ForEach(visibleDays, id: \.self) { day in dayColumn(day) }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
        }.padding(DS.Space.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { reload(); MeetingSchedule.shared.refresh() }
        .onChange(of: date) { _, _ in reload() }
        .onChange(of: mode) { _, _ in reload() }
        .onChange(of: calendarStore.events.count) { _, _ in reload() }
        .onReceive(NotificationCenter.default.publisher(for: .EKEventStoreChanged)) { _ in reload() }
        .onReceive(NotificationCenter.default.publisher(for: .murmurNotesChanged)) { _ in reload() }
        .task(id: "\(date.timeIntervalSince1970)-\(mode)-\(CloudAccount.shared.credentials?.userID ?? "")") {
            guard let start = days.first, let last = days.last, let end = Calendar.current.date(byAdding: .day, value: 1, to: last) else { return }
            await calendarStore.load(from: start, to: end); reload()
            while !Task.isCancelled {
                do { try await Task.sleep(for: DS.Timing.calendarRefresh) } catch { return }
                await calendarStore.load(from: start, to: end); reload()
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
                if let name = event.calendarName { Text(name).font(DS.Font.caption).foregroundStyle(DS.Color.textSecondary) }
                if let location = event.location { Text(location).font(DS.Font.body) }
                if let description = event.eventDescription { Text(description).font(DS.Font.body) }
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
                    ActionButton(title: "Edit event", emphasis: .normal) { editEvent = event; selected = nil; editing = true }.disabled(!calendarStore.calendars.contains(where: { $0.id == event.calendarSourceID && $0.can_write == true }) && !CalendarService.shared.localSources.contains(where: { $0.id == event.calendarSourceID && $0.canWrite }))
                    ActionButton(title: "Record meeting", systemImage: "mic", emphasis: .prominent) {
                        selected = nil
                        onRecord(event)
                    }.disabled(!canRecord)
                    if event.conferenceURL != nil {
                        ActionButton(title: "Join meeting", systemImage: "arrow.up.right", emphasis: .normal) { MeetingSchedule.shared.join(event) }
                    }
                    if let note = store.listSessions().first(where: { $0.calendarEventID == event.id || (event.legacyEventID != nil && events.filter { $0.legacyEventID == event.legacyEventID }.count == 1 && $0.calendarEventID == event.legacyEventID) }) {
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
        .sheet(isPresented: $editing) {
            CalendarEventEditor(event: editEvent, date: date, workspace: calendarStore, onSaved: {
                editing = false
                Task {
                    guard let start = days.first, let last = days.last, let end = Calendar.current.date(byAdding: .day, value: 1, to: last) else { return }
                    await calendarStore.load(from: start, to: end, force: true); reload()
                }
            }, onClose: { editing = false })
        }
    }
    private var weekTimeline: some View {
        GeometryReader { geometry in
            let columnWidth = max(DS.Layout.calendarDayMinimumWidth, (geometry.size.width - DS.Layout.calendarTimeWidth) / CGFloat(days.count))
            ScrollView(.horizontal) {
                VStack(spacing: DS.Space.zero) {
                    HStack(alignment: .top, spacing: DS.Space.zero) {
                        VStack(spacing: DS.Space.zero) {
                            Color.clear.frame(height: DS.Layout.calendarDayHeaderHeight)
                            if days.contains(where: { matching($0).contains(where: \.isAllDay) }) {
                                Text("All day").font(DS.Font.caption).foregroundStyle(DS.Color.textSecondary).padding(.top, DS.Space.sm)
                            }
                        }.frame(width: DS.Layout.calendarTimeWidth)
                        ForEach(days, id: \.self) { day in
                            VStack(alignment: .leading, spacing: DS.Space.zero) {
                                VStack(alignment: .leading, spacing: DS.Space.xs) {
                                    Text(day.formatted(.dateTime.weekday(.abbreviated))).font(DS.Font.caption).foregroundStyle(DS.Color.textSecondary)
                                    Readout(day.formatted(.dateTime.day()), color: Calendar.current.isDateInToday(day) ? DS.Color.accent : DS.Color.text)
                                }.padding(.horizontal, DS.Space.sm).frame(height: DS.Layout.calendarDayHeaderHeight, alignment: .leading)
                                let allDay = matching(day).filter(\.isAllDay)
                                if !allDay.isEmpty {
                                    ScrollView {
                                        VStack(spacing: DS.Space.xs) {
                                            ForEach(allDay, id: \.occurrenceID) { event in
                                                Button(event.title) { selected = event }.buttonStyle(.plain).font(DS.Font.caption).lineLimit(1)
                                                    .padding(DS.Space.xs).frame(maxWidth: .infinity, alignment: .leading)
                                                    .background(DS.Color.calendarEvent, in: .rect(cornerRadius: DS.Radius.sm)).help(event.title)
                                            }
                                        }
                                    }.frame(height: min(DS.Layout.calendarAllDayMaximumHeight, CGFloat(allDay.count) * DS.Layout.calendarMinimumEventHeight))
                                    .padding(.horizontal, DS.Space.xs).padding(.bottom, DS.Space.sm)
                                }
                            }.frame(width: columnWidth, alignment: .leading)
                        }
                    }
                    Divider()
                    ScrollViewReader { scroll in
                        ScrollView(.vertical) {
                            HStack(alignment: .top, spacing: DS.Space.zero) {
                                VStack(alignment: .trailing, spacing: DS.Space.zero) {
                                    ForEach(0..<24, id: \.self) { hour in
                                        Readout(String(format: "%02d:00", hour), color: DS.Color.textSecondary)
                                            .frame(width: DS.Layout.calendarTimeWidth, height: DS.Layout.calendarHourHeight, alignment: .topTrailing)
                                            .id(hour)
                                    }
                                }
                                ForEach(days, id: \.self) { day in timelineColumn(day, columnWidth: columnWidth) }
                            }
                        }.onAppear { scroll.scrollTo(DS.Layout.calendarOpeningHour, anchor: .top) }
                    }
                }.frame(width: DS.Layout.calendarTimeWidth + columnWidth * CGFloat(days.count), height: geometry.size.height)
            }
        }
    }
    private func matching(_ day: Date) -> [CalendarEvent] {
        let end = Calendar.current.date(byAdding: .day, value: 1, to: day) ?? day
        return events.filter { $0.displayStart < end && $0.displayEnd > day && (query.isEmpty || $0.title.localizedCaseInsensitiveContains(query)) }
    }
    private struct PositionedEvent: Identifiable {
        let event: CalendarEvent
        let placement: CalendarTimelineLayout.Placement
        var id: String { event.occurrenceID }
    }
    private func positions(_ day: Date) -> [PositionedEvent] {
        let calendar = Calendar.current, end = calendar.date(byAdding: .day, value: 1, to: day) ?? day
        func minute(_ date: Date) -> Double {
            if date <= day { return 0 }; if date >= end { return 1440 }
            let parts = calendar.dateComponents([.hour, .minute], from: date)
            return Double((parts.hour ?? 0) * 60 + (parts.minute ?? 0))
        }
        let visible = matching(day).filter { !$0.isAllDay }
        let byID = Dictionary(uniqueKeysWithValues: visible.map { ($0.occurrenceID, $0) })
        let intervals = visible.map { CalendarTimelineLayout.Interval(id: $0.occurrenceID, start: minute($0.start), end: minute($0.end)) }
        return CalendarTimelineLayout.place(intervals, minimumDuration: Double(DS.Layout.calendarMinimumEventHeight / DS.Layout.calendarHourHeight * 60)).compactMap { position in
            byID[position.id].map { PositionedEvent(event: $0, placement: position) }
        }
    }
    private func timelineColumn(_ day: Date, columnWidth: CGFloat) -> some View {
        let placed = positions(day)
        return ZStack(alignment: .topLeading) {
            VStack(spacing: DS.Space.zero) {
                ForEach(0..<24, id: \.self) { _ in
                    Divider().frame(height: DS.Layout.calendarHourHeight, alignment: .top)
                }
            }
            ForEach(placed) { item in
                let width = columnWidth / CGFloat(item.placement.columns)
                let height = CGFloat(item.placement.end - item.placement.start) / 60 * DS.Layout.calendarHourHeight
                timelineEvent(item, width: width, height: height)
                    .offset(x: CGFloat(item.placement.lane) * width + DS.Space.xxs, y: CGFloat(item.placement.start) / 60 * DS.Layout.calendarHourHeight)
            }
        }.frame(width: columnWidth, height: 24 * DS.Layout.calendarHourHeight)
            .overlay(alignment: .trailing) { Rectangle().fill(DS.Color.separator).frame(width: DS.Stroke.hairline) }
    }
    private func timelineEvent(_ item: PositionedEvent, width: CGFloat, height: CGFloat) -> some View {
        let detailed = height >= DS.Layout.calendarEventDetailHeight
        let time = item.event.start.formatted(.dateTime.hour().minute())
        return Button { selected = item.event } label: {
            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                Text(item.event.title).font(DS.Font.caption).lineLimit(height >= DS.Layout.calendarEventTitleWrapHeight ? 2 : 1)
                if detailed { Readout(time, color: DS.Color.textSecondary) }
            }.padding(DS.Space.xxs)
                .frame(width: width - DS.Space.xs, height: max(DS.Space.zero, height - DS.Space.xxs), alignment: .topLeading)
                .background(DS.Color.calendarEvent, in: RoundedRectangle(cornerRadius: DS.Radius.sm))
        }.buttonStyle(.plain)
            .help(item.event.title + " · " + time + "–" + item.event.end.formatted(.dateTime.hour().minute()))
            .accessibilityLabel(item.event.title + ", " + time)
    }
    private func dayColumn(_ day: Date) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            Text(day.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                .font(DS.Font.headline).foregroundStyle(DS.Color.textSecondary)
            let matching = events.filter { $0.displayStart < Calendar.current.date(byAdding: .day, value: 1, to: day)! && $0.displayEnd > day && (query.isEmpty || $0.title.localizedCaseInsensitiveContains(query)) }
            if matching.isEmpty { Text("No meetings").font(DS.Font.body).foregroundStyle(DS.Color.textTertiary).padding(.vertical, DS.Space.lg) }
            ForEach(matching, id: \.occurrenceID) { event in
                Button { selected = event } label: {
                    HStack(alignment: .top, spacing: DS.Space.lg) {
                        if mode != "Week" {
                            Readout(event.isAllDay ? "All day" : event.start.formatted(.dateTime.hour().minute()) + "–" + event.end.formatted(.dateTime.hour().minute()), color: DS.Color.textSecondary)
                                .frame(width: DS.Layout.calendarTimeWidth, alignment: .leading)
                        }
                        VStack(alignment: .leading, spacing: DS.Space.xs) {
                            if mode == "Week" {
                                Readout(event.isAllDay ? "All day" : event.start.formatted(.dateTime.hour().minute()) + "–" + event.end.formatted(.dateTime.hour().minute()), color: DS.Color.textSecondary)
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
                let matches = events.filter { $0.displayStart < Calendar.current.date(byAdding: .day, value: 1, to: day)! && $0.displayEnd > day && (query.isEmpty || $0.title.localizedCaseInsensitiveContains(query)) }
                VStack(alignment: .leading, spacing: DS.Space.sm) {
                    Button { date = day; mode = "Day" } label: {
                        Readout(String(Calendar.current.component(.day, from: day)), color: Calendar.current.isDate(day, equalTo: date, toGranularity: .month) ? DS.Color.text : DS.Color.textSecondary)
                            .padding(DS.Space.xs)
                            .background(Calendar.current.isDateInToday(day) ? DS.Color.selection : .clear, in: .rect(cornerRadius: DS.Radius.sm))
                    }.buttonStyle(.plain).accessibilityLabel(day.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                    ForEach(Array(matches.prefix(DS.Layout.calendarMonthPreviewCount)), id: \.occurrenceID) { event in
                        Button { selected = event } label: {
                            HStack(spacing: DS.Space.xs) {
                                Readout(event.isAllDay ? "All day" : event.start.formatted(.dateTime.hour().minute()), color: DS.Color.textSecondary)
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
        events = CalendarService.shared.events(from: start, to: end, cloudEvents: CloudAccount.shared.isConnected && (calendarStore.hasAuthoritativeSnapshot || !calendarStore.events.isEmpty) ? calendarStore.events : nil).filter { source.isEmpty || $0.calendarSourceID == source }
    }
}

struct ConnectionsWorkspace: View {
    var body: some View { ConnectedAppsWorkspace() }
}

extension Notification.Name {
    static let murmurShowPage = Notification.Name("com.jasonhunt.murmur.showPage")
}
