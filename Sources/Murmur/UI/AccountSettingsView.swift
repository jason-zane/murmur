import AppKit
import SwiftUI

/// Shared with Connections so account identity and sync status use the same language.
struct AccountCard: View {
    @State private var account = CloudAccount.shared
    @State private var sync = CloudSync.shared

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: DS.Space.lg) {
                SectionLabel(text: "Account")
                HStack(spacing: DS.Space.md) {
                    Image(systemName: "person.crop.circle")
                        .font(DS.Font.largeSymbol).foregroundStyle(DS.Color.accent)
                        .frame(width: DS.Account.avatarSize, height: DS.Account.avatarSize)
                        .background(DS.Color.accentSoft, in: .rect(cornerRadius: DS.Radius.md))
                    VStack(alignment: .leading, spacing: DS.Space.xs) {
                        Text(account.isConnected ? "Signed in as" : "Not signed in")
                            .font(DS.Font.caption).foregroundStyle(DS.Color.textSecondary)
                        Text(account.isConnected ? account.email : "Your notes are on this Mac")
                            .font(DS.Font.headline).textSelection(.enabled)
                    }
                }
                Hint("Use the same account on your Mac and the web to see the same notes.")
                Divider()
                if account.isConnected {
                    Label(sync.status, systemImage: sync.needsAttention ? "icloud.slash" : "icloud")
                        .font(DS.Font.bodyEmphasis).foregroundStyle(DS.Color.textSecondary)
                    HStack(spacing: DS.Space.md) {
                        if sync.requiresSignIn {
                            ActionButton(title: account.isSigningIn ? "Signing in…" : "Sign in again", systemImage: "arrow.right", emphasis: .prominent) {
                                Task { await account.signIn() }
                            }.disabled(account.isSigningIn)
                        } else {
                            ActionButton(title: sync.isSyncing ? "Syncing…" : "Sync now", systemImage: "arrow.triangle.2.circlepath", emphasis: .prominent) {
                                Task { await sync.sync() }
                            }.disabled(sync.isSyncing)
                        }
                        ActionButton(title: "Open web settings", systemImage: "arrow.up.right", emphasis: .quiet) {
                            NSWorkspace.shared.open(account.siteURL.appendingPathComponent("settings"))
                        }
                        Spacer(minLength: DS.Space.zero)
                        ActionButton(title: "Sign out", emphasis: .quiet) { account.signOut() }
                    }
                } else {
                    ActionButton(title: account.isSigningIn ? "Signing in…" : "Sign in to Voice Notes", systemImage: "arrow.right", emphasis: .prominent) {
                        Task { await account.signIn() }
                    }.disabled(account.isSigningIn)
                }
                if let message = account.message ?? sync.message { Hint(message) }
                if !sync.issues.isEmpty {
                    DisclosureGroup("Notes waiting to sync") {
                        VStack(alignment: .leading, spacing: DS.Space.md) {
                            ForEach(sync.issues) { issue in
                                VStack(alignment: .leading, spacing: DS.Space.xs) {
                                    Text(issue.title).font(DS.Font.callout)
                                    Hint(issue.message)
                                }
                            }
                        }.padding(.top, DS.Space.md)
                    }.font(DS.Font.caption)
                }
                Hint("Signing out on this Mac keeps your local notes and stops syncing.")
            }
        }
    }
}

struct CalendarAccountDetails: View {
    @State private var account = CloudAccount.shared
    @State private var sync = CloudSync.shared

    var body: some View {
        HStack(alignment: .top, spacing: DS.Space.lg) {
            Image(systemName: "calendar").font(DS.Font.largeSymbol).foregroundStyle(DS.Color.textSecondary)
            VStack(alignment: .leading, spacing: DS.Space.sm) {
                Text("Google Calendar").font(DS.Font.headline)
                Text(status).font(DS.Font.body).foregroundStyle(DS.Color.textSecondary)
                    .textSelection(.enabled)
                if let error = sync.calendarError { Hint(error) }
                Hint("Read-only access to your upcoming meetings. Manage this connection on the web.")
                ActionButton(title: sync.calendarConnected ? "Manage connection" : "Connect Google Calendar", systemImage: "arrow.up.right", emphasis: .normal) {
                    NSWorkspace.shared.open(account.siteURL.appendingPathComponent("connections"))
                }
            }
        }
    }

    private var status: String {
        if !account.isConnected { return "Sign in to see your connected calendar." }
        if sync.calendarConnected {
            if let email = sync.calendarEmail, !email.isEmpty { return "Connected as " + email }
            return "Connected"
        }
        return sync.isSyncing ? "Checking connection…" : "Not connected"
    }
}

struct AccountSettingsCards: View {
    @State private var account = CloudAccount.shared

    var body: some View {
        AccountCard()
        Card {
            VStack(alignment: .leading, spacing: DS.Space.lg) {
                SectionLabel(text: "Connections")
                CalendarAccountDetails()
                Divider()
                Text("Connected apps").font(DS.Font.headline)
                Hint("Connect ChatGPT, Claude and other apps to read your synced notes. Review or revoke their access in Connections.")
                ActionButton(title: "Manage connected apps", systemImage: "arrow.up.right", emphasis: .quiet) {
                    NSWorkspace.shared.open(account.siteURL.appendingPathComponent("connections"))
                }
            }
        }
        Card {
            VStack(alignment: .leading, spacing: DS.Space.md) {
                SectionLabel(text: "Your data")
                Hint("Audio stays on this Mac. Completed notes and transcripts sync privately to your account. You can keep recording and editing offline.")
                ActionButton(title: "Your data & privacy", systemImage: "arrow.up.right", emphasis: .quiet) {
                    NSWorkspace.shared.open(account.siteURL.appendingPathComponent("privacy"))
                }
            }
        }
    }
}
