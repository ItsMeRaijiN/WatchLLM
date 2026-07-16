import XCTest
@testable import WatchLLM_Watch_App

final class SSEParserTests: XCTestCase {
    func testRawLFStreamPreservesEventBoundariesAndDone() {
        let events = decode("event: first\ndata: {\"n\":1}\n\n: keep-alive\n\ndata: {\"n\":2}\n\ndata: [DONE]\n\n")

        XCTAssertEqual(events.count, 3)
        XCTAssertEqual(events[0].name, "first")
        XCTAssertEqual(text(events[0]), "{\"n\":1}")
        XCTAssertEqual(text(events[1]), "{\"n\":2}")
        XCTAssertEqual(text(events[2]), "[DONE]")
    }

    func testCRLFAndMultilineData() {
        let events = decode("event: multi\r\ndata: line 1\r\ndata: line 2\r\n\r\n")

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].name, "multi")
        XCTAssertEqual(text(events[0]), "line 1\nline 2")
    }

    func testBareCRSeparators() {
        let events = decode("data: one\r\rdata: two\r\r")

        XCTAssertEqual(events.map(text), ["one", "two"])
    }

    private func decode(_ raw: String) -> [SSEEvent] {
        var lineDecoder = SSELineDecoder()
        var parser = SSEParser()
        var events: [SSEEvent] = []

        for byte in raw.utf8 {
            if let line = lineDecoder.consume(byte),
               let event = parser.consume(line) {
                events.append(event)
            }
        }
        if let line = lineDecoder.finish(),
           let event = parser.consume(line) {
            events.append(event)
        }
        if let event = parser.finish() {
            events.append(event)
        }
        return events
    }

    private func text(_ event: SSEEvent) -> String {
        String(decoding: event.data, as: UTF8.self)
    }
}
