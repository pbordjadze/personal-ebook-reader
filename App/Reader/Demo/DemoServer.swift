#if DEBUG
import Foundation
import ReaderCore

/// The fixture catalog as a server (`DemoFiles.swift`, made by `tools/make_fixtures.py`): demo
/// scenarios and the app's tests browse, search and download from it without a network.
nonisolated struct DemoServer: CatalogTransport {
    static let address = URL(string: "https://books.example.com/opds")!

    /// When set, a request without this login is turned down, as a server with accounts does.
    var requiredLogin: ServerLogin?

    static func file(_ path: String) -> Data? {
        files[path].flatMap { Data(base64Encoded: $0.base64, options: .ignoreUnknownCharacters) }
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        guard let url = request.url, CatalogAddress.isSameOrigin(url, as: Self.address) else {
            throw URLError(.cannotFindHost)
        }
        if let requiredLogin, request.value(forHTTPHeaderField: "Authorization") != requiredLogin.authorization {
            return (Data(), Self.response(url, status: 401, type: nil))
        }
        let path = url.path(percentEncoded: true) + (url.query(percentEncoded: true).map { "?" + $0 } ?? "")
        guard let data = Self.file(path) else { return (Data(), Self.response(url, status: 404, type: nil)) }
        return (data, Self.response(url, status: 200, type: Self.files[path]?.type))
    }

    func download(for request: URLRequest) async throws -> (URL, HTTPURLResponse) {
        let (data, response) = try await data(for: request)
        let file = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try data.write(to: file)
        return (file, response)
    }

    private static func response(_ url: URL, status: Int, type: String?) -> HTTPURLResponse {
        HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1",
                        headerFields: type.map { ["Content-Type": $0] })!
    }
}
#endif
