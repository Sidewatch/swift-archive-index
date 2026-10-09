# Audit log

Last full audit: **24 Sep 2026** — the day the package was written, replacing Sidewatch's
`unzip -l` / `unzip -p` parsing in its archive preview, so the Quick Look extension (sandboxed,
no tools to spawn) could list archives too. Add a dated line under *History* when you audit
again, and keep *Known non-issues* current so the next pass skips them.

## What a full audit checks

1. `swift build` warnings (none allowed except those listed under known non-issues) and `swift test` green.
2. Dead code: every `func`/type/property declared once and referenced nowhere in the package or the family.
   Public API is NOT dead because Sidewatch does not call it.
3. Every public declaration documented with `///`.
4. The README's usage sample compiles against the current API.
5. Every read of archive bytes goes through `ByteReader` (bounds-checked); no subscript on a
   `Data` from the file outside it and `TarIndex`'s block slices, which are length-checked first.

## Known non-issues

- `ArchiveNode` is a class marked `@unchecked Sendable`: it is built whole by `ArchiveTree.build`
  and never mutated after, and an outline view needs reference identity for its items.
- Zip names without the UTF-8 flag are read as UTF-8 first and Latin-1 second, not CP437; the
  difference is a few box-drawing and accented code points in archives from 1990s DOS tools.
- A tar that ends without its two zero blocks lists fine (tar tools accept it with a warning);
  `truncated` is thrown only when a member's data runs past the file.
- `Compression`'s `.zlib` is raw DEFLATE (RFC 1951), which is exactly a zip member's stream;
  proven by the test that inflates a member the system's `zip` wrote.

## History

- 24 Sep 2026 — written; nine tests; mutants checked: ZIP64 extra ignored (4 failures), tar long
  names dropped (2), tree left unsorted (4).
- 9 Oct 2026 — corrupt-input pass (`HostileArchiveTests`, six tests). Fixed: a ZIP64 end record claiming
  trillions of entries made `entries(in:)` reserve for them (the unfixed reader died asking for 87 TB; the
  reserve is now bounded by the bytes after the directory offset); a tar size field that overflows an `Int`
  (base-256 all ones), is negative, or runs past the file now throws `truncated` instead of wrapping into a
  negative block step (`octal` refuses more bits than an `Int`, `sizeField` is optional, one guard covers every
  member type); a negative pax `size` record is ignored. Mutants: the unfixed reader crashes one test and fails
  two. Checked and sound: a member claiming 4 GB lists and refuses to unpack (`ByteReader`), `../../x` is shown
  under a `..` folder and unpacked under its last component only, a ten-level path folds into ten folders.
