import AppKit
import MurmurSessions
import SwiftUI

/// What you see with no note selected: today, what's coming up, and — only until they're
/// granted — the permissions a first call needs.
struct HomeView: View {
    let onRecord: () -> Void
    let onNewNote: () -> Void
    @State private var schedule = MeetingSchedule.shared
    @State private var settings = MeetingSettings.shared
    @State private var requesting = false
    @State private var audioGranted = SystemAudioCapture.isKnownGranted
    @State private var microphoneGranted = Permissions.hasMicrophone

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.xxl) {
                Readout(Date().formatted(.dateTime.weekday(.wide).day().month(.wide)), color: DS.Color.textTertiary)
                agenda
                if !microphoneGranted || !audioGranted { setup }
                Hint("Voice Notes offers to record when a call starts in Meet, Zoom or Teams. Change this in Settings ▸ Meetings.")
            }
            .padding(DS.Space.page)
            .frame(maxWidth: DS.Layout.homeWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .onAppear { schedule.refresh(); refreshPermissions() }
        .task {
            while !Task.isCancelled {
                do { try await Task.sleep(for: DS.Timing.refresh) } catch { return }
                refreshPermissions()
            }
        }
    }

    private var agenda: some View {
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            HStack {
                Text("Up next").font(DS.Font.headline)
                Spacer()
                if schedule.calendarGranted {
                    Label(settings.autoOpenMeetings ? "Links open automatically" : "Calendar connected", systemImage: "calendar")
                        .font(DS.Font.caption).foregroundStyle(DS.Color.textSecondary)
                }
            }
            if !settings.calendarEnabled {
                Text("Connect your calendar to see upcoming meetings and open their links on time.")
                    .font(DS.Font.body).foregroundStyle(DS.Color.textSecondary)
                ActionButton(title: "Use my calendar", emphasis: .normal) { settings.calendarEnabled = true; connectCalendar() }
            } else if !schedule.calendarGranted {
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
            } else if schedule.events.isEmpty {
                EmptyState(
                    icon: "calendar",
                    label: "Nothing scheduled",
                    detail: "No meetings in the next day. Record a meeting or write a note any time."
                ) {
                    HStack(spacing: DS.Space.sm) {
                        ActionButton(title: "Record meeting", systemImage: "mic", emphasis: .normal, action: onRecord)
                        ActionButton(title: "New note", emphasis: .quiet, action: onNewNote)
                    }
                }
                .frame(maxHeight: DS.Layout.editorHeight)
            } else {
                VStack(spacing: DS.Space.zero) {
                    ForEach(schedule.events.prefix(6), id: \.occurrenceID) { event in
                        CalendarMeetingRow(event: event, schedule: schedule)
                        Divider()
                    }
                }
            }
            if let message = schedule.message {
                Text(message).font(DS.Font.caption).foregroundStyle(DS.Color.textSecondary)
            }
        }
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

    private func refreshPermissions() {
        microphoneGranted = Permissions.hasMicrophone
        audioGranted = SystemAudioCapture.isKnownGranted
    }

    private func connectCalendar() {
        if CalendarService.shared.isDenied { CalendarService.openSettings(); return }
        requesting = true
        Task { await schedule.requestCalendar(); requesting = false }
    }
}

private struct CalendarMeetingRow: View {
    let event: CalendarEvent
    let schedule: MeetingSchedule
    var body: some View {
        HStack(alignment: .center, spacing: DS.Space.md) {
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                Readout(event.start.formatted(.dateTime.hour().minute()), color: DS.Color.text)
                if !Calendar.current.isDateInToday(event.start) { Text("Tomorrow").font(DS.Font.caption).foregroundStyle(DS.Color.textTertiary) }
            }.frame(width: DS.Layout.transcriptTime, alignment: .leading)
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                Text(event.title).font(DS.Font.bodyEmphasis).lineLimit(2)
                Text(event.conferenceURL.flatMap { MeetingLink.provider(for: $0) } ?? "Calendar meeting")
                    .font(DS.Font.caption).foregroundStyle(DS.Color.textSecondary)
            }
            Spacer(minLength: DS.Space.sm)
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
        }
        .padding(.vertical, DS.Space.lg)
    }
}
