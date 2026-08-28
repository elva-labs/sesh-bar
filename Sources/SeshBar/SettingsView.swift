import AwseshCore
import KeyboardShortcuts
import SwiftUI

struct SettingsView: View {
    @ObservedObject var state: AppState

    @State private var editing: EditTarget? = nil
    @State private var confirmRemove: String? = nil

    struct EditTarget: Identifiable {
        var id: String { original ?? "new" }
        var original: String?
        var name = ""
        var startUrl = ""
        var ssoRegion = "us-east-1"
        var defaultRegion = "us-east-1"
    }

    var body: some View {
        Form {
            Section("General") {
                KeyboardShortcuts.Recorder("Open sesh-bar:", name: .togglePopover)
            }
            Section("SSO sessions") {
                if state.sessions.isEmpty {
                    Text("No sessions yet.").foregroundStyle(.secondary)
                }
                ForEach(state.sessions, id: \.name) { session in
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(session.name)
                            Text(session.startUrl).font(.caption).foregroundStyle(.secondary)
                                .lineLimit(1).truncationMode(.middle)
                        }
                        Spacer()
                        if session.authenticated {
                            Text("Signed in").font(.caption).foregroundStyle(.green)
                            Button("Sign out") { state.signOut(session: session.name) }
                                .controlSize(.small)
                        } else {
                            Button("Sign in…") { state.signIn(session: session.name) }
                                .controlSize(.small)
                        }
                        Button {
                            editing = EditTarget(original: session.name, name: session.name,
                                                 startUrl: session.startUrl,
                                                 ssoRegion: session.ssoRegion,
                                                 defaultRegion: session.defaultRegion)
                        } label: { Image(systemName: "pencil") }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Edit \(session.name)")
                        Button(role: .destructive) {
                            confirmRemove = session.name
                        } label: { Image(systemName: "trash") }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Remove \(session.name)")
                    }
                }
                Button("Add session…") { editing = EditTarget(original: nil) }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 380)
        .sheet(item: $editing) { target in
            SessionForm(state: state, target: target) { editing = nil }
        }
        .sheet(item: $state.loginFlow) { flow in
            LoginSheet(state: state, flow: flow)
        }
        .confirmationDialog("Remove session \"\(confirmRemove ?? "")\"?",
                            isPresented: .init(get: { confirmRemove != nil },
                                               set: { if !$0 { confirmRemove = nil } })) {
            Button("Remove and clear its credentials", role: .destructive) {
                if let name = confirmRemove { state.removeSession(named: name) }
                confirmRemove = nil
            }
        } message: {
            Text("Also signs out and removes its profiles from ~/.aws/credentials.")
        }
    }
}

struct SessionForm: View {
    @ObservedObject var state: AppState
    @State var target: SettingsView.EditTarget
    let onClose: () -> Void

    private var valid: Bool {
        !target.name.isEmpty && target.startUrl.hasPrefix("https://")
            && !target.ssoRegion.isEmpty && !target.defaultRegion.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(target.original == nil ? "Add SSO session" : "Edit \(target.original!)")
                .font(.headline)
            Form {
                TextField("Name", text: $target.name)
                    .disabled(target.original != nil) // name is the storage key
                TextField("Start URL", text: $target.startUrl, prompt: Text("https://…awsapps.com/start"))
                TextField("SSO region", text: $target.ssoRegion)
                TextField("Default region", text: $target.defaultRegion)
            }
            HStack {
                Spacer()
                Button("Cancel", action: onClose).keyboardShortcut(.cancelAction)
                Button("Save") {
                    state.saveSession(SSOSession(name: target.name,
                                                 startUrl: target.startUrl,
                                                 ssoRegion: target.ssoRegion,
                                                 defaultRegion: target.defaultRegion))
                    onClose()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!valid)
            }
        }
        .padding(16)
        .frame(width: 380)
    }
}
