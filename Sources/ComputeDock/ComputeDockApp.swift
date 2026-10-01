import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
struct ComputeDockApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var store = MonitorStore()
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .preferredColorScheme(.light)
                .frame(minWidth: 1050, minHeight: 720)
                .onAppear { store.start() }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in store.shutdown() }
        }
        .defaultSize(width: 1340, height: 880)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("监控") {
                Button(store.paused ? "继续监控" : "暂停监控") { store.togglePause() }.keyboardShortcut("p", modifiers: [.command, .shift])
                Button(store.demoMode ? "使用真实服务器" : "进入演示模式") { store.setDemo(!store.demoMode) }
            }
        }
    }
}
