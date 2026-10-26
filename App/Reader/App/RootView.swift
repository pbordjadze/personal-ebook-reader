import ReaderCore
import SwiftUI

/// Where the library's navigation stack can go.
nonisolated enum Route: Hashable {
    /// A catalog feed, optionally opened on the results of a search.
    case catalog(URL, search: String? = nil)
    case book(OPDSEntry)
    case shelfBook(ShelfBook)
}

/// The app's root: the library, and the catalog and books pushed over it.
struct RootView: View {
    @State private var library: Library
    @State private var path: [Route]
    @State private var showsServerForm: Bool

    init() {
        #if DEBUG
        if let demo = DemoMode.setup() {
            _library = State(initialValue: demo.library)
            _path = State(initialValue: demo.path)
            _showsServerForm = State(initialValue: demo.showsServerForm)
            return
        }
        #endif
        _library = State(initialValue: Library.onDevice())
        _path = State(initialValue: [])
        _showsServerForm = State(initialValue: false)
    }

    var body: some View {
        NavigationStack(path: $path) {
            LibraryView(showsServerForm: $showsServerForm)
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .catalog(let url, let search): CatalogView(url: url, initialSearch: search)
                    case .book(let entry): BookDetailView(entry: entry)
                    case .shelfBook(let book): ShelfBookView(book: book)
                    }
                }
        }
        .sheet(isPresented: $showsServerForm) {
            ServerFormView()
        }
        .environment(library)
    }
}
