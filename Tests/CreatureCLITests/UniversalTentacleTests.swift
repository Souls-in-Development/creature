import Testing
import Foundation
@testable import CreatureCLI
import CreatureWorkspace
import CreatureTrunk

/// Universality: every catalogued language (not just Swift/Python) is indexed
/// into the trunk via the `.universal` regex tentacle — structurally present,
/// linkable across languages by shape, and honestly UNKNOWN (never green,
/// because no compiler probe stands behind a regex header-scan).
@Suite struct UniversalTentacleTests {

    @Test func recognisesCataloguedNonSwiftPythonExtensions() {
        // Dedicated AST tentacles.
        #expect(Tentacle(filePath: "a.swift")?.language == "swift")
        #expect(Tentacle(filePath: "a.py")?.language == "python")

        // Universal tentacle, resolved from the bundled catalogue.
        #expect(Tentacle(filePath: "a.rs")?.language == "rust")
        #expect(Tentacle(filePath: "a.ts")?.language == "typescript")
        #expect(Tentacle(filePath: "a.go")?.language == "go")
        #expect(Tentacle(filePath: "a.rb")?.language == "ruby")

        // A genuinely unknown extension stays unindexable.
        #expect(Tentacle(filePath: "a.zzz") == nil)
    }

    @Test func universalTentacleIsTheUniversalCase() {
        guard case .universal(let lang)? = Tentacle(filePath: "x.go") else {
            Issue.record("expected .universal for a .go file")
            return
        }
        #expect(lang == "go")
    }

    @Test func rustFunctionSkeletonMatchesSwiftAndPythonShape() {
        // A Rust `fn add(a, b)`, a Swift `func add(a:b:)`, and a Python
        // `def add(a, b)` must all normalise to the same Channel-0 skeleton
        // `func add/2` — that shared shape is what links them by truthKey.
        let rust = Tentacle(filePath: "lib.rs")!
            .index(source: "fn add(a: i32, b: i32) -> i32 { a + b }", module: "lib")
        #expect(rust.count == 1)
        let skeleton = rust[0].channel(at: 0)?.content ?? ""
        #expect(skeleton.contains("func add/2"))
    }

    @Test func universalNodesAreUnknownNeverGreen() {
        // THE BOUND: a regex header-scan cannot certify a file compiles, so a
        // universal-language node must be `.unknown` — surfacing that green is
        // not being claimed — not `.green`.
        let (nodes, status) = Tentacle(filePath: "app.ts")!
            .indexWithStatus(source: "function greet(name) { return name; }", module: "app")
        #expect(nodes.count == 1)
        let s = status[nodes[0].id]
        #expect(s == .unknown)
        #expect(s != .green)
    }

    @Test func universalExtractsTypesAcrossKeywords() {
        // The generic extractor recognises type/scope declarations by keyword,
        // keeping the keyword as the kind so a Rust `trait` and a TS `interface`
        // stay distinguishable in the skeleton.
        let go = Tentacle(filePath: "srv.go")!
            .index(source: "type Server struct { port int }\nfunc Serve() {}", module: "srv")
        let skeleton = go[0].channel(at: 0)?.content ?? ""
        #expect(skeleton.contains("func Serve/0"))
        #expect(skeleton.contains("struct Server") || skeleton.contains("type Server"))
    }
}
