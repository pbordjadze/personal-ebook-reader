import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif
import Testing
@testable import ReaderCore

/// The fixtures stand in for a reader's server in every test (`tools/make_fixtures.py` makes
/// them): these check they are what the later tests will take them for.
struct FixtureTests {
    static let root = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "Fixtures")

    func data(_ path: String) throws -> Data {
        try Data(contentsOf: Self.root.appending(path: path))
    }

    @Test(arguments: ["opds/root.xml", "opds/new.xml", "opds/new-2.xml", "opds/search-persuasion.xml", "opds/opensearch.xml"])
    func catalogFeedsAreWellFormed(path: String) throws {
        let parser = XMLParser(data: try data(path))
        #expect(parser.parse(), "\(path): \(String(describing: parser.parserError))")
    }

    /// Every acquisition link the feeds offer in a format the app opens has a book behind it,
    /// and the one book offered only as MOBI is the case the app turns down.
    @Test func acquisitionLinksPointAtTheBooks() throws {
        var offered: [(href: String, type: String)] = []
        for feed in ["opds/new.xml", "opds/new-2.xml", "opds/search-persuasion.xml"] {
            let links = LinkCollector()
            let parser = XMLParser(data: try data(feed))
            parser.delegate = links
            #expect(parser.parse())
            offered += links.acquisitions
        }
        let openable = offered.filter { BookFormat(mediaType: $0.type) != nil }
        #expect(Set(openable.map(\.href)) == ["/opds/download/1/epub/", "/opds/download/1/pdf/", "/opds/download/2/pdf/"])
        #expect(offered.contains { BookFormat(mediaType: $0.type) == nil })
    }

    @Test func epubStartsWithItsUncompressedMediaType() throws {
        let epub = try data("books/pride-and-prejudice.epub")
        #expect(epub.prefix(4) == Data([0x50, 0x4B, 0x03, 0x04]))
        #expect(String(decoding: epub[30..<38], as: UTF8.self) == "mimetype")
        #expect(String(decoding: epub[38..<58], as: UTF8.self) == "application/epub+zip")
    }

    @Test(arguments: ["books/pride-and-prejudice.pdf", "books/pride-and-prejudice-scanned.pdf"])
    func pdfsAreWhole(path: String) throws {
        let pdf = try data(path)
        #expect(pdf.prefix(5) == Data("%PDF-".utf8))
        #expect(String(decoding: pdf.suffix(6), as: UTF8.self) == "%%EOF\n")
    }

    @Test(arguments: ["register", "auth", "auth-unauthorized", "push-progress", "pull-progress", "pull-progress-none"])
    func kosyncExchangesHaveARequestAndAReply(name: String) throws {
        let exchange = try #require(try JSONSerialization.jsonObject(with: data("kosync/\(name).json")) as? [String: Any])
        let request = try #require(exchange["request"] as? [String: Any])
        let response = try #require(exchange["response"] as? [String: Any])
        #expect(request["method"] is String && request["path"] is String)
        #expect(response["status"] is Int)
    }
}

private final class LinkCollector: NSObject, XMLParserDelegate {
    var acquisitions: [(href: String, type: String)] = []

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String] = [:]) {
        guard elementName == "link", attributes["rel"] == "http://opds-spec.org/acquisition",
              let href = attributes["href"], let type = attributes["type"] else { return }
        acquisitions.append((href, type))
    }
}
