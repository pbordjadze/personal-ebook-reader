# Personal Ebook Reader

An iPhone reader for your own book library: it reads an OPDS catalog (such as Calibre-Web's), opens
EPUB and PDF with the Readium Swift toolkit, and keeps your place with a KOReader sync (kosync)
server. No account, no analytics, no DRM: books and positions travel only between your phone and
the server you name.

Work in progress.

## Privacy

No account, no analytics, no ads, no third-party services. Books and positions travel only between
your iPhone and the servers you add. See [PRIVACY.md](PRIVACY.md).

## Building

Swift 6, SwiftUI, iOS 26. `ReaderCore` (the app's portable logic) builds and tests on Linux:
`tools/swift.sh test`, against the fixtures in `Tests/Fixtures` (a made-up library of
public-domain books). The app builds on CI; see [CLAUDE.md](CLAUDE.md).
