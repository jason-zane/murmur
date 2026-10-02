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
    @State private var actionFeedback: String?
    @State private var binAccount: String?
    @State private var savedNoteID: String?
    @State private var fullPageReading = false
    private let syntheticPreview = PreviewEnvironment.hasSyntheticMail
    init() {
        if PreviewEnvironment.hasSyntheticMail, let root = PreviewEnvironment.root {
            _mailbox = State(initialValue: MailWorkspaceStore(transport: PreviewMailTransport(), root: root.appendingPathComponent("mail")))
        } else {
            _fullPageReading = State(initialValue: UserDefaults.standard.bool(forKey: "mailFullPageReading"))
        }
    }
    private let folders = [("Inbox", "in:inbox"), ("Starred", "is:starred"), ("Sent", "in:sent"), ("Archive", "in:all -in:inbox -in:trash -in:spam"), ("Spam", "in:spam"), ("Bin", "in:trash")]
    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            if let error { InlineNotice(text: error, tone: .warning) }
            if let notice = mailbox.notice { InlineNotice(text: notice, tone: .info) }
            if let actionFeedback {
                HStack {
                    Text(actionFeedback).font(DS.Font.caption).foregroundStyle(DS.Color.textSecondary)
                    if let binAccount { Button("Open Bin") { accountID = binAccount; folder = "in:trash"; self.binAccount = nil } }
                    if let savedNoteID { Button("Open note") { NotificationCenter.default.post(name: .murmurShowSession, object: savedNoteID) } }
                    Spacer()
                    Button("Dismiss", systemImage: "xmark") { self.actionFeedback = nil; binAccount = nil; savedNoteID = nil }.labelStyle(.iconOnly).help("Dismiss action feedback")
                }
            }
            if syntheticPreview { Text("Synthetic Mail preview · changes stay in the preview; sending and Gmail saves are disabled.").font(DS.Font.caption).foregroundStyle(DS.Color.textSecondary) }
            if !CloudAccount.shared.isConnected && !syntheticPreview {
                EmptyState(icon: "envelope", label: "Connect Gmail", detail: "Sign in to your Concourse account, then connect Gmail in Connected apps.")
                ActionButton(title: "Connect apps", emphasis: .normal) { NotificationCenter.default.post(name: .murmurShowPage, object: MainPage.connections) }
            } else {
                HStack(spacing: DS.Space.zero) {
                    accountNavigation.frame(width: DS.Layout.mailNavigationWidth)
                    Divider()
                    if fullPageReading {
                        ZStack(alignment: .topLeading) {
                            mailboxList.opacity(selected == nil ? 1 : 0).allowsHitTesting(selected == nil).accessibilityHidden(selected != nil)
                            reader.opacity(selected == nil ? 0 : 1).allowsHitTesting(selected != nil).accessibilityHidden(selected == nil)
                        }.frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        HSplitView {
                            mailboxList.frame(minWidth: DS.Layout.mailListMinimumWidth, idealWidth: DS.Layout.mailListWidth, maxWidth: DS.Layout.mailListMaximumWidth)
                            reader.frame(minWidth: DS.Layout.mailReaderWidth)
                        }
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .top) { Divider() }

            }
        }.padding(DS.Space.md)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .navigationTitle("Mail")
        .toolbar {
            if fullPageReading, selected != nil {
                ToolbarItem(placement: .navigation) {
                    WorkspaceCommand(title: "Back to messages", systemImage: "arrow.left", help: "Return to this inbox and its search.") { selected = nil; mailbox.closeConversation() }
                }
            }
            WorkspaceCommandArea {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button { fullPageReading = false } label: {
                            Label("Side-by-side", systemImage: fullPageReading ? "rectangle.split.2x1" : "checkmark")
                        }
                        Button { fullPageReading = true } label: {
                            Label("Full page", systemImage: fullPageReading ? "checkmark" : "rectangle")
                        }
                    } label: {
                        Label(fullPageReading ? "Full page" : "Side-by-side", systemImage: fullPageReading ? "rectangle" : "rectangle.split.2x1")
                    }.labelStyle(WorkspaceCommandLabelStyle(iconOnly: false))
                        .fixedSize(horizontal: true, vertical: false)
                        .accessibilityLabel("Reading view")
                        .accessibilityValue(fullPageReading ? "Full page" : "Side-by-side")
                        .help("Choose a side-by-side reading pane or a full-page inbox and conversation.")
                }
                ToolbarItem(placement: .primaryAction) {
                    toolbarButton("New message", icon: "square.and.pencil", detail: "Write a message and choose its From account.", iconOnly: false) { compose() }.disabled(mailbox.accounts.isEmpty)
                }
                ToolbarSpacer(.fixed, placement: .primaryAction)
                ToolbarItemGroup(placement: .primaryAction) {
                    if let selected {
                        toolbarButton("Reply", icon: "arrowshape.turn.up.left", detail: "Reply to the latest message in this thread.") { if let message = mailbox.messages.last { compose(reply: message) } }.disabled(mailbox.messages.isEmpty)
                        toolbarButton("Reply all", icon: "arrowshape.turn.up.left.2", detail: "Reply to the sender and other recipients of the latest message.") { if let message = mailbox.messages.last { compose(reply: message, replyAll: true) } }.disabled(mailbox.messages.isEmpty)
                        toolbarButton("Forward", icon: "arrowshape.turn.up.right", detail: "Forward the latest message, keeping its attachments.") { if let message = mailbox.messages.last { forward(message, account: selected.accountID) } }.disabled(mailbox.messages.isEmpty)
                        toolbarButton("Create note", icon: "note.text", detail: "Save the latest message as a note in Concourse on this Mac.", iconOnly: false) { createNote(selected) }.disabled(mailbox.messages.isEmpty)
                        toolbarButton("Archive", icon: "archivebox", detail: "Remove this thread from Inbox. Find it in Archive.") { act("archive", selected) }.disabled(mailbox.isActing(on: selected))
                        toolbarButton(selected.unread ? "Mark read" : "Mark unread", icon: selected.unread ? "envelope.open" : "envelope.badge", detail: "Change the read status of this thread.") { act(selected.unread ? "read" : "unread", selected) }.disabled(mailbox.isActing(on: selected))
                        toolbarButton(selected.starred ? "Unstar" : "Star", icon: selected.starred ? "star.fill" : "star", detail: "Change the star on this thread.") { act(selected.starred ? "unstar" : "star", selected) }.disabled(mailbox.isActing(on: selected))
                        toolbarButton(folder == "in:trash" ? "Restore to Inbox" : "Move to Bin", icon: folder == "in:trash" ? "arrow.uturn.backward" : "trash", detail: folder == "in:trash" ? "Move this thread from Bin to Inbox." : "Move the whole thread to Bin. You can restore it from Bin.") { act(folder == "in:trash" ? "restore" : "trash", selected) }.disabled(mailbox.isActing(on: selected))
                    }
                }
                ToolbarSpacer(.fixed, placement: .primaryAction)
                ToolbarItem(placement: .primaryAction) {
                    WorkspaceMoreMenu(scope: "Mail") {
                        Toggle("Formatted messages", isOn: $formatted)
                        Button("Open web Mail…") { fullMailbox = true }
                        Divider()
                        Menu("Mailbox appearance") { ForEach(mailbox.accounts) { account in Button(account.label) { preferences = account } } }
                        Button("Manage connected accounts") { NotificationCenter.default.post(name: .murmurShowPage, object: MainPage.connections) }
                        Divider()
                        Button("Clear downloaded mail") { do { try mailbox.clearDownloaded(); selected = nil; mailbox.closeConversation() } catch { self.error = error.localizedDescription } }
                    }
                }
            }
        }
        .onChange(of: accountID) { _, _ in selected = nil; mailbox.closeConversation(); search = ""; query = "" }
        .onChange(of: fullPageReading) { _, value in if !syntheticPreview { UserDefaults.standard.set(value, forKey: "mailFullPageReading") } }
        .onChange(of: folder) { _, _ in selected = nil; mailbox.closeConversation(); search = ""; query = "" }
        .onChange(of: CloudAccount.shared.credentials?.userID) { _, _ in selected = nil; composing = nil; preferences = nil; actionFeedback = nil; binAccount = nil; savedNoteID = nil; mailbox.reset() }
        .task(id: refreshID) { await monitor() }
        .task(id: selected?.identity) { if let selected { await mailbox.open(selected) } }
        .sheet(item: $composing) { draft in
            NativeMailComposer(initial: draft, mailbox: mailbox) { composing = nil; Task { await refresh() } }
        }
        .sheet(item: $preferences) { account in MailboxPreferences(account: account, mailbox: mailbox) { preferences = nil } }
        .sheet(isPresented: $fullMailbox) { CloudWorkspace(path: "/mail").frame(width: DS.Layout.windowWidth, height: DS.Layout.windowHeight) }
    }
    private var mailboxList: some View {
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
        }
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
        GeometryReader { geometry in
            let horizontalRows = fullPageReading && geometry.size.width >= DS.Layout.mailHorizontalRowMinimumWidth
            ScrollView {
                LazyVStack(alignment: .leading, spacing: DS.Space.zero) {
                    ForEach(mailbox.threads.filter { search.isEmpty || !mailbox.offline || [$0.subject, $0.from, $0.snippet].joined(separator: " ").localizedCaseInsensitiveContains(search) }, id: \.identity) { thread in
                        Button {
                            selected = thread
                        } label: {
                            Group {
                                if horizontalRows { horizontalThreadSummary(thread) }
                                else { threadSummary(thread) }
                            }.padding(.horizontal, DS.Space.md)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .frame(height: horizontalRows ? DS.Layout.mailHorizontalRowHeight : accountID.isEmpty ? DS.Layout.mailStackedAccountRowHeight : DS.Layout.mailStackedRowHeight)
                                .background(selected?.identity == thread.identity ? DS.Color.accentSoft : .clear, in: RoundedRectangle(cornerRadius: DS.Radius.sm))
                        }.buttonStyle(.plain)
                            .accessibilityValue(thread.unread ? "Unread" : "Read")
                            .accessibilityIdentifier("mail-thread-row-" + thread.identity)
                        Divider()
                    }
                    if mailbox.threads.isEmpty && !mailbox.loading { EmptyState(icon: "tray", label: "No mail in this view", detail: mailbox.offline ? "Only downloaded mail is available offline." : "Try a different folder or search.") }
                    if !mailbox.pages.isEmpty {
                        ActionButton(title: "Load older messages", emphasis: .normal) { Task { await mailbox.load(accountID: accountID, query: mailQuery, more: true) } }.disabled(mailbox.loading)
                    }
                }
            }
        }
    }
    private func horizontalThreadSummary(_ thread: MailThread) -> some View {
        HStack(spacing: DS.Space.md) {
            Text(mailSenderName(thread.from)).font(DS.Font.bodyEmphasis).lineLimit(1)
                .frame(width: DS.Layout.mailSenderColumnWidth, alignment: .leading)
            Text(thread.subject).font(DS.Font.mailSubject(unread: thread.unread)).lineLimit(1)
                .frame(width: DS.Layout.mailSubjectColumnWidth, alignment: .leading)
            Text(thread.snippet).font(DS.Font.caption).foregroundStyle(DS.Color.textSecondary).lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            if accountID.isEmpty {
                Group {
                    if let account = mailbox.accounts.first(where: { $0.id == thread.accountID }) { MailboxBadge(account: account) }
                    else { Text("Mailbox unavailable").font(DS.Font.caption).foregroundStyle(DS.Color.textSecondary) }
                }.frame(width: DS.Layout.mailAccountColumnWidth, alignment: .trailing)
            }
            unreadIndicator(thread)
        }
    }
    private func unreadIndicator(_ thread: MailThread) -> some View {
        Image(systemName: "circle.fill").font(DS.Font.caption).foregroundStyle(DS.Color.accent)
            .frame(width: DS.Layout.mailUnreadIndicatorWidth).opacity(thread.unread ? 1 : 0)
            .accessibilityHidden(true)
    }
    private func threadSummary(_ thread: MailThread) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.compact) {
            HStack { Text(mailSenderName(thread.from)).font(DS.Font.bodyEmphasis).lineLimit(1); Spacer(); unreadIndicator(thread) }
            Text(thread.subject).font(DS.Font.mailSubject(unread: thread.unread)).lineLimit(1)
            Text(thread.snippet).font(DS.Font.caption).foregroundStyle(DS.Color.textSecondary).lineLimit(1)
            if accountID.isEmpty, let account = mailbox.accounts.first(where: { $0.id == thread.accountID }) {
                MailboxBadge(account: account).frame(maxWidth: DS.Layout.mailAccountColumnWidth, alignment: .leading)
            }
        }
    }
    @ViewBuilder private var reader: some View {
        if let selected {
            VStack(alignment: .leading, spacing: DS.Space.zero) {
                ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.lg) {
                    if let account = mailbox.accounts.first(where: { $0.id == selected.accountID }) { MailboxBadge(account: account) }
                    Text(selected.subject).font(DS.Font.title)
                    if mailbox.readerLoading { ProgressView(mailbox.messages.isEmpty ? "Opening conversation…" : "Updating conversation…").controlSize(.small).font(DS.Font.caption) }
                    else if mailbox.messages.isEmpty { Text(mailbox.offline ? "Open this conversation while connected to download it." : "This conversation is unavailable. Try opening it again.").font(DS.Font.body).foregroundStyle(DS.Color.textSecondary) }
                    ForEach(mailbox.messages) { message in
                        VStack(alignment: .leading, spacing: DS.Space.md) {
                            Text(mailSenderName(message.from)).font(DS.Font.headline)
                            Text("To " + mailAddresses(message.to).map(mailSenderName).joined(separator: ", ")).font(DS.Font.caption).foregroundStyle(DS.Color.textSecondary)
                            DisclosureGroup("Message details") {
                                VStack(alignment: .leading, spacing: DS.Space.sm) {
                                    LabeledContent("From", value: message.from)
                                    LabeledContent("To", value: message.to)
                                    if !message.cc.isEmpty { LabeledContent("Cc", value: message.cc) }
                                    if !message.reply_to.isEmpty { LabeledContent("Reply to", value: message.reply_to) }
                                    LabeledContent("Sent", value: message.date)
                                }.textSelection(.enabled)
                            }.font(DS.Font.caption).foregroundStyle(DS.Color.textSecondary)
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
                        }
                        Divider()
                    }
                }.padding(DS.Space.lg)
                }.id(selected.identity)
            }
        } else { EmptyState(icon: "envelope.open", label: "Select a message", detail: "Choose a conversation to read it here.").frame(maxWidth: .infinity, maxHeight: .infinity) }
    }
    private func toolbarButton(_ title: String, icon: String, detail: String, iconOnly: Bool = true, action: @escaping () -> Void) -> some View {
        WorkspaceCommand(title: title, systemImage: icon, help: detail, iconOnly: iconOnly, action: action)
    }
    private func createNote(_ thread: MailThread) {
        guard let message = mailbox.messages.last else { return }
        do {
            savedNoteID = try mailbox.createNote(from: message, thread: thread)
            binAccount = nil; error = nil; actionFeedback = "Note saved in Concourse on this Mac."
        } catch { self.error = error.localizedDescription }
    }
    private func forward(_ message: MailMessage, account: String?) {
        let identity = selected?.identity, owner = mailbox.signedInUserID
        Task { do { guard let account else { return }; let draft = try await mailbox.forward(message, accountID: account); guard selected?.identity == identity, mailbox.signedInUserID == owner else { return }; composing = draft } catch is CancellationError {} catch { self.error = error.localizedDescription } }
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
        guard !mailbox.isActing(on: thread) else { return }
        let owner = mailbox.signedInUserID
        error = nil; savedNoteID = nil; binAccount = nil
        actionFeedback = action == "trash" ? "Moving thread to Bin…" : "Updating thread…"
        Task {
            do {
                try await mailbox.action(action, thread: thread)
                guard mailbox.signedInUserID == owner else { return }
                actionFeedback = action == "trash" ? "Thread moved to Bin. Restore it from Bin when needed." : action == "restore" ? "Thread restored to Inbox." : action == "archive" ? "Thread archived." : "Thread updated."
                if action == "trash" { binAccount = thread.accountID }
                if selected?.identity == thread.identity, ["archive", "trash", "restore"].contains(action) { selected = nil; mailbox.closeConversation() }
                await refresh()
                if selected?.identity == thread.identity, let updated = mailbox.threads.first(where: { $0.identity == thread.identity }) { selected = updated }
            } catch is CancellationError { if mailbox.signedInUserID == owner { actionFeedback = "Update was interrupted. Refresh this folder to check its status." } }
            catch { if mailbox.signedInUserID == owner { actionFeedback = nil; self.error = error.localizedDescription } }
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
                    InlineNotice(text: "Formatted content is preserved. Continue in web Mail, or convert it to plain text to edit the body here.", tone: .info)
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
