import Testing
import Foundation
@testable import CreatureTrunk

@Suite struct IncrementalUpdaterTests {

    // MARK: - Helpers

    private func makeSimpleTree() -> (trunk: CodeTrunk, moduleID: String, typeID: String, funcID: String) {
        var trunk = CodeTrunk()
        let moduleCoord = TrunkCoordinate(path: ["Demo"], kind: "module", truthKey: "module")
        let typeCoord = TrunkCoordinate(path: ["Demo", "Greeter"], kind: "struct", truthKey: "type")
        let funcCoord = TrunkCoordinate(path: ["Demo", "Greeter", "hello"], kind: "func", truthKey: "func")
        trunk.add(TrunkNode(id: "module", coordinate: moduleCoord, channels: []))
        trunk.add(TrunkNode(id: "type", coordinate: typeCoord, channels: []))
        trunk.add(TrunkNode(id: "func", coordinate: funcCoord, channels: []))
        return (trunk, "module", "type", "func")
    }

    private func fullRebuild(
        trunk: CodeTrunk,
        leafStatus: [String: TrunkStatus],
        bridge: TrunkBridge? = nil
    ) -> [String: TrunkStatus] {
        let tree = TreeIndex.from(nodes: trunk.nodes)
        let engine = RollUpEngine(tree: tree, leafStatus: leafStatus, bridge: bridge)
        return engine.compute()
    }

    // MARK: - Structural propagation

    @Test func structuralLeafToRedRollsUpAncestors() {
        let (trunk, moduleID, typeID, funcID) = makeSimpleTree()
        var leafStatus: [String: TrunkStatus] = [
            moduleID: .green,
            typeID: .green,
            funcID: .green
        ]
        let tree = TreeIndex.from(nodes: trunk.nodes)
        let engine = RollUpEngine(tree: tree, leafStatus: leafStatus)
        var updater = IncrementalUpdater(
            tree: tree,
            rolledUpStatus: engine.compute(),
            leafStatus: leafStatus
        )

        let changed = updater.update(nodeID: funcID, to: .red)

        #expect(changed[funcID] == .red)
        #expect(changed[typeID] == .red)
        #expect(changed[moduleID] == .red)
        #expect(updater.rolledUpStatus[funcID] == .red)
        #expect(updater.rolledUpStatus[typeID] == .red)
        #expect(updater.rolledUpStatus[moduleID] == .red)
    }

    @Test func structuralLeafToGreenRollsUpGreen() {
        let (trunk, moduleID, typeID, funcID) = makeSimpleTree()
        var leafStatus: [String: TrunkStatus] = [
            moduleID: .green,
            typeID: .green,
            funcID: .red
        ]
        let tree = TreeIndex.from(nodes: trunk.nodes)
        let engine = RollUpEngine(tree: tree, leafStatus: leafStatus)
        var updater = IncrementalUpdater(
            tree: tree,
            rolledUpStatus: engine.compute(),
            leafStatus: leafStatus
        )

        let changed = updater.update(nodeID: funcID, to: .green)

        #expect(changed[funcID] == .green)
        #expect(changed[typeID] == .green)
        #expect(changed[moduleID] == .green)
    }

    @Test func structuralUnknownBlocksGreen() {
        let (trunk, moduleID, typeID, funcID) = makeSimpleTree()
        var leafStatus: [String: TrunkStatus] = [
            moduleID: .green,
            typeID: .green,
            funcID: .green
        ]
        let tree = TreeIndex.from(nodes: trunk.nodes)
        let engine = RollUpEngine(tree: tree, leafStatus: leafStatus)
        var updater = IncrementalUpdater(
            tree: tree,
            rolledUpStatus: engine.compute(),
            leafStatus: leafStatus
        )

        let changed = updater.update(nodeID: funcID, to: .unknown)

        #expect(changed[funcID] == .unknown)
        #expect(changed[typeID] == .unknown)
        #expect(changed[moduleID] == .unknown)
    }

    @Test func structuralYellowRollsUpYellow() {
        let (trunk, moduleID, typeID, funcID) = makeSimpleTree()
        var leafStatus: [String: TrunkStatus] = [
            moduleID: .green,
            typeID: .green,
            funcID: .green
        ]
        let tree = TreeIndex.from(nodes: trunk.nodes)
        let engine = RollUpEngine(tree: tree, leafStatus: leafStatus)
        var updater = IncrementalUpdater(
            tree: tree,
            rolledUpStatus: engine.compute(),
            leafStatus: leafStatus
        )

        let changed = updater.update(nodeID: funcID, to: .yellow)

        #expect(changed[funcID] == .yellow)
        #expect(changed[typeID] == .yellow)
        #expect(changed[moduleID] == .yellow)
    }

    @Test func structuralNoChangeWhenRedundant() {
        let (trunk, moduleID, typeID, funcID) = makeSimpleTree()
        var leafStatus: [String: TrunkStatus] = [
            moduleID: .red,
            typeID: .red,
            funcID: .green
        ]
        let tree = TreeIndex.from(nodes: trunk.nodes)
        let engine = RollUpEngine(tree: tree, leafStatus: leafStatus)
        var updater = IncrementalUpdater(
            tree: tree,
            rolledUpStatus: engine.compute(),
            leafStatus: leafStatus
        )

        let changed = updater.update(nodeID: funcID, to: .red)

        // func changes, but type and module are already red so they don't change
        #expect(changed[funcID] == .red)
        #expect(changed[typeID] == nil)
        #expect(changed[moduleID] == nil)
        #expect(updater.rolledUpStatus[typeID] == .red)
        #expect(updater.rolledUpStatus[moduleID] == .red)
    }

    @Test func structuralSiblingNotAffected() {
        var trunk = CodeTrunk()
        let coordA = TrunkCoordinate(path: ["Demo", "A"], kind: "struct", truthKey: "a")
        let coordAFunc = TrunkCoordinate(path: ["Demo", "A", "f"], kind: "func", truthKey: "af")
        let coordB = TrunkCoordinate(path: ["Demo", "B"], kind: "struct", truthKey: "b")
        trunk.add(TrunkNode(id: "a", coordinate: coordA, channels: []))
        trunk.add(TrunkNode(id: "a.f", coordinate: coordAFunc, channels: []))
        trunk.add(TrunkNode(id: "b", coordinate: coordB, channels: []))

        var leafStatus: [String: TrunkStatus] = ["a.f": .green, "a": .green, "b": .green]
        let tree = TreeIndex.from(nodes: trunk.nodes)
        let engine = RollUpEngine(tree: tree, leafStatus: leafStatus)
        var updater = IncrementalUpdater(
            tree: tree,
            rolledUpStatus: engine.compute(),
            leafStatus: leafStatus
        )

        let changed = updater.update(nodeID: "a.f", to: .red)

        #expect(changed["a.f"] == .red)
        #expect(changed["a"] == .red)
        #expect(changed["b"] == nil)
        #expect(updater.rolledUpStatus["b"] == .green)
    }

    // MARK: - Edge propagation

    @Test func reverseEdgePropagatesToSource() {
        var trunk = CodeTrunk()
        let addCoord = TrunkCoordinate(path: ["Demo", "add"], kind: "func", truthKey: "add2")
        let calcCoord = TrunkCoordinate(path: ["Demo", "calculate"], kind: "func", truthKey: "calc0")
        trunk.add(TrunkNode(id: "add", coordinate: addCoord, channels: []))
        trunk.add(TrunkNode(id: "calc", coordinate: calcCoord, channels: []))

        var leafStatus: [String: TrunkStatus] = ["add": .green, "calc": .green]
        let bridge = TrunkBridge(edges: [
            TrunkEdge(source: "calc", target: "add", kind: .call)
        ])
        let tree = TreeIndex.from(nodes: trunk.nodes)
        let engine = RollUpEngine(tree: tree, leafStatus: leafStatus, bridge: bridge)
        var updater = IncrementalUpdater(
            tree: tree,
            rolledUpStatus: engine.compute(),
            leafStatus: leafStatus,
            bridge: bridge
        )

        let changed = updater.update(nodeID: "add", to: .red)

        #expect(changed["add"] == .red)
        #expect(changed["calc"] == .red)
    }

    @Test func reverseEdgeNoChangeWhenSourceAlreadyRed() {
        var trunk = CodeTrunk()
        let addCoord = TrunkCoordinate(path: ["Demo", "add"], kind: "func", truthKey: "add2")
        let calcCoord = TrunkCoordinate(path: ["Demo", "calculate"], kind: "func", truthKey: "calc0")
        trunk.add(TrunkNode(id: "add", coordinate: addCoord, channels: []))
        trunk.add(TrunkNode(id: "calc", coordinate: calcCoord, channels: []))

        var leafStatus: [String: TrunkStatus] = ["add": .green, "calc": .red]
        let bridge = TrunkBridge(edges: [
            TrunkEdge(source: "calc", target: "add", kind: .call)
        ])
        let tree = TreeIndex.from(nodes: trunk.nodes)
        let engine = RollUpEngine(tree: tree, leafStatus: leafStatus, bridge: bridge)
        var updater = IncrementalUpdater(
            tree: tree,
            rolledUpStatus: engine.compute(),
            leafStatus: leafStatus,
            bridge: bridge
        )

        let changed = updater.update(nodeID: "add", to: .red)

        #expect(changed["add"] == .red)
        #expect(changed["calc"] == nil)
        #expect(updater.rolledUpStatus["calc"] == .red)
    }

    @Test func multipleReverseEdgesPropagated() {
        var trunk = CodeTrunk()
        let sharedCoord = TrunkCoordinate(path: ["Demo", "shared"], kind: "func", truthKey: "s")
        let aCoord = TrunkCoordinate(path: ["Demo", "A"], kind: "func", truthKey: "a")
        let bCoord = TrunkCoordinate(path: ["Demo", "B"], kind: "func", truthKey: "b")
        trunk.add(TrunkNode(id: "shared", coordinate: sharedCoord, channels: []))
        trunk.add(TrunkNode(id: "a", coordinate: aCoord, channels: []))
        trunk.add(TrunkNode(id: "b", coordinate: bCoord, channels: []))

        var leafStatus: [String: TrunkStatus] = ["shared": .green, "a": .green, "b": .green]
        let bridge = TrunkBridge(edges: [
            TrunkEdge(source: "a", target: "shared", kind: .reference),
            TrunkEdge(source: "b", target: "shared", kind: .call)
        ])
        let tree = TreeIndex.from(nodes: trunk.nodes)
        let engine = RollUpEngine(tree: tree, leafStatus: leafStatus, bridge: bridge)
        var updater = IncrementalUpdater(
            tree: tree,
            rolledUpStatus: engine.compute(),
            leafStatus: leafStatus,
            bridge: bridge
        )

        let changed = updater.update(nodeID: "shared", to: .red)

        #expect(changed["shared"] == .red)
        #expect(changed["a"] == .red)
        #expect(changed["b"] == .red)
    }

    // MARK: - Structural + edge combined

    @Test func structuralAndEdgePropagationTogether() {
        var trunk = CodeTrunk()
        let module = TrunkCoordinate(path: ["Demo"], kind: "module", truthKey: "m")
        let addCoord = TrunkCoordinate(path: ["Demo", "add"], kind: "func", truthKey: "add2")
        let calcCoord = TrunkCoordinate(path: ["Demo", "calculate"], kind: "func", truthKey: "calc0")
        trunk.add(TrunkNode(id: "demo", coordinate: module, channels: []))
        trunk.add(TrunkNode(id: "add", coordinate: addCoord, channels: []))
        trunk.add(TrunkNode(id: "calc", coordinate: calcCoord, channels: []))

        var leafStatus: [String: TrunkStatus] = ["demo": .green, "add": .green, "calc": .green]
        let bridge = TrunkBridge(edges: [
            TrunkEdge(source: "calc", target: "add", kind: .call)
        ])
        let tree = TreeIndex.from(nodes: trunk.nodes)
        let engine = RollUpEngine(tree: tree, leafStatus: leafStatus, bridge: bridge)
        var updater = IncrementalUpdater(
            tree: tree,
            rolledUpStatus: engine.compute(),
            leafStatus: leafStatus,
            bridge: bridge
        )

        let changed = updater.update(nodeID: "add", to: .red)

        #expect(changed["add"] == .red)
        #expect(changed["demo"] == .red)
        #expect(changed["calc"] == .red)
    }

    @Test func edgeToParentStructuralAncestor() {
        // add is child of demo, calc has edge to add
        var trunk = CodeTrunk()
        let module = TrunkCoordinate(path: ["Demo"], kind: "module", truthKey: "m")
        let addCoord = TrunkCoordinate(path: ["Demo", "add"], kind: "func", truthKey: "add2")
        let calcCoord = TrunkCoordinate(path: ["Demo", "calculate"], kind: "func", truthKey: "calc0")
        trunk.add(TrunkNode(id: "demo", coordinate: module, channels: []))
        trunk.add(TrunkNode(id: "add", coordinate: addCoord, channels: []))
        trunk.add(TrunkNode(id: "calc", coordinate: calcCoord, channels: []))

        var leafStatus: [String: TrunkStatus] = ["demo": .green, "add": .green, "calc": .green]
        let bridge = TrunkBridge(edges: [
            TrunkEdge(source: "calc", target: "add", kind: .call)
        ])
        let tree = TreeIndex.from(nodes: trunk.nodes)
        let engine = RollUpEngine(tree: tree, leafStatus: leafStatus, bridge: bridge)
        var updater = IncrementalUpdater(
            tree: tree,
            rolledUpStatus: engine.compute(),
            leafStatus: leafStatus,
            bridge: bridge
        )

        let changed = updater.update(nodeID: "calc", to: .red)

        // calc is red, its parent demo should be red
        // add is NOT affected because add's rolledUp depends on add's own status and its children,
        // not on calc's status (the edge is calc->add, not add->calc)
        #expect(changed["calc"] == .red)
        #expect(changed["demo"] == .red)
        #expect(changed["add"] == nil)
    }

    // MARK: - Correctness gate: incremental matches full rebuild

    @Test func incrementalMatchesFullRebuildAfterLeafChange() {
        var trunk = CodeTrunk()
        let module = TrunkCoordinate(path: ["Demo"], kind: "module", truthKey: "m")
        let typeA = TrunkCoordinate(path: ["Demo", "A"], kind: "struct", truthKey: "a")
        let typeB = TrunkCoordinate(path: ["Demo", "B"], kind: "struct", truthKey: "b")
        let funcA = TrunkCoordinate(path: ["Demo", "A", "f"], kind: "func", truthKey: "af")
        let funcB = TrunkCoordinate(path: ["Demo", "B", "g"], kind: "func", truthKey: "bg")
        trunk.add(TrunkNode(id: "demo", coordinate: module, channels: []))
        trunk.add(TrunkNode(id: "a", coordinate: typeA, channels: []))
        trunk.add(TrunkNode(id: "b", coordinate: typeB, channels: []))
        trunk.add(TrunkNode(id: "a.f", coordinate: funcA, channels: []))
        trunk.add(TrunkNode(id: "b.g", coordinate: funcB, channels: []))

        var leafStatus: [String: TrunkStatus] = [
            "demo": .green, "a": .green, "b": .green,
            "a.f": .green, "b.g": .green
        ]
        let bridge = TrunkBridge(edges: [
            TrunkEdge(source: "a.f", target: "b.g", kind: .call)
        ])
        let tree = TreeIndex.from(nodes: trunk.nodes)
        let engine = RollUpEngine(tree: tree, leafStatus: leafStatus, bridge: bridge)
        var updater = IncrementalUpdater(
            tree: tree,
            rolledUpStatus: engine.compute(),
            leafStatus: leafStatus,
            bridge: bridge
        )

        updater.update(nodeID: "b.g", to: .red)

        let rebuilt = fullRebuild(trunk: trunk, leafStatus: updater.leafStatus, bridge: bridge)

        #expect(updater.rolledUpStatus == rebuilt)
    }

    @Test func incrementalMatchesFullRebuildMultipleChanges() {
        var trunk = CodeTrunk()
        let module = TrunkCoordinate(path: ["Demo"], kind: "module", truthKey: "m")
        let typeA = TrunkCoordinate(path: ["Demo", "A"], kind: "struct", truthKey: "a")
        let typeB = TrunkCoordinate(path: ["Demo", "B"], kind: "struct", truthKey: "b")
        let funcA = TrunkCoordinate(path: ["Demo", "A", "f"], kind: "func", truthKey: "af")
        let funcB = TrunkCoordinate(path: ["Demo", "B", "g"], kind: "func", truthKey: "bg")
        trunk.add(TrunkNode(id: "demo", coordinate: module, channels: []))
        trunk.add(TrunkNode(id: "a", coordinate: typeA, channels: []))
        trunk.add(TrunkNode(id: "b", coordinate: typeB, channels: []))
        trunk.add(TrunkNode(id: "a.f", coordinate: funcA, channels: []))
        trunk.add(TrunkNode(id: "b.g", coordinate: funcB, channels: []))

        var leafStatus: [String: TrunkStatus] = [
            "demo": .green, "a": .green, "b": .green,
            "a.f": .green, "b.g": .green
        ]
        let bridge = TrunkBridge(edges: [
            TrunkEdge(source: "a.f", target: "b.g", kind: .call)
        ])
        let tree = TreeIndex.from(nodes: trunk.nodes)
        let engine = RollUpEngine(tree: tree, leafStatus: leafStatus, bridge: bridge)
        var updater = IncrementalUpdater(
            tree: tree,
            rolledUpStatus: engine.compute(),
            leafStatus: leafStatus,
            bridge: bridge
        )

        updater.update(nodeID: "a.f", to: .yellow)
        updater.update(nodeID: "b.g", to: .red)
        updater.update(nodeID: "demo", to: .unknown)

        let rebuilt = fullRebuild(trunk: trunk, leafStatus: updater.leafStatus, bridge: bridge)

        #expect(updater.rolledUpStatus == rebuilt)
    }

    @Test func incrementalMatchesFullRebuildWithComplexEdges() {
        var trunk = CodeTrunk()
        let module = TrunkCoordinate(path: ["Demo"], kind: "module", truthKey: "m")
        let addCoord = TrunkCoordinate(path: ["Demo", "add"], kind: "func", truthKey: "add2")
        let calcCoord = TrunkCoordinate(path: ["Demo", "calc"], kind: "func", truthKey: "calc0")
        let mainCoord = TrunkCoordinate(path: ["Demo", "main"], kind: "func", truthKey: "main0")
        trunk.add(TrunkNode(id: "demo", coordinate: module, channels: []))
        trunk.add(TrunkNode(id: "add", coordinate: addCoord, channels: []))
        trunk.add(TrunkNode(id: "calc", coordinate: calcCoord, channels: []))
        trunk.add(TrunkNode(id: "main", coordinate: mainCoord, channels: []))

        var leafStatus: [String: TrunkStatus] = [
            "demo": .green, "add": .green, "calc": .green, "main": .green
        ]
        let bridge = TrunkBridge(edges: [
            TrunkEdge(source: "calc", target: "add", kind: .call),
            TrunkEdge(source: "main", target: "calc", kind: .call),
            TrunkEdge(source: "main", target: "add", kind: .reference)
        ])
        let tree = TreeIndex.from(nodes: trunk.nodes)
        let engine = RollUpEngine(tree: tree, leafStatus: leafStatus, bridge: bridge)
        var updater = IncrementalUpdater(
            tree: tree,
            rolledUpStatus: engine.compute(),
            leafStatus: leafStatus,
            bridge: bridge
        )

        updater.update(nodeID: "add", to: .red)

        let rebuilt = fullRebuild(trunk: trunk, leafStatus: updater.leafStatus, bridge: bridge)

        #expect(updater.rolledUpStatus == rebuilt)
    }

    // MARK: - Edge cycles

    @Test func cycleConvergesCorrectly() {
        var trunk = CodeTrunk()
        let aCoord = TrunkCoordinate(path: ["Demo", "A"], kind: "func", truthKey: "a")
        let bCoord = TrunkCoordinate(path: ["Demo", "B"], kind: "func", truthKey: "b")
        trunk.add(TrunkNode(id: "a", coordinate: aCoord, channels: []))
        trunk.add(TrunkNode(id: "b", coordinate: bCoord, channels: []))

        var leafStatus: [String: TrunkStatus] = ["a": .green, "b": .green]
        let bridge = TrunkBridge(edges: [
            TrunkEdge(source: "a", target: "b", kind: .call),
            TrunkEdge(source: "b", target: "a", kind: .call)
        ])
        let tree = TreeIndex.from(nodes: trunk.nodes)
        let engine = RollUpEngine(tree: tree, leafStatus: leafStatus, bridge: bridge)
        var updater = IncrementalUpdater(
            tree: tree,
            rolledUpStatus: engine.compute(),
            leafStatus: leafStatus,
            bridge: bridge
        )

        updater.update(nodeID: "a", to: .red)

        let rebuilt = fullRebuild(trunk: trunk, leafStatus: updater.leafStatus, bridge: bridge)

        #expect(updater.rolledUpStatus == rebuilt)
        #expect(updater.rolledUpStatus["a"] == .red)
        #expect(updater.rolledUpStatus["b"] == .red)
    }

    @Test func cycleNoInfiniteLoop() {
        var trunk = CodeTrunk()
        let aCoord = TrunkCoordinate(path: ["Demo", "A"], kind: "func", truthKey: "a")
        let bCoord = TrunkCoordinate(path: ["Demo", "B"], kind: "func", truthKey: "b")
        trunk.add(TrunkNode(id: "a", coordinate: aCoord, channels: []))
        trunk.add(TrunkNode(id: "b", coordinate: bCoord, channels: []))

        var leafStatus: [String: TrunkStatus] = ["a": .green, "b": .green]
        let bridge = TrunkBridge(edges: [
            TrunkEdge(source: "a", target: "b", kind: .call),
            TrunkEdge(source: "b", target: "a", kind: .call)
        ])
        let tree = TreeIndex.from(nodes: trunk.nodes)
        let engine = RollUpEngine(tree: tree, leafStatus: leafStatus, bridge: bridge)
        var updater = IncrementalUpdater(
            tree: tree,
            rolledUpStatus: engine.compute(),
            leafStatus: leafStatus,
            bridge: bridge
        )

        // Should complete without hanging
        updater.update(nodeID: "a", to: .red)

        #expect(updater.rolledUpStatus["a"] == .red)
        #expect(updater.rolledUpStatus["b"] == .red)
    }

    // MARK: - Empty / edge cases

    @Test func emptyWorklistReturnsEmpty() {
        let tree = TreeIndex.from(nodes: [])
        var updater = IncrementalUpdater(
            tree: tree,
            rolledUpStatus: [:],
            leafStatus: [:]
        )
        let changed = updater.update(nodeID: "missing", to: .red)
        #expect(changed.isEmpty)
    }

    @Test func updateUnknownNodeDoesNothing() {
        let (trunk, _, _, _) = makeSimpleTree()
        let tree = TreeIndex.from(nodes: trunk.nodes)
        var leafStatus: [String: TrunkStatus] = [:]
        let engine = RollUpEngine(tree: tree, leafStatus: leafStatus)
        var updater = IncrementalUpdater(
            tree: tree,
            rolledUpStatus: engine.compute(),
            leafStatus: leafStatus
        )
        let changed = updater.update(nodeID: "nonexistent", to: .red)
        #expect(changed.isEmpty)
    }

    // MARK: - Performance

    @Test func performanceIncrementalUpdate10KNodes() {
        var trunk = CodeTrunk()
        var leafStatus: [String: TrunkStatus] = [:]

        let moduleCount = 100
        let typeCount = 10
        let funcCount = 10

        for m in 0..<moduleCount {
            let mID = "M\(m)"
            let mCoord = TrunkCoordinate(path: [mID], kind: "module", truthKey: mID)
            trunk.add(TrunkNode(id: mID, coordinate: mCoord, channels: []))
            leafStatus[mID] = .green

            for t in 0..<typeCount {
                let tID = "M\(m).T\(t)"
                let tCoord = TrunkCoordinate(path: [mID, "T\(t)"], kind: "struct", truthKey: tID)
                trunk.add(TrunkNode(id: tID, coordinate: tCoord, channels: []))
                leafStatus[tID] = .green

                for f in 0..<funcCount {
                    let fID = "M\(m).T\(t).F\(f)"
                    let fCoord = TrunkCoordinate(path: [mID, "T\(t)", "F\(f)"], kind: "func", truthKey: fID)
                    trunk.add(TrunkNode(id: fID, coordinate: fCoord, channels: []))
                    leafStatus[fID] = .green
                }
            }
        }

        let tree = TreeIndex.from(nodes: trunk.nodes)
        let engine = RollUpEngine(tree: tree, leafStatus: leafStatus)
        var updater = IncrementalUpdater(
            tree: tree,
            rolledUpStatus: engine.compute(),
            leafStatus: leafStatus
        )

        let start = Date()
        // Change one deep leaf
        updater.update(nodeID: "M99.T9.F9", to: .red)
        let elapsed = Date().timeIntervalSince(start)

        #expect(elapsed < 0.1, "Incremental update took \(elapsed * 1000) ms, expected < 100 ms")
    }
}
