import Foundation

/// Formatting changes only. Every preset keeps the words, names, numbers and intent.
enum DictationStyle: String, CaseIterable, Identifiable, Sendable {
    case original, message, email
    var id: String { rawValue }
    var title: String {
        switch self { case .original: "Original"; case .message: "Message"; case .email: "Email" }
    }
    var detail: String {
        switch self {
        case .original: "Keep your wording, with punctuation, paragraphs and spoken lists."
        case .message: "Keep messages conversational and compact, with fewer paragraph breaks."
        case .email: "Use readable paragraphs and clearly spoken lists. No added greeting or sign-off."
        }
    }
    var instructions: String {
        switch self {
        case .original: "Keep the speaker's natural paragraphing."
        case .message: "Format as a compact chat message. Avoid unnecessary paragraph breaks; keep explicitly spoken lists. Do not change the tone or words."
        case .email: "Format as an email body, separating distinct topics into paragraphs and clearly spoken lists into bullet points. Never add a subject, greeting, sign-off or words the speaker did not say."
        }
    }
}
