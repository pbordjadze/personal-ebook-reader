import Foundation
import ReaderCore

/// How the catalog's requests reach a server: URLSession on a device; the fixtures in demo
/// scenarios and tests (`DemoServer`).
nonisolated protocol CatalogTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
    /// Downloads to a temporary file that the caller moves or deletes.
    func download(for request: URLRequest) async throws -> (URL, HTTPURLResponse)
}

nonisolated enum CatalogError: Error, Hashable {
    /// The server turned the login down (401 or 403).
    case unauthorized
    case status(Int)
    /// The address answers, but not with an OPDS feed.
    case notACatalog
    case noSearch
    case offline
    case unreachable
}

/// Talks to one library server: its feeds, covers and books. The login goes only to that server
/// (`CatalogAddress.isSameOrigin`), never to another host a catalog links to.
nonisolated struct CatalogClient: Sendable {
    var server: URL
    var login: ServerLogin?
    var transport: any CatalogTransport

    func request(for url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        if let login, CatalogAddress.isSameOrigin(url, as: server) {
            request.setValue(login.authorization, forHTTPHeaderField: "Authorization")
        }
        return request
    }

    /// Parsing runs off the main actor: a page of a large catalog is a lot of XML.
    @concurrent func feed(at url: URL) async throws -> OPDSFeed {
        let data = try await data(at: url)
        do {
            return try OPDSFeed(data: data, url: url)
        } catch {
            throw CatalogError.notACatalog
        }
    }

    func data(at url: URL) async throws -> Data {
        let (data, response) = try await Self.translatingErrors { try await transport.data(for: request(for: url)) }
        try Self.check(response)
        return data
    }

    /// The address of the results for `terms`, fetching the OpenSearch description first when the
    /// catalog points to one.
    func searchURL(_ search: OPDSSearch, terms: String) async throws -> URL? {
        switch search {
        case .template(let template):
            return template.url(for: terms)
        case .description(let url):
            guard let template = OPDSSearchTemplate.parse(description: try await data(at: url), url: url) else {
                throw CatalogError.noSearch
            }
            return template.url(for: terms)
        }
    }

    /// Downloads a book to a temporary file.
    func download(_ acquisition: OPDSAcquisition) async throws -> URL {
        let (file, response) = try await Self.translatingErrors { try await transport.download(for: request(for: acquisition.url)) }
        do {
            try Self.check(response)
        } catch {
            try? FileManager.default.removeItem(at: file)
            throw error
        }
        return file
    }

    private static func check(_ response: HTTPURLResponse) throws {
        switch response.statusCode {
        case 200..<300: return
        case 401, 403: throw CatalogError.unauthorized
        default: throw CatalogError.status(response.statusCode)
        }
    }

    private static func translatingErrors<T>(_ body: () async throws -> T) async throws -> T {
        do {
            return try await body()
        } catch let error as URLError {
            switch error.code {
            case .cancelled: throw CancellationError()
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .internationalRoamingOff:
                throw CatalogError.offline
            case .userAuthenticationRequired: throw CatalogError.unauthorized
            default: throw CatalogError.unreachable
            }
        }
    }
}

/// URLSession, ephemeral so that nothing it fetches (feeds, covers, books) lands in a shared cache,
/// and with redirects kept to HTTPS and the login kept to its server.
nonisolated struct URLSessionTransport: CatalogTransport {
    private let session = URLSession(configuration: .ephemeral, delegate: RedirectGuard(), delegateQueue: nil)

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw CatalogError.unreachable }
        return (data, http)
    }

    func download(for request: URLRequest) async throws -> (URL, HTTPURLResponse) {
        let (file, response) = try await session.download(for: request)
        guard let http = response as? HTTPURLResponse else {
            try? FileManager.default.removeItem(at: file)
            throw CatalogError.unreachable
        }
        return (file, http)
    }
}

private nonisolated final class RedirectGuard: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest) async -> URLRequest? {
        guard let target = request.url, target.scheme?.lowercased() == "https" else { return nil }
        guard let origin = task.originalRequest?.url, CatalogAddress.isSameOrigin(target, as: origin) else {
            var request = request
            request.setValue(nil, forHTTPHeaderField: "Authorization")
            return request
        }
        return request
    }
}
