import AppKit
import MurmurSessions
import SwiftUI

struct ConnectionsView: View {
    @State private var account = CloudAccount.shared
    @State private var copied = false
    @State private var localConfigured = ClaudeDesktopIntegration.isConfigured
    @State private var allowWrites = ClaudeDesktopIntegration.allowsWrites
    @State private var localMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.xxl) {
                VStack(alignment: .leading, spacing: DS.Space.sm) {
                    Text("Connections").font(DS.Font.pageTitle)
                    Text("Google Calendar and the apps connected to your Voice Notes account.")
                        .font(DS.Font.documentBody).foregroundStyle(DS.Color.textSecondary).padding(.top, DS.Space.md)
                }
                AccountCard()
                connectorSection
                CalendarAccountDetails()
                Divider()
                localSection
            }
            .padding(DS.Space.page)
            .frame(maxWidth: DS.Layout.documentWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(DS.Color.surface)
        .task(id: copied) {
            guard copied else { return }
            do { try await Task.sleep(for: DS.Timing.feedback); copied = false } catch {}
        }
    }
    private var connectorSection: some View {
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            Label("One link. Your whole library.", systemImage: "link").font(DS.Font.documentHeading)
            Text("Add Voice Notes in ChatGPT or Claude’s connector settings. Paste this URL, choose OAuth, and sign in. Your synced notes are available even when this Mac is asleep.")
                .font(DS.Font.body).foregroundStyle(DS.Color.textSecondary)
            HStack(spacing: DS.Space.md) {
                Text(account.mcpURL.absoluteString).font(DS.Font.readout).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                ActionButton(title: copied ? "Copied" : "Copy URL", systemImage: copied ? "checkmark" : "doc.on.doc", emphasis: .normal) {
                    NSPasteboard.general.clearContents(); NSPasteboard.general.setString(account.mcpURL.absoluteString, forType: .string); copied = true
                }
            }
            .padding(DS.Space.md)
            .background(DS.Color.window, in: .rect(cornerRadius: DS.Radius.md))
            Text("“What did we decide last week?”    “Help me prepare for my next meeting.”")
                .font(DS.Font.documentBody).italic().foregroundStyle(DS.Color.textSecondary)
            Text("Connected AI apps can read synced notes and your calendar agenda. They cannot edit them. Text they request is shared with that provider.")
                .font(DS.Font.caption).foregroundStyle(DS.Color.textTertiary)
            ActionButton(title: "Manage connected apps", systemImage: "arrow.up.right", emphasis: .quiet) {
                NSWorkspace.shared.open(account.siteURL.appendingPathComponent("connections"))
            }
        }
    }
    private var localSection: some View {
        DisclosureGroup("Advanced · connect directly to this Mac") {
            VStack(alignment: .leading, spacing: DS.Space.lg) {
                Text("Claude Desktop, Cursor and local MCP clients can read this Mac’s files without a cloud account. This Mac must be running.")
                    .font(DS.Font.body).foregroundStyle(DS.Color.textSecondary)
                Toggle("Allow local Claude to save summaries", isOn: $allowWrites).font(DS.Font.body).toggleStyle(.switch)
                HStack(spacing: DS.Space.sm) {
                    ActionButton(title: localConfigured ? "Update local Claude connection" : "Set up local Claude", emphasis: .normal) {
                        do { try ClaudeDesktopIntegration.configure(allowWrites: allowWrites); localConfigured = true; localMessage = "Configured. Quit and reopen Claude Desktop to load this connection." }
                        catch { localMessage = error.localizedDescription }
                    }
                    ActionButton(title: "Open notes folder", systemImage: "folder", emphasis: .quiet) { NSWorkspace.shared.open(SessionStore.defaultRoot) }
                }
                if let localMessage { Text(localMessage).font(DS.Font.caption).foregroundStyle(DS.Color.textSecondary) }
            }.padding(.top, DS.Space.lg)
        }.font(DS.Font.callout)
    }
}
