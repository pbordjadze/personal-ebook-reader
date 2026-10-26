import ReaderCore
import SwiftUI

/// A page of the server's catalog: feeds to go into, or books with their covers, loading the
/// next page as the list reaches its end, and the catalog's search (its OpenSearch template).
///
/// Demo scenarios: `catalog` (the first page), `catalog-new` (books; also `-dark`) and
/// `catalog-search` (a search's results).
struct CatalogView: View {
    let url: URL
    var initialSearch: String?
    @Environment(Library.self) private var library
    @State private var page: Page?
    @State private var failure: String?
    @State private var query = ""
    @State private var results: Page?
    @State private var searchFailure: String?
    @State private var searching = false

    /// A list of entries as loaded so far, and where its next page is.
    struct Page {
        var title: String
        var entries: [OPDSEntry]
        var nextURL: URL?
        var search: OPDSSearch?

        init(_ feed: OPDSFeed) {
            title = feed.title
            entries = feed.entries
            nextURL = feed.nextURL
            search = feed.search
        }

        /// Adds the next page, leaving out entries already listed (a catalog that changes while
        /// it's paged can repeat one).
        mutating func append(_ feed: OPDSFeed) {
            let listed = Set(entries.map(\.id))
            entries += feed.entries.filter { !listed.contains($0.id) }
            nextURL = feed.nextURL
        }
    }

    var body: some View {
        list
            .overlay { overlay }
            .navigationTitle(page?.title ?? "")
            .searchable(text: $query, prompt: Text("Titles and Authors"))
            .onSubmit(of: .search) { Task { await search() } }
            .onChange(of: query) { _, query in
                if query.isEmpty {
                    results = nil
                    searchFailure = nil
                }
            }
            // Once: coming back from a book keeps the pages and search already loaded.
            .task { if page == nil { await load() } }
            .refreshable { await load() }
    }

    /// While a search is typed, the page stays until its results arrive.
    private var shown: Page? { query.isEmpty ? page : results ?? page }

    private var list: some View {
        List {
            if let shown {
                ForEach(shown.entries) { entry in
                    if entry.isBook {
                        NavigationLink(value: Route.book(entry)) { BookRow(entry: entry) }
                    } else if let feed = entry.feedURL {
                        NavigationLink(value: Route.catalog(feed)) { FeedRow(entry: entry) }
                    }
                }
                if let next = shown.nextURL {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .listRowSeparator(.hidden)
                        .task(id: next) { await loadMore(next) }
                }
            }
        }
    }

    @ViewBuilder private var overlay: some View {
        if let failure = query.isEmpty ? failure : searchFailure {
            ContentUnavailableView {
                Label("Can’t Load the Catalog", systemImage: "exclamationmark.icloud")
            } description: {
                Text(failure)
            } actions: {
                Button("Try Again") {
                    Task {
                        if query.isEmpty { await load() } else { await search() }
                    }
                }
            }
        } else if searching || shown == nil {
            ProgressView()
        } else if let shown, shown.entries.isEmpty {
            if query.isEmpty {
                ContentUnavailableView("Nothing Here", systemImage: "books.vertical")
            } else {
                ContentUnavailableView.search(text: query)
            }
        }
    }

    private func load() async {
        guard let client = library.client else { return }
        do {
            page = Page(try await client.feed(at: url))
            failure = nil
            if let initialSearch, query.isEmpty {
                query = initialSearch
                await search()
            }
        } catch is CancellationError {
        } catch {
            failure = message(for: error)
        }
        #if DEBUG
        if page != nil, initialSearch == nil || results != nil { DemoMode.markReady(.catalog) }
        #endif
    }

    private func loadMore(_ next: URL) async {
        guard let client = library.client else { return }
        do {
            let feed = try await client.feed(at: next)
            if !query.isEmpty, results != nil { results?.append(feed) } else { page?.append(feed) }
        } catch {
            // The spinner stays at the end of the list; reaching it again retries.
        }
    }

    private func search() async {
        let terms = query
        guard let client = library.client, !terms.isEmpty else { return }
        guard let search = page?.search else {
            searchFailure = message(for: CatalogError.noSearch)
            return
        }
        searching = true
        defer { searching = false }
        do {
            guard let url = try await client.searchURL(search, terms: terms) else { return }
            let feed = try await client.feed(at: url)
            guard terms == query else { return }
            results = Page(feed)
            searchFailure = nil
        } catch is CancellationError {
        } catch {
            searchFailure = message(for: error)
        }
    }
}

/// A book in a catalog list: its cover, title and authors, and whether it's on this iPhone.
private struct BookRow: View {
    let entry: OPDSEntry
    @Environment(Library.self) private var library

    var body: some View {
        HStack(spacing: 12) {
            CoverView(source: .remote(entry.thumbnailURL ?? entry.coverURL), width: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title)
                    .font(.headline)
                if !entry.authors.isEmpty {
                    Text(entry.authors.formatted(.list(type: .and)))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            if library.shelf.books.contains(where: { $0.entryID == entry.id }) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.tint)
                    .accessibilityLabel("On This iPhone")
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// A feed in a navigation list, with its description.
private struct FeedRow: View {
    let entry: OPDSEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(entry.title)
            if let summary = entry.summary {
                Text(summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
