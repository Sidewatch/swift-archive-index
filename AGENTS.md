# Swift Archive Index

What is inside an archive, read from its directory without unpacking it: `Archive.listing(at:)`
tells the kind by the first bytes (a `.jar` is a zip; a name means nothing), lists every member
(`ArchiveEntry`: path, size, compressed size, directory, time, method) and folds them into
`ArchiveNode`s (`ArchiveTree`: folders first, Finder order, folder sizes summed);
`Archive.data(for:kind:in:)` unpacks ONE member — stored bytes as they are, DEFLATE through
Compression's raw inflate; bzip2 / LZMA / zstd and encrypted members are refused by name.
`ZipIndex` reads the central directory from the file's tail (ZIP64 markers, extra field and the
64-bit end record honoured); `TarIndex` walks 512-byte headers (ustar prefix, pax `path` / `size`
records, GNU `L` long names, v7 by checksum). Both map the file, so a large archive costs its
directory, not its size.

- Module `ArchiveIndex` in `Sources/ArchiveIndex`; tests in `Tests`; `swift test` is the whole check.
- No dependencies. macOS 14, tools 6.2, Swift 6 language mode.
- Every read is bounds-checked through `ByteReader`; a truncated or hostile file is a thrown
  `ArchiveError`, never a trap. Keep it so — the Quick Look extension hands this whatever Finder points at.
- Tests build real archives with `/usr/bin/zip` and `/usr/bin/tar` (`COPYFILE_DISABLE=1`, or
  bsdtar adds `._` AppleDouble members for the fixtures' extended attributes) and one ZIP64 by hand.

Read `CONTRIBUTING.md` for the folder layout and the pull-request rules.

@CONTRIBUTING.md
