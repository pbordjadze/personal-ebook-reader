import Foundation
import ReaderCore

/// What the library screens say when the server, the address or the phone lets them down.
func message(for error: any Error) -> String {
    switch error {
    case CatalogAddress.Problem.empty:
        String(localized: "error.address.empty", defaultValue: "Enter your server’s address.",
               comment: "Server form: Save was tapped with no address.")
    case CatalogAddress.Problem.invalid:
        String(localized: "error.address.invalid", defaultValue: "That doesn’t look like a web address.",
               comment: "Server form: the address can't be read as a URL.")
    case CatalogAddress.Problem.notHTTPS:
        String(localized: "error.address.https", defaultValue: "The server needs an https:// address: books and logins travel only over a secure connection.",
               comment: "Server form: the address starts with http://.")
    case CatalogError.unauthorized:
        String(localized: "error.unauthorized", defaultValue: "The server didn’t accept the user name and password.",
               comment: "Server form, catalog or download: the server answered 401 or 403.")
    case CatalogError.status(let status):
        String(localized: "error.status", defaultValue: "The server answered with an error (\(status.formatted(.number.grouping(.never)))).",
               comment: "Catalog or download: the server's HTTP error. The argument is the status code, such as 500.")
    case CatalogError.notACatalog:
        String(localized: "error.notCatalog", defaultValue: "There’s no OPDS catalog at this address.",
               comment: "Server form or catalog: the address answers, but not with an OPDS feed.")
    case CatalogError.noSearch:
        String(localized: "error.noSearch", defaultValue: "This catalog can’t be searched.",
               comment: "Catalog: the server offers no search.")
    case CatalogError.offline:
        String(localized: "error.offline", defaultValue: "You’re offline. Books on this iPhone still open.",
               comment: "Catalog or download: no internet connection.")
    case CatalogError.unreachable:
        String(localized: "error.unreachable", defaultValue: "The server can’t be reached.",
               comment: "Server form, catalog or download: the connection failed.")
    default:
        String(localized: "error.other", defaultValue: "Something went wrong: \(error.localizedDescription)",
               comment: "Any other failure, such as a book that couldn't be saved. The argument is the system's description.")
    }
}
