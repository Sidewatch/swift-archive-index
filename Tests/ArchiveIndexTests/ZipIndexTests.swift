//
//  ZipIndexTests.swift
//  ArchiveIndexTests
//
//  Real zips from the system's zip tool, a hand-built ZIP64, and the refusals.
//
//  Created by David Sherlock on 9/24/26.
//

import XCTest
@testable import ArchiveIndex

final class ZipIndexTests: XCTestCase {
    var dir: URL!
    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("archive-index-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("src/nested/deeper"), withIntermediateDirectories: true)
        try "hello, zip\n".write(to: dir.appendingPathComponent("src/a.txt"), atomically: true, encoding: .utf8)
        try String(repeating: "the quick brown fox jumps over the lazy dog\n", count: 200).write(to: dir.appendingPathComponent("src/nested/b.txt"), atomically: true, encoding: .utf8)
        try Data([0, 1, 2, 3, 0xFF]).write(to: dir.appendingPathComponent("src/nested/deeper/c.bin"))
        try "ü".write(to: dir.appendingPathComponent("src/nested/spa ce ü.md"), atomically: true, encoding: .utf8)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    /// The archive the system's zip writes for `src`, with `flags` (`-0` stores, nothing deflates).
    func zip(_ name: String, flags: [String] = []) throws -> URL {
        let out = dir.appendingPathComponent(name)
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        p.currentDirectoryURL = dir.appendingPathComponent("src")
        p.arguments = ["-q", "-r"] + flags + [out.path, "."]
        p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
        try p.run(); p.waitUntilExit()
        XCTAssertEqual(p.terminationStatus, 0)
        return out
    }

    func testListsEveryMemberWithSizesFoldersAndTimesWithoutUnpacking() throws {
        let url = try zip("deflated.zip")
        let entries = try ZipIndex.entries(at: url)
        let byPath = Dictionary(uniqueKeysWithValues: entries.map { ($0.path, $0) })
        XCTAssertEqual(byPath["a.txt"]?.size, 11)
        XCTAssertEqual(byPath["nested/b.txt"]?.size, 44 * 200)
        XCTAssertEqual(byPath["nested/b.txt"]?.method, .deflate)
        XCTAssertLessThan(byPath["nested/b.txt"]!.compressedSize, 44 * 200, "a repeated line deflates")
        XCTAssertEqual(byPath["nested/deeper/c.bin"]?.size, 5)
        XCTAssertEqual(byPath["nested/spa ce ü.md"]?.size, 2, "UTF-8 names (flag bit 11) decode")
        XCTAssertEqual(byPath["nested/"]?.isDirectory, true)
        XCTAssertEqual(byPath["nested/deeper/"]?.isDirectory, true)
        XCTAssertNotNil(byPath["a.txt"]?.modified)
        XCTAssertLessThan(abs(byPath["a.txt"]!.modified!.timeIntervalSinceNow), 600, "the DOS time decodes to about now")
        XCTAssertEqual(entries.first?.name, entries.first?.path.split(separator: "/").last.map(String.init))
        XCTAssertEqual(Archive.kind(at: url), .zip)
        XCTAssertTrue(ZipIndex.isZip(head: try Data(contentsOf: url).prefix(4)))
    }

    func testUnpacksOneStoredAndOneDeflatedMember() throws {
        let deflated = try zip("d.zip")
        let stored = try zip("s.zip", flags: ["-0"])
        let d = try ZipIndex.entries(at: deflated).first { $0.path == "nested/b.txt" }!
        XCTAssertEqual(d.method, .deflate)
        XCTAssertEqual(String(data: try ZipIndex.data(for: d, in: deflated), encoding: .utf8), String(repeating: "the quick brown fox jumps over the lazy dog\n", count: 200))
        let s = try ZipIndex.entries(at: stored).first { $0.path == "nested/deeper/c.bin" }!
        XCTAssertEqual(s.method, .stored)
        XCTAssertEqual(try ZipIndex.data(for: s, in: stored), Data([0, 1, 2, 3, 0xFF]))
        let small = try ZipIndex.entries(at: deflated).first { $0.path == "a.txt" }!
        XCTAssertEqual(String(data: try Archive.data(for: small, kind: .zip, in: deflated), encoding: .utf8), "hello, zip\n")
    }

    func testListingTotalsAndTree() throws {
        let listing = try Archive.listing(at: try zip("t.zip"))
        XCTAssertEqual(listing.kind, .zip)
        XCTAssertEqual(listing.fileCount, 4)
        XCTAssertEqual(listing.folderCount, 2)
        XCTAssertEqual(listing.totalSize, 11 + 8800 + 5 + 2)
        let roots = listing.tree
        XCTAssertEqual(roots.map(\.name), ["nested", "a.txt"], "folders first, then files")
        let nested = roots[0]
        XCTAssertEqual(nested.children.map(\.name), ["deeper", "b.txt", "spa ce ü.md"])
        XCTAssertEqual(nested.size, 8800 + 5 + 2, "a folder's size is what lies beneath it")
        XCTAssertEqual(nested.fileCount, 3)
        XCTAssertEqual(nested.children[0].children.first?.path, "nested/deeper/c.bin")
    }

    /// A ZIP64 archive built by hand: one stored member whose sizes and offset the 32-bit header
    /// marks 0xFFFFFFFF, carried in the extra field, and an end record that defers to the 64-bit
    /// one through its locator. Every count in the ordinary end record is the 0xFFFF marker.
    func testReadsZip64Markers() throws {
        let body = Data("zip64 body".utf8), name = Data("big.txt".utf8)
        func le16(_ v: Int) -> [UInt8] { [UInt8(v & 0xFF), UInt8(v >> 8 & 0xFF)] }
        func le32(_ v: Int) -> [UInt8] { le16(v & 0xFFFF) + le16(v >> 16 & 0xFFFF) }
        func le64(_ v: Int) -> [UInt8] { le32(v & 0xFFFF_FFFF) + le32(v >> 32) }
        var file = Data()
        // local header
        file += le32(0x0403_4B50) + le16(45) + le16(0) + le16(0) + le16(0) + le16(0x21) + le32(0) + le32(body.count) + le32(body.count) + le16(name.count) + le16(0)
        file += name + body
        let cdOffset = file.count
        let extra = le16(1) + le16(24) + le64(body.count) + le64(body.count) + le64(0)
        file += le32(0x0201_4B50) + le16(45) + le16(45) + le16(0) + le16(0) + le16(0) + le16(0x21) + le32(0)
        file += le32(0xFFFF_FFFF) + le32(0xFFFF_FFFF) + le16(name.count) + le16(extra.count) + le16(0) + le16(0) + le16(0) + le32(0) + le32(0xFFFF_FFFF)
        file += name + extra
        let cdSize = file.count - cdOffset
        let end64 = file.count
        file += le32(0x0606_4B50) + le64(44) + le16(45) + le16(45) + le32(0) + le32(0) + le64(1) + le64(1) + le64(cdSize) + le64(cdOffset)
        file += le32(0x0706_4B50) + le32(0) + le64(end64) + le32(1)
        file += le32(0x0605_4B50) + le16(0) + le16(0) + le16(0xFFFF) + le16(0xFFFF) + le32(0xFFFF_FFFF) + le32(0xFFFF_FFFF) + le16(0)
        let entries = try ZipIndex.entries(in: file)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.path, "big.txt")
        XCTAssertEqual(entries.first?.size, body.count)
        XCTAssertEqual(entries.first?.compressedSize, body.count)
        XCTAssertEqual(entries.first?.offset, 0)
        XCTAssertEqual(try ZipIndex.data(for: entries[0], in: file), body)
    }

    func testRefusesWhatItCannotRead() throws {
        XCTAssertThrowsError(try ZipIndex.entries(in: Data("not a zip at all, just text".utf8))) { XCTAssertEqual($0 as? ArchiveError, .notAnArchive) }
        let url = try zip("cut.zip")
        let whole = try Data(contentsOf: url)
        XCTAssertThrowsError(try ZipIndex.entries(in: whole.prefix(whole.count - 5)), "a clipped tail has no end record")
        let entries = try ZipIndex.entries(at: url)
        let big = entries.first { $0.path == "nested/b.txt" }!
        XCTAssertThrowsError(try ZipIndex.data(for: big, in: whole.prefix(big.offset + 40))) { XCTAssertEqual($0 as? ArchiveError, .truncated) }
        let encrypted = ArchiveEntry(path: "x", size: 1, compressedSize: 1, isDirectory: false, modified: nil, method: .stored, offset: big.offset)
        var flagged = whole
        flagged[big.offset + 6] = 1   // the local header's encryption bit
        XCTAssertThrowsError(try ZipIndex.data(for: encrypted, in: flagged)) { XCTAssertEqual($0 as? ArchiveError, .encrypted) }
        let bzip = ArchiveEntry(path: "x", size: 1, compressedSize: 1, isDirectory: false, modified: nil, method: .other(12), offset: big.offset)
        XCTAssertThrowsError(try ZipIndex.data(for: bzip, in: whole)) { XCTAssertEqual($0 as? ArchiveError, .unsupportedMethod(12)) }
        XCTAssertFalse(ZipIndex.isZip(head: Data("PK".utf8)))
        XCTAssertNil(ArchiveKind.detect(head: Data(repeating: 0x41, count: 600)))
    }
}
