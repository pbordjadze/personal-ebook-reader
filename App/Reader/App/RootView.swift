import SwiftUI

/// The app's first screen: the library. Until a server is added (the library slice) it is empty.
///
/// Demo scenarios (Debug builds, `ci/scenarios.txt`): `library-empty` (and its `-dark` and
/// `-long-text` variants) with no server added.
struct RootView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView {
                Label("No Books Yet", systemImage: "books.vertical")
            } description: {
                Text("Add your library’s server to see your books here.")
            }
            .navigationTitle("Library")
            #if DEBUG
            .onAppear { DemoMode.markReady() }
            #endif
        }
    }
}
