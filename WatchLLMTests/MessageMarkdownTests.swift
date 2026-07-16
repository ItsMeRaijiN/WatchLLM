import XCTest
@testable import WatchLLM_Watch_App

final class MessageMarkdownTests: XCTestCase {
    func testParagraphsAndListLinesKeepTheirWhitespace() {
        let source = "Akapit pierwszy.\n\nAkapit drugi.\n- punkt jeden\n- punkt dwa"

        let rendered = MessageMarkdown.render(source)

        XCTAssertEqual(String(rendered.characters), source)
    }

    func testInlineFormattingStillRemovesMarkdownMarkers() {
        let rendered = MessageMarkdown.render("To jest **ważne** i `krótkie`.")

        XCTAssertEqual(String(rendered.characters), "To jest ważne i krótkie.")
    }
}
