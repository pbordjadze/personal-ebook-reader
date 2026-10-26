#if DEBUG
import Foundation
import os
import ReaderCore

/// The state each demo scenario starts in, from the fixture catalog (`DemoServer`):
///
/// - `library-empty`: no server, no books.
/// - `library-shelf`: a server and two books on the shelf.
/// - `server-form`: adding a server.
/// - `catalog`: the catalog's first page (a navigation feed).
/// - `catalog-new`: a page of books, with covers.
/// - `catalog-search`: the results of a search.
/// - `book-detail`: a book offered as EPUB and PDF, its PDF already on the shelf.
/// - `shelf-book`: a book on the shelf, with no server.
extension DemoMode {
    enum Screen {
        case library, serverForm, catalog, book, shelfBook
    }

    struct Setup {
        var library: Library
        var path: [Route] = []
        var showsServerForm = false
    }

    /// The scenario without the suffixes that only change how it is captured.
    static var state: String {
        var state = scenario ?? ""
        for suffix in ["-long-text", "-dark"] where state.hasSuffix(suffix) { state.removeLast(suffix.count) }
        return state
    }

    static var screen: Screen {
        switch state {
        case "server-form": .serverForm
        case "catalog", "catalog-new", "catalog-search": .catalog
        case "book-detail": .book
        case "shelf-book": .shelfBook
        default: .library
        }
    }

    /// A fresh library in the app's temporary folder, set up for the scenario; nil outside demo mode.
    static func setup() -> Setup? {
        guard isActive else { return nil }
        let folder = FileManager.default.temporaryDirectory.appending(path: "demo-library")
        try? FileManager.default.removeItem(at: folder)
        if !["library-empty", "server-form", "shelf-book"].contains(state) {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try? JSONEncoder().encode(Server(url: DemoServer.address, username: ""))
                .write(to: folder.appending(path: "server.json"))
        }
        let library = Library(folder: folder, passwords: MemoryPasswordStore(), transport: DemoServer())
        let newBooks = URL(string: "/opds/new", relativeTo: DemoServer.address)!.absoluteURL
        let books = (DemoServer.file("/opds/new").flatMap { try? OPDSFeed(data: $0, url: newBooks) })?.entries ?? []
        var setup = Setup(library: library)
        switch state {
        case "library-shelf":
            for (index, entry) in books.enumerated() {
                shelve(entry, as: entry.downloads.first?.format ?? .pdf, into: library, minutesAgo: index)
            }
        case "server-form":
            setup.showsServerForm = true
        case "catalog":
            setup.path = [.catalog(DemoServer.address)]
        case "catalog-new":
            setup.path = [.catalog(newBooks)]
        case "catalog-search":
            setup.path = [.catalog(DemoServer.address, search: "persuasion")]
        case "book-detail":
            if let book = books.first {
                shelve(book, as: .pdf, into: library, minutesAgo: 0)
                setup.path = [.book(book)]
            }
        case "shelf-book":
            if let book = books.first {
                shelve(book, as: .epub, into: library, minutesAgo: 0)
                setup.path = library.shelf.books.first.map { [.shelfBook($0)] } ?? []
            }
        default:
            break
        }
        return setup
    }

    private static func shelve(_ entry: OPDSEntry, as format: BookFormat, into library: Library, minutesAgo: Int) {
        guard let acquisition = entry.downloads.first(where: { $0.format == format }),
              let data = DemoServer.file(acquisition.url.path(percentEncoded: true)) else { return }
        let file = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let cover = entry.coverURL.flatMap { DemoServer.file($0.path(percentEncoded: true)) }
        let book = ShelfBook(entryID: entry.id, title: entry.title, authors: entry.authors, summary: entry.summary,
                             format: format, length: data.count, addedAt: Date.now.addingTimeInterval(-Double(minutesAgo * 60)),
                             hasCover: cover != nil)
        do {
            try data.write(to: file)
            try library.shelve(book, file: file, cover: cover)
        } catch {
            Log.demo.error("demo shelf: \(error.localizedDescription, privacy: .public)")
        }
    }
}
#endif
