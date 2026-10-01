import AppKit
import SwiftUI

// THESIS: Connect a useful part of the day before learning configuration.
// OWN-WORLD: Native lists, semantic surfaces and one indigo action accent.
// STORY: Choose calendars, Gmail or AI assistance; authorise only that action.
// FIRST VIEWPORT: Three task rows precede optional account maintenance.
// FORM: Task-led setup within the established native world; no brand replacement.
struct ConnectedAppsWorkspace: View {
    @State private var account = CloudAccount.shared
    @State private var sync = CloudSync.shared
    @State private var destination: String?
    @State private var configured = ClaudeDesktopIntegration.isConfigured
    @State private var message: String?
    @State private var advanced = false
    @State private var showWelcome = false
    @State private var localAuthorised = CalendarService.shared.isAuthorized

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.xxl) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: DS.Space.sm) {
                        Text("Connected apps").font(DS.Font.title)
                        Hint("Bring your day together. Connect only what you want to use.")
                    }
                    Spacer()
                    ActionButton(title: "Setup guide", emphasis: .quiet) { showWelcome = true }
                }
                if !account.isConnected {
                    VStack(alignment: .leading, spacing: DS.Space.md) {
                        Text("Start with your Concourse account").font(DS.Font.headline)
                        Hint("Sign in once, then connect your calendars and Gmail. Your downloaded content stays available offline.")
                        ActionButton(title: account.isSigningIn ? "Signing in…" : "Sign in to Concourse", emphasis: .prominent) { Task { await account.signIn() } }.disabled(account.isSigningIn)
                        if let message = account.message { InlineNotice(text: message, tone: .warning) }
                    }
                } else {
                    Label(account.email, systemImage: "checkmark.circle").font(DS.Font.callout).foregroundStyle(DS.Color.textSecondary)
                }
                VStack(spacing: DS.Space.zero) {
                    connection("Google Calendar", icon: "calendar", detail: sync.calendarConnected ? "Account linked. Manage calendars to check each account’s status, retry updates or reconnect." : "Work and personal calendars together, including past meetings.", action: sync.calendarConnected ? "Manage calendars" : "Connect Google Calendar") { destination = "/connections?focus=calendar" }
                    Divider()
                    connection("Gmail", icon: "envelope", detail: "Read, reply and organise work and personal inboxes. Google asks for mailbox access separately.", action: "Connect or manage Gmail") { destination = "/connections?focus=gmail" }
                    Divider()
                    connection("Calendars on this Mac", icon: "desktopcomputer", detail: localAuthorised ? "Available offline. Choose which calendars appear from Calendar ▸ Calendars." : "Use the accounts already set up in Apple Calendar.", action: localAuthorised ? "Open Calendar" : "Allow calendars") {
                        if localAuthorised { NotificationCenter.default.post(name: .murmurShowPage, object: MainPage.calendar) }
                        else if CalendarService.shared.isDenied { CalendarService.openSettings() }
                        else { Task { localAuthorised = await CalendarService.shared.requestAccess() } }
                    }
                }
                VStack(alignment: .leading, spacing: DS.Space.lg) {
                    Text("Ask about your notes").font(DS.Font.headline)
                    Hint("Connected AI apps can read your note library and agenda. Text they request is shared with that provider; Gmail stays private to this workspace.")
                    connection("Claude Desktop", icon: "text.bubble", detail: configured ? "Configured on this Mac. Restart Claude Desktop after changing the connection." : "Connect Claude Desktop to this Mac’s notes. Text it requests is shared with Claude; no Concourse account needed.", action: configured ? "Open Claude Desktop" : "Connect Claude Desktop") {
                        do {
                            if configured { NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: "/Applications/Claude.app"), configuration: NSWorkspace.OpenConfiguration()) }
                            else { try ClaudeDesktopIntegration.configure(); configured = true; message = "Connected. Quit and reopen Claude Desktop to load your notes." }
                        } catch { message = error.localizedDescription }
                    }
                    connection("ChatGPT and Claude on the web", icon: "sparkles", detail: "Read synced notes and your agenda from an AI app. Setup opens a short provider guide.", action: "Set up AI apps") { destination = "/connections?focus=ai" }
                    if let message { InlineNotice(text: message, tone: .info) }
                }
                DisclosureGroup("Account and advanced connection settings", isExpanded: $advanced) {
                    ConnectionsSettings().padding(.top, DS.Space.lg)
                }.font(DS.Font.callout)
            }.padding(DS.Space.xxl).frame(maxWidth: .infinity, alignment: .leading)
        }
        .task {
            while !Task.isCancelled {
                localAuthorised = CalendarService.shared.isAuthorized
                configured = ClaudeDesktopIntegration.isConfigured
                do { try await Task.sleep(for: DS.Timing.permissionPoll) } catch { return }
            }
        }
        .sheet(isPresented: Binding(get: { destination != nil }, set: { if !$0 { destination = nil } })) {
            VStack(spacing: DS.Space.zero) {
                HStack { Text("Connect your apps").font(DS.Font.headline); Spacer(); ActionButton(title: "Done", emphasis: .normal) { destination = nil } }.padding(DS.Space.lg)
                Divider()
                if account.isConnected { CloudWorkspace(path: destination ?? "/connections") }
                else {
                    VStack(alignment: .leading, spacing: DS.Space.lg) {
                        Text("Sign in to connect your apps").font(DS.Font.title)
                        Hint("A Concourse account keeps your Google connections together and syncs your notes. You’ll choose the Google accounts and permissions next.")
                        ActionButton(title: account.isSigningIn ? "Signing in…" : "Sign in to Concourse", emphasis: .prominent) { Task { await account.signIn() } }.disabled(account.isSigningIn)
                        if let message = account.message { InlineNotice(text: message, tone: .warning) }
                        Spacer()
                    }.padding(DS.Space.xxl)
                }
            }.frame(width: DS.Layout.settingsWidth, height: DS.Layout.windowHeight)
        }
        .sheet(isPresented: $showWelcome) {
            WorkspaceWelcome { target in
                showWelcome = false
                if let target { NotificationCenter.default.post(name: .murmurShowPage, object: target) }
            }
        }
    }

    private func connection(_ title: String, icon: String, detail: String, action: String, perform: @escaping () -> Void) -> some View {
        HStack(alignment: .top, spacing: DS.Space.lg) {
            Image(systemName: icon).font(DS.Font.symbol).foregroundStyle(DS.Color.accent).frame(width: DS.Layout.brandMark)
            VStack(alignment: .leading, spacing: DS.Space.sm) { Text(title).font(DS.Font.bodyEmphasis); Hint(detail) }
            Spacer(minLength: DS.Space.lg)
            ActionButton(title: action, emphasis: .normal, action: perform)
        }.padding(.vertical, DS.Space.lg)
    }
}

struct WorkspaceWelcome: View {
    let onDone: (MainPage?) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xl) {
            HStack { Image(systemName: "waveform").font(DS.Font.largeSymbol).foregroundStyle(DS.Color.accent); Spacer(); ActionButton(title: "Not now", emphasis: .quiet) { onDone(nil) } }
            Text("Your day, in one place").font(DS.Font.documentTitle)
            Hint("Sign in to Concourse, connect your Google calendars and Gmail, then move between your day and your notes.")
            VStack(alignment: .leading, spacing: DS.Space.lg) {
                Label("Calendar · connect work and personal accounts", systemImage: "calendar")
                Label("Mail · bring your Gmail inboxes together", systemImage: "envelope")
                Label("Notes · write, record and find decisions", systemImage: "book.closed")
            }.font(DS.Font.body)
            Hint("Your downloaded content stays available offline. You can revisit setup from Connected apps.")
            Spacer(minLength: DS.Space.zero)
            HStack { ActionButton(title: "Set up my workspace", emphasis: .prominent) { onDone(.connections) }; ActionButton(title: "Start with Today", emphasis: .normal) { onDone(.home) } }
        }.padding(DS.Space.xxl).frame(width: DS.Layout.sheetNarrow, height: DS.Layout.sheetHeight).background(DS.Color.window)
    }
}
