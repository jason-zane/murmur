import AppKit
import SwiftUI
import Testing
@testable import Murmur

@Suite @MainActor struct MeetingOfferTests {
    private let now = Date(timeIntervalSince1970: 1_000)
    private var candidate: MeetingCandidate {
        MeetingCandidate(bundleID: "com.google.Chrome", pid: 123, label: "Teams",
                         callNoun: "Teams call", isKnown: true, isBrowser: true, since: now)
    }

    @Test func detectionOnlyOffersAndTimeoutCannotBeAccepted() {
        let detector = MeetingDetector()
        var decisions: [MeetingDetector.Decision] = []
        detector.onDecision = { decisions.append($0) }
        detector.showOffer(candidate, at: now)
        #expect(decisions == [.offer(candidate, quiet: false)])
        #expect(detector.offered == candidate)
        detector.expireOffer(at: now.addingTimeInterval(14))
        #expect(detector.offered != nil)
        #expect(detector.acceptOffer(at: now.addingTimeInterval(15)) == nil)
        #expect(detector.offered == nil)
        detector.showOffer(candidate, at: now.addingTimeInterval(16))
        #expect(detector.offered == nil)
        #expect(decisions.count == 1)
    }

    @Test func explicitAcceptanceIsOneShot() {
        let detector = MeetingDetector()
        detector.showOffer(candidate, at: now)
        #expect(detector.acceptOffer(at: now.addingTimeInterval(5)) == candidate)
        #expect(detector.acceptOffer(at: now.addingTimeInterval(6)) == nil)
    }

    @Test func dismissedOfferCannotBeAccepted() {
        let detector = MeetingDetector()
        detector.showOffer(candidate, at: now)
        detector.decline()
        #expect(detector.acceptOffer(at: now) == nil)
        let other = MeetingDetector()
        other.showOffer(candidate, at: now)
        other.dismissOffer()
        #expect(other.acceptOffer(at: now) == nil)
    }

    @Test(arguments: HUDPosition.allCases)
    func offerUsesChosenEdge(_ position: HUDPosition) {
        let screen = NSRect(x: 100, y: 50, width: 1440, height: 900)
        let frame = position.frame(in: screen, canvas: DS.Offer.canvas)
        #expect(screen.contains(frame))
        switch position {
        case .top: #expect(frame.maxY == screen.maxY)
        case .bottom: #expect(frame.minY == screen.minY)
        case .left: #expect(frame.minX == screen.minX)
        case .right: #expect(frame.maxX == screen.maxX)
        }
    }

    @Test func renderOffer() throws {
        guard ProcessInfo.processInfo.environment["MURMUR_RENDER_OFFER"] == "1" else { return }
        let detector = MeetingDetector()
        detector.showOffer(candidate)
        let view = NSHostingView(rootView: OfferView(detector: detector, onStart: { _ in }, onDecline: {}))
        view.frame = NSRect(origin: .zero, size: DS.Offer.canvas)
        let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = view
        view.layoutSubtreeIfNeeded()
        let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: URL(fileURLWithPath: "/tmp/murmur-meeting-offer.png"))
    }
}
