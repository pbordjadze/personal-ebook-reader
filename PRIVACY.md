# Reader privacy policy

Last updated October 25, 2026.

Reader has no account, no analytics and no ads, and uses no third-party services. Its developer
receives nothing from the app: not your books, your library, your reading or anything about how
you use it.

## Where your books and your place go

Reader works with servers you add yourself: a library server that offers your books as an OPDS
catalog, and, if you choose, a reading-sync server (the KOReader sync protocol). Reader talks only
to those servers, over HTTPS:

- **Your library server** receives the requests to list, search and download your books, and the
  login you gave Reader for it.
- **Your sync server**, if you add one, receives your login, an identifier for each book you read
  (computed from the book's file), how far you are in it, and a name and identifier for this
  device, so your other devices can pick up where you left off.

What those servers keep is up to whoever runs them.

## What stays on your iPhone

- **Your books** that you download, and your place in each, are stored in the app on your iPhone.
  Deleting a book deletes its file; deleting the app deletes all of them. They are included in
  your iPhone's own backups like any app's data.
- **Your logins** are stored in your iPhone's Keychain.

## Permissions

Reader asks for no permissions.

## Children

Reader is not directed at children and collects nothing from anyone.

## Changes

Changes to this policy are published here, in the app's public repository, with the date above.

## Contact

Questions: open an issue at https://github.com/pbordjadze/personal-ebook-reader/issues.
