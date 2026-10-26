import ReaderCore
import SwiftUI

/// A book in the catalog: its cover, title, authors and description, and a download for each
/// format the app opens (EPUB, PDF), or which ones are already on this iPhone.
///
/// Demo scenario: `book-detail` (also `-dark` and `-long-text`).
struct BookDetailView: View {
    let entry: OPDSEntry
    @Environment(Library.self) private var library
    @State private var failure: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 12) {
                    CoverView(source: .remote(entry.coverURL ?? entry.thumbnailURL), width: 160)
                    Text(entry.title)
                        .font(.title2.bold())
                        .multilineTextAlignment(.center)
                    if !entry.authors.isEmpty {
                        Text(entry.authors.formatted(.list(type: .and)))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    if let issued = entry.issued {
                        Text(issued)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
                downloads
                if let summary = entry.summary {
                    Text(summary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding()
        }
        .navigationTitle(entry.title)
        .navigationBarTitleDisplayMode(.inline)
        .alert("Download Failed", isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
            Button("OK") { failure = nil }
        } message: {
            Text(failure ?? "")
        }
        #if DEBUG
        .onAppear { DemoMode.markReady(.book) }
        #endif
    }

    @ViewBuilder private var downloads: some View {
        if entry.downloads.isEmpty {
            Text("This book isn’t offered as EPUB or PDF, the formats this app opens.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        } else {
            VStack(spacing: 12) {
                ForEach(entry.downloads, id: \.url) { acquisition in
                    if let format = acquisition.format {
                        download(acquisition, as: format)
                    }
                }
            }
        }
    }

    @ViewBuilder private func download(_ acquisition: OPDSAcquisition, as format: BookFormat) -> some View {
        if library.shelf.contains(entryID: entry.id, format: format) {
            Label(String(localized: "book.onShelf", defaultValue: "\(format.label) on this iPhone",
                         comment: "Book screen: this format of the book is downloaded. The argument is EPUB or PDF."),
                  systemImage: "checkmark.circle.fill")
                .foregroundStyle(.secondary)
        } else if library.isDownloading(entry, as: format) {
            ProgressView {
                Text(String(localized: "book.downloading", defaultValue: "Downloading \(format.label)…",
                            comment: "Book screen: a download under way. The argument is EPUB or PDF."))
            }
        } else {
            Button {
                Task {
                    do {
                        try await library.download(entry, acquisition)
                    } catch is CancellationError {
                    } catch {
                        failure = message(for: error)
                    }
                }
            } label: {
                VStack(spacing: 2) {
                    Text(String(localized: "book.download", defaultValue: "Download \(format.label)",
                                comment: "Book screen: the button that downloads the book. The argument is EPUB or PDF."))
                    if let length = acquisition.length {
                        Text(Int64(length).formatted(.byteCount(style: .file)))
                            .font(.caption)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(library.server == nil)
        }
    }
}
