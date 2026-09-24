//
//  ArchiveNode.swift
//  ArchiveIndex
//
//  A folded view of an archive's entries: folders holding files, folders first.
//
//  Created by David Sherlock on 9/24/26.
//

import Foundation

/// A node of the tree `ArchiveTree.build` folds an archive's flat paths into. A reference type
/// so an outline view can use nodes as its items; built whole before it is handed out and never
/// mutated after, which is what makes the `@unchecked Sendable` honest.
public final class ArchiveNode: @unchecked Sendable {
    /// The node's own name (no path).
    public let name: String
    /// The full path inside the archive — for a file, the entry's path to extract by.
    public let path: String
    /// Whether the node is a folder.
    public let isDirectory: Bool
    /// A file's unpacked size; a folder's is the sum of everything beneath it.
    public private(set) var size: Int
    /// A folder's children, folders first, each group in Finder's order.
    public private(set) var children: [ArchiveNode] = []

    init(name: String, path: String, isDirectory: Bool, size: Int) {
        self.name = name; self.path = path; self.isDirectory = isDirectory; self.size = size
    }

    func append(_ child: ArchiveNode) { children.append(child) }
    func settle() {
        children.sort { $0.isDirectory != $1.isDirectory ? $0.isDirectory : $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        for child in children { child.settle() }
        if isDirectory { size = children.reduce(0) { $0 + $1.size } }
    }

    /// How many files (not folders) the node holds, itself included when it is one.
    public var fileCount: Int { isDirectory ? children.reduce(0) { $0 + $1.fileCount } : 1 }
}
