import ReaderCore
import SwiftUI
import UIKit

/// Adds the library server, or changes or removes it: its catalog's address and a login. Saving
/// checks the address answers as an OPDS catalog with that login before keeping it.
///
/// Demo scenario: `server-form`.
struct ServerFormView: View {
    @Environment(Library.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var address = ""
    @State private var username = ""
    @State private var password = ""
    @State private var checking = false
    @State private var problem: String?
    @State private var confirmsRemoval = false
    @State private var saving: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Address", text: $address, prompt: Text(verbatim: "https://books.example.com/opds"))
                        .textContentType(.URL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Catalog")
                } footer: {
                    Text("Your library’s OPDS catalog. For Calibre-Web, its address followed by /opds.")
                }
                Section {
                    TextField("User Name", text: $username)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Password", text: $password)
                        .textContentType(.password)
                } header: {
                    Text("Login")
                } footer: {
                    Text("Leave these empty if the catalog needs no login. The password stays in this iPhone’s Keychain.")
                }
                if let problem {
                    Section {
                        Label(problem, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    }
                }
                if library.server != nil {
                    Section {
                        Button("Remove Server", role: .destructive) { confirmsRemoval = true }
                    } footer: {
                        Text("Books on this iPhone stay.")
                    }
                }
            }
            .disabled(checking)
            .navigationTitle(library.server == nil ? Text("Add Server") : Text("Server"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) {
                        saving?.cancel()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if checking {
                        ProgressView()
                            .accessibilityLabel("Checking the Server")
                    } else {
                        Button("Save") { saving = Task { await save() } }
                            .disabled(address.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            .confirmationDialog("Remove the server?", isPresented: $confirmsRemoval, titleVisibility: .visible) {
                Button("Remove Server", role: .destructive) {
                    library.removeServer()
                    dismiss()
                }
            } message: {
                Text("Books on this iPhone stay.")
            }
        }
        .onAppear {
            if let server = library.server, address.isEmpty {
                address = server.url.absoluteString
                username = server.username
                password = library.password ?? ""
            }
            #if DEBUG
            DemoMode.markReady(.serverForm)
            #endif
        }
        .onDisappear { saving?.cancel() }
    }

    private func save() async {
        checking = true
        defer { checking = false }
        problem = nil
        do {
            try await library.addServer(address: address, username: username, password: password)
            dismiss()
        } catch is CancellationError {
        } catch {
            problem = message(for: error)
        }
    }
}
