import AwseshCore
import SwiftUI

struct ContentView: View {
    @ObservedObject var state: AppState
    let openSettings: () -> Void
    let closePopover: () -> Void

    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            IdentityHeader(state: state)
            Divider()

            searchField
            Divider()

            if state.sessions.isEmpty {
                emptyState
            } else {
                accountList
            }

            Divider()
            footer
        }
        .frame(width: 380, height: 540)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay {
            if let target = state.accountSettingsTarget {
                AccountSettingsCard(state: state, entry: target)
            } else if let flow = state.loginFlow {
                LoginCard(state: state, flow: flow)
            }
        }
        .overlay(alignment: .bottom) { noticeBanner }
        .onChange(of: state.focusToken) { _ in searchFocused = true }
        .onAppear { searchFocused = true }
    }

    private var searchField: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.tertiary)
            TextField("Search accounts, roles, sessions…", text: $state.search)
                .textFieldStyle(.plain)
                .focused($searchFocused)
            if !state.search.isEmpty {
                Button {
                    state.search = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "person.badge.key")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.tertiary)
            Text("No SSO sessions").font(.headline)
            Text("Add your AWS SSO portal in Settings to get started.")
                .font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Open Settings…") { openSettings() }
                .controlSize(.small)
            Spacer()
        }
        .padding(.horizontal, 24)
    }

    // MARK: - List

    private var accountList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                    let starred = state.starredEntries
                    if !starred.isEmpty {
                        Section {
                            ForEach(Array(starred.enumerated()), id: \.element.id) { index, entry in
                                AccountRow(state: state, entry: entry,
                                           quickIndex: index < 9 ? index + 1 : nil)
                            }
                        } header: {
                            sectionLabel {
                                Image(systemName: "star.fill")
                                    .font(.system(size: 8))
                                    .foregroundStyle(.orange)
                                Text("STARRED")
                            }
                        }
                    }
                    ForEach(state.sessions, id: \.name) { session in
                        let entries = state.sessionEntries(session)
                        Section {
                            if !session.authenticated {
                                signInRow(session)
                            } else if entries.isEmpty && state.search.isEmpty {
                                Text("No accounts cached — refresh.")
                                    .font(.caption).foregroundStyle(.tertiary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 14).padding(.vertical, 6)
                            } else {
                                ForEach(entries) { entry in
                                    AccountRow(state: state, entry: entry)
                                }
                            }
                        } header: {
                            sessionHeader(session)
                        }
                    }
                    Color.clear.frame(height: 4)
                }
            }
            .onChange(of: state.selectedEntryID) { id in
                if let id { proxy.scrollTo(id, anchor: nil) }
            }
        }
    }

    private func sectionLabel<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 5) {
            content()
            Spacer()
        }
        .font(.system(size: 10, weight: .semibold))
        .kerning(0.6)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14).padding(.top, 8).padding(.bottom, 3)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func sessionHeader(_ session: SessionInfo) -> some View {
        sectionLabel {
            Text(session.name.uppercased())
            if session.authenticated, let expiry = expiryInfo(date: session.tokenExpires) {
                Circle().fill(expiry.tone).frame(width: 5, height: 5)
                    .help("SSO token: \(expiry.label)")
            }
        }
        .contentShape(Rectangle())
        .contextMenu {
            if session.authenticated {
                Button("Refresh accounts") { state.refreshFromAWS() }
                Button("Sign out") { state.signOut(session: session.name) }
            } else {
                Button("Sign in…") { state.signIn(session: session.name) }
            }
            Divider()
            Button("Manage sessions…") { openSettings() }
        }
    }

    private func signInRow(_ session: SessionInfo) -> some View {
        HStack {
            Text("Not signed in").font(.caption).foregroundStyle(.tertiary)
            Spacer()
            Button("Sign in…") { state.signIn(session: session.name) }
                .controlSize(.small)
        }
        .padding(.horizontal, 14).padding(.vertical, 6)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 2) {
            FooterButton(systemImage: "arrow.clockwise", help: "Refresh accounts from AWS (⌘R)",
                         spinning: state.isLoading) { state.refreshFromAWS() }
                .keyboardShortcut("r", modifiers: .command)
            FooterButton(systemImage: "gearshape", help: "Settings (⌘,)") { openSettings() }

            Spacer()

            Text("↑↓ navigate · ↩ switch")
                .font(.system(size: 10))
                .foregroundStyle(.quaternary)

            Spacer()

            FooterButton(systemImage: "power", help: "Quit sesh-bar (⌘Q)") { NSApp.terminate(nil) }
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder
    private var noticeBanner: some View {
        if let notice = state.notice {
            Text(notice)
                .font(.caption).lineLimit(3)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.quaternary))
                .padding(.bottom, 40)
                .task {
                    try? await Task.sleep(nanoseconds: 4_000_000_000)
                    state.notice = nil
                }
        }
    }
}

// MARK: - Footer button (hover + pressed feedback)

struct FooterButton: View {
    let systemImage: String
    let help: String
    var spinning = false
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Group {
                if spinning {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: systemImage)
                        .font(.system(size: 12, weight: .medium))
                }
            }
            .frame(width: 26, height: 24)
            .foregroundStyle(hovering ? .primary : .secondary)
            .background(hovering ? Color.primary.opacity(0.07) : .clear,
                        in: RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(PressableButtonStyle())
        .onHover { hovering = $0 }
        .help(help)
        .accessibilityLabel(help)
    }
}

/// Subtle press feedback — the interface confirming it heard the click.
struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Identity header

struct IdentityHeader: View {
    @ObservedObject var state: AppState

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            if let active = state.active {
                ZStack(alignment: .bottomTrailing) {
                    AccountAvatar(name: active.accountName, size: 32, active: true)
                    if let expiry = expiryInfo(iso: active.expiration) {
                        Circle().fill(expiry.tone).frame(width: 9, height: 9)
                            .overlay(Circle().strokeBorder(Color(nsColor: .windowBackgroundColor), lineWidth: 1.5))
                    }
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(active.accountName)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    HStack(spacing: 4) {
                        Text("\(shortRole(active.roleName)) · \(active.region ?? "no region")")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        if state.activeSessionSignedOut {
                            Text("· SSO signed out, credentials still valid")
                                .font(.system(size: 11))
                                .foregroundStyle(.orange)
                        }
                    }
                    .lineLimit(1)
                }
                Spacer()
                if hovering {
                    FooterButton(systemImage: "xmark.circle",
                                 help: "Clear active profile (revokes nothing upstream, empties [default])") {
                        state.clearActive()
                    }
                }
                if let expiry = expiryInfo(iso: active.expiration) {
                    Text(expiry.label)
                        .font(.system(size: 10, weight: .medium).monospacedDigit())
                        .padding(.horizontal, 6).padding(.vertical, 2.5)
                        .background(expiry.tone.opacity(0.14), in: Capsule())
                        .foregroundStyle(expiry.tone)
                }
            } else {
                AccountAvatar(name: "?", size: 32, active: false)
                VStack(alignment: .leading, spacing: 1) {
                    Text("No active session").font(.system(size: 13, weight: .semibold))
                    Text("Pick an account below")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .contextMenu {
            if state.active != nil {
                Button("Open AWS console") { state.openConsole() }
                Button("Clear active profile") { state.clearActive() }
            }
        }
    }
}

// MARK: - Avatar with deterministic per-account color

struct AccountAvatar: View {
    let name: String
    var size: CGFloat = 26
    var active = false

    @Environment(\.colorScheme) private var scheme

    private var hue: Double {
        // Stable hue from the account name — the same account always gets
        // the same color, which makes the list scannable at a glance.
        var hash: UInt64 = 5381
        for byte in name.utf8 { hash = hash &* 33 &+ UInt64(byte) }
        return Double(hash % 360) / 360.0
    }

    var body: some View {
        let fill = Color(hue: hue, saturation: 0.55, brightness: scheme == .dark ? 0.85 : 0.65)
        Circle()
            .fill(fill.opacity(scheme == .dark ? 0.22 : 0.14))
            .overlay(
                Text(initials(name))
                    .font(.system(size: size * 0.36, weight: .semibold))
                    .foregroundStyle(fill)
            )
            .overlay {
                if active {
                    Circle().strokeBorder(fill.opacity(0.5), lineWidth: 1)
                }
            }
            .frame(width: size, height: size)
    }
}

// MARK: - Expandable pill

/// Collapsed by default (icon or truncated text); a click expands it for a
/// few seconds, then it folds back on its own. The tap never reaches the
/// row underneath.
struct ExpandablePill: View {
    var systemImage: String? = nil
    var collapsedText: String? = nil
    let expandedText: String
    let tint: Color

    @State private var expanded = false
    @State private var collapseTask: Task<Void, Never>?

    var body: some View {
        Button {
            collapseTask?.cancel()
            withAnimation(.easeOut(duration: 0.18)) { expanded.toggle() }
            if expanded {
                collapseTask = Task {
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    guard !Task.isCancelled else { return }
                    withAnimation(.easeOut(duration: 0.18)) { expanded = false }
                }
            }
        } label: {
            HStack(spacing: 3) {
                if let systemImage {
                    Image(systemName: systemImage).font(.system(size: 9, weight: .semibold))
                }
                if expanded {
                    Text(expandedText)
                        .font(.system(size: 10, weight: .medium))
                        .fixedSize()
                        .transition(.opacity)
                } else if let collapsedText {
                    Text(collapsedText)
                        .font(.system(size: 10, weight: .medium))
                        .fixedSize()
                }
            }
            .padding(.horizontal, expanded || collapsedText != nil ? 6 : 4)
            .padding(.vertical, 2)
            .background(tint.opacity(0.13), in: Capsule())
            .foregroundStyle(tint)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(expandedText)
        .accessibilityLabel(expandedText)
    }
}

/// Collapsed form of a role name: first five letters plus an ellipsis.
func collapsedRole(_ role: String) -> String {
    let short = shortRole(role)
    return short.count > 5 ? String(short.prefix(5)) + "…" : short
}

// MARK: - Account row

struct AccountRow: View {
    @ObservedObject var state: AppState
    let entry: AppState.Entry
    var quickIndex: Int? = nil

    @State private var hovering = false

    private var account: AccountInfo { entry.account }
    private var session: SessionInfo { entry.session }

    private var isActive: Bool {
        guard let active = state.active else { return false }
        return active.sessionName == session.name && active.accountId == account.accountId
    }

    private var isSelected: Bool { state.selectedEntryID == entry.id }

    private var displayRole: String {
        if isActive, let role = state.active?.roleName { return role }
        return defaultRole(for: account)
    }

    private var isPending: Bool {
        state.switching?.session == session.name && state.switching?.accountId == account.accountId
    }

    var body: some View {
        Button {
            state.switchTo(session: session.name, account: account,
                           role: defaultRole(for: account))
        } label: {
            HStack(spacing: 9) {
                AccountAvatar(name: account.name, active: isActive)
                VStack(alignment: .leading, spacing: 0) {
                    Text(account.name)
                        .font(.system(size: 12.5, weight: isActive ? .semibold : .regular))
                        .lineLimit(1)
                    Text(account.accountId)
                        .font(.system(size: 10.5).monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
                Spacer(minLength: 4)
                if let quickIndex {
                    Text("⌘\(quickIndex)")
                        .font(.system(size: 9.5, weight: .medium).monospaced())
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 4).padding(.vertical, 1.5)
                        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 4))
                }
                if account.starred {
                    Image(systemName: "star.fill")
                        .font(.system(size: 8)).foregroundStyle(.orange.opacity(0.8))
                }
                if isActive {
                    ExpandablePill(systemImage: "checkmark.circle.fill",
                                   expandedText: "Active", tint: .green)
                }
                if !displayRole.isEmpty {
                    ExpandablePill(collapsedText: collapsedRole(displayRole),
                                   expandedText: shortRole(displayRole),
                                   tint: roleColor(displayRole))
                }
                if isPending {
                    ProgressView().controlSize(.small)
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.accentColor.opacity(0.16)
                          : isActive ? Color.accentColor.opacity(0.08)
                          : hovering ? Color.primary.opacity(0.05) : .clear)
            )
            .overlay(alignment: .leading) {
                if isActive {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.accentColor)
                        .frame(width: 3)
                        .padding(.vertical, 5)
                }
            }
            .padding(.horizontal, 6)
        }
        .buttonStyle(.plain)
        .id(entry.id)
        .disabled(state.switching != nil)
        .onHover { inside in
            hovering = inside
            if inside { state.selectedEntryID = entry.id }
        }
        .contextMenu {
            Button(account.starred ? "Unstar" : "Star") {
                state.toggleStar(session: session.name, account: account)
            }
            Divider()
            ForEach(account.roles.sorted { roleRank($0) < roleRank($1) }, id: \.self) { role in
                Button {
                    state.switchTo(session: session.name, account: account, role: role)
                } label: {
                    if isActive && state.active?.roleName == role {
                        Label(shortRole(role), systemImage: "checkmark")
                    } else {
                        Text(shortRole(role))
                    }
                }
            }
            Divider()
            Button("Account settings…") { state.accountSettingsTarget = entry }
        }
    }
}

// MARK: - Login sheet

struct LoginSheet: View {
    @ObservedObject var state: AppState
    let flow: LoginFlow

    var body: some View {
        VStack(spacing: 12) {
            Text("Sign in to \(flow.sessionName)").font(.headline)
            Text("Confirm this code in the browser window that just opened:")
                .font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Text(flow.info.userCode)
                .font(.title2.monospaced().weight(.semibold))
                .textSelection(.enabled)
            if let error = state.loginError {
                Text(error).font(.caption).foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            } else {
                ProgressView().controlSize(.small)
                Text("Waiting for approval…").font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Button("Reopen browser") {
                    if let url = URL(string: flow.info.verificationUriComplete) {
                        NSWorkspace.shared.open(url)
                    }
                }
                Button("Cancel") { state.cancelLogin() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(width: 300)
    }
}

// MARK: - Account settings overlay

/// In-popover card (not a .sheet — sheets displace NSPopovers).
struct AccountSettingsCard: View {
    @ObservedObject var state: AppState
    let entry: AppState.Entry

    @State private var defaultRolePick: String
    @State private var region: String
    @State private var profiles: [String: String]

    init(state: AppState, entry: AppState.Entry) {
        self.state = state
        self.entry = entry
        _defaultRolePick = State(initialValue: defaultRole(for: entry.account))
        _region = State(initialValue: entry.account.preferredRegion ?? "")
        _profiles = State(initialValue: entry.account.profileNames)
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(0.25)
                .onTapGesture { state.accountSettingsTarget = nil }

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 9) {
                    AccountAvatar(name: entry.account.name, size: 30)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(entry.account.name).font(.system(size: 13, weight: .semibold))
                        Text(entry.account.accountId)
                            .font(.system(size: 10.5).monospacedDigit())
                            .foregroundStyle(.tertiary)
                    }
                }

                if !entry.account.roles.isEmpty {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("DEFAULT ROLE").settingsLabel()
                        Picker("", selection: $defaultRolePick) {
                            ForEach(entry.account.roles.sorted { roleRank($0) < roleRank($1) }, id: \.self) {
                                Text(shortRole($0)).tag($0)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .controlSize(.small)
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("REGION OVERRIDE").settingsLabel()
                    TextField(entry.session.defaultRegion, text: $region)
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.small)
                        .font(.system(size: 11).monospaced())
                    Text("Empty uses the session default.")
                        .font(.system(size: 10)).foregroundStyle(.tertiary)
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text("PROFILE NAME PER ROLE").settingsLabel()
                    ForEach(entry.account.roles.sorted { roleRank($0) < roleRank($1) }, id: \.self) { role in
                        HStack(spacing: 6) {
                            Text(shortRole(role))
                                .font(.system(size: 11))
                                .frame(width: 90, alignment: .leading)
                                .lineLimit(1)
                            TextField("default", text: Binding(
                                get: { profiles[role] ?? "" },
                                set: { profiles[role] = $0 }))
                                .textFieldStyle(.roundedBorder)
                                .controlSize(.small)
                                .font(.system(size: 11).monospaced())
                        }
                    }
                    Text("Named roles write to that profile in ~/.aws/credentials instead of [default] — reach them with AWS_PROFILE=name.")
                        .font(.system(size: 10)).foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack {
                    Spacer()
                    Button("Cancel") { state.accountSettingsTarget = nil }
                    Button("Save") {
                        state.saveAccountSettings(entry: entry,
                                                  defaultRole: defaultRolePick,
                                                  region: region,
                                                  profileNamesByRole: profiles)
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(14)
            .frame(width: 320)
            .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.quaternary))
            .shadow(color: .black.opacity(0.25), radius: 18, y: 6)
            .padding(.top, 48)
        }
    }
}

extension Text {
    func settingsLabel() -> some View {
        self.font(.system(size: 9.5, weight: .semibold)).kerning(0.5).foregroundStyle(.secondary)
    }
}

// MARK: - Login overlay card (same reasoning: no sheets in popovers)

struct LoginCard: View {
    @ObservedObject var state: AppState
    let flow: LoginFlow

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(0.25)
            VStack(spacing: 12) {
                LoginSheet(state: state, flow: flow)
            }
            .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.quaternary))
            .shadow(color: .black.opacity(0.25), radius: 18, y: 6)
            .padding(.top, 90)
        }
    }
}
