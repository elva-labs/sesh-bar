import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// Global shortcut that toggles the popover from anywhere, recorded in
    /// Settings. KeyboardShortcuts owns recording, validation, persistence.
    static let togglePopover = Self("togglePopover")
}
