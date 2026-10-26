import Foundation

/// A book downloaded to the phone, readable without the server.
public struct ShelfBook: Sendable, Hashable, Codable, Identifiable {
    /// The catalog entry's id and the format: the same book may be on the shelf as EPUB and PDF.
    public var id: String { Self.id(entryID: entryID, format: format) }

    public static func id(entryID: String, format: BookFormat) -> String { "\(entryID) \(format.rawValue)" }

    public var entryID: String
    public var title: String
    public var authors: [String]
    public var summary: String?
    public var format: BookFormat
    /// The size of the file in bytes.
    public var length: Int
    public var addedAt: Date
    public var hasCover: Bool

    public init(entryID: String, title: String, authors: [String], summary: String?, format: BookFormat,
                length: Int, addedAt: Date, hasCover: Bool) {
        self.entryID = entryID
        self.title = title
        self.authors = authors
        self.summary = summary
        self.format = format
        self.length = length
        self.addedAt = addedAt
        self.hasCover = hasCover
    }

    /// The book's file name in the shelf's folder: a stable hash of its id, since entry ids are
    /// URNs or URLs that make poor file names.
    public var fileName: String { "\(Self.stem(entryID)).\(format.fileExtension)" }

    /// The cover's file name, shared by every format of the book.
    public var coverFileName: String { "\(Self.stem(entryID)).cover" }

    /// FNV-1a, 64 bits, in hex: deterministic across launches and platforms, unlike `Hasher`.
    static func stem(_ id: String) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in id.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x0000_0100_0000_01b3
        }
        let hex = String(hash, radix: 16)
        return String(repeating: "0", count: 16 - hex.count) + hex
    }
}

/// The books on the phone, newest first. Saved as JSON beside the books' files.
public struct Shelf: Sendable, Hashable, Codable {
    public private(set) var books: [ShelfBook]

    public init(books: [ShelfBook] = []) {
        self.books = books.sorted(by: Self.newestFirst)
    }

    public func contains(entryID: String, format: BookFormat) -> Bool {
        books.contains { $0.entryID == entryID && $0.format == format }
    }

    /// Adds a book, replacing the same book in the same format.
    public mutating func add(_ book: ShelfBook) {
        books.removeAll { $0.id == book.id }
        books.append(book)
        books.sort(by: Self.newestFirst)
    }

    /// Removes a book; returns the files no other shelf book needs any more.
    @discardableResult
    public mutating func remove(_ book: ShelfBook) -> [String] {
        books.removeAll { $0.id == book.id }
        let coverStillUsed = books.contains { $0.entryID == book.entryID }
        return [book.fileName] + (book.hasCover && !coverStillUsed ? [book.coverFileName] : [])
    }

    private static func newestFirst(_ a: ShelfBook, _ b: ShelfBook) -> Bool {
        a.addedAt != b.addedAt ? a.addedAt > b.addedAt : a.id < b.id
    }
}
