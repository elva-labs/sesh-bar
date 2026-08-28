import AppKit
import AwseshCore
import KeyboardShortcuts
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var settingsWindow: NSWindow?
    private let state = AppState()
    private var trayTimer: Timer?
    private var keyMonitor: Any?

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

        KeyboardShortcuts.onKeyUp(for: .togglePopover) { [weak self] in
            self?.togglePopoverFromShortcut()
        }

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

    private func togglePopoverFromShortcut() {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            showPopover()
        }
    }

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
        state.popoverOpened()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
        popover.contentViewController?.view.window?.makeKey()
        installKeyMonitor()
    }

    func popoverDidClose(_ notification: Notification) {
        popover.contentSize = Self.popoverSize
        removeKeyMonitor()
    }

    /// Keyboard navigation for the list while the popover is key: arrows move
    /// the selection, Return switches, Escape clears the search then closes.
    /// Instant, unanimated — this runs dozens of times a day.
    private func installKeyMonitor() {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self,
                  self.popover.isShown,
                  event.window === self.popover.contentViewController?.view.window
            else { return event }

            let modifiers = event.modifierFlags.intersection([.command, .option, .control])

            // ⌘1…⌘9: quick-select the Nth starred account.
            if modifiers == .command,
               self.state.accountSettingsTarget == nil, self.state.loginFlow == nil,
               let chars = event.charactersIgnoringModifiers, chars.count == 1,
               let digit = Int(chars), (1...9).contains(digit) {
                self.state.quickSelect(digit)
                return nil
            }

            guard modifiers.isEmpty else { return event }

            // While an overlay card is up, it owns the keyboard; Escape
            // dismisses it, everything else passes through to its fields.
            if self.state.accountSettingsTarget != nil {
                if event.keyCode == 53 { self.state.accountSettingsTarget = nil; return nil }
                return event
            }
            if self.state.loginFlow != nil {
                if event.keyCode == 53 { self.state.cancelLogin(); return nil }
                return event
            }

            switch event.keyCode {
            case 125: // down
                self.state.moveSelection(1)
                return nil
            case 126: // up
                self.state.moveSelection(-1)
                return nil
            case 36, 76: // return / keypad enter
                self.state.activateSelection()
                return nil
            case 53: // escape
                if self.state.search.isEmpty {
                    self.popover.performClose(nil)
                } else {
                    self.state.search = ""
                }
                return nil
            default:
                return event
            }
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
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
            window.setContentSize(NSSize(width: 480, height: 380))
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
