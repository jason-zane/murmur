import AuthenticationServices
import Foundation
import Testing
@testable import Murmur

@MainActor
struct CloudAuthenticationTests {
    @Test func browserCallbackCanArriveOffTheMainActor() async throws {
        let expected = URL(string: "murmur://oauth/callback?code=test&state=test")!
        let result: URL = try await withCheckedThrowingContinuation { continuation in
            let completion = CloudAccount.authenticationCompletion(resuming: continuation)
            DispatchQueue.global().async {
                #expect(!Thread.isMainThread)
                completion(expected, nil)
            }
        }
        #expect(result == expected)
        MainActor.assertIsolated()
    }

    @Test func browserCancellationReturnsAnErrorWithoutCrashing() async {
        do {
            let _: URL = try await withCheckedThrowingContinuation { continuation in
                let completion = CloudAccount.authenticationCompletion(resuming: continuation)
                DispatchQueue.global().async {
                    completion(nil, ASWebAuthenticationSessionError(.canceledLogin))
                }
            }
            Issue.record("A cancelled sign-in must not succeed")
        } catch let error as ASWebAuthenticationSessionError {
            #expect(error.code == .canceledLogin)
        } catch {
            Issue.record("The browser cancellation error should be preserved: \(error)")
        }
    }
}
