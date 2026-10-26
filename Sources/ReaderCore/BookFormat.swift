import Foundation

/// The kinds of book the app opens, and how a catalog names them.
///
/// An OPDS acquisition link names its file by media type; a book offered only in other formats
/// (MOBI, AZW3, CBZ) has no `BookFormat` and isn't offered for download.
public enum BookFormat: String, Sendable, Codable, CaseIterable {
    case epub
    case pdf

    /// The format of a link's media type, ignoring case and parameters
    /// (`application/epub+zip; charset=utf-8`); nil for a format the app can't open.
    public init?(mediaType: String) {
        let essence = mediaType.split(separator: ";", maxSplits: 1).first ?? ""
        switch essence.trimmingCharacters(in: .whitespaces).lowercased() {
        case "application/epub+zip": self = .epub
        case "application/pdf": self = .pdf
        default: return nil
        }
    }

    public var mediaType: String {
        switch self {
        case .epub: "application/epub+zip"
        case .pdf: "application/pdf"
        }
    }

    /// The extension a downloaded book is saved with.
    public var fileExtension: String { rawValue }
}
