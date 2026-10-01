import Foundation

enum MailboxColour: String, CaseIterable, Codable, Sendable {
    case indigo, teal, violet, amber, slate
    var title: String { rawValue.capitalized }
    static func defaultColour(_ id: String) -> Self {
        allCases[id.utf8.reduce(0) { ($0 + Int($1)) % allCases.count }]
    }
}
enum MailboxIcon: String, CaseIterable, Codable, Sendable {
    case initials, mail, work, personal, none
    var title: String { rawValue.capitalized }
    var symbol: String? {
        switch self {
        case .mail: "envelope"
        case .work: "briefcase"
        case .personal: "person"
        case .initials, .none: nil
        }
    }
}
