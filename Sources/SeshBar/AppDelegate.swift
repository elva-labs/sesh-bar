import AppKit
import AwseshCore
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var settingsWindow: NSWindow?
    private let state = AppState()
    private var trayTimer: Timer?

    private static let popoverSize = NSSize(width: 380, height: 540)

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        buildMainMenu()

        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.statusItem = statusItem
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "person.badge.key",
                                   accessibilityDescription: "sesh-bar")
            button.imagePosition = .imageLeading
            button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.target = self
        }

        popover.behavior = .transient
        popover.animates = false
        popover.contentSize = Self.popoverSize
        popover.delegate = self
        popover.contentViewController = NSHostingController(rootView: ContentView(
            state: state,
            openSettings: { [weak self] in self?.openSettings() },
            closePopover: { [weak self] in self?.popover.performClose(nil) }
        ))

        state.onActiveChanged = { [weak self] in self?.updateTrayTitle() }
        state.reload()

        // Keep the tray title's expiry-driven look fresh even while closed.
        trayTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.state.reload()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        trayTimer?.invalidate()
    }

    private func updateTrayTitle() {
        guard let button = statusItem?.button else { return }
        if let active = state.active {
            button.title = " " + active.accountName
        } else {
            button.title = ""
        }
    }

    // MARK: - Popover / tray

    @objc private func statusItemClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showContextMenu()
            return
        }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            showPopover()
        }
    }

    private func showPopover() {
        guard let button = statusItem?.button else { return }
        state.reload()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
        popover.contentViewController?.view.window?.makeKey()
    }

    func popoverDidClose(_ notification: Notification) {
        popover.contentSize = Self.popoverSize
    }

    private func showContextMenu() {
        guard let statusItem else { return }
        let menu = NSMenu()
        menu.addItem(withTitle: "Open sesh-bar", action: #selector(openFromMenu), keyEquivalent: "")
        menu.addItem(withTitle: "Refresh accounts", action: #selector(refreshFromMenu), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(openSettingsFromMenu), keyEquivalent: ",")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit sesh-bar", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        for item in menu.items { item.target = item.action == #selector(NSApplication.terminate(_:)) ? nil : self }
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil // so left-click keeps toggling the popover
    }

    @objc private func openFromMenu() { showPopover() }
    @objc private func refreshFromMenu() { state.refreshFromAWS() }
    @objc private func openSettingsFromMenu() { openSettings() }

    // MARK: - Settings

    @objc func openSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentRect: .zero,
                                  styleMask: [.titled, .closable],
                                  backing: .buffered, defer: false)
            window.title = "sesh-bar Settings"
            window.contentViewController = NSHostingController(rootView: SettingsView(state: state))
            window.isReleasedWhenClosed = false
            window.setContentSize(NSSize(width: 480, height: 320))
            window.center()
            settingsWindow = window
        }
        popover.performClose(nil)
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Main menu (key equivalents for text fields)

    private func buildMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit sesh-bar", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        NSApp.mainMenu = mainMenu
    }
}
