import XCTest
@testable import WatchLLM_Watch_App

final class ConversationContextTests: XCTestCase {
    func testBudgetKeepsNewestCompletePairAndPendingUser() {
        let messages = [
            message(.user, "111111"),
            message(.assistant, "aaaaaa"),
            message(.user, "222222"),
            message(.assistant, "bbbbbb"),
            message(.user, "3333"),
        ]

        let context = ConversationContext.messages(from: messages, characterBudget: 16)

        XCTAssertEqual(context.map(\.text), ["222222", "bbbbbb", "3333"])
        XCTAssertEqual(context.first?.role, .user)
    }

    func testPairIsNotSplitWhenItDoesNotFit() {
        let messages = [
            message(.user, "111111"),
            message(.assistant, "aaaaaa"),
            message(.user, "3333"),
        ]

        let context = ConversationContext.messages(from: messages, characterBudget: 10)

        XCTAssertEqual(context.map(\.text), ["3333"])
    }

    func testContinuationAssistantMessagesAreMergedIntoTheSameTurn() {
        let messages = [
            message(.user, "question"),
            message(.assistant, "first part"),
            message(.assistant, "continued part"),
            message(.user, "next"),
        ]

        let context = ConversationContext.messages(from: messages, characterBudget: 100)

        XCTAssertEqual(context.map(\.role), [.user, .assistant, .user])
        XCTAssertEqual(context[1].text, "first part\n\ncontinued part")
    }

    func testNewestPromptIsKeptEvenAboveBudgetAndErrorsAreIgnored() {
        let messages = [
            message(.user, "old"),
            ChatMessage(role: .assistant, text: "error", isError: true),
            message(.user, "a very long newest prompt"),
        ]

        let context = ConversationContext.messages(from: messages, characterBudget: 5)

        XCTAssertEqual(context.map(\.text), ["a very long newest prompt"])
    }

    func testConversationTitleIsNormalizedAndTruncated() {
        let title = ConversationContext.title(from: "  Pierwsza\n  wiadomość   z odstępami  ", limit: 20)

        XCTAssertEqual(title, "Pierwsza wiadomość z…")
    }

    private func message(_ role: ChatMessage.Role, _ text: String) -> ChatMessage {
        ChatMessage(role: role, text: text)
    }
}
