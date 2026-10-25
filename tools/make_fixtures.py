#!/usr/bin/env python3
"""Writes the test fixtures in `Tests/Fixtures`: a reader's server, in files.

    tools/make_fixtures.py [--check]

Tests never need a real server (CLAUDE.md › Fixtures). This makes, byte for byte the same on
every run:
  - `opds/`: a Calibre-Web-shaped OPDS 1.2 catalog: a navigation feed, an acquisition feed of
    new books in two pages, an OpenSearch description and a search result;
  - `books/`: the books those feeds offer, from public-domain text (Jane Austen, *Pride and
    Prejudice*, 1813): an EPUB 3 of two chapters, a PDF with a text layer, and a "scanned" PDF
    whose pages are images with an invisible OCR text layer over them;
  - `covers/`: a cover image per book;
  - `kosync/`: the KOReader sync server's requests and replies, one JSON file each.
`--check` makes them in a scratch directory and fails when the committed ones differ (a file
changed, missing or left over).
"""
import filecmp
import json
import os
import struct
import sys
import tempfile
import zipfile
import zlib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "Tests", "Fixtures")

CHAPTER_1 = [
    "It is a truth universally acknowledged, that a single man in possession of a good fortune, "
    "must be in want of a wife.",
    "However little known the feelings or views of such a man may be on his first entering a "
    "neighbourhood, this truth is so well fixed in the minds of the surrounding families, that he "
    "is considered the rightful property of some one or other of their daughters.",
    "\u201cMy dear Mr. Bennet,\u201d said his lady to him one day, \u201chave you heard that "
    "Netherfield Park is let at last?\u201d",
    "Mr. Bennet replied that he had not.",
    "\u201cBut it is,\u201d returned she; \u201cfor Mrs. Long has just been here, and she told me "
    "all about it.\u201d",
    "Mr. Bennet made no answer.",
    "\u201cDo you not want to know who has taken it?\u201d cried his wife impatiently.",
    "\u201cYou want to tell me, and I have no objection to hearing it.\u201d",
    "This was invitation enough.",
]
CHAPTER_2 = [
    "Mr. Bennet was among the earliest of those who waited on Mr. Bingley. He had always intended "
    "to visit him, though to the last always assuring his wife that he should not go; and till the "
    "evening after the visit was paid she had no knowledge of it.",
]

# The catalog's books. A book's files are named by its id; `formats` are what the server offers.
BOOKS = [
    {"id": 1, "title": "Pride and Prejudice", "author": "Jane Austen", "formats": ["epub", "pdf"], "issued": 1813,
     "updated": "2026-10-20T09:00:00+00:00", "color": (0x6b, 0x2d, 0x3a)},
    {"id": 2, "title": "Pride and Prejudice (Scanned)", "author": "Jane Austen", "formats": ["pdf"], "issued": 1813,
     "updated": "2026-10-19T09:00:00+00:00", "color": (0x8a, 0x7a, 0x5c)},
    {"id": 3, "title": "Persuasion", "author": "Jane Austen", "formats": ["mobi"], "issued": 1817,
     "updated": "2026-10-18T09:00:00+00:00", "color": (0x2f, 0x4f, 0x6b)},
]
MEDIA = {"epub": "application/epub+zip", "pdf": "application/pdf", "mobi": "application/x-mobipocket-ebook"}
FILES = {(1, "epub"): "books/pride-and-prejudice.epub", (1, "pdf"): "books/pride-and-prejudice.pdf",
         (2, "pdf"): "books/pride-and-prejudice-scanned.pdf"}
STAMP = (2026, 10, 20, 9, 0, 0)


def xml_escape(s):
    return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace('"', "&quot;")


# ---------------------------------------------------------------- OPDS

ATOM = ('<?xml version="1.0" encoding="UTF-8"?>\n'
        '<feed xmlns="http://www.w3.org/2005/Atom" xmlns:dc="http://purl.org/dc/terms/"\n'
        '      xmlns:opds="http://opds-spec.org/2010/catalog"\n'
        '      xmlns:opensearch="http://a9.com/-/spec/opensearch/1.1/">\n')
NAV = "application/atom+xml;profile=opds-catalog;kind=navigation"
ACQ = "application/atom+xml;profile=opds-catalog;kind=acquisition"


def feed_head(id_, title, self_href, kind, extra_links=()):
    links = [("self", self_href, kind), ("start", "/opds", NAV),
             ("search", "/opds/osd", "application/opensearchdescription+xml")] + list(extra_links)
    out = ATOM + f"  <id>{id_}</id>\n  <title>{xml_escape(title)}</title>\n"
    out += "  <updated>2026-10-20T09:00:00+00:00</updated>\n"
    out += "  <author><name>Calibre-Web</name></author>\n"
    for rel, href, type_ in links:
        out += f'  <link rel="{rel}" href="{xml_escape(href)}" type="{type_}"/>\n'
    return out


def root_feed():
    out = feed_head("urn:fixture:root", "Library", "/opds", NAV)
    for id_, title, href, content in [
        ("new", "Recently Added Books", "/opds/new", "The latest books"),
        ("authors", "Authors", "/opds/author", "Books ordered by author"),
    ]:
        out += (f"  <entry>\n    <title>{title}</title>\n    <id>urn:fixture:{id_}</id>\n"
                f"    <updated>2026-10-20T09:00:00+00:00</updated>\n"
                f'    <link rel="subsection" href="{href}" type="{ACQ}"/>\n'
                f'    <content type="text">{content}</content>\n  </entry>\n')
    return out + "</feed>\n"


def book_entry(book):
    i = book["id"]
    out = (f"  <entry>\n    <title>{xml_escape(book['title'])}</title>\n"
           f"    <id>urn:uuid:00000000-0000-4000-8000-{i:012d}</id>\n"
           f"    <updated>{book['updated']}</updated>\n"
           f"    <author><name>{xml_escape(book['author'])}</name></author>\n"
           "    <dc:language>en</dc:language>\n"
           f"    <dc:issued>{book['issued']}</dc:issued>\n")
    out += f'    <link rel="http://opds-spec.org/image" href="/opds/cover/{i}" type="image/png"/>\n'
    out += f'    <link rel="http://opds-spec.org/image/thumbnail" href="/opds/cover/{i}" type="image/png"/>\n'
    for fmt in book["formats"]:
        size = os.path.getsize(os.path.join(OUT, FILES[(i, fmt)])) if (i, fmt) in FILES else 280000
        out += (f'    <link rel="http://opds-spec.org/acquisition" href="/opds/download/{i}/{fmt}/" '
                f'type="{MEDIA[fmt]}" length="{size}" title="{fmt.upper()}"/>\n')
    out += "  </entry>\n"
    return out


def new_feeds():
    first = feed_head("urn:fixture:new", "Recently Added Books", "/opds/new", ACQ,
                      [("next", "/opds/new?offset=2", ACQ)])
    first += "  <opensearch:totalResults>3</opensearch:totalResults>\n"
    first += "  <opensearch:itemsPerPage>2</opensearch:itemsPerPage>\n"
    first += "".join(book_entry(b) for b in BOOKS[:2]) + "</feed>\n"
    second = feed_head("urn:fixture:new", "Recently Added Books", "/opds/new?offset=2", ACQ,
                       [("previous", "/opds/new", ACQ)])
    second += "".join(book_entry(b) for b in BOOKS[2:]) + "</feed>\n"
    return first, second


def search_feed():
    out = feed_head("urn:fixture:search", "Search: persuasion", "/opds/search/persuasion", ACQ)
    return out + book_entry(BOOKS[2]) + "</feed>\n"


OPENSEARCH = """<?xml version="1.0" encoding="UTF-8"?>
<OpenSearchDescription xmlns="http://a9.com/-/spec/opensearch/1.1/">
  <ShortName>Library</ShortName>
  <Description>Search the library</Description>
  <InputEncoding>UTF-8</InputEncoding>
  <OutputEncoding>UTF-8</OutputEncoding>
  <Url type="application/atom+xml" template="/opds/search/{searchTerms}"/>
  <Url type="application/atom+xml;profile=opds-catalog;kind=acquisition" template="/opds/search/{searchTerms}"/>
</OpenSearchDescription>
"""

# ---------------------------------------------------------------- PNG


def png(width, height, pixel):
    """An 8-bit RGB (or grayscale, when `pixel` returns an int) PNG from pixel(x, y)."""
    gray = isinstance(pixel(0, 0), int)
    rows = bytearray()
    for y in range(height):
        rows.append(0)
        for x in range(width):
            p = pixel(x, y)
            rows += bytes([p]) if gray else bytes(p)

    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))
    header = struct.pack(">IIBBBBB", width, height, 8, 0 if gray else 2, 0, 0, 0)
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header)
            + chunk(b"IDAT", zlib.compress(bytes(rows), 9)) + chunk(b"IEND", b""))


def cover(color):
    """A plain cover: the book's colour with a lighter band where a title would be."""
    light = tuple(min(255, c + 90) for c in color)
    return png(120, 180, lambda x, y: light if 60 <= y < 90 and 12 <= x < 108 else color)

# ---------------------------------------------------------------- EPUB


def xhtml(title, paragraphs):
    body = "\n".join(f"    <p>{xml_escape(p)}</p>" for p in paragraphs)
    return ('<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE html>\n'
            '<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" '
            'xml:lang="en" lang="en">\n'
            f"  <head><title>{title}</title><link rel=\"stylesheet\" href=\"style.css\" type=\"text/css\"/></head>\n"
            f"  <body>\n    <section epub:type=\"chapter\">\n    <h1>{title}</h1>\n{body}\n    </section>\n  </body>\n</html>\n")


def entry(name):
    info = zipfile.ZipInfo(name, STAMP)
    info.external_attr = 0o644 << 16  # rw-r--r--, so an unzipped book is readable
    return info


def epub():
    files = [
        ("META-INF/container.xml",
         '<?xml version="1.0" encoding="UTF-8"?>\n'
         '<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">\n'
         '  <rootfiles>\n    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>\n'
         '  </rootfiles>\n</container>\n'),
        ("OEBPS/content.opf",
         '<?xml version="1.0" encoding="UTF-8"?>\n'
         '<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="uid" xml:lang="en">\n'
         '  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">\n'
         '    <dc:identifier id="uid">urn:uuid:00000000-0000-4000-8000-000000000001</dc:identifier>\n'
         '    <dc:title>Pride and Prejudice</dc:title>\n'
         '    <dc:creator>Jane Austen</dc:creator>\n'
         '    <dc:language>en</dc:language>\n'
         '    <meta property="dcterms:modified">2026-10-20T09:00:00Z</meta>\n'
         '    <meta name="cover" content="cover"/>\n'
         '  </metadata>\n  <manifest>\n'
         '    <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>\n'
         '    <item id="cover" href="cover.png" media-type="image/png" properties="cover-image"/>\n'
         '    <item id="style" href="style.css" media-type="text/css"/>\n'
         '    <item id="ch1" href="chapter-1.xhtml" media-type="application/xhtml+xml"/>\n'
         '    <item id="ch2" href="chapter-2.xhtml" media-type="application/xhtml+xml"/>\n'
         '  </manifest>\n  <spine>\n    <itemref idref="ch1"/>\n    <itemref idref="ch2"/>\n  </spine>\n</package>\n'),
        ("OEBPS/nav.xhtml",
         '<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE html>\n'
         '<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" xml:lang="en" lang="en">\n'
         '  <head><title>Contents</title></head>\n  <body>\n    <nav epub:type="toc" id="toc">\n'
         '      <h1>Contents</h1>\n      <ol>\n'
         '        <li><a href="chapter-1.xhtml">Chapter 1</a></li>\n'
         '        <li><a href="chapter-2.xhtml">Chapter 2</a></li>\n'
         '      </ol>\n    </nav>\n  </body>\n</html>\n'),
        ("OEBPS/style.css", "body { margin: 0 5%; }\np { text-indent: 1.5em; margin: 0; }\nh1 { text-align: center; }\n"),
        ("OEBPS/chapter-1.xhtml", xhtml("Chapter 1", CHAPTER_1)),
        ("OEBPS/chapter-2.xhtml", xhtml("Chapter 2", CHAPTER_2)),
    ]
    path = os.path.join(OUT, FILES[(1, "epub")])
    with zipfile.ZipFile(path, "w") as z:
        # The mimetype comes first and uncompressed (EPUB OCF): readers sniff it at byte 38.
        z.writestr(entry("mimetype"), "application/epub+zip", zipfile.ZIP_STORED)
        z.writestr(entry("OEBPS/cover.png"), cover(BOOKS[0]["color"]), zipfile.ZIP_STORED)
        for name, text in files:
            z.writestr(entry(name), text.encode(), zipfile.ZIP_DEFLATED)

# ---------------------------------------------------------------- PDF

PAGE_W, PAGE_H = 432, 648  # 6 × 9 in


def pdf_text(s):
    # WinAnsiEncoding: curly quotes are 0x93/0x94; parentheses and backslashes are escaped.
    s = s.replace("\\", "\\\\").replace("(", "\\(").replace(")", "\\)")
    return s.replace("\u201c", "\\223").replace("\u201d", "\\224")


def wrap(text, width=62):
    lines, line = [], ""
    for word in text.split():
        if line and len(line) + 1 + len(word) > width:
            lines.append(line)
            line = word
        else:
            line = f"{line} {word}" if line else word
    return lines + [line]


def page_lines(title, paragraphs):
    lines = [(title, True)]
    for p in paragraphs:
        lines += [(line, False) for line in wrap(p)] + [("", False)]
    return lines


def text_ops(lines, render_mode=0):
    ops = [f"BT {render_mode} Tr"]
    y = PAGE_H - 72
    for line, heading in lines:
        size = 16 if heading else 10.5
        if line:
            ops.append(f"/F1 {size} Tf 1 0 0 1 54 {y} Tm ({pdf_text(line)}) Tj")
        y -= 24 if heading else 14
    ops.append("ET")
    return "\n".join(ops).encode("latin-1")


def scan_image(lines):
    """A page as a scanner sees it: grey paper, dark bars where the words are, at 1/2 scale."""
    w, h = PAGE_W // 2, PAGE_H // 2
    ink = set()
    y = PAGE_H - 72
    for line, heading in lines:
        if line:
            top = (PAGE_H - y) // 2 - (6 if heading else 4)
            col = 27
            for word in line.split():
                span = len(word) * (5 if heading else 3)
                for yy in range(top, top + (6 if heading else 4)):
                    for xx in range(col, min(w - 1, col + span)):
                        ink.add((xx, yy))
                col += span + 3
        y -= 24 if heading else 14
    return w, h, gray_pixels(w, h, lambda x, y: 40 if (x, y) in ink else 232 - ((x * 7 + y * 13) % 9))


def gray_pixels(w, h, pixel):
    return bytes(pixel(x, y) for y in range(h) for x in range(w))


def pdf(path, pages, scanned=False):
    """Writes a PDF of `pages` (lists of (line, heading)); scanned pages are images under an
    invisible text layer, as OCR leaves them."""
    objects = []

    def add(body):
        objects.append(body)
        return len(objects)

    font = add(b"<< /Type /Font /Subtype /Type1 /BaseFont /Times-Roman /Encoding /WinAnsiEncoding >>")
    pages_id = add(None)  # written once the pages are known
    kids = []
    for lines in pages:
        resources = f"/Font << /F1 {font} 0 R >>"
        content = b""
        if scanned:
            w, h, pixels = scan_image(lines)
            data = zlib.compress(pixels, 9)
            image = add(f"<< /Type /XObject /Subtype /Image /Width {w} /Height {h} /ColorSpace /DeviceGray "
                        f"/BitsPerComponent 8 /Filter /FlateDecode /Length {len(data)} >>\nstream\n".encode()
                        + data + b"\nendstream")
            resources += f" /XObject << /Im1 {image} 0 R >>"
            content = f"q {PAGE_W} 0 0 {PAGE_H} 0 0 cm /Im1 Do Q\n".encode()
        content += text_ops(lines, 3 if scanned else 0)
        stream = zlib.compress(content, 9)
        contents = add(f"<< /Length {len(stream)} /Filter /FlateDecode >>\nstream\n".encode() + stream + b"\nendstream")
        kids.append(add(f"<< /Type /Page /Parent {pages_id} 0 R /MediaBox [0 0 {PAGE_W} {PAGE_H}] "
                        f"/Resources << {resources} >> /Contents {contents} 0 R >>".encode()))
    objects[pages_id - 1] = (f"<< /Type /Pages /Kids [{' '.join(f'{k} 0 R' for k in kids)}] "
                             f"/Count {len(kids)} >>").encode()
    title = "Pride and Prejudice (Scanned)" if scanned else "Pride and Prejudice"
    info = add(f"<< /Title ({title}) /Author (Jane Austen) /CreationDate (D:20261020090000Z) >>".encode())
    catalog = add(f"<< /Type /Catalog /Pages {pages_id} 0 R >>".encode())

    out = bytearray(b"%PDF-1.7\n%\xe2\xe3\xcf\xd3\n")
    offsets = []
    for i, body in enumerate(objects, 1):
        offsets.append(len(out))
        out += f"{i} 0 obj\n".encode() + body + b"\nendobj\n"
    xref = len(out)
    out += f"xref\n0 {len(objects) + 1}\n0000000000 65535 f \n".encode()
    out += b"".join(f"{o:010d} 00000 n \n".encode() for o in offsets)
    out += (f"trailer\n<< /Size {len(objects) + 1} /Root {catalog} 0 R /Info {info} 0 R "
            f"/ID [<00000000000000000000000000000001> <00000000000000000000000000000001>] >>\n"
            f"startxref\n{xref}\n%%EOF\n").encode()
    with open(path, "wb") as f:
        f.write(out)

# ---------------------------------------------------------------- kosync

DOCUMENT = "0c3b5f1a2e4d6c8b9a7f5e3d1c2b4a69"  # a partial-MD5 document id, as KOReader computes one


def kosync():
    """The kosync API's exchanges (KOReader's sync server protocol, v1), one file each:
    the request a client sends and the reply a server gives."""
    headers = {"Accept": "application/vnd.koreader.v1+json", "x-auth-user": "reader",
               "x-auth-key": "5ebe2294ecd0e0f08eab7690d2a6ee69"}  # md5("secret"), as clients send it
    position = "/body/DocFragment[2]/body/section/p[1]/text().0"
    return {
        "register.json": {
            "request": {"method": "POST", "path": "/users/create",
                        "headers": {"Accept": headers["Accept"], "Content-Type": "application/json"},
                        "body": {"username": "reader", "password": headers["x-auth-key"]}},
            "response": {"status": 201, "body": {"username": "reader"}}},
        "auth.json": {
            "request": {"method": "GET", "path": "/users/auth", "headers": headers},
            "response": {"status": 200, "body": {"authorized": "OK"}}},
        "auth-unauthorized.json": {
            "request": {"method": "GET", "path": "/users/auth", "headers": {**headers, "x-auth-key": "wrong"}},
            "response": {"status": 401, "body": {"code": 2001, "message": "Unauthorized"}}},
        "push-progress.json": {
            "request": {"method": "PUT", "path": "/syncs/progress",
                        "headers": {**headers, "Content-Type": "application/json"},
                        "body": {"document": DOCUMENT, "progress": position, "percentage": 0.5,
                                 "device": "iPhone", "device_id": "6B1D2A7E0F3C4E5A9B8C7D6E5F4A3B2C"}},
            "response": {"status": 200, "body": {"document": DOCUMENT, "timestamp": 1792929600}}},
        "pull-progress.json": {
            "request": {"method": "GET", "path": f"/syncs/progress/{DOCUMENT}", "headers": headers},
            "response": {"status": 200, "body": {"document": DOCUMENT, "progress": position, "percentage": 0.5,
                                                 "device": "Kobo", "device_id": "A1B2C3D4E5F60718293A4B5C6D7E8F90",
                                                 "timestamp": 1792929600}}},
        "pull-progress-none.json": {
            "request": {"method": "GET", "path": "/syncs/progress/ffffffffffffffffffffffffffffffff", "headers": headers},
            "response": {"status": 200, "body": {}}},
    }

# ----------------------------------------------------------------


def write_all():
    for d in ("opds", "books", "covers", "kosync"):
        os.makedirs(os.path.join(OUT, d), exist_ok=True)
    epub()
    pages = [page_lines("Chapter 1", CHAPTER_1[:5]), page_lines("", CHAPTER_1[5:]),
             page_lines("Chapter 2", CHAPTER_2)]
    pdf(os.path.join(OUT, FILES[(1, "pdf")]), pages)
    pdf(os.path.join(OUT, FILES[(2, "pdf")]), pages, scanned=True)
    for book in BOOKS:
        with open(os.path.join(OUT, "covers", f"{book['id']}.png"), "wb") as f:
            f.write(cover(book["color"]))
    new, new2 = new_feeds()
    for name, text in [("root.xml", root_feed()), ("new.xml", new), ("new-2.xml", new2),
                       ("search-persuasion.xml", search_feed()), ("opensearch.xml", OPENSEARCH)]:
        with open(os.path.join(OUT, "opds", name), "w") as f:
            f.write(text)
    for name, exchange in kosync().items():
        with open(os.path.join(OUT, "kosync", name), "w") as f:
            json.dump(exchange, f, indent=2, sort_keys=True)
            f.write("\n")


def differences(made, committed):
    """Paths, relative to the fixtures, that differ between two trees or are in only one."""
    found = []

    def walk(cmp, prefix):
        found.extend(prefix + n for n in cmp.left_only + cmp.right_only + cmp.funny_files)
        found.extend(prefix + n for n in cmp.common_files
                     if not filecmp.cmp(os.path.join(cmp.left, n), os.path.join(cmp.right, n), shallow=False))
        for name, sub in cmp.subdirs.items():
            walk(sub, prefix + name + "/")
    walk(filecmp.dircmp(made, committed), "")
    return sorted(found)


if __name__ == "__main__":
    if sys.argv[1:] == ["--check"]:
        committed = OUT
        with tempfile.TemporaryDirectory() as scratch:
            OUT = scratch
            write_all()
            changed = differences(scratch, committed)
            count = sum(len(names) for _, _, names in os.walk(scratch))
        if changed:
            sys.exit("fixtures differ from tools/make_fixtures.py (run it and commit): " + ", ".join(changed))
        print(f"{count} fixtures match tools/make_fixtures.py")
    else:
        write_all()
