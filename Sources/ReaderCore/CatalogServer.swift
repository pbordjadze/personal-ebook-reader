import Foundation

/// What the reader types to add a library server, made into the addresses to try.
public enum CatalogAddress {
    public enum Problem: Error, Equatable {
        case empty
        case invalid
        /// Books and logins travel over HTTPS only (no App Transport Security exception).
        case notHTTPS
    }

    /// The catalog addresses `input` may mean, to be tried in order: as typed (with `https://`
    /// when no scheme is given), then, for a bare host, Calibre-Web's `/opds`.
    public static func candidates(for input: String) throws(Problem) -> [URL] {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw .empty }
        let typed = trimmed.contains("://") ? trimmed : "https://" + trimmed
        guard var components = URLComponents(string: typed), let host = components.host, !host.isEmpty,
              !host.contains(" ") else { throw .invalid }
        guard components.scheme?.lowercased() == "https" else { throw .notHTTPS }
        components.scheme = "https"
        components.fragment = nil
        guard let url = components.url else { throw .invalid }
        guard components.path.isEmpty || components.path == "/" else { return [url] }
        components.path = "/opds"
        return [url, components.url].compactMap { $0 }
    }

    /// Whether `url` is on the same server (scheme, host and port) as `server`: the login is sent
    /// only there, never to another host a catalog links to or redirects to.
    public static func isSameOrigin(_ url: URL, as server: URL) -> Bool {
        url.scheme?.lowercased() == server.scheme?.lowercased()
            && url.host()?.lowercased() == server.host()?.lowercased()
            && (url.port ?? 443) == (server.port ?? 443)
    }
}

/// A login for a library server, sent as HTTP Basic authentication, which OPDS servers
/// (Calibre-Web among them) ask for.
public struct ServerLogin: Sendable, Hashable {
    public var username: String
    public var password: String

    public init(username: String, password: String) {
        self.username = username
        self.password = password
    }

    /// The `Authorization` header's value.
    public var authorization: String {
        "Basic " + Data("\(username):\(password)".utf8).base64EncodedString()
    }
}
