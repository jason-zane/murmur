import Testing
import MurmurSessions

struct MeetingActionsTests {
    @Test func actionMetadataComesFromItsOwnSourcePassage() throws {
        let source = """
        [0:00] Maya: I will send the Orchard checklist on Thursday.
        [18:40] Sam: We will keep the budget at three thousand dollars. I will send the Cobalt worksheet on Monday.
        """
        let action = try #require(SourceBackedAction.verifying(task: "send the Cobalt worksheet", owner: "Sam", dueDate: "Monday", quote: "I will send the Cobalt worksheet on Monday.", in: source))
        #expect(action.markdown == "- [ ] send the Cobalt worksheet — Sam (Monday) [18:40]")
        let mixed = try #require(SourceBackedAction.verifying(task: "send the Cobalt worksheet", owner: "Maya", dueDate: "Thursday", quote: "I will send the Cobalt worksheet on Monday.", in: source))
        #expect(mixed.owner == nil && mixed.dueDate == nil)
        #expect(mixed.timestamp == "18:40")
        let unrelatedDate = try #require(SourceBackedAction.verifying(task: "keep the budget", owner: "Sam", dueDate: "Monday", quote: "We will keep the budget at three thousand dollars. I will send the Cobalt worksheet on Monday.", in: source))
        #expect(unrelatedDate.dueDate == nil)
        #expect(SourceBackedAction.verifying(task: "increase the budget", owner: "Sam", dueDate: nil, quote: "I will send the Cobalt worksheet on Monday.", in: source) == nil)
        #expect(SourceBackedAction.verifying(task: "send the budget", owner: "Sam", dueDate: nil, quote: "I will send the budget.", in: source) == nil)
    }

    @Test func ambiguousQuotesCannotBorrowAnotherSpeakersIdentity() throws {
        let source = "[0:00] Maya: I will send it.\n[2:00] Sam: I will send it."
        #expect(SourceBackedAction.verifying(task: "send it", owner: "Sam", dueDate: nil, quote: "I will send it.", in: source) == nil)
        let action = try #require(SourceBackedAction.verifying(task: "send it", owner: "Sam", dueDate: nil, quote: "[2:00] Sam: I will send it.", in: source))
        #expect(action.timestamp == "2:00" && action.owner == "Sam")
        #expect(SourceBackedAction.unique([action, action]).count == 1)
    }

    @Test func omittedProjectNamesAreRestoredFromTheSourceWithoutInventingTaskWords() throws {
        let quote = "I will send the Orchard checklist on Thursday."
        let action = try #require(SourceBackedAction.verifying(task: "send the checklist", owner: "Maya", dueDate: "Thursday", quote: quote, in: "[0:00] Maya: " + quote))
        #expect(action.task == "send the Orchard checklist")
        #expect(action.owner == "Maya" && action.dueDate == "Thursday")
        #expect(SourceBackedAction.verifying(task: "approve the checklist", owner: "Maya", dueDate: "Thursday", quote: quote, in: quote) == nil)
    }
}
