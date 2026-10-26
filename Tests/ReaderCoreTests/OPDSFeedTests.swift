import Foundation
import Testing
@testable import ReaderCore

struct OPDSFeedTests {
    static let server = URL(string: "https://books.example.com/opds")!

    func feed(_ name: String, at path: String = "/opds") throws -> OPDSFeed {
        let data = try Data(contentsOf: FixtureTests.root.appending(path: "opds/\(name)"))
        return try OPDSFeed(data: data, url: URL(string: path, relativeTo: Self.server)!.absoluteURL)
    }

    func url(_ path: String) -> URL { URL(string: "https://books.example.com\(path)")! }

    @Test func navigationFeedLeadsToOtherFeeds() throws {
        let root = try feed("root.xml")
        #expect(root.title == "Library")
        #expect(root.entries.map(\.title) == ["Recently Added Books", "Authors"])
        #expect(root.entries.map(\.feedURL) == [url("/opds/new"), url("/opds/author")])
        #expect(root.entries.allSatisfy { !$0.isBook })
        #expect(root.entries.first?.summary == "The latest books")
        #expect(root.search == .description(url("/opds/osd")))
        #expect(root.nextURL == nil)
    }

    @Test func acquisitionFeedListsBooksWithCoversAndFiles() throws {
        let new = try feed("new.xml", at: "/opds/new")
        #expect(new.title == "Recently Added Books")
        #expect(new.nextURL == url("/opds/new?offset=2"))
        let book = try #require(new.entries.first)
        #expect(book.id == "urn:uuid:00000000-0000-4000-8000-000000000001")
        #expect(book.title == "Pride and Prejudice")
        #expect(book.authors == ["Jane Austen"])
        #expect(book.issued == "1813")
        #expect(book.coverURL == url("/opds/cover/1"))
        #expect(book.thumbnailURL == url("/opds/cover/1"))
        #expect(book.isBook)
        #expect(book.downloads.map(\.format) == [.epub, .pdf])
        #expect(book.downloads.map(\.url) == [url("/opds/download/1/epub/"), url("/opds/download/1/pdf/")])
        #expect(book.downloads.first?.length == 3288)
    }

    @Test func aBookOfferedOnlyAsMOBIHasNothingToDownload() throws {
        let page = try feed("new-2.xml", at: "/opds/new?offset=2")
        let book = try #require(page.entries.first)
        #expect(book.title == "Persuasion")
        #expect(book.isBook)
        #expect(book.downloads.isEmpty)
        #expect(book.acquisitions.first?.format == nil)
        #expect(page.nextURL == nil)
    }

    @Test func somethingElseIsNotAFeed() {
        let html = Data("<html><body>Please log in</body></html>".utf8)
        #expect(throws: OPDSFeed.ParseError.notAFeed) { try OPDSFeed(data: html, url: Self.server) }
        #expect(throws: OPDSFeed.ParseError.notAFeed) { try OPDSFeed(data: Data("not xml".utf8), url: Self.server) }
    }

    @Test func descriptionsLoseTheirMarkupAndEveryEntryHasAnID() throws {
        let xml = """
            <feed xmlns="http://www.w3.org/2005/Atom"><title>T</title>
              <entry><id>a</id><title>A</title>
                <author><name>One</name></author><author><name>Two</name></author>
                <summary>Short</summary>
                <content type="html">&lt;p&gt;Fish &amp;amp; &lt;b&gt;chips&lt;/b&gt;&lt;/p&gt;</content>
              </entry>
              <entry><title>B</title>
                <link rel="subsection" href="/opds/b" type="application/atom+xml;profile=opds-catalog"/>
                <content type="xhtml"><div xmlns="http://www.w3.org/1999/xhtml"><p>Line <i>one</i></p></div></content>
              </entry>
            </feed>
            """
        let feed = try OPDSFeed(data: Data(xml.utf8), url: Self.server)
        #expect(feed.entries.map(\.authors) == [["One", "Two"], []])
        #expect(feed.entries.map(\.summary) == ["Fish & chips", "Line one"])
        #expect(feed.entries.map(\.id) == ["a", url("/opds/b").absoluteString])
    }

    @Test func aSearchTemplateInTheFeedIsUsedDirectly() throws {
        let xml = """
            <feed xmlns="http://www.w3.org/2005/Atom"><title>T</title>
              <link rel="search" type="application/atom+xml" href="/feed.php?query={searchTerms}"/>
            </feed>
            """
        let feed = try OPDSFeed(data: Data(xml.utf8), url: Self.server)
        guard case .template(let template) = feed.search else { Issue.record("no template"); return }
        #expect(template.url(for: "war & peace") == url("/feed.php?query=war%20%26%20peace"))
    }

    @Test func openSearchDescriptionGivesTheTemplate() throws {
        let data = try Data(contentsOf: FixtureTests.root.appending(path: "opds/opensearch.xml"))
        let template = try #require(OPDSSearchTemplate.parse(description: data, url: url("/opds/osd")))
        #expect(template.url(for: "persuasion") == url("/opds/search/persuasion"))
        #expect(template.url(for: " pride/prejudice ") == url("/opds/search/pride%2Fprejudice"))
        #expect(template.url(for: "   ") == nil)
    }

    @Test func optionalTemplateParametersAreLeftEmpty() {
        let template = OPDSSearchTemplate(template: "/search?q={searchTerms}&page={startPage?}", base: Self.server)
        #expect(template.url(for: "emma") == url("/search?q=emma&page="))
    }
}
