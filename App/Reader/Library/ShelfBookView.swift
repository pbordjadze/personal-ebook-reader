import ReaderCore
import SwiftUI

/// A book on this iPhone: what it is, and removing its download. Shown from the shelf, with or
/// without the server.
struct ShelfBookView: View {
    let book: ShelfBook
    @Environment(Library.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var confirmsRemoval = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 12) {
                    CoverView(source: .file(library.coverURL(for: book)), width: 160)
                    Text(book.title)
                        .font(.title2.bold())
                        .multilineTextAlignment(.center)
                    if !book.authors.isEmpty {
                        Text(book.authors.formatted(.list(type: .and)))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    HStack(spacing: 6) {
                        Text(verbatim: book.format.label)
                        Text(Int64(book.length).formatted(.byteCount(style: .file)))
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                Button("Remove Download", role: .destructive) { confirmsRemoval = true }
                    .buttonStyle(.bordered)
                if let summary = book.summary {
                    Text(summary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding()
        }
        .navigationTitle(book.title)
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Remove this book from your iPhone?", isPresented: $confirmsRemoval, titleVisibility: .visible) {
            Button("Remove Download", role: .destructive) {
                library.delete(book)
                dismiss()
            }
        } message: {
            Text("You can download it again from the catalog.")
        }
    }
}
