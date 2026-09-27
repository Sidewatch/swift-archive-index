# Swift Archive Index

What is inside an archive, read from its directory without unpacking it — and one member unpacked on demand. Zip (and every zip-shaped container: jar, war, ipa, vsix, whl, nupkg, crx, epub) through its central directory, ZIP64 included; uncompressed tar (ustar, pax, GNU long names, old v7) block by block.

## Features

- 📦 **Listing without unpacking** — `Archive.listing(at:)` reads the directory only; the kind is decided by the bytes, never the name
- 🌳 **A tree** — `listing.tree`: folders first, Finder order, folder sizes summed
- 🔓 **One member on demand** — `Archive.data(for:kind:in:)`, stored or DEFLATE (through Compression's raw inflate)
- 🗜 **ZIP64 and every tar dialect** — ustar, pax, GNU long names, old v7
- 🧾 **Honest refusals** — `ArchiveError`: not an archive, truncated, an encrypted member, a method not unpacked here (bzip2, LZMA, zstd), a corrupt DEFLATE stream
- 🪶 **Zero dependencies** — Foundation and Compression

## Requirements

- macOS 14+
- Swift 6.2+ (Swift 6 language mode)

## Installation

### Swift Package Manager

```swift
dependencies: [
    .package(url: "https://github.com/Sidewatch/swift-archive-index.git", from: "0.1.0")
]
```

## Usage

```swift
import ArchiveIndex

let listing = try Archive.listing(at: url)        // kind by the bytes, never the name
listing.fileCount, listing.folderCount, listing.totalSize
for entry in listing.entries { entry.path; entry.size; entry.isDirectory; entry.modified }
let roots = listing.tree                          // folders first, Finder order, folder sizes summed
let bytes = try Archive.data(for: entry, kind: listing.kind, in: url)   // stored or DEFLATE
```

## Notes

- `ZipIndex` and `TarIndex` are the readers behind `Archive`; both take a `URL` (mapped, so a large archive costs its directory, not its size) or a `Data`.
- No gzip: a `.tar.gz` has no index to read.

## For agents

Read `CONTRIBUTING.md` first: the folder layout and the PR rules. `swift test` is the whole
check, and a new test must fail before the change it covers. `CLAUDE.md` / `AGENTS.md` carry a
module map.

## License

MIT — see [LICENSE](LICENSE).
