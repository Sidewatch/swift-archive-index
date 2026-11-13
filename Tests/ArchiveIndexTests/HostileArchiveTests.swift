//
//  HostileArchiveTests.swift
//  ArchiveIndexTests
//
//  Hand-made archives whose headers lie: sizes that overflow, go negative or run past the file,
//  and a directory count no file could hold. Each is a refusal or a listing, never a trap.
//
//  Created by David Sherlock on 10/9/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import XCTest
@testable import ArchiveIndex

final class HostileArchiveTests: XCTestCase {
    // MARK: - Tar headers

    /// A 512-byte ustar header with a valid checksum, `size` written as given.
    func header(name: String, size: Data, type: UInt8) -> Data {
        var block = [UInt8](repeating: 0, count: 512)
        func put(_ bytes: Data, at: Int) { for (i, b) in bytes.enumerated() where at + i < 512 { block[at + i] = b } }
        put(Data(name.utf8.prefix(100)), at: 0)
        put(Data("0000644\0".utf8), at: 100)
        put(Data("0000000\0".utf8), at: 108)
        put(Data("0000000\0".utf8), at: 116)
        put(size.prefix(12), at: 124)
        put(Data("00000000000\0".utf8), at: 136)
        put(Data("        ".utf8), at: 148)
        block[156] = type
        put(Data("ustar\0".utf8), at: 257)
        put(Data("00".utf8), at: 263)
        let sum = block.reduce(0) { $0 + Int($1) }
        put(Data(String(format: "%06o\0 ", sum).utf8), at: 148)
        return Data(block)
    }

    func testABase256SizeOfAllOnesIsRefusedNotTrappedOn() {
        // Eleven 0xFF bytes after the base-256 marker: more bits than an Int holds.
        let tar =
            header(name: "member.bin", size: Data([0x80] + [UInt8](repeating: 0xFF, count: 11)), type: UInt8(ascii: "0"))
            + Data(repeating: 0x41, count: 512) + Data(count: 1024)
        XCTAssertTrue(TarIndex.isTar(head: tar.prefix(512)))
        XCTAssertThrowsError(try TarIndex.entries(in: tar)) { XCTAssertEqual($0 as? ArchiveError, .truncated) }
    }

    func testAnOctalSizePastTheFileIsTruncated() {
        let tar = header(name: "member.bin", size: Data("77777777777\0".utf8), type: UInt8(ascii: "0")) + Data(repeating: 0x41, count: 512)
        XCTAssertThrowsError(try TarIndex.entries(in: tar)) { XCTAssertEqual($0 as? ArchiveError, .truncated) }
    }

    func testANegativePaxSizeAndAnOversizeLongNameNeverIndexOutOfRange() throws {
        let record = Data("8 size=-5\n".utf8)
        var tar = header(name: "pax", size: Data(String(format: "%011o", record.count).utf8) + Data([0]), type: UInt8(ascii: "x"))
        tar += record + Data(count: 512 - record.count)
        tar += header(name: "member.txt", size: Data("00000000005\0".utf8), type: UInt8(ascii: "0"))
        tar += Data("hello".utf8) + Data(count: 507)
        // The pax size record is ignored (negative); the member lists with its own size.
        let listed = try TarIndex.entries(in: tar + Data(count: 1024))
        XCTAssertEqual(listed.map(\.path), ["member.txt"])
        XCTAssertEqual(listed.first?.size, 5)
        XCTAssertEqual(try TarIndex.data(for: listed[0], in: tar), Data("hello".utf8))
        // A GNU long-name header whose data runs past the file is a truncation, not a slice past the end.
        let longName = tar + header(name: "././@LongLink", size: Data("77777777777\0".utf8), type: UInt8(ascii: "L")) + Data(count: 1024)
        XCTAssertThrowsError(try TarIndex.entries(in: longName)) { XCTAssertEqual($0 as? ArchiveError, .truncated) }
        // A negative size on a file member is a lie about the data; the archive is refused.
        let negative = header(name: "neg.bin", size: Data([0xFF] + [UInt8](repeating: 0xFF, count: 11)), type: UInt8(ascii: "0"))
        XCTAssertThrowsError(try TarIndex.entries(in: negative + Data(count: 1024)))
    }

    func testATenLevelPathListsAsItsFolders() throws {
        let data = Data("deep\n".utf8)
        let tar =
            header(name: "a/b/c/d/e/f/g/h/i/j/deep.txt", size: Data(String(format: "%011o\0", data.count).utf8), type: UInt8(ascii: "0"))
            + data + Data(count: 512 - data.count) + Data(count: 1024)
        let listing = ArchiveListing(kind: .tar, entries: try TarIndex.entries(in: tar))
        XCTAssertEqual(listing.fileCount, 1)
        var node = listing.tree.first
        var depth = 0
        while let n = node, n.isDirectory { depth += 1; node = n.children.first }
        XCTAssertEqual(depth, 10)
        XCTAssertEqual(node?.name, "deep.txt")
    }

    // MARK: - Zip directories

    func le16(_ v: Int) -> Data { Data([UInt8(v & 0xFF), UInt8(v >> 8 & 0xFF)]) }
    func le32(_ v: Int) -> Data { Data((0..<4).map { UInt8(v >> (8 * $0) & 0xFF) }) }
    func le64(_ v: Int) -> Data { Data((0..<8).map { UInt8(v >> (8 * $0) & 0xFF) }) }

    func testAZip64DirectoryCountNoFileCouldHoldIsRefusedWithoutReservingIt() {
        var end64 = le32(0x0606_4B50) + le64(44) + le16(45) + le16(45) + le32(0) + le32(0)
        end64 += le64(1 << 40) + le64(1 << 40) + le64(0) + le64(0)
        let locator = le32(0x0706_4B50) + le32(0) + le64(0) + le32(1)
        var end = le32(0x0605_4B50) + le16(0) + le16(0) + le16(0xFFFF) + le16(0xFFFF)
        end += le32(0xFFFF_FFFF) + le32(0xFFFF_FFFF) + le16(0)
        XCTAssertThrowsError(try ZipIndex.entries(in: end64 + locator + end)) {
            XCTAssertTrue([ArchiveError.truncated, .notAnArchive].contains($0 as? ArchiveError), "\($0)")
        }
    }

    func testAMemberClaimingFourGigabytesListsAndRefusesToUnpack() throws {
        let member = Data("junk".utf8), name = Data("../../x".utf8), declared = 0xF000_0000
        var local = le32(0x0403_4B50) + le16(20) + le16(0) + le16(0) + le16(0) + le16(0)
        local += le32(0) + le32(declared) + le32(declared) + le16(name.count) + le16(0)
        local += name + member
        var central = le32(0x0201_4B50) + le16(20) + le16(20) + le16(0) + le16(0) + le16(0) + le16(0)
        central += le32(0) + le32(declared) + le32(declared) + le16(name.count) + le16(0) + le16(0)
        central += le16(0) + le16(0) + le32(0) + le32(0) + name
        var end = le32(0x0605_4B50) + le16(0) + le16(0) + le16(1) + le16(1)
        end += le32(central.count) + le32(local.count) + le16(0)
        let zip = local + central + end
        let entries = try ZipIndex.entries(in: zip)
        XCTAssertEqual(entries.map(\.path), ["../../x"])
        XCTAssertEqual(entries.first?.size, declared)
        XCTAssertEqual(entries.first?.name, "x", "the name a member is unpacked under is its last component")
        XCTAssertThrowsError(try ZipIndex.data(for: entries[0], in: zip)) { XCTAssertEqual($0 as? ArchiveError, .truncated) }
        XCTAssertEqual(ArchiveTree.build(entries).first?.name, "..", "a parent-relative path is shown as written, under a `..` folder")
    }

    func testAZip64LocatorPointingAtTheEndOfAnIntIsRefusedNotTrappedOn() {
        // The locator names an end record at Int.max: reading four bytes there must not add past an Int.
        let locator = le32(0x0706_4B50) + le32(0) + le64(Int.max) + le32(1)
        var end = le32(0x0605_4B50) + le16(0) + le16(0) + le16(0xFFFF) + le16(0xFFFF)
        end += le32(0xFFFF_FFFF) + le32(0xFFFF_FFFF) + le16(0)
        XCTAssertThrowsError(try ZipIndex.entries(in: locator + end)) {
            XCTAssertTrue([ArchiveError.truncated, .notAnArchive].contains($0 as? ArchiveError), "\($0)")
        }
        let reader = ByteReader(data: Data(count: 16))
        XCTAssertNil(reader.u32(Int.max))
        XCTAssertNil(reader.bytes(8, Int.max))
        XCTAssertNil(reader.u64(0 + 8 + 1))
    }

    func testDeclaredSizesThatSumPastAnIntAreHeldNotTrappedOn() {
        let huge = (0..<4).map {
            ArchiveEntry(path: "big-\($0).bin", size: Int.max / 2, compressedSize: 0, isDirectory: false, modified: nil, method: .stored)
        }
        XCTAssertEqual(ArchiveListing(kind: .zip, entries: huge).totalSize, Int.max)
        let inAFolder = huge.map {
            ArchiveEntry(path: "d/" + $0.path, size: $0.size, compressedSize: 0, isDirectory: false, modified: nil, method: .stored)
        }
        XCTAssertEqual(ArchiveTree.build(inAFolder).first?.size, Int.max)
    }

    func testAPathOfFortyThousandLevelsIsFoldedToTheDepthLimit() {
        let deep = String(repeating: "a/", count: 40_000) + "leaf.txt"
        let tree = ArchiveTree.build([
            ArchiveEntry(path: deep, size: 3, compressedSize: 3, isDirectory: false, modified: nil, method: .stored)
        ])
        var depth = 0
        var node = tree.first
        while let current = node, current.isDirectory { depth += 1; node = current.children.first }
        XCTAssertEqual(depth, ArchiveTree.depthLimit - 1)
        XCTAssertEqual(node?.path, deep, "the file keeps the path the archive wrote")
        XCTAssertEqual(tree.first?.size, 3)
        XCTAssertEqual(tree.first?.fileCount, 1)
    }
}
