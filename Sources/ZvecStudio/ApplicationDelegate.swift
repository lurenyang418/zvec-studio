import AppKit

@MainActor
final class ApplicationDelegate: NSObject, NSApplicationDelegate {
    var shutdownHandler: (@MainActor @Sendable () async -> Void)?
    private var terminationInProgress = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        let application = NSApplication.shared
        application.setActivationPolicy(.regular)
        DispatchQueue.main.async {
            application.windows.first?.orderFrontRegardless()
            application.activate()
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !terminationInProgress, let shutdownHandler else { return .terminateNow }
        terminationInProgress = true
        Task { @MainActor in
            await shutdownHandler()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
