import Foundation
import Testing
@testable import ReaderCore

struct ShelfTests {
    func book(_ id: String, _ format: BookFormat = .epub, at seconds: TimeInterval, cover: Bool = true) -> ShelfBook {
        ShelfBook(entryID: id, title: id, authors: ["Jane Austen"], summary: nil, format: format, length: 100,
                  addedAt: Date(timeIntervalSince1970: seconds), hasCover: cover)
    }

    @Test func newestFirstAndOneCopyPerFormat() {
        var shelf = Shelf()
        shelf.add(book("a", at: 1))
        shelf.add(book("b", at: 2))
        shelf.add(book("a", .pdf, at: 3))
        shelf.add(book("a", at: 4))
        #expect(shelf.books.map(\.id) == ["a epub", "a pdf", "b epub"])
        #expect(shelf.contains(entryID: "a", format: .pdf))
        #expect(!shelf.contains(entryID: "b", format: .pdf))
    }

    @Test func removingTheLastFormatAlsoRemovesTheCover() {
        let epub = book("urn:uuid:1", at: 1)
        let pdf = book("urn:uuid:1", .pdf, at: 2)
        var shelf = Shelf(books: [epub, pdf])
        #expect(shelf.remove(epub) == [epub.fileName])
        #expect(shelf.remove(pdf) == [pdf.fileName, pdf.coverFileName])
        #expect(shelf.books.isEmpty)
        let stem = ShelfBook.stem("x")
        #expect(Shelf(books: [book("x", at: 1, cover: false)]).removing("x") == ["\(stem).epub", "\(stem).cover"])
    }

    @Test func fileNamesAreStableAndSafe() {
        let book = book("urn:uuid:00000000-0000-4000-8000-000000000001", .pdf, at: 0)
        #expect(book.fileName == "\(ShelfBook.stem(book.entryID)).pdf")
        #expect(ShelfBook.stem("") == "cbf29ce484222325")
        #expect(ShelfBook.stem("a") == "af63dc4c8601ec8c")
        #expect(book.coverFileName.hasSuffix(".cover"))
        #expect(!book.fileName.contains(":") && !book.fileName.contains("/"))
    }

    @Test func survivesARoundTrip() throws {
        let shelf = Shelf(books: [book("a", at: 1), book("b", .pdf, at: 2)])
        let decoded = try JSONDecoder().decode(Shelf.self, from: JSONEncoder().encode(shelf))
        #expect(decoded == shelf)
    }
}

private extension Shelf {
    func removing(_ entryID: String) -> [String] {
        var copy = self
        return books.first { $0.entryID == entryID }.map { copy.remove($0) } ?? []
    }
}
