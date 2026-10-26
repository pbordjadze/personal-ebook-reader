import Foundation
import Testing
@testable import ReaderCore

struct CatalogServerTests {
    @Test func aBareHostAlsoTriesCalibreWebsPath() throws {
        #expect(try CatalogAddress.candidates(for: " books.example.com ").map(\.absoluteString)
            == ["https://books.example.com", "https://books.example.com/opds"])
        #expect(try CatalogAddress.candidates(for: "https://books.example.com:8083/").map(\.absoluteString)
            == ["https://books.example.com:8083/", "https://books.example.com:8083/opds"])
    }

    @Test func aPathIsTakenAsTyped() throws {
        #expect(try CatalogAddress.candidates(for: "books.example.com/feed.php").map(\.absoluteString)
            == ["https://books.example.com/feed.php"])
        #expect(try CatalogAddress.candidates(for: "HTTPS://books.example.com/opds#top").map(\.absoluteString)
            == ["https://books.example.com/opds"])
    }

    @Test func onlyHTTPS() {
        #expect(throws: CatalogAddress.Problem.notHTTPS) { try CatalogAddress.candidates(for: "http://books.example.com") }
        #expect(throws: CatalogAddress.Problem.empty) { try CatalogAddress.candidates(for: "  ") }
        #expect(throws: CatalogAddress.Problem.invalid) { try CatalogAddress.candidates(for: "https://") }
        #expect(throws: CatalogAddress.Problem.invalid) { try CatalogAddress.candidates(for: "my books") }
    }

    @Test func theLoginGoesOnlyToTheSameServer() {
        let server = URL(string: "https://books.example.com/opds")!
        #expect(CatalogAddress.isSameOrigin(URL(string: "https://BOOKS.example.com:443/opds/cover/1")!, as: server))
        #expect(!CatalogAddress.isSameOrigin(URL(string: "https://covers.example.com/1.png")!, as: server))
        #expect(!CatalogAddress.isSameOrigin(URL(string: "https://books.example.com:8443/opds")!, as: server))
        #expect(!CatalogAddress.isSameOrigin(URL(string: "http://books.example.com/opds")!, as: server))
    }

    @Test func basicAuthorization() {
        #expect(ServerLogin(username: "reader", password: "pa:ss").authorization == "Basic cmVhZGVyOnBhOnNz")
    }
}
