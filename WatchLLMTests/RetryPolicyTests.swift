import XCTest
@testable import WatchLLM_Watch_App

final class RetryPolicyTests: XCTestCase {
    func testRetriesTransientErrorOnlyBeforeTextArrives() {
        let error = LLMAPIError(message: "busy", isRetryable: true)

        XCTAssertTrue(RetryPolicy.shouldRetry(error, attempt: 0, receivedText: false))
        XCTAssertFalse(RetryPolicy.shouldRetry(error, attempt: 0, receivedText: true))
        XCTAssertFalse(RetryPolicy.shouldRetry(error, attempt: 1, receivedText: false))
    }

    func testRetryableHTTPStatuses() {
        XCTAssertTrue(RetryPolicy.isRetryableHTTPStatus(429))
        XCTAssertTrue(RetryPolicy.isRetryableHTTPStatus(503))
        XCTAssertFalse(RetryPolicy.isRetryableHTTPStatus(400))
        XCTAssertFalse(RetryPolicy.isRetryableHTTPStatus(401))
    }

    func testRetryAfterSeconds() {
        XCTAssertEqual(RetryPolicy.retryAfter(from: "12"), 12)
    }

    func testRetryAfterHTTPDate() {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss z"
        let now = formatter.date(from: "2015-10-21 07:27:50 GMT")!

        let delay = RetryPolicy.retryAfter(
            from: "Wed, 21 Oct 2015 07:28:00 GMT",
            now: now
        )

        XCTAssertEqual(delay, 10)
    }
}
