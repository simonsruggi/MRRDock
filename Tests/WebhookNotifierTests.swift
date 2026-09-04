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
