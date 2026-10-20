import AppKit
import SwiftUI
import SonosKit

extension Notification.Name {
    static let sonosMenuBarOnly = Notification.Name("sonosMenuBarOnly")
    static let sonosOpenMainWindow = Notification.Name("sonosOpenMainWindow")
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        if UserDefaults.standard.bool(forKey: AppModel.menuBarOnlyKey) {
            NSApp.setActivationPolicy(.accessory)
        }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(menuBarOnlyChanged(_:)),
            name: .sonosMenuBarOnly,
            object: nil
        )
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let url = Bundle.module.url(forResource: "AppIcon", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            NSApp.applicationIconImage = image
        }
        if UserDefaults.standard.bool(forKey: AppModel.menuBarOnlyKey) {
            closeMainWindows()
            DispatchQueue.main.async { [weak self] in
                self?.closeMainWindows()
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    @objc func menuBarOnlyChanged(_ note: Notification) {
        let only = note.userInfo?["value"] as? Bool ?? false
        if only {
            NSApp.setActivationPolicy(.accessory)
            closeMainWindows()
        } else {
            NSApp.setActivationPolicy(.regular)
            NotificationCenter.default.post(name: .sonosOpenMainWindow, object: nil)
        }
    }

    private func closeMainWindows() {
        for window in NSApp.windows {
            let identifier = window.identifier?.rawValue ?? ""
            if window.title == "Sonos Local" || identifier == "main" {
                window.close()
            }
        }
    }
}

@main
@MainActor
struct SonosLocalApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel()

    var body: some Scene {
        Window("Sonos Local", id: "main") {
            RootView()
                .environment(model)
        }
        .defaultSize(width: 1140, height: 780)
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Playback") {
                Button("Play or Pause") { model.togglePlay() }
                    .keyboardShortcut(.space, modifiers: [])
                Button("Next") { model.next() }
                    .keyboardShortcut(.rightArrow, modifiers: [.command])
                Button("Previous") { model.previous() }
                    .keyboardShortcut(.leftArrow, modifiers: [.command])
                Divider()
                Button("Search Again") { model.refresh() }
                    .keyboardShortcut("r", modifiers: [.command])
            }
        }

        MenuBarExtra {
            MenuBarView()
                .environment(model)
        } label: {
            Image(systemName: model.menuBarSymbol)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(model)
        }
    }
}
