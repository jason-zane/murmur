import CryptoKit
import Darwin
import Foundation

/// The complete, finished text document exchanged with Murmur cloud. Recovery drafts and
/// audio never cross this boundary. Dates and optional fields are normalized before hashing.
public struct CloudDocument: Codable, Sendable, Equatable {
    public var session: MeetingSession
    public var transcript: [TranscriptSegment]
    public var bullets: [NoteBullet]
    public var note: String?

    public init(session: MeetingSession, transcript: [TranscriptSegment], bullets: [NoteBullet], note: String?) {
        self.session = session; self.transcript = transcript; self.bullets = bullets; self.note = note
    }
    public var fingerprint: String {
        let data = (try? CloudCoding.encoder.encode(self)) ?? Data()
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

public enum CloudCoding {
    public static var encoder: JSONEncoder {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601; return encoder
    }
    public static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { value in
            let text = try value.singleValueContainer().decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: text) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            guard let date = formatter.date(from: text) else {
                throw DecodingError.dataCorruptedError(in: try value.singleValueContainer(), debugDescription: "Invalid cloud date")
            }
            return date
        }
        return decoder
    }
}

public enum CloudImportError: LocalizedError {
    case changedLocally, atomicReplacementFailed
    public var errorDescription: String? {
        switch self {
        case .changedLocally: "This note changed while syncing. It will sync on the next pass."
        case .atomicReplacementFailed: "The cloud note could not be saved safely. Your existing note is intact."
        }
    }
}

extension SessionStore {
    public func cloudDocument(for id: String) throws -> CloudDocument? {
        try locked { unlockedCloudDocument(for: id) }
    }
    private func unlockedCloudDocument(for id: String) -> CloudDocument? {
        guard let session = session(id: id), !session.state.isInterrupted else { return nil }
        return CloudDocument(session: session, transcript: transcript(for: id), bullets: bullets(for: id), note: note(for: id))
    }

    /// Installs a coherent directory in one filesystem exchange. A crash cannot leave a
    /// new manifest next to an old transcript. Readers see the old or new complete copy.
    public func importCloudDocument(_ document: CloudDocument, expectedLocalFingerprint: String?,
                                    preserveConflict: Bool = false) throws -> String? {
        try locked {
            let id = document.session.id
            guard Self.isValidID(id), directory(for: id).lastPathComponent == id else { throw SessionStoreError.invalidID }
            guard !document.session.state.isInterrupted else { throw SessionStoreError.recording }
            if session(id: id)?.state.isInterrupted == true { throw SessionStoreError.recording }
            let existing = unlockedCloudDocument(for: id)
            guard existing?.fingerprint == expectedLocalFingerprint else { throw CloudImportError.changedLocally }
            let fm = FileManager.default
            let destination = directory(for: id)
            let staging = root.appendingPathComponent(".sync-" + UUID().uuidString)
            defer { try? fm.removeItem(at: staging) }
            if existing != nil { try fm.copyItem(at: destination, to: staging) }
            else { try fm.createDirectory(at: staging, withIntermediateDirectories: false) }

            if let old = existing?.note, old != document.note {
                var version = 1
                while fm.fileExists(atPath: staging.appendingPathComponent("note.\(version).md").path) { version += 1 }
                try old.write(to: staging.appendingPathComponent("note.\(version).md"), atomically: true, encoding: .utf8)
            }
            try Self.writeCloudFiles(document, into: staging)
            var conflictID: String?
            if preserveConflict, var conflict = existing {
                conflict.session.id = MeetingSession.makeID()
                conflict.session.title += " (copy from this Mac)"
                let conflictDirectory = directory(for: conflict.session.id)
                let conflictStaging = root.appendingPathComponent(".conflict-" + UUID().uuidString)
                defer { try? fm.removeItem(at: conflictStaging) }
                try fm.copyItem(at: destination, to: conflictStaging)
                try Self.writeCloudFiles(conflict, into: conflictStaging)
                try fm.moveItem(at: conflictStaging, to: conflictDirectory)
                conflictID = conflict.session.id
            }
            if existing != nil {
                guard renamex_np(staging.path, destination.path, UInt32(RENAME_SWAP)) == 0 else {
                    throw CloudImportError.atomicReplacementFailed
                }
            } else { try fm.moveItem(at: staging, to: destination) }
            return conflictID
        }
    }

    private static func writeCloudFiles(_ document: CloudDocument, into directory: URL) throws {
        try CloudCoding.encoder.encode(document.session).write(to: directory.appendingPathComponent("session.json"), options: .atomic)
        try CloudCoding.encoder.encode(document.bullets).write(to: directory.appendingPathComponent("notes.json"), options: .atomic)
        var transcript = Data()
        for segment in document.transcript { transcript.append(try CloudCoding.encoder.encode(segment)); transcript.append(0x0a) }
        try transcript.write(to: directory.appendingPathComponent("transcript.jsonl"), options: .atomic)
        let noteURL = directory.appendingPathComponent("note.md")
        if let note = document.note { try note.write(to: noteURL, atomically: true, encoding: .utf8) }
        else if FileManager.default.fileExists(atPath: noteURL.path) { try FileManager.default.removeItem(at: noteURL) }
    }
}

public struct CloudSyncEntry: Codable, Sendable {
    public var version: Int
    public var fingerprint: String
    public var removedLocally: Bool
    public init(version: Int, fingerprint: String, removedLocally: Bool = false) {
        self.version = version; self.fingerprint = fingerprint; self.removedLocally = removedLocally
    }
}

public enum CloudSyncAction: Equatable, Sendable {
    case upload(expectedVersion: Int), download, conflict, unchanged, keepLocalRemoval

    public static func decide(localFingerprint: String?, previous: CloudSyncEntry?, remoteVersion: Int?) -> Self {
        if previous?.removedLocally == true && localFingerprint == nil { return .keepLocalRemoval }
        guard let localFingerprint else { return previous == nil ? .download : .keepLocalRemoval }
        let localChanged = previous?.fingerprint != localFingerprint
        let remoteChanged = remoteVersion != previous?.version
        if remoteVersion == nil { return .upload(expectedVersion: 0) }
        if localChanged && remoteChanged { return .conflict }
        if localChanged { return .upload(expectedVersion: previous?.version ?? 0) }
        if remoteChanged { return .download }
        return .unchanged
    }
}
