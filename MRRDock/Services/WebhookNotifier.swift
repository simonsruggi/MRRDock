import Foundation

/// Posts to a Discord or Slack incoming webhook. The payload shape is picked
/// from the host, so the user pastes one URL and gets a proper embed either way.
struct WebhookNotifier {
    let url: URL

    /// Only https, and only the two hosts that actually accept these payloads:
    /// the URL comes from a text field and this app has live revenue figures to
    /// leak, so an arbitrary host is not somewhere they should go by accident.
    static let allowedHosts: Set<String> = ["discord.com", "discordapp.com", "hooks.slack.com"]

    init?(urlString: String) {
        guard let url = URL(string: urlString.trimmingCharacters(in: .whitespaces)),
              url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased(),
              Self.allowedHosts.contains(host) || host.hasSuffix(".discord.com") else { return nil }
        self.url = url
    }

    var isDiscord: Bool {
        guard let host = url.host?.lowercased() else { return false }
        return host.contains("discord")
    }

    func payload(title: String, body: String, positive: Bool) -> [String: Any] {
        if isDiscord {
            return ["embeds": [[
                "title": title,
                "description": body,
                "color": positive ? 0x2ECC71 : 0xE74C3C,
                "footer": ["text": "MRRDock"],
            ]]]
        }
        return ["text": "*\(title)*\n\(body)"]
    }

    @discardableResult
    func send(title: String, body: String, positive: Bool) async -> Bool {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Discord rejects requests without a User-Agent with a 403.
        request.setValue("MRRDock/\(AppInfo.version)", forHTTPHeaderField: "User-Agent")
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload(title: title, body: body, positive: positive))
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            return (200..<300).contains(code)
        } catch {
            NSLog("[MRRDock] webhook failed: %@", error.localizedDescription)
            return false
        }
    }
}
