import Testing
import Foundation
@testable import CreatureTrunk

@Suite struct TrunkBridgeTests {

    @Test func emptyBridgeHasNoEdges() {
        let bridge = TrunkBridge()
        #expect(bridge.edges.isEmpty)
        #expect(bridge.edges(from: "any").isEmpty)
        #expect(bridge.edges(to: "any").isEmpty)
    }

    @Test func addEdgeAndRetrieve() {
        var bridge = TrunkBridge()
        let edge = TrunkEdge(source: "a", target: "b", kind: .call)
        bridge.add(edge)
        #expect(bridge.edges.count == 1)
        #expect(bridge.edges(from: "a").first?.target == "b")
        #expect(bridge.edges(to: "b").first?.source == "a")
        #expect(bridge.targets(of: "a") == ["b"])
        #expect(bridge.sources(of: "b") == ["a"])
    }

    @Test func edgeHashableAndEquatable() {
        let e1 = TrunkEdge(source: "a", target: "b", kind: .call)
        let e2 = TrunkEdge(source: "a", target: "b", kind: .call)
        let e3 = TrunkEdge(source: "a", target: "b", kind: .reference)
        #expect(e1 == e2)
        #expect(e1.hashValue == e2.hashValue)
        #expect(e1 != e3)
    }

    @Test func edgeKindRawValue() {
        #expect(TrunkEdgeKind.call.rawValue == "call")
        #expect(TrunkEdgeKind.reference.rawValue == "reference")
        #expect(TrunkEdgeKind.typeDependency.rawValue == "typeDependency")
    }

    @Test func codableRoundTrip() throws {
        var bridge = TrunkBridge()
        bridge.add(TrunkEdge(source: "a", target: "b", kind: .call))
        let data = try JSONEncoder().encode(bridge)
        let decoded = try JSONDecoder().decode(TrunkBridge.self, from: data)
        #expect(decoded.edges.count == 1)
        #expect(decoded.edges.first?.source == "a")
        #expect(decoded.edges.first?.target == "b")
        #expect(decoded.edges.first?.kind == .call)
    }
}

@Suite struct TrunkBridgeResolutionTests {

    private func makeTrunk() -> CodeTrunk {
        var trunk = CodeTrunk()
        // Two functions with the SAME truthKey — simulating cross-language link
        let coordA = TrunkCoordinate(path: ["Module", "add"], kind: "func", truthKey: "hash_add2")
        let coordB = TrunkCoordinate(path: ["Module", "Calculator", "sum"], kind: "func", truthKey: "hash_sum2")
        let coordC = TrunkCoordinate(path: ["Module", "add"], kind: "func", truthKey: "hash_add2")
        trunk.add(TrunkNode(id: "add", coordinate: coordA, channels: []))
        trunk.add(TrunkNode(id: "sum", coordinate: coordB, channels: []))
        trunk.add(TrunkNode(id: "add_py", coordinate: coordC, channels: []))
        return trunk
    }

    @Test func resolveUnresolvedEdgeToConcreteNode() {
        let trunk = makeTrunk()
        let unresolved = [UnresolvedEdge(source: "sum", targetTruthKey: "hash_add2", kind: .call)]
        let bridge = TrunkBridge.resolve(unresolved: unresolved, against: trunk)

        // sum calls add/2; there are TWO nodes with that truthKey (add and add_py)
        // — conservative over-approximation creates both edges.
        #expect(bridge.edges.count == 2)
        #expect(bridge.edges.contains { $0.source == "sum" && $0.target == "add" })
        #expect(bridge.edges.contains { $0.source == "sum" && $0.target == "add_py" })
    }

    @Test func unresolvedEdgeWithNoMatchProducesNoEdges() {
        let trunk = makeTrunk()
        let unresolved = [UnresolvedEdge(source: "sum", targetTruthKey: "does_not_exist", kind: .call)]
        let bridge = TrunkBridge.resolve(unresolved: unresolved, against: trunk)
        #expect(bridge.edges.isEmpty)
    }

    @Test func multipleUnresolvedEdgesResolveCorrectly() {
        let trunk = makeTrunk()
        let unresolved = [
            UnresolvedEdge(source: "sum", targetTruthKey: "hash_add2", kind: .call),
            UnresolvedEdge(source: "add", targetTruthKey: "hash_sum2", kind: .call)
        ]
        let bridge = TrunkBridge.resolve(unresolved: unresolved, against: trunk)
        // sum→add, sum→add_py, add→sum
        #expect(bridge.edges.count == 3)
    }
}

@Suite struct TrunkAtlasEdgePropagationTests {

    /// The core demo: a function `add` is broken (red). Its caller `calculate`
    /// is green on its own, but turns red via edge propagation because it
    /// depends on `add`.
    @Test func brokenCalleeReddensCaller() {
        var trunk = CodeTrunk()
        let addCoord = TrunkCoordinate(path: ["Demo", "add"], kind: "func", truthKey: "add2")
        let calcCoord = TrunkCoordinate(path: ["Demo", "calculate"], kind: "func", truthKey: "calc0")
        trunk.add(TrunkNode(id: "add", coordinate: addCoord, channels: []))
        trunk.add(TrunkNode(id: "calc", coordinate: calcCoord, channels: []))

        let leafStatus: [String: TrunkStatus] = ["add": .red, "calc": .green]
        let bridge = TrunkBridge(edges: [
            TrunkEdge(source: "calc", target: "add", kind: .call)
        ])
        let atlas = TrunkAtlas(trunk: trunk, leafStatus: leafStatus, bridge: bridge)

        // add is red on its own
        #expect(atlas.ownStatus(for: "add") == .red)
        // calc is green on its own (no syntax error in calc)
        #expect(atlas.ownStatus(for: "calc") == .green)
        // but calc's rolled-up status is red because it depends on add
        #expect(atlas.status(for: "calc") == .red)
        // add's rolled-up status is also red (its own status)
        #expect(atlas.status(for: "add") == .red)
        // overall is red
        #expect(atlas.overall == .red)
    }

    /// A sibling that does NOT call the broken function stays green.
    @Test func siblingCallerNotAffected() {
        var trunk = CodeTrunk()
        let addCoord = TrunkCoordinate(path: ["Demo", "add"], kind: "func", truthKey: "add2")
        let calcCoord = TrunkCoordinate(path: ["Demo", "calculate"], kind: "func", truthKey: "calc0")
        let otherCoord = TrunkCoordinate(path: ["Demo", "other"], kind: "func", truthKey: "other0")
        trunk.add(TrunkNode(id: "add", coordinate: addCoord, channels: []))
        trunk.add(TrunkNode(id: "calc", coordinate: calcCoord, channels: []))
        trunk.add(TrunkNode(id: "other", coordinate: otherCoord, channels: []))

        let leafStatus: [String: TrunkStatus] = ["add": .red, "calc": .green, "other": .green]
        let bridge = TrunkBridge(edges: [
            TrunkEdge(source: "calc", target: "add", kind: .call)
        ])
        let atlas = TrunkAtlas(trunk: trunk, leafStatus: leafStatus, bridge: bridge)

        #expect(atlas.status(for: "calc") == .red)
        #expect(atlas.status(for: "other") == .green)
        #expect(atlas.status(for: "add") == .red)
    }

    /// No bridge → no edge propagation (backward compatibility).
    @Test func nilBridgeMeansNoPropagation() {
        var trunk = CodeTrunk()
        let addCoord = TrunkCoordinate(path: ["Demo", "add"], kind: "func", truthKey: "add2")
        let calcCoord = TrunkCoordinate(path: ["Demo", "calculate"], kind: "func", truthKey: "calc0")
        trunk.add(TrunkNode(id: "add", coordinate: addCoord, channels: []))
        trunk.add(TrunkNode(id: "calc", coordinate: calcCoord, channels: []))

        let leafStatus: [String: TrunkStatus] = ["add": .red, "calc": .green]
        let atlas = TrunkAtlas(trunk: trunk, leafStatus: leafStatus, bridge: nil)

        // calc stays green because there's no bridge
        #expect(atlas.status(for: "calc") == .green)
        #expect(atlas.overall == .red) // because add itself is red
    }

    /// Multiple edges from one source: all targets are considered.
    @Test func multipleTargetsWorstWins() {
        var trunk = CodeTrunk()
        let a = TrunkCoordinate(path: ["Demo", "a"], kind: "func", truthKey: "a")
        let b = TrunkCoordinate(path: ["Demo", "b"], kind: "func", truthKey: "b")
        let c = TrunkCoordinate(path: ["Demo", "c"], kind: "func", truthKey: "c")
        trunk.add(TrunkNode(id: "a", coordinate: a, channels: []))
        trunk.add(TrunkNode(id: "b", coordinate: b, channels: []))
        trunk.add(TrunkNode(id: "c", coordinate: c, channels: []))

        let leafStatus: [String: TrunkStatus] = ["b": .yellow]
        let bridge = TrunkBridge(edges: [
            TrunkEdge(source: "a", target: "b", kind: .call),
            TrunkEdge(source: "a", target: "c", kind: .call)
        ])
        let atlas = TrunkAtlas(trunk: trunk, leafStatus: leafStatus, bridge: bridge)

        // a depends on b (yellow) and c (green) → worst is yellow
        #expect(atlas.status(for: "a") == .yellow)
    }

    /// Structural roll-up + edge propagation together: a red leaf inside a
    /// container + a broken dependency both redden the container.
    @Test func structuralAndEdgePropagationTogether() {
        var trunk = CodeTrunk()
        let module = TrunkCoordinate(path: ["Demo"], kind: "module", truthKey: "m")
        let addCoord = TrunkCoordinate(path: ["Demo", "add"], kind: "func", truthKey: "add2")
        let calcCoord = TrunkCoordinate(path: ["Demo", "calculate"], kind: "func", truthKey: "calc0")
        trunk.add(TrunkNode(id: "demo", coordinate: module, channels: []))
        trunk.add(TrunkNode(id: "add", coordinate: addCoord, channels: []))
        trunk.add(TrunkNode(id: "calc", coordinate: calcCoord, channels: []))

        let leafStatus: [String: TrunkStatus] = ["add": .red]
        let bridge = TrunkBridge(edges: [
            TrunkEdge(source: "calc", target: "add", kind: .call)
        ])
        let atlas = TrunkAtlas(trunk: trunk, leafStatus: leafStatus, bridge: bridge)

        // Module is red because add is red (structural descendance)
        // AND because calc is red (structural descendance) due to edge propagation
        #expect(atlas.status(for: "demo") == .red)
        #expect(atlas.status(for: "calc") == .red)
        #expect(atlas.status(for: "add") == .red)
    }
}
