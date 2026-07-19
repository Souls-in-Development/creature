import Foundation
import SwiftSyntax
import SwiftParser
import CreatureTrunk

extension SwiftIndexer {

    /// Index one Swift source file the same way `indexWithStatus(source:module:)`
    /// does, but also collect `UnresolvedEdge` objects for every function call
    /// found inside a leaf declaration body.
    ///
    /// - Parameters:
    ///   - source: raw Swift source text.
    ///   - module: the enclosing module name — becomes `path[0]` for every
    ///     node this file produces.
    ///   - file: the source file path recorded on each node's `SourceSpan`
    ///     (see `SwiftIndexer.index(source:module:file:)`). Defaults to
    ///     `module` when absent; `WorkspaceIndexer` passes the real on-disk
    ///     path so spans match `SwiftCompileProbe`'s probed files.
    /// - Returns: the flat node list, the per-node status map, and the list of
    ///   unresolved call edges extracted from function bodies.
    public static func indexWithBridge(
        source: String,
        module: String,
        file: String? = nil
    ) -> (nodes: [TrunkNode], status: [String: TrunkStatus], edges: [UnresolvedEdge]) {
        let tree = Parser.parse(source: source)
        let visitor = DeclarationVisitor(module: module, file: file ?? module, tree: tree, computeStatus: true)
        visitor.walk(tree)
        return (visitor.nodes, visitor.status, visitor.edges)
    }
}
