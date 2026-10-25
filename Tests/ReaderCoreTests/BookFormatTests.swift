import Testing
@testable import ReaderCore

struct BookFormatTests {
    @Test(arguments: [
        ("application/epub+zip", BookFormat.epub),
        ("application/pdf", .pdf),
        ("Application/EPUB+zip", .epub),
        ("application/pdf; charset=binary", .pdf),
    ])
    func readsTheMediaTypesTheAppOpens(mediaType: String, format: BookFormat) {
        #expect(BookFormat(mediaType: mediaType) == format)
    }

    @Test(arguments: ["application/x-mobipocket-ebook", "application/vnd.comicbook+zip", "", "application/epub"])
    func turnsDownTheRest(mediaType: String) {
        #expect(BookFormat(mediaType: mediaType) == nil)
    }

    @Test func roundTripsItsOwnMediaType() {
        for format in BookFormat.allCases {
            #expect(BookFormat(mediaType: format.mediaType) == format)
        }
    }
}
