import Foundation
import AVFoundation
import Testing
import MurmurSessions
@testable import Murmur

@MainActor
@Suite(.serialized) struct AppWorkflowTests {
    @Test func connectingClaudePreservesOtherServersAndBacksUpConfig() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("murmur-config-test-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("config.json")
        let original = Data(#"{"mcpServers":{"existing":{"command":"my-server"}},"preferences":{"theme":"dark"}}"#.utf8)
        try original.write(to: url)
        try ClaudeDesktopIntegration.configure(allowWrites: true, configURL: url, serverPath: "/usr/bin/true")
        let data = try Data(contentsOf: url)
        let config = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let servers = try #require(config["mcpServers"] as? [String: Any])
        #expect((servers["existing"] as? [String: Any])?["command"] as? String == "my-server")
        #expect((servers["murmur"] as? [String: Any])?["args"] as? [String] == ["--allow-writes"])
        #expect((config["preferences"] as? [String: Any])?["theme"] as? String == "dark")
        let backup = try #require(FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).first { $0.lastPathComponent.hasPrefix("claude_config.before-murmur-") })
        #expect(try Data(contentsOf: backup) == original)
        try Data("{broken".utf8).write(to: url)
        #expect(throws: (any Error).self) { try ClaudeDesktopIntegration.configure(configURL: url, serverPath: "/usr/bin/true") }
        #expect(try String(contentsOf: url, encoding: .utf8) == "{broken")
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["MURMUR_MODEL_SMOKE"] == "1"))
    func localSummarySmoke() async throws {
        print("Apple Intelligence: \(FoundationModelFormatter.unavailableReason ?? "available")")
        guard FoundationModelFormatter.isAvailable else { return }
        let store = SessionStore(root: FileManager.default.temporaryDirectory.appendingPathComponent("murmur-summary-test-\(UUID())"))
        defer { try? FileManager.default.removeItem(at: store.root) }
        let s = try store.createNote(title: "Pilot launch review")
        try store.append([
            TranscriptSegment(start: 0, end: 5, source: .you, text: "Let's decide when to launch the pilot."),
            TranscriptSegment(start: 6, end: 12, source: .call, speaker: "Maya", text: "We agreed to launch the pilot on Friday. I will send the checklist on Thursday."),
            TranscriptSegment(start: 15, end: 20, source: .you, text: "The budget remains two thousand dollars. We still need to decide who owns support."),
        ], to: s.id)
        try store.saveBullets([NoteBullet(at: 6, text: "Friday pilot. Maya owns checklist. Support owner unresolved.")], for: s.id)
        let service = MeetingSummaryService()
        service.generate(id: s.id, template: .meeting, store: store)
        let deadline = ContinuousClock.now.advanced(by: .seconds(90))
        while service.isWorking(s.id), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(100)) }
        #expect(!service.isWorking(s.id))
        #expect(service.errors[s.id] == nil)
        let summary = try #require(store.note(for: s.id))
        print("Synthetic meeting summary:\n\(summary)")
        #expect(summary.localizedCaseInsensitiveContains("Friday"))
        #expect(summary.localizedCaseInsensitiveContains("Maya"))
        #expect(summary.localizedCaseInsensitiveContains("support"))
        let actions = summary.split(separator: "\n").filter { $0.contains("[ ]") }
        #expect(actions.contains { $0.localizedCaseInsensitiveContains("checklist") && $0.localizedCaseInsensitiveContains("Thursday") })
        #expect(!actions.contains { $0.localizedCaseInsensitiveContains("support") })
        #expect(!summary.localizedCaseInsensitiveContains("undefined"))
        #expect(store.transcript(for: s.id).count == 3)
        #expect(store.bullets(for: s.id).count == 1)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["MURMUR_MODEL_SMOKE"] == "1"))
    func localLongSummaryReadsFirstAndLastParts() async throws {
        guard FoundationModelFormatter.isAvailable else { return }
        let store = SessionStore(root: FileManager.default.temporaryDirectory.appendingPathComponent("murmur-long-summary-test-\(UUID())"))
        defer { try? FileManager.default.removeItem(at: store.root) }
        let s = try store.createNote(title: "Synthetic planning review")
        var segments = [TranscriptSegment(start: 0, end: 8, source: .call, speaker: "Maya", text: "We agreed that the Orchard pilot launches on Friday. I will send the Orchard checklist on Thursday.")]
        for index in 1...36 {
            segments.append(TranscriptSegment(start: Double(index * 30), end: Double(index * 30 + 20), source: .you,
                text: "We reviewed the current product flow and discussed how people find their next step. Clear labels and understandable feedback matter during setup. We considered several options, but did not choose a new design or commit to additional work during this part of the discussion."))
        }
        segments.append(TranscriptSegment(start: 1_120, end: 1_135, source: .call, speaker: "Sam", text: "Our final decision is to keep the Cobalt budget at three thousand dollars. I will send the Cobalt budget worksheet on Monday."))
        try store.append(segments, to: s.id)
        #expect(MeetingNotes.source(session: s, bullets: [], segments: segments).count > 10_000)
        let service = MeetingSummaryService()
        service.generate(id: s.id, template: .meeting, store: store)
        let deadline = ContinuousClock.now.advanced(by: .seconds(180))
        while service.isWorking(s.id), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(100)) }
        #expect(!service.isWorking(s.id))
        #expect(service.errors[s.id] == nil)
        let note = try #require(store.note(for: s.id))
        print("Long synthetic meeting summary:\n\(note)")
        #expect(note.localizedCaseInsensitiveContains("Orchard"))
        #expect(note.localizedCaseInsensitiveContains("Cobalt"))
        #expect(note.localizedCaseInsensitiveContains("Monday"))
        let actions = note.split(separator: "\n").filter { $0.contains("[ ]") }
        #expect(actions.count == 2)
        #expect(actions.contains {
            $0.localizedCaseInsensitiveContains("worksheet") &&
            $0.localizedCaseInsensitiveContains("Sam") &&
            $0.localizedCaseInsensitiveContains("Monday")
        })
        #expect(actions.contains {
            $0.localizedCaseInsensitiveContains("checklist") &&
            $0.localizedCaseInsensitiveContains("Maya") &&
            $0.localizedCaseInsensitiveContains("Thursday")
        })
        #expect(store.transcript(for: s.id).count == segments.count)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["MURMUR_CAPTURE_SMOKE"] == "1"))
    func appleMeetingTranscriberAcceptsAudioAndFinishes() async throws {
        let transcriber = AppleMeetingTranscriber()
        let events = try await AsyncDeadline.run(for: .seconds(45)) { try await transcriber.start(source: .you, offset: 0) }
        let format = try #require(await transcriber.preferredInputFormat())
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4_096))
        buffer.frameLength = buffer.frameCapacity
        for channel in 0..<Int(format.channelCount) {
            buffer.floatChannelData?[channel].initialize(repeating: 0, count: Int(buffer.frameLength))
        }
        await transcriber.feed(AudioChunk(buffer: buffer))
        try await AsyncDeadline.run(for: .seconds(20)) { await transcriber.finish() }
        var failures: [String] = []
        for await event in events { if case .failed(_, let message) = event { failures.append(message) } }
        #expect(failures.isEmpty)
    }
}
