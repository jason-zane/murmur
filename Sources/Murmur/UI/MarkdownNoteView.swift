import SwiftUI

/// Lightweight native Markdown rendering for meeting notes. No web view or remote content.
/// Source timestamps are local navigation links; checkboxes edit the original Markdown.
struct MarkdownNoteView: View {
    let text: String
    var onToggleTask: ((Int) -> Void)?
    var onTimestamp: ((TimeInterval) -> Void)?

    private struct Block: Identifiable {
        let id: Int
        let source: String
        var trimmed: String { source.trimmingCharacters(in: .whitespaces) }
    }
    private var blocks: [Block] {
        text.components(separatedBy: "\n").enumerated().compactMap { index, line in
            line.trimmingCharacters(in: .whitespaces).isEmpty ? nil : Block(id: index, source: line)
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            ForEach(blocks) { block in
                if block.trimmed.hasPrefix("#") {
                    Text(Self.inline(String(block.trimmed.drop(while: { $0 == "#" || $0 == " " }))))
                        .font(DS.Font.documentHeading).foregroundStyle(DS.Color.text)
                        .padding(.top, DS.Space.md)
                        .textSelection(.enabled)
                } else if block.trimmed.hasPrefix("- [ ] ") || block.trimmed.lowercased().hasPrefix("- [x] ") {
                    HStack(alignment: .firstTextBaseline, spacing: DS.Space.sm) {
                        let checked = block.trimmed.lowercased().hasPrefix("- [x]")
                        Button { onToggleTask?(block.id) } label: {
                            Image(systemName: checked ? "checkmark.square.fill" : "square")
                                .foregroundStyle(checked ? DS.Color.accent : DS.Color.textTertiary)
                        }
                        .buttonStyle(.plain).disabled(onToggleTask == nil)
                        .accessibilityLabel((checked ? "Mark incomplete: " : "Mark complete: ") + String(block.trimmed.dropFirst(6)))
                        NoteLine(text: String(block.trimmed.dropFirst(6)), checked: checked, onTimestamp: onTimestamp)
                    }
                } else if block.trimmed.hasPrefix("- ") || block.trimmed.hasPrefix("* ") {
                    HStack(alignment: .firstTextBaseline, spacing: DS.Space.sm) {
                        Text("•").foregroundStyle(DS.Color.textTertiary)
                        NoteLine(text: String(block.trimmed.dropFirst(2)), onTimestamp: onTimestamp)
                    }
                } else if block.trimmed == "---" {
                    Divider().padding(.vertical, DS.Space.sm)
                } else {
                    NoteLine(text: block.source, onTimestamp: onTimestamp)
                }
            }
        }
        .font(DS.Font.documentBody)
        .lineSpacing(DS.Layout.proseLineSpacing)
        .frame(maxWidth: .infinity, alignment: .leading)
        .tint(DS.Color.accent)
    }

    private static func inline(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
    }

    /// Real buttons are keyboard/VoiceOver reachable, including when the surrounding
    /// prose is selectable. They also give timestamps the same readout style everywhere.
    private struct NoteLine: View {
        let text: String
        var checked = false
        var onTimestamp: ((TimeInterval) -> Void)?
        private struct Reference: Identifiable { let id: Int; let label: String; let seconds: TimeInterval }
        private var parsed: (String, [Reference]) {
            guard let regex = try? NSRegularExpression(pattern: "\\[(\\d{1,3}:\\d{2}(?::\\d{2})?)\\](?!\\()") else { return (text, []) }
            let source = text as NSString
            var clean = text, references: [Reference] = []
            for match in regex.matches(in: text, range: NSRange(location: 0, length: source.length)).reversed() {
                let label = source.substring(with: match.range(at: 1))
                let seconds = label.split(separator: ":").compactMap { Double($0) }.reduce(0) { $0 * 60 + $1 }
                if let range = Range(match.range, in: clean) {
                    clean.removeSubrange(range)
                    references.insert(Reference(id: match.range.location, label: label, seconds: seconds), at: 0)
                }
            }
            return (clean.trimmingCharacters(in: .whitespaces), references)
        }
        var body: some View {
            let (prose, references) = parsed
            HStack(alignment: .firstTextBaseline, spacing: DS.Space.sm) {
                Text(MarkdownNoteView.inline(prose)).strikethrough(checked)
                    .foregroundStyle(checked ? DS.Color.textSecondary : DS.Color.text)
                    .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                ForEach(references) { reference in
                    Button { onTimestamp?(reference.seconds) } label: { Readout(reference.label, color: DS.Color.accent) }
                        .buttonStyle(.plain).disabled(onTimestamp == nil)
                        .help("Show this moment in the transcript")
                        .accessibilityLabel("Show transcript at " + reference.label)
                }
            }
        }
    }
}
