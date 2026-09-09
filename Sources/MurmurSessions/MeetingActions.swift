import Foundation

public struct SourceExcerpt: Sendable, Equatable {
    public let quote: String
    public let context: String
    public let timestamp: String?

    public static func verifying(_ quote: String, in source: String) -> SourceExcerpt? {
        let source = source.precomposedStringWithCanonicalMapping
        let quote = quote.precomposedStringWithCanonicalMapping.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !quote.isEmpty, !quote.contains("\n"), let location = source.range(of: quote),
              source.range(of: quote, range: location.upperBound..<source.endIndex) == nil else { return nil }
        let line = String(source[source.lineRange(for: location)]).trimmingCharacters(in: .whitespacesAndNewlines)
        var timestamp: String?
        if let end = line.firstIndex(of: "]"), line.hasPrefix("[") {
            let candidate = String(line[line.index(after: line.startIndex)..<end])
            if candidate.range(of: #"^\d+:\d{2}(?::\d{2})?$"#, options: .regularExpression) != nil { timestamp = candidate }
        }
        return .init(quote: quote, context: line, timestamp: timestamp)
    }

    public var referencedQuote: String {
        quote + (!quote.hasPrefix("[") ? timestamp.map { " [" + $0 + "]" } ?? "" : "")
    }
}

/// An action extracted from one source passage. Names, dates and the task itself must
/// occur in that passage; a later summary rewrite never supplies these fields.
public struct SourceBackedAction: Sendable, Equatable {
    public let task: String
    public let owner: String?
    public let dueDate: String?
    public let timestamp: String?
    public let sourceQuote: String

    public static func verifying(task: String, owner: String?, dueDate: String?, quote: String,
                                 in source: String) -> SourceBackedAction? {
        let task = task.precomposedStringWithCanonicalMapping.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !task.isEmpty, !task.contains("\n"), let excerpt = SourceExcerpt.verifying(quote, in: source),
              let groundedTask = taskPhrase(task, in: excerpt.quote) else { return nil }
        let owner = stated(owner).flatMap { containsPhrase($0, in: excerpt.context) ? $0 : nil }
        // A date in another sentence cannot become this task's deadline, even when the
        // model quoted a whole turn containing both a decision and a follow-up.
        var taskSentence = excerpt.quote
        if let taskRange = excerpt.quote.range(of: groundedTask) {
            excerpt.quote.enumerateSubstrings(in: excerpt.quote.startIndex..<excerpt.quote.endIndex, options: .bySentences) { _, range, _, stop in
                if range.overlaps(taskRange) { taskSentence = String(excerpt.quote[range]); stop = true }
            }
        }
        let dueDate = stated(dueDate).flatMap { containsPhrase($0, in: taskSentence) ? $0 : nil }
        return .init(task: groundedTask, owner: owner, dueDate: dueDate, timestamp: excerpt.timestamp, sourceQuote: excerpt.quote)
    }

    public var markdown: String {
        "- [ ] " + task + (owner.map { " — " + $0 } ?? "")
            + (dueDate.map { " (" + $0 + ")" } ?? "")
            + (timestamp.map { " [" + $0 + "]" } ?? "")
    }

    public static func unique(_ actions: [SourceBackedAction]) -> [SourceBackedAction] {
        var seen: Set<String> = []
        return actions.filter {
            seen.insert([$0.task, $0.owner ?? "", $0.dueDate ?? ""].joined(separator: "\n").lowercased()).inserted
        }
    }

    private static func containsPhrase(_ phrase: String, in text: String) -> Bool {
        let pattern = #"(?<![\p{L}\p{N}_])"# + NSRegularExpression.escapedPattern(for: phrase) + #"(?![\p{L}\p{N}_])"#
        return text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// The model sometimes omits a modifier ("send the checklist" for "send the Orchard
    /// checklist"). Restore the contiguous source phrase rather than drop the commitment
    /// or publish a task with its project name missing. Every displayed word is from source.
    private static func taskPhrase(_ phrase: String, in quote: String) -> String? {
        if containsPhrase(phrase, in: quote), let match = quote.range(of: phrase, options: .caseInsensitive) {
            return String(quote[match])
        }
        guard let regex = try? NSRegularExpression(pattern: #"[\p{L}\p{N}]+(?:['’][\p{L}\p{N}]+)*"#) else { return nil }
        let source = quote as NSString, candidate = phrase as NSString
        let words = regex.matches(in: quote, range: NSRange(location: 0, length: source.length))
        let wanted = regex.matches(in: phrase, range: NSRange(location: 0, length: candidate.length)).map { candidate.substring(with: $0.range).lowercased() }
        guard wanted.count >= 2 else { return nil }
        var matches: [(Int, NSRange)] = []
        for start in words.indices where source.substring(with: words[start].range).lowercased() == wanted[0] {
            var next = 1, end = start
            while next < wanted.count, end + 1 < words.count {
                end += 1
                if source.substring(with: words[end].range).lowercased() == wanted[next] { next += 1 }
            }
            guard next == wanted.count, end - start + 1 <= wanted.count + 4 else { continue }
            let range = NSRange(location: words[start].range.location, length: NSMaxRange(words[end].range) - words[start].range.location)
            let text = source.substring(with: range)
            guard text.range(of: #"[.!?]\s|[\n;]"#, options: .regularExpression) == nil else { continue }
            matches.append((end - start, range))
        }
        guard let shortest = matches.map(\.0).min() else { return nil }
        let best = matches.filter { $0.0 == shortest }
        guard best.count == 1 else { return nil }
        return source.substring(with: best[0].1)
    }
    private static func stated(_ value: String?) -> String? {
        guard let text = value?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty,
              !["undefined", "null", "unknown", "not stated", "not specified", "n/a", "none", "unassigned", "tbd"].contains(text.lowercased()) else { return nil }
        return text
    }
}
