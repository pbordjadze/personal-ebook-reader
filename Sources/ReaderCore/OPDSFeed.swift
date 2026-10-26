import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

/// One page of an OPDS 1.2 catalog: a navigation feed (its entries lead to other feeds) or an
/// acquisition feed (its entries are books). Calibre-Web, COPS and most servers speak this Atom
/// dialect; links in it are resolved against the feed's own address.
public struct OPDSFeed: Sendable, Hashable {
    public var title: String
    public var entries: [OPDSEntry]
    /// The next page of the same list, when the server pages it.
    public var nextURL: URL?
    public var search: OPDSSearch?

    public init(title: String, entries: [OPDSEntry], nextURL: URL? = nil, search: OPDSSearch? = nil) {
        self.title = title
        self.entries = entries
        self.nextURL = nextURL
        self.search = search
    }

    public enum ParseError: Error, Equatable {
        /// The document isn't XML, or isn't an Atom feed (a login page, an HTML error).
        case notAFeed
    }

    /// Parses a feed fetched from `url`.
    public init(data: Data, url: URL) throws {
        let reader = FeedReader(base: url)
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        parser.delegate = reader
        guard parser.parse(), reader.sawFeed else { throw ParseError.notAFeed }
        self.init(title: reader.title, entries: reader.entries, nextURL: reader.nextURL, search: reader.search)
    }
}

/// An entry of a feed: a book, or a link to another feed.
public struct OPDSEntry: Sendable, Hashable, Identifiable {
    public var id: String
    public var title: String
    public var authors: [String]
    /// Plain text: an HTML description has its markup removed.
    public var summary: String?
    /// The publication year or date as the server gives it (`dc:issued`).
    public var issued: String?
    /// For a navigation entry, the feed it leads to.
    public var feedURL: URL?
    public var coverURL: URL?
    public var thumbnailURL: URL?
    public var acquisitions: [OPDSAcquisition]

    public init(id: String, title: String, authors: [String] = [], summary: String? = nil, issued: String? = nil,
                feedURL: URL? = nil, coverURL: URL? = nil, thumbnailURL: URL? = nil,
                acquisitions: [OPDSAcquisition] = []) {
        self.id = id
        self.title = title
        self.authors = authors
        self.summary = summary
        self.issued = issued
        self.feedURL = feedURL
        self.coverURL = coverURL
        self.thumbnailURL = thumbnailURL
        self.acquisitions = acquisitions
    }

    /// A book is an entry with something to download, whether or not the app can open it.
    public var isBook: Bool { !acquisitions.isEmpty }

    /// The downloads the app can open, one per format, EPUB first.
    public var downloads: [OPDSAcquisition] {
        BookFormat.allCases.compactMap { format in acquisitions.first { $0.format == format } }
    }
}

/// A file an entry offers (an `http://opds-spec.org/acquisition` link).
public struct OPDSAcquisition: Sendable, Hashable {
    public var url: URL
    public var mediaType: String
    /// The size in bytes, when the server says.
    public var length: Int?

    public init(url: URL, mediaType: String, length: Int? = nil) {
        self.url = url
        self.mediaType = mediaType
        self.length = length
    }

    /// nil for a format the app can't open (MOBI, AZW3, CBZ…).
    public var format: BookFormat? { BookFormat(mediaType: mediaType) }
}

/// How a catalog is searched: an OpenSearch description to fetch first, or a template to fill.
public enum OPDSSearch: Sendable, Hashable {
    case description(URL)
    case template(OPDSSearchTemplate)
}

/// An OpenSearch URL template such as `/opds/search/{searchTerms}`, resolved against the
/// address it came from.
public struct OPDSSearchTemplate: Sendable, Hashable {
    public var template: String
    public var base: URL

    public init(template: String, base: URL) {
        self.template = template
        self.base = base
    }

    /// The address of the results for `terms`. The terms are percent-encoded so that they stay
    /// one value whether the template puts them in the path or the query; OpenSearch's optional
    /// parameters (`{startPage?}`) are left empty.
    public func url(for terms: String) -> URL? {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        let trimmed = terms.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: allowed) else {
            return nil
        }
        var filled = template.replacingOccurrences(of: "{searchTerms}", with: encoded)
        while let open = filled.range(of: "{"), let close = filled.range(of: "}", range: open.upperBound..<filled.endIndex) {
            filled.removeSubrange(open.lowerBound..<close.upperBound)
        }
        return URL(string: filled, relativeTo: base)?.absoluteURL
    }

    /// The template an OpenSearch description fetched from `url` offers for OPDS results, or nil
    /// when it offers none.
    public static func parse(description data: Data, url: URL) -> OPDSSearchTemplate? {
        let reader = OpenSearchReader()
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        parser.delegate = reader
        guard parser.parse() else { return nil }
        let atom = reader.urls.filter { $0.type.lowercased().hasPrefix("application/atom+xml") }
        let best = atom.first { $0.type.contains("opds-catalog") } ?? atom.first
        return best.map { OPDSSearchTemplate(template: $0.template, base: url) }
    }
}

// MARK: - Parsing

private let atomNS = "http://www.w3.org/2005/Atom"
private let dcNS = "http://purl.org/dc/terms/"
private let dcElementsNS = "http://purl.org/dc/elements/1.1/"

private final class FeedReader: NSObject, XMLParserDelegate {
    let base: URL
    var sawFeed = false
    var title = ""
    var entries: [OPDSEntry] = []
    var nextURL: URL?
    var search: OPDSSearch?

    private var entry: OPDSEntry?
    private var path: [String] = []
    private var text = ""
    private var contentIsHTML = false

    init(base: URL) { self.base = base }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String] = [:]) {
        path.append(name)
        let ns = namespaceURI ?? ""
        if ns == atomNS, name == "feed", path.count == 1 { sawFeed = true }
        if ns == atomNS, name == "entry" {
            entry = OPDSEntry(id: "", title: "")
        } else if ns == atomNS, name == "link" {
            link(attributes)
        } else if ns == atomNS, name == "content" || name == "summary", path.count == 3 {
            contentIsHTML = ["html", "xhtml"].contains(attributes["type"]?.lowercased() ?? "")
        }
        // Text is gathered per element, but inside `content` it runs through any XHTML children.
        if !inContent { text = "" }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

    func parser(_ parser: XMLParser, foundCDATA data: Data) { text += String(decoding: data, as: UTF8.self) }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        let ns = namespaceURI ?? ""
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let withinContent = inContent
        defer {
            path.removeLast()
            if !withinContent { text = "" }
        }
        if ns == atomNS, name == "entry", var finished = entry {
            // Atom requires an id; a server that leaves it out still needs its entries told apart.
            if finished.id.isEmpty {
                finished.id = (finished.feedURL ?? finished.acquisitions.first?.url)?.absoluteString ?? finished.title
            }
            if !finished.id.isEmpty { entries.append(finished) }
            entry = nil
            return
        }
        if entry != nil {
            guard path.count == 3 || (path.count == 4 && path[2] == "author") else { return }
            switch (ns, name) {
            case (atomNS, "id"): entry?.id = value
            case (atomNS, "title"): entry?.title = value
            case (atomNS, "name") where path[2] == "author": if !value.isEmpty { entry?.authors.append(value) }
            case (atomNS, "content"), (atomNS, "summary"):
                let plain = contentIsHTML ? Self.plainText(value) : value
                if !plain.isEmpty, entry?.summary == nil || name == "content" { entry?.summary = plain }
            case (dcNS, "issued"), (dcElementsNS, "date"): if entry?.issued == nil, !value.isEmpty { entry?.issued = value }
            default: break
            }
        } else if ns == atomNS, name == "title", path.count == 2 {
            title = value
        }
    }

    /// Inside an entry's `content` or `summary`, whose XHTML children's text is kept.
    private var inContent: Bool {
        entry != nil && path.count > 3 && (path[2] == "content" || path[2] == "summary")
    }

    private func link(_ attributes: [String: String]) {
        guard let href = attributes["href"], let url = URL(string: href, relativeTo: base)?.absoluteURL else { return }
        let rel = attributes["rel"] ?? "alternate"
        let type = attributes["type"] ?? ""
        if entry != nil {
            switch rel {
            case "http://opds-spec.org/image", "http://opds-spec.org/cover", "x-stanza-cover-image":
                entry?.coverURL = url
            case "http://opds-spec.org/image/thumbnail", "http://opds-spec.org/thumbnail", "x-stanza-cover-image-thumbnail":
                entry?.thumbnailURL = url
            case _ where rel.hasPrefix("http://opds-spec.org/acquisition"):
                entry?.acquisitions.append(OPDSAcquisition(url: url, mediaType: type, length: attributes["length"].flatMap { Int($0) }))
            default:
                if type.lowercased().hasPrefix("application/atom+xml"), entry?.feedURL == nil { entry?.feedURL = url }
            }
        } else if path.count == 2 {
            switch rel {
            case "next": nextURL = url
            case "search":
                if type.lowercased().hasPrefix("application/opensearchdescription+xml") {
                    search = .description(url)
                } else if href.contains("{searchTerms}") {
                    search = .template(OPDSSearchTemplate(template: href, base: base))
                }
            default: break
            }
        }
    }

    /// Text without its markup, for a description sent as escaped HTML.
    static func plainText(_ html: String) -> String {
        var out = ""
        var inTag = false
        for character in html {
            if character == "<" { inTag = true; out += " " } else if character == ">" { inTag = false } else if !inTag { out.append(character) }
        }
        // `&amp;` last, so that an escaped entity (`&amp;lt;`) stays one.
        let entities = [("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'"), ("&nbsp;", " "), ("&amp;", "&")]
        for (entity, character) in entities { out = out.replacingOccurrences(of: entity, with: character) }
        return out.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}

private final class OpenSearchReader: NSObject, XMLParserDelegate {
    var urls: [(type: String, template: String)] = []

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String] = [:]) {
        guard name == "Url", let template = attributes["template"] else { return }
        urls.append((attributes["type"] ?? "", template))
    }
}
