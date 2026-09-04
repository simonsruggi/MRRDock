import XCTest
@testable import MRRDock

final class WebhookNotifierTests: XCTestCase {
    func testOnlyHTTPSDiscordAndSlackAreAccepted() {
        XCTAssertNotNil(WebhookNotifier(urlString: "https://discord.com/api/webhooks/123/abc"))
        XCTAssertNotNil(WebhookNotifier(urlString: "https://hooks.slack.com/services/T/B/x"))
        XCTAssertNil(WebhookNotifier(urlString: "http://discord.com/api/webhooks/123/abc"))
        XCTAssertNil(WebhookNotifier(urlString: "https://evil.example.com/collect"))
        XCTAssertNil(WebhookNotifier(urlString: ""))
        XCTAssertNil(WebhookNotifier(urlString: "https://discord.com.evil.example/x"))
    }

    func testPayloadShapeFollowsTheHost() throws {
        let discord = try XCTUnwrap(WebhookNotifier(urlString: "https://discord.com/api/webhooks/1/x"))
        let embeds = discord.payload(title: "T", body: "B", positive: true)["embeds"] as? [[String: Any]]
        XCTAssertEqual(embeds?.first?["title"] as? String, "T")

        let slack = try XCTUnwrap(WebhookNotifier(urlString: "https://hooks.slack.com/services/T/B/x"))
        XCTAssertEqual(slack.payload(title: "T", body: "B", positive: false)["text"] as? String, "*T*\nB")
    }
}

final class ProviderErrorTests: XCTestCase {
    func testHTTPErrorsShowTheProviderMessageNotTheRawJSON() {
        let revenueCat = #"{"doc_url":"https://errors.rev.cat/authentication-error","message":"Invalid API key.","object":"error","retryable":false}"#
        XCTAssertEqual(ProviderError.http(401, revenueCat).errorDescription, "HTTP 401: Invalid API key.")

        let stripe = #"{"error":{"type":"invalid_request_error","message":"Invalid API Key provided: rk_live_***"}}"#
        XCTAssertEqual(ProviderError.http(401, stripe).errorDescription, "HTTP 401: Invalid API Key provided: rk_live_***")

        let lemonSqueezy = #"{"errors":[{"status":"401","detail":"Unauthenticated."}]}"#
        XCTAssertEqual(ProviderError.http(401, lemonSqueezy).errorDescription, "HTTP 401: Unauthenticated.")
    }

    func testNonJSONBodiesFallBackToTheTruncatedText() {
        XCTAssertEqual(ProviderError.http(502, "<html>Bad gateway</html>").errorDescription,
                       "HTTP 502: <html>Bad gateway</html>")
        XCTAssertEqual(ProviderError.http(500, "   ").errorDescription, "HTTP 500")
    }
}
