import Testing
import Foundation
@testable import CreatureTrunk

/// B3 reducer tests — the reworked reducer produces per-grammar `NodeReadiness`
/// (one verdict per language that participates in a node), exercised with
/// SYNTHETIC diagnostics only (no subprocess, no real compiler). Assertions read
/// the DERIVED discrete `TrunkStatus.from(readiness:)` label.
///
/// THE BOUND is what these encode: a node can never be greener than its
/// enclosing scope's verdict. `scopeClean` (the compiler's affirmative exit-0)
/// is the ONLY thing that earns `green`. A diagnostic attributed to a node
/// refines *where* the breakage is; it never grants health. So when a scope
/// fails to type-check, its nodes are `.unknown` — not green, and not
/// necessarily red either. We simply cannot certify them.
///
/// Every node is given a Swift language channel so it PARTICIPATES in the
/// "swift" grammar — a node with no language channel participates in nothing.
@Suite struct DiagnosticReducerTests {

    /// Reduce synthetic diagnostics + one grammar's coverage to the discrete
    /// per-node `TrunkStatus`. `scopeClean` is REQUIRED — every test must state
    /// whether the compiler certified the scope, because that is the whole point.
    private func statuses(
        diagnostics: [Diagnostic],
        probedFiles: Set<String>,
        trunk: CodeTrunk,
        scopeClean: Bool,
        language: String = "swift",
        usrMap: [String: String]? = nil
    ) -> [String: TrunkStatus] {
        let coverage = DiagnosticReducer.GrammarCoverage(
            language: language, probedFiles: probedFiles,
            diagnostics: diagnostics, scopeClean: scopeClean,
            usrMap: usrMap
        )
        let readiness = DiagnosticReducer.reduce(coverages: [coverage], trunk: trunk)
        return readiness.mapValues { TrunkStatus.from(readiness: $0) }
    }

    /// A single Swift channel so a node participates in the "swift" grammar.
    private func swiftChannels() -> [TrunkChannel] {
        [TrunkChannel(index: 1, language: "swift", content: "")]
    }

    /// module (1..12) ⊃ type (2..10) ⊃ func (3..5), all in one file.
    private func makeSpannedTrunk(file: String = "Demo.swift") -> (trunk: CodeTrunk, moduleID: String, typeID: String, funcID: String) {
        var trunk = CodeTrunk()
        let moduleID = "module-1", typeID = "type-1", funcID = "func-1"

        trunk.add(TrunkNode(
            id: moduleID,
            coordinate: TrunkCoordinate(path: ["Demo"], kind: "module", truthKey: "m"),
            channels: swiftChannels(),
            span: SourceSpan(file: file, startLine: 1, endLine: 12)
        ))
        trunk.add(TrunkNode(
            id: typeID,
            coordinate: TrunkCoordinate(path: ["Demo", "Greeter"], kind: "struct", truthKey: "t"),
            channels: swiftChannels(),
            span: SourceSpan(file: file, startLine: 2, endLine: 10)
        ))
        trunk.add(TrunkNode(
            id: funcID,
            coordinate: TrunkCoordinate(path: ["Demo", "Greeter", "hello"], kind: "func", truthKey: "f"),
            channels: swiftChannels(),
            span: SourceSpan(file: file, startLine: 3, endLine: 5)
        ))
        return (trunk, moduleID, typeID, funcID)
    }

    /// A single node at /a.swift lines 2..3, id "func-node", for USR-based tests.
    private func makeTrunkWithUSR() -> (trunk: CodeTrunk, funcID: String) {
        var trunk = CodeTrunk()
        let funcID = "func-node"
        trunk.add(TrunkNode(
            id: funcID,
            coordinate: TrunkCoordinate(path: ["a"], kind: "func", truthKey: "f"),
            channels: swiftChannels(),
            span: SourceSpan(file: "/a.swift", startLine: 2, endLine: 3)
        ))
        return (trunk, funcID)
    }

    // MARK: - THE BOUND (the false-green regression guards)

    /// The single most important test in B3. A scope that did not type-check can
    /// contain NO green node — even when not one diagnostic could be attributed.
    /// This is the exact shape of the bug: swiftc exits 1, attribution finds
    /// nothing, and the old rule handed back green.
    @Test func scopeThatFailedToTypeCheckHasNoGreenNodes() {
        let (trunk, moduleID, typeID, funcID) = makeSpannedTrunk()

        // Compiler said the unit does NOT type-check, but no diagnostic reached
        // any node (attribution gap — a dropped diagnostic, a span miss, a path
        // mismatch: it does not matter which).
        let status = statuses(diagnostics: [], probedFiles: ["Demo.swift"], trunk: trunk, scopeClean: false)

        #expect(status[moduleID] == .unknown)
        #expect(status[typeID] == .unknown)
        #expect(status[funcID] == .unknown)
        // Stated explicitly: green-by-absence is dead.
        #expect(status[funcID] != .green)
        #expect(status[moduleID] != .green)
    }

    /// Attribution refines *where*; it never grants health. The node owning the
    /// error is red; its siblings are unknown (the scope failed), NOT green.
    @Test func attributionNarrowsBlameButSiblingsAreUnknownNotGreen() {
        let (trunk, moduleID, typeID, funcID) = makeSpannedTrunk()

        let diag = Diagnostic(
            file: "Demo.swift", startLine: 4, endLine: 4,
            severity: .error, message: "cannot find 'foo' in scope", producer: "test"
        )
        let status = statuses(diagnostics: [diag], probedFiles: ["Demo.swift"], trunk: trunk, scopeClean: false)

        #expect(status[funcID] == .red)       // innermost containing node owns it
        #expect(status[typeID] == .unknown)   // scope failed → cannot certify
        #expect(status[moduleID] == .unknown)
        #expect(status[typeID] != .green)
    }

    /// An unattributable diagnostic must NOT silently vanish. It can't redden a
    /// node, but the failed scope still prevents every node being certified.
    @Test func unattributableDiagnosticDoesNotVanishItBlocksCertification() {
        let (trunk, _, _, _) = makeSpannedTrunk()

        let stray = Diagnostic(
            file: "Nonexistent.swift", startLine: 1, endLine: 1,
            severity: .error, message: "stray", producer: "test"
        )
        let status = statuses(
            diagnostics: [stray],
            probedFiles: ["Demo.swift", "Nonexistent.swift"],
            trunk: trunk, scopeClean: false
        )

        // Nothing to attach to — but the evidence is not dropped on the floor:
        // the scope did not type-check, so nothing is green.
        #expect(status.values.allSatisfy { $0 == .unknown })
        #expect(status.values.allSatisfy { $0 != .green })
    }

    // MARK: - Attribution (innermost containment), on a clean-scope baseline

    @Test func diagnosticMapsToInnermostContainingNode() {
        let (trunk, moduleID, typeID, funcID) = makeSpannedTrunk()

        // Line 4 is inside func (3..5) ⊂ type (2..10) ⊂ module (1..12).
        let diag = Diagnostic(
            file: "Demo.swift", startLine: 4, endLine: 4,
            severity: .error, message: "cannot find 'foo' in scope", producer: "test"
        )
        let status = statuses(diagnostics: [diag], probedFiles: ["Demo.swift"], trunk: trunk, scopeClean: false)

        #expect(status[funcID] == .red)  // innermost wins, not the type or module
        #expect(status[typeID] != .red)
        #expect(status[moduleID] != .red)
    }

    @Test func diagnosticOnTypeButOutsideFunctionMapsToType() {
        let (trunk, moduleID, typeID, funcID) = makeSpannedTrunk()

        // Line 8: inside the type (2..10), outside the function (3..5).
        let diag = Diagnostic(
            file: "Demo.swift", startLine: 8, endLine: 8,
            severity: .error, message: "type error", producer: "test"
        )
        let status = statuses(diagnostics: [diag], probedFiles: ["Demo.swift"], trunk: trunk, scopeClean: false)

        #expect(status[typeID] == .red)
        #expect(status[funcID] != .red)
        #expect(status[moduleID] != .red)
    }

    @Test func moduleLevelDiagnosticWithNoContainingDeclAttachesToShallowestNode() {
        let (trunk, moduleID, typeID, funcID) = makeSpannedTrunk()

        // Line 1: only inside the module span, not the type or function.
        let diag = Diagnostic(
            file: "Demo.swift", startLine: 1, endLine: 1,
            severity: .error, message: "top-level error", producer: "test"
        )
        let status = statuses(diagnostics: [diag], probedFiles: ["Demo.swift"], trunk: trunk, scopeClean: false)

        #expect(status[moduleID] == .red)
        #expect(status[typeID] != .red)
        #expect(status[funcID] != .red)
    }

    @Test func overlappingDiagnosticsFoldWorstOf() {
        let (trunk, _, _, funcID) = makeSpannedTrunk()

        let warn = Diagnostic(file: "Demo.swift", startLine: 3, endLine: 3, severity: .warning, message: "warn", producer: "test")
        let err = Diagnostic(file: "Demo.swift", startLine: 5, endLine: 5, severity: .error, message: "err", producer: "test")
        let status = statuses(diagnostics: [warn, err], probedFiles: ["Demo.swift"], trunk: trunk, scopeClean: false)

        #expect(status[funcID] == .red)  // error beats warning on the same node
    }

    // MARK: - USR attribution

    @Test func diagnosticWithUSRMatchesNodeByUSR() {
        let (trunk, funcID) = makeTrunkWithUSR()

        // Diagnostic is on line 10 — outside the node's span (2..3) — but the USR
        // map should attribute it to func-node anyway.
        let diag = Diagnostic(
            file: "/a.swift", startLine: 10, endLine: 10,
            severity: .error, message: "type error", producer: "test",
            usr: "s:Func"
        )
        let status = statuses(
            diagnostics: [diag], probedFiles: ["/a.swift"], trunk: trunk,
            scopeClean: false, usrMap: ["s:Func": funcID]
        )

        #expect(status[funcID] == .red)
    }

    @Test func diagnosticWithoutUSRFallsBackToSpanMatch() {
        let (trunk, funcID) = makeTrunkWithUSR()

        // No USR — should fall back to span matching (line 2 is inside the span 2..3).
        let diag = Diagnostic(
            file: "/a.swift", startLine: 2, endLine: 2,
            severity: .error, message: "syntax error", producer: "test"
        )
        let status = statuses(
            diagnostics: [diag], probedFiles: ["/a.swift"], trunk: trunk,
            scopeClean: false, usrMap: nil
        )

        #expect(status[funcID] == .red)
    }

    // MARK: - Clean scope: green IS reachable, and warnings/notes behave

    @Test func cleanScopeWithNoDiagnosticsIsAllGreen() {
        let (trunk, moduleID, typeID, funcID) = makeSpannedTrunk()

        // The compiler affirmatively certified the unit. THIS is what earns green.
        let status = statuses(diagnostics: [], probedFiles: ["Demo.swift"], trunk: trunk, scopeClean: true)

        #expect(status[moduleID] == .green)
        #expect(status[typeID] == .green)
        #expect(status[funcID] == .green)
    }

    /// A warning does not fail the build, so the scope is still clean — the
    /// warned node drops to caution, its siblings stay green.
    @Test func warningOnCleanScopeMapsToYellowNotRed() {
        let (trunk, moduleID, _, funcID) = makeSpannedTrunk()

        let diag = Diagnostic(file: "Demo.swift", startLine: 4, endLine: 4, severity: .warning, message: "unused variable", producer: "test")
        let status = statuses(diagnostics: [diag], probedFiles: ["Demo.swift"], trunk: trunk, scopeClean: true)

        #expect(status[funcID] == .yellow)
        #expect(status[moduleID] == .green)
    }

    @Test func noteDoesNotWorsenStatusOnCleanScope() {
        let (trunk, _, _, funcID) = makeSpannedTrunk()

        let note = Diagnostic(file: "Demo.swift", startLine: 4, endLine: 4, severity: .note, message: "note: here", producer: "test")
        let status = statuses(diagnostics: [note], probedFiles: ["Demo.swift"], trunk: trunk, scopeClean: true)

        #expect(status[funcID] == .green)
    }

    // MARK: - Coverage: probed vs unprobed (void default)

    @Test func unprobedFileNodesAreUnknownNotGreen() {
        let (trunk, moduleID, typeID, funcID) = makeSpannedTrunk()

        // Probe set does NOT contain Demo.swift — even on a clean scope.
        let status = statuses(diagnostics: [], probedFiles: ["OtherFile.swift"], trunk: trunk, scopeClean: true)

        #expect(status[moduleID] == .unknown)
        #expect(status[typeID] == .unknown)
        #expect(status[funcID] == .unknown)
        #expect(status[moduleID] != .green)
    }

    @Test func nodeWithoutSpanIsUnknownEvenIfFileProbedAndScopeClean() {
        var trunk = CodeTrunk()
        trunk.add(TrunkNode(
            id: "no-span",
            coordinate: TrunkCoordinate(path: ["Demo", "x"], kind: "func", truthKey: "x"),
            channels: swiftChannels()
            // no span → we cannot know which file it is in
        ))

        let status = statuses(diagnostics: [], probedFiles: ["Demo.swift"], trunk: trunk, scopeClean: true)
        #expect(status["no-span"] == .unknown)
    }

    @Test func nodeWithoutLanguageChannelParticipatesInNothingAndIsUnknown() {
        var trunk = CodeTrunk()
        trunk.add(TrunkNode(
            id: "no-channel",
            coordinate: TrunkCoordinate(path: ["Demo", "y"], kind: "func", truthKey: "y"),
            channels: [], // no grammar channel → participates in nothing
            span: SourceSpan(file: "Demo.swift", startLine: 1, endLine: 3)
        ))

        let status = statuses(diagnostics: [], probedFiles: ["Demo.swift"], trunk: trunk, scopeClean: true)
        #expect(status["no-channel"] == .unknown)
    }

    @Test func mixedProbedAndUnprobedFilesInOneTrunk() {
        var trunk = CodeTrunk()
        trunk.add(TrunkNode(
            id: "probed",
            coordinate: TrunkCoordinate(path: ["A", "f"], kind: "func", truthKey: "af"),
            channels: swiftChannels(),
            span: SourceSpan(file: "A.swift", startLine: 1, endLine: 3)
        ))
        trunk.add(TrunkNode(
            id: "unprobed",
            coordinate: TrunkCoordinate(path: ["B", "g"], kind: "func", truthKey: "bg"),
            channels: swiftChannels(),
            span: SourceSpan(file: "B.swift", startLine: 1, endLine: 3)
        ))

        let status = statuses(diagnostics: [], probedFiles: ["A.swift"], trunk: trunk, scopeClean: true)

        #expect(status["probed"] == .green)
        #expect(status["unprobed"] == .unknown)
    }
}

/// The `unknown` status's ordering + worst-of semantics (D1).
@Suite struct TrunkStatusUnknownTests {

    @Test func rawValuesDidNotShift() {
        #expect(TrunkStatus.green.rawValue == 0)
        #expect(TrunkStatus.yellow.rawValue == 1)
        #expect(TrunkStatus.red.rawValue == 2)
        #expect(TrunkStatus.unknown.rawValue == 3)
    }

    @Test func severityCarriesTheSemanticOrdering() {
        // green < unknown < yellow < red — decoupled from rawValue.
        #expect(TrunkStatus.green.severity < TrunkStatus.unknown.severity)
        #expect(TrunkStatus.unknown.severity < TrunkStatus.yellow.severity)
        #expect(TrunkStatus.yellow.severity < TrunkStatus.red.severity)
    }

    @Test func comparableUsesSeverityNotRawValue() {
        #expect(TrunkStatus.green < TrunkStatus.unknown)
        #expect(TrunkStatus.unknown < TrunkStatus.yellow)
        #expect(TrunkStatus.yellow < TrunkStatus.red)
        #expect(TrunkStatus.unknown < TrunkStatus.red)
    }

    @Test func worstOfPairHonoursTheRequiredSemantics() {
        #expect(TrunkStatus.worst(.green, .unknown) == .unknown)  // unprobed blocks green
        #expect(TrunkStatus.worst(.yellow, .unknown) == .yellow)  // known warning worse than "didn't check"
        #expect(TrunkStatus.worst(.red, .unknown) == .red)
    }

    @Test func subtreeWithAnyUnknownDoesNotRollUpToGreen() {
        #expect(TrunkStatus.worst(of: [.green, .green, .unknown]) == .unknown)
        #expect(TrunkStatus.worst(of: [.green, .unknown, .red]) == .red)
    }

    @Test func codableRoundTripIncludingUnknown() throws {
        for status in TrunkStatus.allCases {
            let data = try JSONEncoder().encode(status)
            let decoded = try JSONDecoder().decode(TrunkStatus.self, from: data)
            #expect(decoded == status)
        }
    }

    @Test func unknownHasDistinctAtlasColour() {
        let unknown = TrunkAtlas.colour(for: .unknown)
        let green = TrunkAtlas.colour(for: .green)
        let red = TrunkAtlas.colour(for: .red)
        #expect(unknown.saturation == 0.0)
        #expect(green.saturation > 0.0)
        #expect(red.saturation > 0.0)
    }
}
