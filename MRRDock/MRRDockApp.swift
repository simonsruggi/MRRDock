import SwiftUI

@main
struct MRRDockApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        if MCPServer.requested { MRRDockTools.server().run() }
    }

    var body: some Scene {
        Settings { EmptyView() }
    }
}
