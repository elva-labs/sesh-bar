import AwseshCore
import SwiftUI

struct ContentView: View {
    @ObservedObject var state: AppState
    let openSettings: () -> Void
    let closePopover: () -> Void

    @State private var search = ""

    var body: some View {
        VStack(spacing: 0) {
            IdentityHeader(state: state)
            Divider()

            TextField("Search accounts, roles, sessions…", text: $search)
                .textFieldStyle(.roundedBorder)
                .controlSize(.small)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
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
        .overlay(alignment: .bottom) { noticeBanner }
        .sheet(item: $state.loginFlow) { flow in
            LoginSheet(state: state, flow: flow)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Text("No SSO sessions configured").font(.headline)
            Text("Add your AWS SSO portal in Settings to get started.")
                .font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Open Settings…") { openSettings() }
            Spacer()
        }
        .padding(.horizontal, 24)
    }

    // MARK: - List

    private struct Entry: Identifiable {
        let session: SessionInfo
        let account: AccountInfo
        var id: String { "\(session.name)|\(account.accountId)" }
    }

    private func matches(_ entry: Entry) -> Bool {
        let term = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !term.isEmpty else { return true }
        let haystack = "\(entry.session.name) \(entry.account.name) \(entry.account.accountId) \(entry.account.roles.joined(separator: " "))".lowercased()
        return term.split(separator: " ").allSatisfy { haystack.contains($0) }
    }

    private var starredEntries: [Entry] {
        state.sessions.filter(\.authenticated).flatMap { session in
            (state.accounts[session.name] ?? []).filter(\.starred)
                .map { Entry(session: session, account: $0) }
        }.filter(matches)
    }

    private var accountList: some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                let starred = starredEntries
                if !starred.isEmpty {
                    Section {
                        ForEach(starred) { entry in
                            AccountRow(state: state, session: entry.session, account: entry.account)
                        }
                    } header: {
                        groupHeader { Label("Starred", systemImage: "star.fill")
                            .foregroundStyle(.orange) }
                    }
                }
                ForEach(state.sessions, id: \.name) { session in
                    let entries = (state.accounts[session.name] ?? [])
                        .filter { !$0.starred }
                        .map { Entry(session: session, account: $0) }
                        .filter(matches)
                    Section {
                        if !session.authenticated {
                            signInRow(session)
                        } else if entries.isEmpty && search.isEmpty {
                            Text("No accounts cached — refresh.")
                                .font(.caption).foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 12).padding(.vertical, 6)
                        } else {
                            ForEach(entries) { entry in
                                AccountRow(state: state, session: entry.session, account: entry.account)
                            }
                        }
                    } header: {
                        sessionHeader(session)
                    }
                }
            }
        }
    }

    private func groupHeader<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack {
            content().font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 12).padding(.vertical, 4)
        .background(.regularMaterial)
    }

    private func sessionHeader(_ session: SessionInfo) -> some View {
        groupHeader {
            Text(session.name)
            if session.authenticated, let expiry = expiryInfo(date: session.tokenExpires) {
                Circle().fill(expiry.tone).frame(width: 6, height: 6)
                    .help("SSO token: \(expiry.label)")
            }
        }
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
            Text("Not signed in").font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button("Sign in…") { state.signIn(session: session.name) }
                .controlSize(.small)
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Button { state.refreshFromAWS() } label: {
                if state.isLoading {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .buttonStyle(.borderless)
            .disabled(state.isLoading)
            .help("Refresh accounts from AWS (⌘R)")
            .keyboardShortcut("r", modifiers: .command)

            Button { openSettings() } label: { Image(systemName: "gearshape") }
                .buttonStyle(.borderless)
                .help("Settings (⌘,)")

            Spacer()

            Button { NSApp.terminate(nil) } label: { Image(systemName: "power") }
                .buttonStyle(.borderless)
                .help("Quit sesh-bar (⌘Q)")
                .accessibilityLabel("Quit")
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
    }

    @ViewBuilder
    private var noticeBanner: some View {
        if let notice = state.notice {
            Text(notice)
                .font(.caption).lineLimit(3)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
                .padding(.bottom, 40)
                .task {
                    try? await Task.sleep(nanoseconds: 4_000_000_000)
                    state.notice = nil
                }
        }
    }
}

// MARK: - Identity header

struct IdentityHeader: View {
    @ObservedObject var state: AppState

    var body: some View {
        HStack(spacing: 10) {
            if let active = state.active {
                ZStack(alignment: .bottomTrailing) {
                    avatar(initials(active.accountName))
                    if let expiry = expiryInfo(iso: active.expiration) {
                        Circle().fill(expiry.tone).frame(width: 9, height: 9)
                            .overlay(Circle().strokeBorder(.background, lineWidth: 1.5))
                    }
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(active.accountName).font(.headline).lineLimit(1)
                    Text("\(shortRole(active.roleName)) · \(active.region ?? "no region")")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                if let expiry = expiryInfo(iso: active.expiration) {
                    Text(expiry.label)
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(expiry.tone.opacity(0.15), in: Capsule())
                        .foregroundStyle(expiry.tone)
                }
            } else {
                avatar("–")
                VStack(alignment: .leading, spacing: 1) {
                    Text("No active session").font(.headline)
                    Text("Pick an account below").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .contentShape(Rectangle())
        .contextMenu {
            if state.active != nil {
                Button("Open AWS console") { state.openConsole() }
                Button("Clear active profile") { state.clearActive() }
            }
        }
    }

    private func avatar(_ text: String) -> some View {
        Circle().fill(.quaternary)
            .frame(width: 30, height: 30)
            .overlay(Text(text).font(.caption.weight(.semibold)))
    }
}

// MARK: - Account row

struct AccountRow: View {
    @ObservedObject var state: AppState
    let session: SessionInfo
    let account: AccountInfo

    @State private var hovering = false

    private var isActive: Bool {
        guard let active = state.active else { return false }
        return active.sessionName == session.name && active.accountId == account.accountId
    }

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
            HStack(spacing: 10) {
                Circle().fill(.quaternary)
                    .frame(width: 26, height: 26)
                    .overlay(Text(initials(account.name)).font(.caption2.weight(.semibold)))
                VStack(alignment: .leading, spacing: 1) {
                    Text(account.name).lineLimit(1)
                    Text(account.accountId)
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                Spacer()
                if account.starred {
                    Image(systemName: "star.fill").font(.caption2).foregroundStyle(.orange)
                }
                if isActive {
                    Circle().fill(.green).frame(width: 7, height: 7)
                }
                if !displayRole.isEmpty {
                    Text(shortRole(displayRole))
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(roleColor(displayRole).opacity(0.15), in: Capsule())
                        .foregroundStyle(roleColor(displayRole))
                }
                if isPending {
                    ProgressView().controlSize(.small)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 5)
            .contentShape(Rectangle())
            .background(hovering ? Color.primary.opacity(0.06) : .clear)
        }
        .buttonStyle(.plain)
        .disabled(state.switching != nil)
        .onHover { hovering = $0 }
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
