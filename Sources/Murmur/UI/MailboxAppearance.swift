import SwiftUI

struct MailboxAvatar: View {
    let account: MailAccount
    var body: some View {
        if account.icon != .none {
            Group {
                if let symbol = account.icon.symbol { Image(systemName: symbol) }
                else { Text(String(account.label.prefix(1)).uppercased()) }
            }.font(DS.Font.label).frame(width: DS.Layout.mailboxAvatar, height: DS.Layout.mailboxAvatar)
                .foregroundStyle(DS.Color.mailbox(account.colour))
                .background(DS.Color.mailbox(account.colour).opacity(DS.Color.mailboxFillOpacity), in: .rect(cornerRadius: DS.Radius.sm))
                .accessibilityHidden(true)
        }
    }
}
struct MailboxBadge: View {
    let account: MailAccount
    var body: some View {
        HStack(spacing: DS.Space.xs) {
            MailboxAvatar(account: account)
            Text(account.label).font(DS.Font.caption).lineLimit(1).truncationMode(.middle)
        }.foregroundStyle(DS.Color.mailbox(account.colour))
            .padding(.horizontal, DS.Space.xs).padding(.vertical, DS.Space.xxs)
            .background(DS.Color.mailbox(account.colour).opacity(DS.Color.mailboxFillOpacity), in: .rect(cornerRadius: DS.Radius.sm))
            .help(account.label)
    }
}
struct MailboxPreferences: View {
    let account: MailAccount
    let mailbox: MailWorkspaceStore
    let onClose: () -> Void
    @State private var colour: String
    @State private var icon: MailboxIcon
    @State private var busy = false
    @State private var error: String?
    init(account: MailAccount, mailbox: MailWorkspaceStore, onClose: @escaping () -> Void) {
        self.account = account; self.mailbox = mailbox; self.onClose = onClose
        _colour = State(initialValue: account.identity_colour ?? "")
        _icon = State(initialValue: account.icon)
    }
    private var preview: MailAccount {
        var result = account; result.identity_colour = colour.isEmpty ? nil : colour; result.identity_icon = icon.rawValue; return result
    }
    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            Text("Mailbox appearance").font(DS.Font.title)
            MailboxBadge(account: preview)
            Text("Your address stays visible. Colour and icons help distinguish accounts; they never change the sender or permissions.")
                .font(DS.Font.caption).foregroundStyle(DS.Color.textSecondary)
            PickerRow(title: "Colour", selection: $colour, options: [("", "Automatic")] + MailboxColour.allCases.map { ($0.rawValue, $0.title) })
            PickerRow(title: "Icon", selection: $icon, options: MailboxIcon.allCases.map { ($0, $0.title) })
            if let error { InlineNotice(text: error, tone: .warning) }
            Text("Shared with the web workspace. Built-in icons load without contacting a logo service.").font(DS.Font.caption).foregroundStyle(DS.Color.textSecondary)
            HStack {
                ActionButton(title: "Cancel", emphasis: .quiet) { onClose() }
                Spacer()
                ActionButton(title: busy ? "Saving…" : "Save preferences", emphasis: .prominent) {
                    guard !busy else { return }
                    busy = true; error = nil
                    Task {
                        do { try await mailbox.saveIdentity(accountID: account.id, colour: MailboxColour(rawValue: colour), icon: icon); onClose() }
                        catch { self.error = error.localizedDescription }
                        busy = false
                    }
                }
            }
        }.padding(DS.Space.lg).frame(width: DS.Layout.mailboxPreferencesWidth)
            .disabled(busy).interactiveDismissDisabled(busy)
    }
}
