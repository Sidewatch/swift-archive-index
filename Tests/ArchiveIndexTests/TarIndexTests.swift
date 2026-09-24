//
//  TarIndexTests.swift
//  ArchiveIndexTests
//
//  Real tars from the system's tar tool in its pax and GNU shapes, and the refusals.
//
//  Created by David Sherlock on 9/24/26.
//

import XCTest
@testable import ArchiveIndex

final class TarIndexTests: XCTestCase {
    var dir: URL!
    let longName = String(repeating: "abcdefghij", count: 12) + ".txt"   // 124 characters: past the 100-byte name field
    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("archive-index-tar-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("src/sub"), withIntermediateDirectories: true)
        try "hello, tar\n".write(to: dir.appendingPathComponent("src/a.txt"), atomically: true, encoding: .utf8)
        try Data(repeating: 0x42, count: 1000).write(to: dir.appendingPathComponent("src/sub/b.bin"))
        try "long".write(to: dir.appendingPathComponent("src/sub/\(longName)"), atomically: true, encoding: .utf8)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    func tar(_ name: String, format: String) throws -> URL {
        let out = dir.appendingPathComponent(name)
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        p.currentDirectoryURL = dir.appendingPathComponent("src")
        p.arguments = ["--format", format, "-cf", out.path, "."]
        p.environment = ["COPYFILE_DISABLE": "1", "PATH": "/usr/bin:/bin"]   // no AppleDouble `._` members for the fixtures' extended attributes
        p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
        try p.run(); p.waitUntilExit()
        XCTAssertEqual(p.terminationStatus, 0)
        return out
    }

    func check(_ url: URL, file: StaticString = #filePath, line: UInt = #line) throws {
        XCTAssertEqual(Archive.kind(at: url), .tar, file: file, line: line)
        let entries = try TarIndex.entries(at: url)
        let byPath = Dictionary(uniqueKeysWithValues: entries.map { ($0.path.hasPrefix("./") ? String($0.path.dropFirst(2)) : $0.path, $0) })
        XCTAssertEqual(byPath["a.txt"]?.size, 11, file: file, line: line)
        XCTAssertEqual(byPath["sub/b.bin"]?.size, 1000, file: file, line: line)
        XCTAssertEqual(byPath["sub/"]?.isDirectory, true, "a directory member", file: file, line: line)
        XCTAssertEqual(byPath["sub/\(longName)"]?.size, 4, "a name past 100 bytes comes through the long-name mechanism", file: file, line: line)
        XCTAssertNotNil(byPath["a.txt"]?.modified, file: file, line: line)
        XCTAssertEqual(try TarIndex.data(for: byPath["sub/b.bin"]!, in: url), Data(repeating: 0x42, count: 1000), file: file, line: line)
        XCTAssertEqual(String(data: try Archive.data(for: byPath["sub/\(longName)"]!, kind: .tar, in: url), encoding: .utf8), "long", file: file, line: line)
        XCTAssertEqual(try Archive.listing(at: url).fileCount, 3, file: file, line: line)
    }

    func testReadsAPaxTar() throws { try check(try tar("pax.tar", format: "pax")) }
    func testReadsAGNUTarWithLongNames() throws { try check(try tar("gnu.tar", format: "gnutar")) }
    func testReadsAUstarTarWithAPathSplitIntoPrefixAndName() throws {
        // ustar has no long-name record: a path past 100 bytes is split at a `/` into the 155-byte
        // prefix and the 100-byte name (a BASENAME past 100 bytes cannot be stored at all — the
        // fixture's is skipped by tar, which is ustar's limit, not the reader's).
        let deep = "src/" + String(repeating: "folder-number-", count: 8)   // a 112-character folder name
        try FileManager.default.createDirectory(at: dir.appendingPathComponent(deep), withIntermediateDirectories: true)
        try "deep".write(to: dir.appendingPathComponent(deep + "/x.txt"), atomically: true, encoding: .utf8)
        let url = try tar("ustar.tar", format: "ustar")
        let entries = try TarIndex.entries(at: url)
        let hit = entries.first { $0.path.hasSuffix("/x.txt") }
        XCTAssertEqual(hit?.path, "./" + String(deep.dropFirst(4)) + "/x.txt", entries.map(\.path).joined(separator: ","))
        XCTAssertEqual(String(data: try TarIndex.data(for: try XCTUnwrap(hit), in: url), encoding: .utf8), "deep")
    }

    func testRefusesWhatIsNotATar() throws {
        XCTAssertThrowsError(try TarIndex.entries(in: Data(repeating: 0x41, count: 2048))) { XCTAssertEqual($0 as? ArchiveError, .notAnArchive) }
        XCTAssertFalse(TarIndex.isTar(head: Data(repeating: 0, count: 512)), "an empty block is not a header")
        let url = try tar("cut.tar", format: "pax")
        let whole = try Data(contentsOf: url)
        let big = try TarIndex.entries(at: url).first { $0.path.hasSuffix("b.bin") }!
        XCTAssertThrowsError(try TarIndex.entries(in: whole.prefix(big.offset + 100)), "cut inside a member's data") { XCTAssertEqual($0 as? ArchiveError, .truncated) }
    }
}
