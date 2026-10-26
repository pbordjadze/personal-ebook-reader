import Foundation
import ReaderCore
import Testing
@testable import Reader

/// The library against the fixture catalog (`DemoServer`): adding a server, browsing, searching,
/// downloading to the shelf and reading the shelf back without the server.
@MainActor
struct LibraryTests {
    let folder = FileManager.default.temporaryDirectory.appending(path: "library-tests-\(UUID().uuidString)")

    func makeLibrary(_ server: DemoServer = DemoServer(), passwords: MemoryPasswordStore = MemoryPasswordStore()) -> Library {
        Library(folder: folder, passwords: passwords, transport: server)
    }

    @Test func aBareHostFindsTheCatalogAndIsKept() async throws {
        let passwords = MemoryPasswordStore()
        let login = ServerLogin(username: "reader", password: "secret")
        let first = makeLibrary(DemoServer(requiredLogin: login), passwords: passwords)
        try await first.addServer(address: "books.example.com", username: " reader ", password: "secret")
        #expect(first.server == Server(url: DemoServer.address, username: "reader"))
        #expect(passwords.password == "secret")

        let again = makeLibrary(DemoServer(requiredLogin: login), passwords: passwords)
        #expect(again.server == first.server)
        let client = try #require(again.client)
        let root = try await client.feed(at: DemoServer.address)
        #expect(root.title == "Library")
    }

    @Test func aWrongLoginIsTurnedDownAndNothingIsKept() async {
        let library = makeLibrary(DemoServer(requiredLogin: ServerLogin(username: "reader", password: "secret")))
        await #expect(throws: CatalogError.unauthorized) {
            try await library.addServer(address: "https://books.example.com/opds", username: "reader", password: "wrong")
        }
        #expect(library.server == nil)
    }

    @Test func onlyHTTPSAndOnlyCatalogs() async {
        let library = makeLibrary()
        await #expect(throws: CatalogAddress.Problem.notHTTPS) {
            try await library.addServer(address: "http://books.example.com", username: "", password: "")
        }
        await #expect(throws: CatalogError.status(404)) {
            try await library.addServer(address: "https://books.example.com/elsewhere", username: "", password: "")
        }
        await #expect(throws: CatalogError.notACatalog) {
            try await library.addServer(address: "https://books.example.com/opds/cover/1", username: "", password: "")
        }
        #expect(library.server == nil)
    }

    @Test func theLoginGoesOnlyToTheServer() {
        let client = CatalogClient(server: DemoServer.address, login: ServerLogin(username: "a", password: "b"),
                                   transport: DemoServer())
        #expect(client.request(for: URL(string: "https://books.example.com/opds/new")!)
            .value(forHTTPHeaderField: "Authorization") != nil)
        #expect(client.request(for: URL(string: "https://covers.example.net/1.png")!)
            .value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test func searchGoesThroughTheOpenSearchDescription() async throws {
        let library = makeLibrary()
        try await library.addServer(address: "books.example.com", username: "", password: "")
        let client = try #require(library.client)
        let root = try await client.feed(at: DemoServer.address)
        let search = try #require(root.search)
        let found = try await client.searchURL(search, terms: "persuasion")
        let url = try #require(found)
        let results = try await client.feed(at: url)
        #expect(results.entries.map(\.title) == ["Persuasion"])
    }

    @Test func aDownloadedBookStaysOnTheShelfWithItsCover() async throws {
        let library = makeLibrary()
        try await library.addServer(address: "books.example.com", username: "", password: "")
        let client = try #require(library.client)
        let page = try await client.feed(at: URL(string: "https://books.example.com/opds/new")!)
        let book = try #require(page.entries.first)
        let epub = try #require(book.downloads.first)
        try await library.download(book, epub)
        #expect(library.downloading.isEmpty)

        library.removeServer()
        let offline = makeLibrary()
        #expect(offline.server == nil)
        let shelved = try #require(offline.shelf.books.first)
        #expect(offline.shelf.books.count == 1)
        #expect(shelved.title == "Pride and Prejudice" && shelved.format == .epub && shelved.length == 3288)
        let file = try Data(contentsOf: offline.fileURL(for: shelved))
        #expect(file.prefix(2) == Data("PK".utf8))
        let cover = try #require(offline.coverURL(for: shelved))
        #expect(try Data(contentsOf: cover).prefix(4) == Data([0x89, 0x50, 0x4E, 0x47]))

        offline.delete(shelved)
        #expect(offline.shelf.books.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: offline.fileURL(for: shelved).path))
        #expect(makeLibrary().shelf.books.isEmpty)
    }

    @Test func theDemoServerServesTheFixturesByPath() {
        #expect(DemoServer.file("/opds/new?offset=2") != nil)
        #expect(DemoServer.file("/opds/download/2/pdf/")?.prefix(5) == Data("%PDF-".utf8))
        #expect(DemoServer.file("/opds/author") == nil)
    }
}
