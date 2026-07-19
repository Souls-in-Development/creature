import Foundation
#if canImport(CryptoKit)
import CryptoKit
#else
// Apple's own cross-platform implementation of the same API (swift-crypto).
// Only SHA-256 is used, and it is source-identical on both.
import Crypto
#endif
import SwiftSyntax
import SwiftParser
import CreatureTrunk

/// The Swift cephalopod's first tentacle: an accurate, AST-based Swift
/// indexer built on SwiftSyntax/SwiftParser. Where `CodeIngester` (v0) is a
/// flat, regex-based skeleton over a whole file, `SwiftIndexer` walks the
/// real syntax tree and emits one `TrunkNode` per declaration — nested types,
/// nested methods, top-level functions, and top-level properties all land at
/// their real structural depth in the trunk.
///
/// Colour law is unchanged from `CodeIngester`: Channel 0 is the
/// language-agnostic white truth, Channel 1 is this declaration's own Swift
/// source text (chroma-tagged "swift"). `truthKey` reuses
/// `CodeIngester.truthHash` so Channel-0 skeletons produced here are hashed
/// identically to v0's — a `func name/<arity>` skeleton from this indexer and
/// from `CodeIngester` will share a `truthKey` if their skeleton text matches.
public enum SwiftIndexer {

    /// Index one Swift source file into a flat list of `TrunkNode`s — one per
    /// recognized declaration (struct/class/enum/actor/protocol/extension/
    /// func/init/var/let), nested or top-level.
    ///
    /// - Parameters:
    ///   - source: raw Swift source text.
    ///   - module: the enclosing module name — becomes `path[0]` for every
    ///     node this file produces.
    ///   - file: the source file path recorded on each node's `SourceSpan`
    ///     (see `TrunkNode.span`), so a compiler diagnostic reported at
    ///     `file:line:col` can be attributed back to the node it belongs to
    ///     (`DiagnosticReducer`). Defaults to `module` when a caller has no
    ///     real path (synthetic/single-string indexing) — spans are still
    ///     produced, just keyed by the module name; `WorkspaceIndexer` passes
    ///     the actual on-disk path so it matches `SwiftCompileProbe`'s files.
    public static func index(source: String, module: String, file: String? = nil) -> [TrunkNode] {
        let tree = Parser.parse(source: source)
        let visitor = DeclarationVisitor(module: module, file: file ?? module, tree: tree)
        visitor.walk(tree)
        return visitor.nodes
    }

    /// Index one Swift source file the same way `index(source:module:)` does,
    /// but also compute each node's own Atlas status — the input
    /// `TrunkAtlas` needs (see `TrunkAtlas.leafStatus`).
    ///
    /// Status rule (v0, syntactic validity only — see `TrunkStatus`'s doc
    /// comment for the honest scope): a node is `.red` if the syntax subtree
    /// for its own declaration contains a parse error — i.e.
    /// `SyntaxProtocol.hasError` is true for that declaration's node — and
    /// `.green` otherwise. `hasError` (declared in
    /// `swift-syntax/Sources/SwiftSyntax/SyntaxProtocol.swift`) is true when
    /// the subtree contains a missing node, an unexpected node, or a token
    /// carrying an error-severity `TokenDiagnostic` — exactly "this
    /// declaration didn't parse cleanly," which is what v0 promises and no
    /// more.
    ///
    /// - Returns: the same flat node list `index(source:module:)` would
    ///   produce, plus a `[String: TrunkStatus]` keyed by `TrunkNode.id`
    ///   (only entries that are `.red` are actually needed by `TrunkAtlas`,
    ///   which defaults absent ids to `.green` — but this includes every
    ///   node's status explicitly for callers that want it without relying
    ///   on that default).
    public static func indexWithStatus(
        source: String,
        module: String,
        file: String? = nil
    ) -> (nodes: [TrunkNode], status: [String: TrunkStatus]) {
        let tree = Parser.parse(source: source)
        let visitor = DeclarationVisitor(module: module, file: file ?? module, tree: tree, computeStatus: true)
        visitor.walk(tree)
        return (visitor.nodes, visitor.status)
    }
}

/// One declaration found while walking the tree, before it's turned into a
/// `TrunkNode` — captured at `visit` time (so the enclosing scope stack is
/// correct) and materialized once traversal finishes.
private struct FoundDeclaration {
    let path: [String]
    let kind: String
    let skeletonLine: String
    let sourceText: String
}

/// Walks a parsed `SourceFileSyntax`, maintaining a stack of enclosing
/// container names (module + nested types) so every declaration's
/// `TrunkCoordinate.path` reflects its real nesting, not just its position in
/// a flat file.
///
/// Container decls (struct/class/enum/actor/protocol/extension) push their
/// name on `visit` and pop it on `visitPost` — SwiftSyntax guarantees
/// `visitPost` for a node fires after all of that node's descendants have
/// been visited, so the stack is always accurate for whatever is currently
/// being visited.
final class DeclarationVisitor: SyntaxVisitor {
    private let module: String
    private let computeStatus: Bool
    /// The source file path stamped onto every node's `SourceSpan` (see
    /// `TrunkNode.span`). Matches whatever the entry point was given — the real
    /// on-disk path from `WorkspaceIndexer`, or the module name as a fallback.
    private let file: String
    /// Maps a declaration's syntax range to 1-based source line numbers, so
    /// each node carries the `[startLine, endLine]` the `DiagnosticReducer`
    /// needs to attribute compiler diagnostics back to it.
    private let locationConverter: SourceLocationConverter
    private var scopeStack: [String] = []
    private(set) var nodes: [TrunkNode] = []
    /// Per-node Atlas status, keyed by `TrunkNode.id`. Only populated when
    /// `computeStatus` is true (`indexWithStatus`); left empty for the plain
    /// `index(source:module:)` path so that call stays exactly as cheap as
    /// before this type existed.
    private(set) var status: [String: TrunkStatus] = [:]
    /// Stack of leaf declaration ids currently being visited (for bridge extraction).
    private(set) var leafStack: [String] = []
    /// Parallel stack tracking how many leaf ids to pop per VariableDeclSyntax.
    private var varDeclPopCounts: [Int] = []
    /// Collected unresolved call edges from function bodies.
    fileprivate(set) var edges: [UnresolvedEdge] = []

    init(module: String, file: String, tree: SourceFileSyntax, computeStatus: Bool = false) {
        self.module = module
        self.file = file
        self.computeStatus = computeStatus
        self.locationConverter = SourceLocationConverter(fileName: file, tree: tree)
        super.init(viewMode: .sourceAccurate)
    }

    private var currentPath: [String] { [module] + scopeStack }

    // MARK: - Container declarations (push/pop scope)

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        enterContainer(name: node.name.text, kind: "struct", node: node)
        return .visitChildren
    }
    override func visitPost(_ node: StructDeclSyntax) { exitContainer() }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        enterContainer(name: node.name.text, kind: "class", node: node)
        return .visitChildren
    }
    override func visitPost(_ node: ClassDeclSyntax) { exitContainer() }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        let caseCount = countEnumCases(in: node)
        recordLeaf(
            name: node.name.text,
            kind: "enum",
            skeletonLine: "enum \(node.name.text)/\(caseCount)",
            sourceText: node.trimmedDescription,
            hasError: node.hasError,
            span: span(of: node)
        )
        enterContainer(name: node.name.text, kind: "enum", node: node, alreadyRecorded: true)
        return .visitChildren
    }
    override func visitPost(_ node: EnumDeclSyntax) { exitContainer() }

    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        enterContainer(name: node.name.text, kind: "actor", node: node)
        return .visitChildren
    }
    override func visitPost(_ node: ActorDeclSyntax) { exitContainer() }

    override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
        enterContainer(name: node.name.text, kind: "protocol", node: node)
        return .visitChildren
    }
    override func visitPost(_ node: ProtocolDeclSyntax) { exitContainer() }

    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        // Extensions have no name token of their own — their identity is the
        // extended type's name (e.g. `extension Foo { ... }` extends "Foo").
        let extendedName = node.extendedType.trimmedDescription
        recordLeaf(
            name: extendedName,
            kind: "extension",
            skeletonLine: "extension \(extendedName)",
            sourceText: extensionSignatureText(node),
            hasError: node.hasError,
            span: span(of: node)
        )
        scopeStack.append(extendedName)
        return .visitChildren
    }
    override func visitPost(_ node: ExtensionDeclSyntax) {
        scopeStack.removeLast()
    }

    // MARK: - Leaf declarations (no scope push, but leaf stack tracking for bridge extraction)

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        let name = node.name.text
        let arity = node.signature.parameterClause.parameters.count
        let id = recordLeaf(
            name: name,
            kind: "func",
            skeletonLine: "func \(name)/\(arity)",
            sourceText: node.trimmedDescription,
            hasError: node.hasError,
            span: span(of: node)
        )
        leafStack.append(id)
        // Function bodies can contain local types/functions; keep walking so
        // those still get indexed, nested under this function's name.
        return .visitChildren
    }
    override func visitPost(_ node: FunctionDeclSyntax) {
        leafStack.removeLast()
    }

    override func visit(_ node: InitializerDeclSyntax) -> SyntaxVisitorContinueKind {
        let arity = node.signature.parameterClause.parameters.count
        let id = recordLeaf(
            name: "init",
            kind: "init",
            skeletonLine: "init/\(arity)",
            sourceText: node.trimmedDescription,
            hasError: node.hasError,
            span: span(of: node)
        )
        leafStack.append(id)
        return .visitChildren
    }
    override func visitPost(_ node: InitializerDeclSyntax) {
        leafStack.removeLast()
    }

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        // A single `var`/`let` decl can bind multiple names, e.g.
        // `var a, b: Int` — emit one TrunkNode per bound identifier.
        let bindingSpecifier = node.bindingSpecifier.text // "var" or "let"
        let declSpan = span(of: node)
        var pushedCount = 0
        for binding in node.bindings {
            guard let identifierPattern = binding.pattern.as(IdentifierPatternSyntax.self) else {
                continue
            }
            let name = identifierPattern.identifier.text
            let id = recordLeaf(
                name: name,
                kind: bindingSpecifier,
                skeletonLine: "\(bindingSpecifier) \(name)",
                sourceText: node.trimmedDescription,
                hasError: node.hasError,
                span: declSpan
            )
            leafStack.append(id)
            pushedCount += 1
        }
        varDeclPopCounts.append(pushedCount)
        // Computed property bodies may contain calls; walk them.
        return .visitChildren
    }
    override func visitPost(_ node: VariableDeclSyntax) {
        let popCount = varDeclPopCounts.removeLast()
        for _ in 0..<popCount {
            leafStack.removeLast()
        }
    }

    // MARK: - Call extraction (bridge edges)

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        guard let currentLeaf = leafStack.last else {
            return .visitChildren
        }
        let name: String
        if let declRef = node.calledExpression.as(IdentifierExprSyntax.self) {
            name = declRef.baseName.text
        } else if let memberAccess = node.calledExpression.as(MemberAccessExprSyntax.self) {
            name = memberAccess.declName.baseName.text
        } else {
            return .visitChildren
        }
        let arity = node.arguments.count
        let skeleton = "func \(name)/\(arity)"
        let truthKey = CodeIngester.truthHash(of: skeleton)
        edges.append(UnresolvedEdge(
            source: currentLeaf,
            targetTruthKey: truthKey,
            kind: .call
        ))
        return .visitChildren
    }

    // MARK: - Scope management

    private func enterContainer(
        name: String,
        kind: String,
        node: some SyntaxProtocol,
        alreadyRecorded: Bool = false
    ) {
        if !alreadyRecorded {
            recordLeaf(
                name: name,
                kind: kind,
                skeletonLine: "\(kind) \(name)",
                sourceText: node.trimmedDescription,
                hasError: node.hasError,
                span: span(of: node)
            )
        }
        scopeStack.append(name)
    }

    private func exitContainer() {
        scopeStack.removeLast()
    }

    /// Record one declaration at the *current* scope (before any push for
    /// this same declaration, if it is itself a container) and turn it
    /// straight into a `TrunkNode`.
    ///
    /// - Parameter hasError: this declaration's own `SyntaxProtocol.hasError`
    ///   (see `SwiftIndexer.indexWithStatus`'s doc comment) — recorded into
    ///   `status` only when `computeStatus` is true, so the plain `index`
    ///   entry point pays nothing for a signal it doesn't ask for.
    /// - Parameter span: this declaration's source line range (see
    ///   `span(of:)`), recorded on the node so a compiler diagnostic can be
    ///   attributed back to it by `DiagnosticReducer`.
    /// - Returns: the `id` of the newly created `TrunkNode`.
    @discardableResult
    private func recordLeaf(name: String, kind: String, skeletonLine: String, sourceText: String, hasError: Bool, span: SourceSpan) -> String {
        let path = currentPath + [name]
        let truthKey = CodeIngester.truthHash(of: skeletonLine)

        let coordinate = TrunkCoordinate(
            path: path,
            kind: kind,
            truthKey: truthKey
        )

        let channel0 = TrunkChannel(index: 0, language: "rosetta", content: skeletonLine)
        let channel1 = TrunkChannel(index: 1, language: "swift", content: sourceText)

        let id = "\(path.joined(separator: "/"))#swift"

        nodes.append(TrunkNode(id: id, coordinate: coordinate, channels: [channel0, channel1], span: span))

        if computeStatus {
            status[id] = hasError ? .red : .green
        }
        return id
    }

    /// The 1-based inclusive source line range of a declaration, as a
    /// `SourceSpan` keyed by this visitor's `file`. Uses the `positionAfterSkippingLeadingTrivia`
    /// so a decl's span starts at its first real token (not at its leading
    /// comments/whitespace), giving a tight range for innermost-node
    /// attribution.
    private func span(of node: some SyntaxProtocol) -> SourceSpan {
        let start = locationConverter.location(for: node.positionAfterSkippingLeadingTrivia)
        let end = locationConverter.location(for: node.endPositionBeforeTrailingTrivia)
        return SourceSpan(file: file, startLine: start.line, endLine: end.line)
    }

    /// Enum case count: sum of `EnumCaseElementListSyntax` elements across
    /// every `case ...` decl directly in the enum's member block (does not
    /// recurse into nested types' own cases).
    private func countEnumCases(in node: EnumDeclSyntax) -> Int {
        node.memberBlock.members.reduce(0) { total, member in
            guard let caseDecl = member.decl.as(EnumCaseDeclSyntax.self) else { return total }
            return total + caseDecl.elements.count
        }
    }

    /// `extension Foo: Bar { ... }` signature text without the member block
    /// body, for a Channel-1 rendering that stays a "declaration", not the
    /// whole extension body (the body's own declarations get their own nodes).
    private func extensionSignatureText(_ node: ExtensionDeclSyntax) -> String {
        var signatureNode = node
        signatureNode.memberBlock = MemberBlockSyntax(members: [])
        return signatureNode.trimmedDescription
    }
}
