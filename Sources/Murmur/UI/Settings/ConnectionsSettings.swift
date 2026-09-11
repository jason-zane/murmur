import AppKit
import MurmurSessions
import SwiftUI

/// What works without an account comes first. Signed in, the account leads and the rest
/// follows; signed out, Claude Desktop is the whole story and the account is an offer.
struct ConnectionsSettings: View {
    @State private var account = CloudAccount.shared

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            if account.isConnected {
                AccountCard()
                Card { CalendarAccountDetails() }
                ConnectedAppsCard()
                ClaudeDesktopCard()
            } else {
                ClaudeDesktopCard()
                AccountCard()
            }
        }
    }
}

// MARK: - Claude Desktop

/// The local connection: Claude Desktop reads this Mac's notes through the bundled MCP
/// server. No account, nothing leaves the machine.
private struct ClaudeDesktopCard: View {
    @State private var configured = ClaudeDesktopIntegration.isConfigured
    @State private var allowWrites = ClaudeDesktopIntegration.allowsWrites
    @State private var message: String?
    @State private var copied = false

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: DS.Space.md) {
                SectionLabel(text: "Claude Desktop")
                HStack(alignment: .top, spacing: DS.Space.md) {
                    VStack(alignment: .leading, spacing: DS.Space.xxs) {
                        Text("Let Claude read your notes on this Mac").font(DS.Font.headline).foregroundStyle(DS.Color.text)
                        Hint(configured ? "Connected. Works while Voice Notes is running."
                             : "Ask about last week's decisions, or have a note summarised. Nothing leaves this Mac.")
                    }
                    Spacer(minLength: DS.Space.md)
                    if configured { Chip(text: "Connected", tint: DS.Color.success, filled: true) }
                }
                ToggleRow(
                    title: "Let Claude save summaries into your notes",
                    hint: "Otherwise Claude can only read.",
                    isOn: $allowWrites
                )
                HStack(spacing: DS.Space.sm) {
                    ActionButton(title: configured ? "Update connection" : "Connect Claude Desktop", emphasis: .prominent) {
                        do {
                            try ClaudeDesktopIntegration.configure(allowWrites: allowWrites)
                            configured = true
                            message = "Configured. Quit and reopen Claude Desktop to load this connection."
                        } catch { message = error.localizedDescription }
                    }
                    ActionButton(title: "Open notes folder", systemImage: "folder", emphasis: .quiet) {
                        NSWorkspace.shared.open(SessionStore.defaultRoot)
                    }
                }
                if let message { Hint(message) }
                DisclosureGroup("Using another app? Copy this configuration") {
                    VStack(alignment: .leading, spacing: DS.Space.sm) {
                        Text(ClaudeDesktopIntegration.snippet(allowWrites: allowWrites))
                            .font(DS.Font.readout)
                            .foregroundStyle(DS.Color.text)
                            .textSelection(.enabled)
                            .padding(DS.Space.md)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(DS.Color.surface, in: .rect(cornerRadius: DS.Radius.sm))
                        ActionButton(title: copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc", emphasis: .quiet) {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(ClaudeDesktopIntegration.snippet(allowWrites: allowWrites), forType: .string)
                            copied = true
                        }
                        Hint("Any MCP app can run the same command. It only answers while Voice Notes is running.")
                    }
                    .padding(.top, DS.Space.sm)
                }
                .font(DS.Font.callout)
            }
        }
        .task(id: copied) {
            guard copied else { return }
            do { try await Task.sleep(for: DS.Timing.feedback); copied = false } catch {}
        }
    }
}

// MARK: - Account

struct AccountCard: View {
    @State private var account = CloudAccount.shared
    @State private var sync = CloudSync.shared
    @State private var confirmSignOut = false

    private var tint: Color { sync.state.isProblem ? DS.Color.warning : DS.Color.textSecondary }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: DS.Space.lg) {
                SectionLabel(text: "Voice Notes account")
                HStack(spacing: DS.Space.md) {
                    Image(systemName: "person.crop.circle")
                        .font(DS.Font.largeSymbol).foregroundStyle(DS.Color.accent)
                        .frame(width: DS.Account.avatarSize, height: DS.Account.avatarSize)
                        .background(DS.Color.accentSoft, in: .rect(cornerRadius: DS.Radius.md))
                    VStack(alignment: .leading, spacing: DS.Space.xs) {
                        Text(account.isConnected ? "Signed in as" : "Not signed in")
                            .font(DS.Font.caption).foregroundStyle(DS.Color.textSecondary)
                        Text(account.isConnected ? account.email : "Your notes stay on this Mac")
                            .font(DS.Font.headline).textSelection(.enabled)
                    }
                    Spacer(minLength: DS.Space.md)
                    if account.isConnected {
                        ActionButton(title: "Sign out", emphasis: .quiet) { confirmSignOut = true }
                    } else {
                        ActionButton(title: account.isSigningIn ? "Signing in…" : "Sign in", systemImage: "arrow.right", emphasis: .normal) {
                            Task { await account.signIn() }
                        }.disabled(account.isSigningIn)
                    }
                }
                if account.isConnected {
                    if let label = sync.state.label {
                        HStack(spacing: DS.Space.sm) {
                            if let symbol = sync.state.symbol {
                                Image(systemName: symbol).font(DS.Font.smallSymbol).foregroundStyle(tint)
                            }
                            Text(label).font(DS.Font.callout).foregroundStyle(tint)
                            if sync.state == .signInRequired {
                                ActionButton(title: account.isSigningIn ? "Signing in…" : "Sign in again", emphasis: .normal) {
                                    Task { await account.signIn() }
                                }.disabled(account.isSigningIn)
                            }
                        }
                    }
                    if sync.state.isProblem, let message = account.message ?? sync.message { Hint(message) }
                    if !sync.issues.isEmpty {
                        DisclosureGroup(sync.issues.count == 1 ? "Which note" : "Which notes") {
                            VStack(alignment: .leading, spacing: DS.Space.md) {
                                ForEach(sync.issues) { issue in
                                    VStack(alignment: .leading, spacing: DS.Space.xs) {
                                        Text(issue.title).font(DS.Font.callout)
                                        Hint(issue.message)
                                    }
                                }
                                ActionButton(title: sync.isSyncing ? "Trying…" : "Try again", systemImage: "arrow.triangle.2.circlepath", emphasis: .normal) {
                                    Task { await sync.sync() }
                                }.disabled(sync.isSyncing)
                            }.padding(.top, DS.Space.md)
                        }.font(DS.Font.caption)
                    }
                    ActionButton(title: "Manage account on the web", systemImage: "arrow.up.right", emphasis: .quiet) {
                        NSWorkspace.shared.open(account.siteURL.appendingPathComponent("settings"))
                    }
                } else {
                    if let message = account.message { Hint(message) }
                    Hint("Optional. Signing in puts your notes on the web, connects Google Calendar, and lets ChatGPT or Claude read them from anywhere.")
                }
            }
        }
        .alert("Sign out of Voice Notes?", isPresented: $confirmSignOut) {
            Button("Sign out", role: .destructive) { account.signOut() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your notes stay on this Mac. Syncing stops until you sign in again.")
        }
    }
}

// MARK: - Connected apps

/// ChatGPT, Claude and anything else that speaks MCP, through the hosted connector.
private struct ConnectedAppsCard: View {
    @State private var account = CloudAccount.shared
    @State private var copied = false

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: DS.Space.md) {
                SectionLabel(text: "Connected apps")
                Text("Let ChatGPT or Claude read your synced notes from anywhere").font(DS.Font.headline).foregroundStyle(DS.Color.text)
                Hint("Add it in ChatGPT or Claude as a connector and sign in. Connected apps can read your notes and agenda; they can't change them. Text they request is shared with that provider.")
                HStack(spacing: DS.Space.md) {
                    Text(account.mcpURL.absoluteString).font(DS.Font.readout).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    ActionButton(title: copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc", emphasis: .normal) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(account.mcpURL.absoluteString, forType: .string)
                        copied = true
                    }
                }
                .padding(DS.Space.md)
                .background(DS.Color.surface, in: .rect(cornerRadius: DS.Radius.md))
                ActionButton(title: "Manage connected apps", systemImage: "arrow.up.right", emphasis: .quiet) {
                    NSWorkspace.shared.open(account.siteURL.appendingPathComponent("connections"))
                }
            }
        }
        .task(id: copied) {
            guard copied else { return }
            do { try await Task.sleep(for: DS.Timing.feedback); copied = false } catch {}
        }
    }
}

// MARK: - Google Calendar

struct CalendarAccountDetails: View {
    @State private var account = CloudAccount.shared
    @State private var sync = CloudSync.shared

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            SectionLabel(text: "Google Calendar")
            HStack(alignment: .top, spacing: DS.Space.md) {
                VStack(alignment: .leading, spacing: DS.Space.xxs) {
                    Text(status).font(DS.Font.body).foregroundStyle(DS.Color.text).textSelection(.enabled)
                    Hint("Your calendar provides meeting names, people and links. Booking permissions and optional email sending are managed separately.")
                    if let error = sync.calendarError { Hint(error) }
                }
                Spacer(minLength: DS.Space.md)
                ActionButton(title: sync.calendarConnected ? "Manage" : "Connect", systemImage: "arrow.up.right", emphasis: .normal) {
                    NSWorkspace.shared.open(account.siteURL.appendingPathComponent("connections"))
                }
            }
        }
    }

    private var status: String {
        if !account.isConnected { return "Sign in to connect Google Calendar." }
        if sync.calendarConnected {
            if let email = sync.calendarEmail, !email.isEmpty { return "Connected as " + email }
            return "Connected"
        }
        return sync.isSyncing ? "Checking connection…" : "Not connected"
    }
}
