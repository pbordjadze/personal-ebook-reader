import Foundation
import Observation
import ReaderCore

/// The library server the reader added. The password isn't here: it's in a `PasswordStore`.
nonisolated struct Server: Codable, Hashable, Sendable {
    var url: URL
    var username: String
}

/// The reader's library: the server whose catalog they browse, and the shelf of books downloaded
/// to the phone, which reads without the server.
///
/// Kept in one folder: `server.json` (the address and user name), `shelf.json`, and `Books/` (the
/// books' files and covers, named by `ShelfBook.fileName`).
@Observable
final class Library {
    private(set) var server: Server? = nil
    private(set) var shelf = Shelf()
    /// The shelf ids (`ShelfBook.id`) of the downloads under way.
    private(set) var downloading: Set<String> = []
    /// The server's client, with its login read from the password store once.
    private(set) var client: CatalogClient? = nil

    let folder: URL
    private let passwords: any PasswordStore
    private let transport: any CatalogTransport
    private let covers = NSCache<NSURL, NSData>()

    init(folder: URL, passwords: any PasswordStore, transport: any CatalogTransport) {
        self.folder = folder
        self.passwords = passwords
        self.transport = transport
        server = try? JSONDecoder().decode(Server.self, from: Data(contentsOf: serverFile))
        if let server {
            let login = server.username.isEmpty ? nil : ServerLogin(username: server.username, password: passwords.password ?? "")
            client = CatalogClient(server: server.url, login: login, transport: transport)
        }
        if let saved = try? JSONDecoder.shelf.decode(Shelf.self, from: Data(contentsOf: shelfFile)) {
            shelf = saved
        }
    }

    /// The library on this iPhone, in the app's Application Support folder.
    static func onDevice() -> Library {
        Library(folder: .applicationSupportDirectory.appending(path: "Library"), passwords: KeychainPasswordStore(),
                transport: URLSessionTransport())
    }

    var password: String? { client?.login?.password }

    // MARK: Server

    /// Keeps the server once its address answers as an OPDS catalog with this login, trying each
    /// address the input may mean (`CatalogAddress.candidates`). Throws `CatalogAddress.Problem`
    /// or `CatalogError`.
    func addServer(address: String, username: String, password: String) async throws {
        let username = username.trimmingCharacters(in: .whitespaces)
        let login = username.isEmpty ? nil : ServerLogin(username: username, password: password)
        var failure: any Error = CatalogError.notACatalog
        for url in try CatalogAddress.candidates(for: address) {
            let client = CatalogClient(server: url, login: login, transport: transport)
            do {
                _ = try await client.feed(at: url)
            } catch CatalogError.unauthorized {
                throw CatalogError.unauthorized
            } catch {
                failure = error
                continue
            }
            let server = Server(url: url, username: username)
            try passwords.setPassword(login?.password)
            try write(JSONEncoder().encode(server), to: serverFile)
            self.server = server
            self.client = client
            covers.removeAllObjects()
            return
        }
        throw failure
    }

    /// Forgets the server and its password. The books on the shelf stay.
    func removeServer() {
        try? passwords.setPassword(nil)
        try? FileManager.default.removeItem(at: serverFile)
        server = nil
        client = nil
        covers.removeAllObjects()
    }

    // MARK: Catalog

    /// A cover from the catalog, kept in memory for the session.
    func coverData(at url: URL) async -> Data? {
        if let cached = covers.object(forKey: url as NSURL) { return cached as Data }
        guard let data = try? await client?.data(at: url) else { return nil }
        covers.setObject(data as NSData, forKey: url as NSURL)
        return data
    }

    // MARK: Shelf

    func fileURL(for book: ShelfBook) -> URL { booksFolder.appending(path: book.fileName) }

    func coverURL(for book: ShelfBook) -> URL? { book.hasCover ? booksFolder.appending(path: book.coverFileName) : nil }

    func isDownloading(_ entry: OPDSEntry, as format: BookFormat) -> Bool {
        downloading.contains(ShelfBook.id(entryID: entry.id, format: format))
    }

    /// Downloads a book and its cover to the shelf.
    func download(_ entry: OPDSEntry, _ acquisition: OPDSAcquisition) async throws {
        guard let client, let format = acquisition.format else { return }
        let id = ShelfBook.id(entryID: entry.id, format: format)
        guard downloading.insert(id).inserted else { return }
        defer { downloading.remove(id) }
        let file = try await client.download(acquisition)
        var cover: Data?
        if let url = entry.coverURL ?? entry.thumbnailURL { cover = await coverData(at: url) }
        let book = ShelfBook(entryID: entry.id, title: entry.title, authors: entry.authors, summary: entry.summary,
                             format: format, length: acquisition.length ?? 0, addedAt: .now, hasCover: cover != nil)
        try shelve(book, file: file, cover: cover)
    }

    /// Moves a downloaded file onto the shelf.
    func shelve(_ book: ShelfBook, file: URL, cover: Data?) throws {
        var book = book
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: booksFolder, withIntermediateDirectories: true)
        let destination = fileURL(for: book)
        try? fileManager.removeItem(at: destination)
        try fileManager.moveItem(at: file, to: destination)
        if let size = try? destination.resourceValues(forKeys: [.fileSizeKey]).fileSize { book.length = size }
        if let cover { try write(cover, to: booksFolder.appending(path: book.coverFileName)) }
        var shelf = shelf
        shelf.add(book)
        try write(JSONEncoder.shelf.encode(shelf), to: shelfFile)
        self.shelf = shelf
    }

    /// Deletes a book's file (and its cover, once no other format of it is left).
    func delete(_ book: ShelfBook) {
        var shelf = shelf
        for name in shelf.remove(book) {
            try? FileManager.default.removeItem(at: booksFolder.appending(path: name))
        }
        try? write(JSONEncoder.shelf.encode(shelf), to: shelfFile)
        self.shelf = shelf
    }

    // MARK: Files

    private var serverFile: URL { folder.appending(path: "server.json") }
    private var shelfFile: URL { folder.appending(path: "shelf.json") }
    private var booksFolder: URL { folder.appending(path: "Books") }

    private func write(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}

private extension JSONEncoder {
    static var shelf: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .sortedKeys
        return encoder
    }
}

private extension JSONDecoder {
    static var shelf: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
