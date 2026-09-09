import AppKit
import MurmurSessions
import SwiftUI

struct MeetingHomeView: View {
    let onRecord: () -> Void
    let onNewNote: () -> Void
    @State private var schedule = MeetingSchedule.shared
    @State private var settings = MeetingSettings.shared
    @State private var requesting = false
    @State private var audioGranted = SystemAudioCapture.isKnownGranted
    @State private var microphoneGranted = Permissions.hasMicrophone
    @State private var audioRequesting = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.xxl) {
                VStack(alignment: .leading, spacing: DS.Space.lg) {
                    Readout(Date().formatted(.dateTime.weekday(.wide).day().month(.wide)), color: DS.Color.textTertiary)
                    HStack(spacing: DS.Space.lg) {
                        VStack(alignment: .leading, spacing: DS.Space.zero) {
                            Text("Room for the").font(DS.Font.heroTitle).foregroundStyle(DS.Color.conversationInk)
                            Text("conversation.").font(DS.Font.heroEmphasis).foregroundStyle(DS.Color.accent)
                            Text("Bring your attention. Keep every good idea.")
                                .font(DS.Font.body).foregroundStyle(DS.Color.textSecondary)
                                .padding(.top, DS.Space.lg)
                        }
                        Spacer(minLength: DS.Space.zero)
                        Image(systemName: "waveform").font(DS.Font.heroSymbol)
                            .foregroundStyle(DS.Color.conversationWave)
                            .rotationEffect(.degrees(DS.Layout.heroTilt))
                            .frame(width: DS.Layout.heroSymbol)
                            .accessibilityHidden(true)
                    }
                    .padding(DS.Space.xl)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(DS.Color.conversationSurface, in: .rect(cornerRadius: DS.Radius.lg))
                    HStack(spacing: DS.Space.md) {
                        ActionButton(title: "Record a conversation", systemImage: "mic", emphasis: .prominent, action: onRecord)
                        ActionButton(title: "Start a note", systemImage: "square.and.pencil", emphasis: .quiet, action: onNewNote)
                    }
                }
                agenda
                if !microphoneGranted || !audioGranted { audioSetup }
                VStack(alignment: .leading, spacing: DS.Space.md) {
                    Label("Made for the way you meet", systemImage: "waveform.and.mic")
                        .font(DS.Font.headline).foregroundStyle(DS.Color.text)
                    Text("When a call starts in Google Meet, Zoom or Teams, Voice Notes can capture both sides. Add your own notes along the way, then turn the conversation into a summary.")
                        .font(DS.Font.body).foregroundStyle(DS.Color.textSecondary)
                        .lineSpacing(DS.Layout.proseLineSpacing)
                    HStack(spacing: DS.Space.md) {
                        Label("On-device transcription", systemImage: "laptopcomputer")
                        Label("No meeting bot", systemImage: "person.crop.circle")
                    }.font(DS.Font.caption).foregroundStyle(DS.Color.textTertiary)
                }
                .padding(.top, DS.Space.sm)
            }
            .padding(DS.Space.page)
            .frame(maxWidth: DS.Layout.homeWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(DS.Color.surface)
        .onAppear { schedule.refresh(); microphoneGranted = Permissions.hasMicrophone; audioGranted = SystemAudioCapture.isKnownGranted }
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
                VStack(alignment: .leading, spacing: DS.Space.sm) {
                    Text("A little breathing room.").font(DS.Font.headline)
                    Text("No meetings in the next day. You can still record a conversation or start a note.")
                        .font(DS.Font.body).foregroundStyle(DS.Color.textSecondary)
                    HStack(spacing: DS.Space.sm) {
                        ActionButton(title: "Record a conversation", systemImage: "mic", emphasis: .normal, action: onRecord)
                        ActionButton(title: "Start a note", emphasis: .quiet, action: onNewNote)
                    }.padding(.top, DS.Space.sm)
                }.padding(.vertical, DS.Space.md)
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

    private var audioSetup: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            Text("Before your first call").font(DS.Font.headline)
            if !microphoneGranted {
                HStack(spacing: DS.Space.md) {
                    Label("Hear your voice", systemImage: "mic").font(DS.Font.body)
                    Spacer()
                    ActionButton(title: "Allow microphone", emphasis: .normal) {
                        Task { microphoneGranted = await Permissions.requestMicrophone(); if !microphoneGranted { Permissions.openMicrophoneSettings() } }
                    }
                }
            }
            if !audioGranted {
                HStack(spacing: DS.Space.md) {
                    VStack(alignment: .leading, spacing: DS.Space.xs) {
                        Label("Hear everyone else", systemImage: "speaker.wave.2").font(DS.Font.body)
                        Text("Allow system audio to capture the other side of the call.")
                            .font(DS.Font.caption).foregroundStyle(DS.Color.textSecondary)
                    }
                    Spacer()
                    ActionButton(title: audioRequesting ? "Requesting…" : "Allow call audio", emphasis: .normal) {
                        audioRequesting = true
                        Task { audioGranted = await SystemAudioCapture.requestPermission(); audioRequesting = false }
                    }.disabled(audioRequesting)
                }
            }
        }
        .padding(DS.Space.lg)
        .background(DS.Color.window, in: .rect(cornerRadius: DS.Radius.md))
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
