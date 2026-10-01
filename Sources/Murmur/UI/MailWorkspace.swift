import AppKit
import MurmurSessions
import SwiftUI
import UniformTypeIdentifiers

struct MailWorkspace: View {
    @State private var mailbox = MailWorkspaceStore()
    @State private var accountID = ""
    @State private var folder = "in:inbox"
    @State private var query = ""
    @State private var search = ""
    @State private var selected: MailThread?
    @State private var composing: MailDraft?
    @State private var error: String?
    @State private var preferences: MailAccount?
    @State private var fullMailbox = false
    @State private var formatted = true
    private let syntheticPreview = PreviewEnvironment.isActive && PreviewEnvironment.launchAction == "mail"
    init() {
        if PreviewEnvironment.isActive && PreviewEnvironment.launchAction == "mail", let root = PreviewEnvironment.root {
            _mailbox = State(initialValue: MailWorkspaceStore(transport: PreviewMailTransport(), root: root.appendingPathComponent("mail")))
        }
    }
    private let folders = [("Inbox", "in:inbox"), ("Starred", "is:starred"), ("Sent", "in:sent"), ("Archive", "in:all -in:inbox -in:trash -in:spam"), ("Spam", "in:spam"), ("Bin", "in:trash")]
    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            if let error { InlineNotice(text: error, tone: .warning) }
            if let notice = mailbox.notice { InlineNotice(text: notice, tone: .info) }
            if syntheticPreview { Text("Synthetic Mail preview · account actions and sending are disabled.").font(DS.Font.caption).foregroundStyle(DS.Color.textSecondary) }
            if !CloudAccount.shared.isConnected && !syntheticPreview {
                EmptyState(icon: "envelope", label: "Connect Gmail", detail: "Sign in to your Concourse account, then connect Gmail in Connected apps.")
                ActionButton(title: "Connect apps", emphasis: .normal) { NotificationCenter.default.post(name: .murmurShowPage, object: MainPage.connections) }
            } else {
                HStack(spacing: DS.Space.zero) {
                    accountNavigation.frame(width: DS.Layout.mailNavigationWidth)
                    Divider()
                    HSplitView {
                        VStack(alignment: .leading, spacing: DS.Space.zero) {
                            VStack(alignment: .leading, spacing: DS.Space.sm) {
                                Text(folderTitle).font(DS.Font.headline)
                                Text(accountID.isEmpty ? "All accounts" : mailbox.accounts.first { $0.id == accountID }?.label ?? "Gmail")
                                    .font(DS.Font.caption).foregroundStyle(DS.Color.textSecondary).lineLimit(1)
                                SearchField(text: $query, placeholder: mailbox.offline ? "Search downloaded mail" : "Search mail")
                                    .onSubmit { search = query }
                                if mailbox.loading { ProgressView("Updating mail…").controlSize(.small).font(DS.Font.caption) }
                            }.padding(DS.Space.md)
                            Divider()
                            if folder == "drafts" { localDrafts.padding(DS.Space.md) }
                            else if folder == "outbox" { outbox.padding(DS.Space.md) }
                            else { threadList }
                        }.frame(minWidth: DS.Layout.mailListMinimumWidth, idealWidth: DS.Layout.mailListWidth, maxWidth: DS.Layout.mailListMaximumWidth)
                        reader.frame(minWidth: DS.Layout.mailReaderWidth)
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .top) { Divider() }

            }
        }.padding(DS.Space.md)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .navigationTitle("Mail")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("New message", systemImage: "square.and.pencil") { compose() }
                    .disabled(mailbox.accounts.isEmpty).help("Write a new message")
                Menu("Mail options", systemImage: "ellipsis") {
                    Button("Full mailbox") { fullMailbox = true }
                    Menu("Mailbox appearance") { ForEach(mailbox.accounts) { account in Button(account.label) { preferences = account } } }
                    Button("Clear downloaded mail") { do { try mailbox.clearDownloaded(); selected = nil } catch { self.error = error.localizedDescription } }
                    Button("Manage connected accounts") { NotificationCenter.default.post(name: .murmurShowPage, object: MainPage.connections) }
                }.help("Mail options")
            }
        }
        .onChange(of: accountID) { _, _ in selected = nil; mailbox.closeConversation(); search = ""; query = "" }
        .onChange(of: folder) { _, _ in selected = nil; mailbox.closeConversation(); search = ""; query = "" }
        .onChange(of: CloudAccount.shared.credentials?.userID) { _, _ in selected = nil; composing = nil; preferences = nil; mailbox.reset() }
        .task(id: refreshID) { await monitor() }
        .task(id: selected?.identity) { if let selected { await mailbox.open(selected) } }
        .sheet(item: $composing) { draft in
            NativeMailComposer(initial: draft, mailbox: mailbox) { composing = nil; Task { await refresh() } }
        }
        .sheet(item: $preferences) { account in MailboxPreferences(account: account, mailbox: mailbox) { preferences = nil } }
        .sheet(isPresented: $fullMailbox) { CloudWorkspace(path: "/mail").frame(width: DS.Layout.windowWidth, height: DS.Layout.windowHeight) }
    }
    private var folderTitle: String { folders.first { $0.1 == folder }?.0 ?? (folder == "drafts" ? "Drafts" : "Outbox") }
    private var accountNavigation: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.lg) {
                navigationItem("All inboxes", icon: "tray.full", active: accountID.isEmpty) { accountID = ""; folder = "in:inbox" }
                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    Text("Gmail accounts").font(DS.Font.caption).foregroundStyle(DS.Color.textSecondary).padding(.horizontal, DS.Space.sm)
                    ForEach(mailbox.accounts) { account in
                        accountNavigationItem(account, active: accountID == account.id) { accountID = account.id; folder = "in:inbox" }
                            .help(account.label)
                            .contextMenu { Button("Mailbox appearance…") { preferences = account } }
                    }
                }
                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    Text(accountID.isEmpty ? "Across all accounts" : "Folders").font(DS.Font.caption).foregroundStyle(DS.Color.textSecondary).padding(.horizontal, DS.Space.sm)
                    ForEach(folders, id: \.1) { name, value in
                        navigationItem(name, icon: folderIcon(value), active: folder == value) { folder = value }
                    }
                    navigationItem("Drafts", icon: "doc", active: folder == "drafts") { folder = "drafts" }
                    navigationItem("Outbox", icon: "tray.and.arrow.up", active: folder == "outbox") { folder = "outbox" }
                }
                ActionButton(title: "Add Gmail account", emphasis: .quiet) { NotificationCenter.default.post(name: .murmurShowPage, object: MainPage.connections) }
            }.padding(.vertical, DS.Space.md).padding(.trailing, DS.Space.sm)
        }
    }
    private func accountNavigationItem(_ account: MailAccount, active: Bool, action: @escaping () -> Void) -> some View {
        let label = account.label
        let parts = label.split(separator: "@", maxSplits: 1).map(String.init)
        return Button(action: action) {
            HStack(spacing: DS.Space.sm) {
                MailboxAvatar(account: account)
                VStack(alignment: .leading, spacing: DS.Space.xxs) {
                    Text(parts.first ?? label).font(DS.Font.body)
                    if parts.count > 1 { Text("@" + parts[1]).font(DS.Font.caption).foregroundStyle(DS.Color.textSecondary) }
                }.lineLimit(1).truncationMode(.tail)
            }.padding(DS.Space.sm).frame(maxWidth: .infinity, alignment: .leading)
                .background(active ? DS.Color.accentSoft : .clear, in: .rect(cornerRadius: DS.Radius.sm))
                .foregroundStyle(active ? DS.Color.accent : DS.Color.text)
        }.buttonStyle(.plain).accessibilityLabel(label).accessibilityAddTraits(active ? .isSelected : [])
    }
    private func navigationItem(_ title: String, icon: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon).font(DS.Font.body).lineLimit(1).truncationMode(.middle)
                .padding(DS.Space.sm).frame(maxWidth: .infinity, alignment: .leading)
                .background(active ? DS.Color.accentSoft : .clear, in: .rect(cornerRadius: DS.Radius.sm))
                .foregroundStyle(active ? DS.Color.accent : DS.Color.text)
        }.buttonStyle(.plain).accessibilityAddTraits(active ? .isSelected : [])
    }
    private func folderIcon(_ value: String) -> String {
        switch value {
        case "in:inbox": "tray"
        case "is:starred": "star"
        case "in:sent": "paperplane"
        case "in:spam": "exclamationmark.shield"
        case "in:trash": "trash"
        default: "archivebox"
        }
    }
    private var refreshID: String { [accountID, folder, search, CloudAccount.shared.credentials?.userID ?? ""].joined(separator: "|") }
    private func monitor() async {
        await refresh()
        while !Task.isCancelled {
            do { try await Task.sleep(for: DS.Timing.mailboxRefresh) } catch { return }
            if composing == nil { await refresh() }
        }
    }
    private var threadList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: DS.Space.zero) {
                ForEach(mailbox.threads.filter { search.isEmpty || !mailbox.offline || [$0.subject, $0.from, $0.snippet].joined(separator: " ").localizedCaseInsensitiveContains(search) }, id: \.identity) { thread in
                    Button {
                        selected = thread
                    } label: {
                        VStack(alignment: .leading, spacing: DS.Space.compact) {
                            HStack { Text(thread.from).font(DS.Font.caption).lineLimit(1); Spacer(); if thread.unread { Image(systemName: "circle.fill").foregroundStyle(DS.Color.accent) } }
                            Text(thread.subject).font(thread.unread ? DS.Font.bodyEmphasis : DS.Font.body).lineLimit(2)
                            Text(thread.snippet).font(DS.Font.caption).foregroundStyle(DS.Color.textSecondary).lineLimit(1)
                            if accountID.isEmpty, let account = mailbox.accounts.first(where: { $0.id == thread.accountID }) { Text(account.label).font(DS.Font.caption).foregroundStyle(DS.Color.mailbox(account.colour)).lineLimit(1) }
                        }.padding(.horizontal, DS.Space.md).padding(.vertical, DS.Space.sm).frame(maxWidth: .infinity, alignment: .leading)
                            .background(selected?.identity == thread.identity ? DS.Color.accentSoft : .clear, in: RoundedRectangle(cornerRadius: DS.Radius.sm))
                    }.buttonStyle(.plain)
                    Divider()
                }
                if mailbox.threads.isEmpty && !mailbox.loading { EmptyState(icon: "tray", label: "No mail in this view", detail: mailbox.offline ? "Only downloaded mail is available offline." : "Try a different folder or search.") }
                if !mailbox.pages.isEmpty {
                    ActionButton(title: "Load older messages", emphasis: .normal) { Task { await mailbox.load(accountID: accountID, query: mailQuery, more: true) } }.disabled(mailbox.loading)
                }
            }
        }
    }
    @ViewBuilder private var reader: some View {
        if let selected {
            VStack(alignment: .leading, spacing: DS.Space.zero) {
                HStack(spacing: DS.Space.md) {
                    readerButton("Reply", icon: "arrowshape.turn.up.left") { if let message = mailbox.messages.last { compose(reply: message) } }.disabled(mailbox.messages.isEmpty)
                    readerButton("Reply all", icon: "arrowshape.turn.up.left.2") { if let message = mailbox.messages.last { compose(reply: message, replyAll: true) } }.disabled(mailbox.messages.isEmpty)
                    readerButton("Forward", icon: "arrowshape.turn.up.right") { if let message = mailbox.messages.last { forward(message, account: selected.accountID) } }.disabled(mailbox.messages.isEmpty)
                    Divider().frame(height: DS.Space.lg)
                    readerButton("Archive", icon: "archivebox") { act("archive", selected) }
                    readerButton(selected.unread ? "Mark read" : "Mark unread", icon: selected.unread ? "envelope.open" : "envelope.badge") { act(selected.unread ? "read" : "unread", selected) }
                    readerButton(selected.starred ? "Unstar" : "Star", icon: selected.starred ? "star.fill" : "star") { act(selected.starred ? "unstar" : "star", selected) }
                    readerButton(folder == "in:trash" ? "Restore" : "Move to Bin", icon: folder == "in:trash" ? "arrow.uturn.backward" : "trash") { act(folder == "in:trash" ? "restore" : "trash", selected) }
                    Spacer(minLength: DS.Space.zero)
                }.padding(DS.Space.md)
                Divider()
                ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.lg) {
                    if let account = mailbox.accounts.first(where: { $0.id == selected.accountID }) { MailboxBadge(account: account) }
                    Text(selected.subject).font(DS.Font.title)
                    Menu("Message view") {
                        Toggle("Formatted messages", isOn: $formatted)
                    }
                    if mailbox.readerLoading { ProgressView(mailbox.messages.isEmpty ? "Opening conversation…" : "Updating conversation…").controlSize(.small).font(DS.Font.caption) }
                    else if mailbox.messages.isEmpty { Text(mailbox.offline ? "Open this conversation while connected to download it." : "This conversation is unavailable. Try opening it again.").font(DS.Font.body).foregroundStyle(DS.Color.textSecondary) }
                    ForEach(mailbox.messages) { message in
                        VStack(alignment: .leading, spacing: DS.Space.md) {
                            Text(message.from).font(DS.Font.bodyEmphasis)
                            Text("To: " + message.to).font(DS.Font.caption).foregroundStyle(DS.Color.textSecondary)
                            if formatted && !message.html.isEmpty { MailHTMLReader(html: message.html) }
                            else { Text(message.text.isEmpty ? "This message has no text content." : message.text).font(DS.Font.body).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                            ForEach(Array(message.attachments.enumerated()), id: \.offset) { _, attachment in
                                ActionButton(title: attachment.name, systemImage: "paperclip", emphasis: .normal) {
                                    Task {
                                        do {
                                            guard let accountID = selected.accountID else { return }
                                            let data = try await mailbox.attachment(attachment, message: message, accountID: accountID)
                                            let panel = NSSavePanel(); panel.nameFieldStringValue = (attachment.name as NSString).lastPathComponent
                                            if panel.runModal() == .OK, let url = panel.url { try data.write(to: url, options: .atomic) }
                                        } catch { self.error = error.localizedDescription }
                                    }
                                }
                            }
                            HStack {
                                ActionButton(title: "Reply", emphasis: .normal) { compose(reply: message) }
                                ActionButton(title: "Reply all", emphasis: .normal) { compose(reply: message, replyAll: true) }
                                ActionButton(title: "Forward", emphasis: .normal) {
                                    Task { do { guard let account = selected.accountID else { return }; composing = try await mailbox.forward(message, accountID: account) } catch { self.error = error.localizedDescription } }
                                }
                            }
                            HStack {
                                ActionButton(title: "Create note", systemImage: "note.text", emphasis: .quiet) {
                                    do {
                                        let store = SessionStore()
                                        let note = try store.createNote(title: message.subject)
                                        try store.saveNote("From: " + message.from + "\nTo: " + message.to + "\n\n" + message.text, for: note.id)
                                        NotificationCenter.default.post(name: .murmurShowSession, object: note.id)
                                    } catch { self.error = error.localizedDescription }
                                }
                                ActionButton(title: "Full mailbox", emphasis: .quiet) { fullMailbox = true }
                            }
                        }
                        Divider()
                    }
                }.padding(DS.Space.lg)
                }.id(selected.identity)
            }
        } else { EmptyState(icon: "envelope.open", label: "Select a message", detail: "Choose a conversation to read it here.").frame(maxWidth: .infinity, maxHeight: .infinity) }
    }
    private func readerButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(title, systemImage: icon, action: action).labelStyle(.iconOnly).buttonStyle(.borderless).tint(DS.Color.textSecondary).help(title).accessibilityLabel(title)
    }
    private func forward(_ message: MailMessage, account: String?) {
        Task { do { guard let account else { return }; composing = try await mailbox.forward(message, accountID: account) } catch { self.error = error.localizedDescription } }
    }
    private var localDrafts: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.lg) {
                Text("Drafts on this Mac and in Gmail are saved separately for each account.").font(DS.Font.caption).foregroundStyle(DS.Color.textSecondary)
                ForEach(mailbox.providerDrafts, id: \.identity) { provider in
                    ActionButton(title: provider.message.subject + " · Gmail", emphasis: .normal) {
                        Task { do { composing = try await mailbox.openProviderDraft(provider) } catch { self.error = error.localizedDescription } }
                    }
                }
                if !mailbox.providerPages.isEmpty {
                    ActionButton(title: "Load older Gmail drafts", emphasis: .normal) { Task { await mailbox.loadProviderDrafts(accountID: accountID, more: true) } }
                }
                ForEach(mailbox.drafts.filter { !$0.queued && $0.cancelRequested != true && (accountID.isEmpty || $0.accountID == accountID) }) { draft in
                    ActionButton(title: draft.subject.isEmpty ? "Untitled draft" : draft.subject, emphasis: .normal) { composing = draft }
                }
            }
        }
    }
    private var outbox: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.lg) {
                ForEach(mailbox.drafts.filter { ($0.queued || $0.cancelRequested == true) && (accountID.isEmpty || $0.accountID == accountID) }) { draft in
                    Text(draft.subject.isEmpty ? "Untitled message" : draft.subject).font(DS.Font.bodyEmphasis)
                    Text(draft.cancelRequested == true ? "Undo pending · reconnect to confirm cancellation." : "Queued on this Mac · delivery continues when connected.").font(DS.Font.caption).foregroundStyle(DS.Color.textSecondary)
                    if let error = draft.error { InlineNotice(text: error, tone: .warning) }
                    if draft.cancelRequested != true {
                        ActionButton(title: "Undo send", emphasis: .normal) { Task { do { try await mailbox.cancelLocalQueue(draft.id) } catch { self.error = "Undo saved on this Mac. Reconnect to confirm cancellation." } } }
                    }
                }
                ForEach(mailbox.outbox.filter { accountID.isEmpty || $0.connection_id == accountID }) { item in
                    Text(item.subject.isEmpty ? "Untitled message" : item.subject).font(DS.Font.bodyEmphasis)
                    Text(item.status + " · " + (mailbox.accounts.first { $0.id == item.connection_id }?.label ?? "Gmail")).font(DS.Font.caption).foregroundStyle(DS.Color.textSecondary)
                    if let error = item.error { InlineNotice(text: error, tone: .warning) }
                    if item.status == "queued" || item.status == "failed" {
                        ActionButton(title: item.status == "queued" ? "Undo send" : "Try sending again", emphasis: .normal) {
                            Task { do { try await mailbox.outboxAction(item.status == "queued" ? "cancel" : "retry", id: item.id); await refresh() } catch { self.error = error.localizedDescription } }
                        }
                    }
                }
                ActionButton(title: "Undo or manage sends", emphasis: .normal) { fullMailbox = true }
            }
        }
    }
    private var mailQuery: String { folder == "drafts" || folder == "outbox" ? "in:inbox" : folder + (search.isEmpty ? "" : " " + search) }
    private func refresh() async {
        await mailbox.load(accountID: accountID, query: mailQuery, metadataOnly: ["drafts", "outbox"].contains(folder))
        if syntheticPreview, selected == nil, let thread = mailbox.threads.first, !["drafts", "outbox"].contains(folder) { selected = thread }
        if folder == "drafts", !Task.isCancelled { await mailbox.loadProviderDrafts(accountID: accountID) }
    }
    private func act(_ action: String, _ thread: MailThread) {
        Task {
            do {
                try await mailbox.action(action, thread: thread)
                if selected?.identity == thread.identity, ["archive", "trash"].contains(action) { selected = nil; mailbox.closeConversation() }
                await refresh()
                if selected?.identity == thread.identity, let updated = mailbox.threads.first(where: { $0.identity == thread.identity }) { selected = updated }
            } catch { self.error = error.localizedDescription }
        }
    }
    private func compose(reply: MailMessage? = nil, replyAll: Bool = false) {
        let sender = reply != nil ? selected?.accountID : accountID.isEmpty ? mailbox.accounts.first?.id : accountID
        guard let sender, let userID = mailbox.signedInUserID else { return }
        var draft = MailDraft(accountID: sender, userID: userID)
        if let reply {
            func address(_ value: String) -> String { if let a = value.firstIndex(of: "<"), let b = value.lastIndex(of: ">"), a < b { return String(value[value.index(after: a)..<b]) }; return value.trimmingCharacters(in: .whitespacesAndNewlines) }
            let own = mailbox.accounts.first { $0.id == sender }?.email?.lowercased() ?? ""
            var recipients = [address(reply.reply_to.isEmpty ? reply.from : reply.reply_to)]
            if replyAll { recipients += mailAddresses(reply.to).map(address); draft.cc = mailAddresses(reply.cc).map(address).filter { $0.lowercased() != own }.joined(separator: ", ") }
            draft.to = Array(Set(recipients.filter { $0.lowercased() != own })).sorted().joined(separator: ", ")
            draft.subject = reply.subject.lowercased().hasPrefix("re:") ? reply.subject : "Re: " + reply.subject
            draft.threadID = reply.thread_id; draft.replyID = reply.message_id; draft.references = reply.references + " " + reply.message_id
        }
        if let signature = mailbox.accounts.first(where: { $0.id == sender })?.signature, !signature.isEmpty { draft.text = "\n\n" + signature }
        composing = draft
    }
}

private struct NativeMailComposer: View {
    let mailbox: MailWorkspaceStore
    let onClose: () -> Void
    @State private var draft: MailDraft
    @State private var busy = false
    @State private var error: String?
    @State private var scheduled = false
    init(initial: MailDraft, mailbox: MailWorkspaceStore, onClose: @escaping () -> Void) {
        self.mailbox = mailbox; self.onClose = onClose; _draft = State(initialValue: initial); _scheduled = State(initialValue: initial.sendAt != nil)
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.lg) {
                HStack {
                    Text("New message").font(DS.Font.title)
                    Spacer()
                    ActionButton(title: "Save and close", emphasis: .quiet) { do { try mailbox.saveLocal(draft); onClose() } catch { self.error = error.localizedDescription } }.disabled(busy).keyboardShortcut(.cancelAction)
                }
                if let error { InlineNotice(text: error, tone: .warning) }
                Picker("From", selection: Binding(get: { draft.accountID }, set: { sender in
                    do {
                        if draft.providerID != nil { try mailbox.saveLocal(draft) }
                        draft = draft.changingSender(to: sender)
                        try mailbox.saveLocal(draft)
                    } catch { self.error = error.localizedDescription }
                })) {
                    if !mailbox.accounts.contains(where: { $0.id == draft.accountID }) { Text("Disconnected account").tag(draft.accountID) }
                    ForEach(mailbox.accounts) { account in Text(account.label).tag(account.id) }
                }.pickerStyle(.menu).accessibilityLabel("From")
                TextField("To · email addresses", text: $draft.to).textFieldStyle(.roundedBorder)
                TextField("Cc", text: $draft.cc).textFieldStyle(.roundedBorder)
                TextField("Bcc", text: $draft.bcc).textFieldStyle(.roundedBorder)
                TextField("Subject", text: $draft.subject).textFieldStyle(.roundedBorder)
                TextEditor(text: $draft.text).frame(minHeight: DS.Layout.mailComposerBodyHeight).disabled(draft.html != nil)
                    .accessibilityLabel("Message body")
                    .overlay(alignment: .topLeading) {
                        if draft.text.isEmpty && draft.html == nil {
                            Text("Write your message…").font(DS.Font.body).foregroundStyle(DS.Color.textSecondary)
                                .padding(DS.Space.sm).allowsHitTesting(false).accessibilityHidden(true)
                        }
                    }
                if draft.html != nil {
                    InlineNotice(text: "Formatted content is preserved. Continue in Full mailbox, or convert it to plain text to edit the body here.", tone: .info)
                    ActionButton(title: "Use plain text", emphasis: .normal) { draft.html = nil }
                }
                ForEach(Array(draft.attachments.enumerated()), id: \.offset) { index, attachment in
                    ActionButton(title: "Remove " + attachment.name, systemImage: "paperclip", emphasis: .quiet) { draft.attachments.remove(at: index) }
                }
                ActionButton(title: "Attach files…", systemImage: "paperclip", emphasis: .normal) { attach() }
                ToggleRow(title: "Send later", isOn: $scheduled).onChange(of: scheduled) { _, value in draft.sendAt = value ? Date().addingTimeInterval(3_600) : nil }
                if scheduled { DatePicker("Send at", selection: Binding(get: { draft.sendAt ?? Date().addingTimeInterval(3_600) }, set: { draft.sendAt = $0 })) }
                Text("Draft edits are saved on this Mac. Save in Gmail to continue on another device.").font(DS.Font.caption).foregroundStyle(DS.Color.textSecondary)
                HStack {
                    ActionButton(title: "Save in Gmail", emphasis: .normal) { Task { await saveProvider() } }.disabled(busy || PreviewEnvironment.isActive)
                    Spacer()
                    ActionButton(title: busy ? "Queueing…" : "Send", emphasis: .prominent) { Task { await send() } }.disabled(busy || PreviewEnvironment.isActive || !mailbox.accounts.contains { $0.id == draft.accountID } || draft.to.isEmpty && draft.cc.isEmpty && draft.bcc.isEmpty)
                }
            }.padding(DS.Space.xxl).disabled(busy)
        }.frame(width: DS.Layout.mailComposerWidth, height: DS.Layout.windowHeight)
        .task(id: draft.to + draft.cc + draft.bcc + draft.subject + draft.text + String(draft.attachments.count) + String(describing: draft.sendAt) + String(draft.html != nil)) {
            guard !busy else { return }
            do {
                try await Task.sleep(for: DS.Timing.autosave)
                guard !Task.isCancelled, !busy else { return }
                try mailbox.saveLocal(draft)
            } catch is CancellationError { } catch { self.error = error.localizedDescription }
        }
        .interactiveDismissDisabled()
    }
    private func attach() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = false; panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        do {
            var total = draft.attachments.reduce(0) { $0 + (Data(base64Encoded: $1.data ?? "")?.count ?? 0) }
            for file in panel.urls {
                let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard total + size <= 18_000_000, draft.attachments.count < 20 else { throw CloudHTTPError(status: 413, message: "Attachments must total less than 18 MB, with at most 20 files.") }
                let data = try Data(contentsOf: file)
                guard total + data.count <= 18_000_000 else { throw CloudHTTPError(status: 413, message: "Attachments must total less than 18 MB.") }; total += data.count
                draft.attachments.append(.init(name: file.lastPathComponent, type: UTType(filenameExtension: file.pathExtension)?.preferredMIMEType ?? "application/octet-stream", data: data.base64EncodedString()))
            }
            try mailbox.saveLocal(draft)
        } catch { self.error = error.localizedDescription }
    }
    private func saveProvider() async {
        busy = true; defer { busy = false }
        do { draft = try await mailbox.saveProvider(draft) } catch { self.error = error.localizedDescription }
    }
    private func send() async {
        busy = true; defer { busy = false }
        if !scheduled { draft.sendAt = nil }
        do { try await mailbox.queue(draft); onClose() }
        catch {
            if mailbox.drafts.contains(where: { $0.id == draft.id && $0.queued }) { onClose() }
            else { self.error = error.localizedDescription }
        }
    }
}
