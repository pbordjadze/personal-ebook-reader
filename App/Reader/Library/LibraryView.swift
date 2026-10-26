import ReaderCore
import SwiftUI

/// The first screen: the way into the server's catalog, and the books on this iPhone, which open
/// without a connection.
///
/// Demo scenarios: `library-empty` (no server; and its `-dark` and `-long-text` variants) and
/// `library-shelf` (a server and two books; also `-dark` and `-long-text`).
struct LibraryView: View {
    @Binding var showsServerForm: Bool
    @Environment(Library.self) private var library

    var body: some View {
        Group {
            if library.server == nil && library.shelf.books.isEmpty {
                ContentUnavailableView {
                    Label("No Books Yet", systemImage: "books.vertical")
                } description: {
                    Text("Add your library’s server to see your books here.")
                } actions: {
                    Button("Add Server") { showsServerForm = true }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                shelfList
            }
        }
        .navigationTitle("Library")
        .toolbar {
            if library.server != nil || !library.shelf.books.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Button { showsServerForm = true } label: {
                        Label("Server", systemImage: "server.rack")
                    }
                }
            }
        }
        #if DEBUG
        .onAppear { DemoMode.markReady(.library) }
        #endif
    }

    private var shelfList: some View {
        List {
            if let server = library.server {
                Section {
                    NavigationLink(value: Route.catalog(server.url)) {
                        Label("Browse the Catalog", systemImage: "books.vertical")
                    }
                }
            }
            Section {
                let books = library.shelf.books
                ForEach(books) { book in
                    NavigationLink(value: Route.shelfBook(book)) {
                        ShelfRow(book: book)
                    }
                }
                .onDelete { offsets in
                    for index in offsets { library.delete(books[index]) }
                }
            } header: {
                Text("On This iPhone")
            } footer: {
                if library.shelf.books.isEmpty {
                    Text("Books you download appear here, ready to read without a connection.")
                }
            }
        }
    }
}

private struct ShelfRow: View {
    let book: ShelfBook
    @Environment(Library.self) private var library

    var body: some View {
        HStack(spacing: 12) {
            CoverView(source: .file(library.coverURL(for: book)), width: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(book.title)
                    .font(.headline)
                if !book.authors.isEmpty {
                    Text(book.authors.formatted(.list(type: .and)))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 6) {
                    Text(verbatim: book.format.label)
                    Text(Int64(book.length).formatted(.byteCount(style: .file)))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

extension BookFormat {
    /// The format's name as people know it; the same in every language.
    var label: String { rawValue.uppercased() }
}
