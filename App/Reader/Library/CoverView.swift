import SwiftUI
import UIKit

/// A book's cover at a 2:3 shape, or a plain stand-in while it loads or when there is none.
/// Decorative for VoiceOver: the title beside it says which book it is.
struct CoverView: View {
    enum Source: Hashable {
        /// From the catalog, through the library's client and its cache.
        case remote(URL?)
        /// From the shelf, on the phone.
        case file(URL?)
    }

    let source: Source
    let width: CGFloat
    /// Covers grow with Dynamic Type, as the titles beside them do.
    @ScaledMetric private var scale: CGFloat = 1
    @Environment(Library.self) private var library
    @State private var image: UIImage?

    var body: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(.quaternary)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "book.closed")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: width * scale, height: width * scale * 1.5)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .accessibilityHidden(true)
            .task(id: source) { image = await load() }
    }

    private func load() async -> UIImage? {
        var data: Data?
        switch source {
        case .remote(let url?): data = await library.coverData(at: url)
        case .file(let url?): data = try? Data(contentsOf: url)
        case .remote(nil), .file(nil): break
        }
        return data.flatMap { UIImage(data: $0) }
    }
}
