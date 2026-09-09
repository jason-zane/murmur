import Testing
@testable import Murmur

@Suite struct BrowserCallStateTests {
    @Test(arguments: ["Join now", "Ask to join", "Rejoin", "Cancel request"])
    func previewAndWaitingRoomsAreNotCalls(_ joinButton: String) {
        #expect(BrowserCallState.googleMeet(buttonLabels: ["Turn off microphone", "Turn off camera", joinButton]) == .preview)
    }

    @Test func mutedJoinedCallRemainsActive() {
        #expect(BrowserCallState.googleMeet(buttonLabels: ["Turn on microphone", "Turn on camera", "Leave call"]) == .active)
    }

    @Test func anotherJoinedWindowWinsOverPreview() {
        #expect(BrowserCallState.googleMeet(buttonLabels: ["Join now", "Leave call (⌘ + W)"]) == .active)
    }

    @Test func unavailableControlsDoNotProveCallParticipation() {
        #expect(BrowserCallState.googleMeet(buttonLabels: []) == .unknown)
        #expect(BrowserCallState.googleMeet(buttonLabels: ["Turn off microphone", "Google Meet"]) == .unknown)
    }
}
