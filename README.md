# Swift Archive Index

What is inside an archive, read from its directory without unpacking it — and one member
unpacked on demand. Zip (and every zip-shaped container: jar, war, ipa, vsix, whl, nupkg, crx,
epub) through its central directory, ZIP64 included; uncompressed tar (ustar, pax, GNU long
names, old v7) block by block. Extracted from [Sidewatch](https://github.com/Sidewatch), where
it backs the archive preview in the app and in its Quick Look extension.

```swift
import ArchiveIndex

let listing = try Archive.listing(at: url)        // kind by the bytes, never the name
listing.fileCount, listing.folderCount, listing.totalSize
for entry in listing.entries { entry.path; entry.size; entry.isDirectory; entry.modified }
let roots = listing.tree                          // folders first, Finder order, folder sizes summed
let bytes = try Archive.data(for: entry, kind: listing.kind, in: url)   // stored or DEFLATE
```

`ZipIndex` and `TarIndex` are the readers behind `Archive`; both take a `URL` (mapped, so a large
archive costs its directory, not its size) or a `Data`. Refusals are `ArchiveError`: not an
archive, truncated, an encrypted member, a method not unpacked here (bzip2, LZMA, zstd), a
corrupt DEFLATE stream. No gzip: a `.tar.gz` has no index to read.

## Layout

- `Sources/ArchiveIndex/Core/Archive.swift` — the entry: kind, listing, one member.
- `Zip/ZipIndex.swift`, `Tar/TarIndex.swift` — the readers.
- `Models/` — `ArchiveEntry`, `ArchiveListing`, `ArchiveNode`; `Enums/` — `ArchiveKind`, `ArchiveMethod`; `Errors/ArchiveError`.
- `Support/ArchiveTree.swift` (flat paths folded into folders), `Support/ByteReader.swift` (bounds-checked little-endian reads).
- `Tests/ArchiveIndexTests` — real archives from the system's `zip` and `tar`, a hand-built ZIP64, the refusals.

MIT. See CONTRIBUTING.md for the family rules.
