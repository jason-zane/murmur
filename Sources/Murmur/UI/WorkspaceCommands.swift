import SwiftUI

/// Shared command treatment for native workspaces. The SDK owns hover, focus,
/// pressed, disabled and toolbar overflow; help never consumes document space.
struct WorkspaceCommand: View {
    let title: String
    let systemImage: String
    var help: String = ""
    var iconOnly = false
    let action: () -> Void

    var body: some View {
        Button(title, systemImage: systemImage, action: action)
            .labelStyle(WorkspaceCommandLabelStyle(iconOnly: iconOnly))
            .help(help.isEmpty ? title : title + " · " + help)
            .accessibilityLabel(title)
            .accessibilityHint(help)
    }
}

private struct WorkspaceCommandLabelStyle: LabelStyle {
    let iconOnly: Bool
    func makeBody(configuration: Configuration) -> some View {
        if iconOnly { configuration.icon }
        else { HStack(spacing: DS.Space.xs) { configuration.icon; configuration.title } }
    }
}

/// One native overflow menu, named by scope in tooltips and accessibility.
struct WorkspaceMoreMenu<Content: View>: View {
    let scope: String
    @ViewBuilder let content: () -> Content
    var body: some View {
        Menu { content() } label: { Image(systemName: "ellipsis") }
            .menuIndicator(.hidden)
            .help("More actions for \(scope)")
            .accessibilityLabel("More actions for \(scope)")
    }
}

/// Each active workspace contributes one trailing area with scoped commands.
struct WorkspaceCommandArea<Content: ToolbarContent>: ToolbarContent {
    @ToolbarContentBuilder let content: () -> Content
    var body: some ToolbarContent {
        ToolbarSpacer(.flexible, placement: .primaryAction)
        content()
    }
}

/// Document view controls lead; selected-content actions trail. At narrow widths
/// the actions get their own row instead of clipping the document or tab labels.
struct WorkspaceSelectionBar<Leading: View, Actions: View>: View {
    @ViewBuilder let leading: () -> Leading
    @ViewBuilder let actions: () -> Actions
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: DS.Space.md) { leading(); Spacer(); actions() }
            VStack(alignment: .leading, spacing: DS.Space.md) {
                leading()
                HStack(spacing: DS.Space.sm) { Spacer(); actions() }
            }
        }
    }
}
