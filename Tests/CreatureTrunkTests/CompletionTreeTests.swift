import Testing
import Foundation
@testable import CreatureTrunk

@Suite struct RollUpEngineTests {

    private func makeTrunk() -> (trunk: CodeTrunk, moduleID: String, typeID: String, funcID: String) {
        var trunk = CodeTrunk()

        let moduleCoord = TrunkCoordinate(path: ["Demo"], kind: "module", truthKey: "module")
        let typeCoord = TrunkCoordinate(path: ["Demo", "Greeter"], kind: "struct", truthKey: "type")
        let funcCoord = TrunkCoordinate(path: ["Demo", "Greeter", "hello"], kind: "func", truthKey: "func")

        let moduleID = "module-1"
        let typeID = "type-1"
        let funcID = "func-1"

        trunk.add(TrunkNode(id: moduleID, coordinate: moduleCoord, channels: []))
        trunk.add(TrunkNode(id: typeID, coordinate: typeCoord, channels: []))
        trunk.add(TrunkNode(id: funcID, coordinate: funcCoord, channels: []))

        return (trunk, moduleID, typeID, funcID)
    }

    @Test func allGreenRollsUpToGreen() {
        let (trunk, moduleID, typeID, funcID) = makeTrunk()
        let leafStatus: [String: TrunkStatus] = [
            moduleID: .green,
            typeID: .green,
            funcID: .green
        ]
        let tree = TreeIndex.from(nodes: trunk.nodes)
        let engine = RollUpEngine(tree: tree, leafStatus: leafStatus)
        let rolledUp = engine.compute()

        #expect(rolledUp[funcID] == .green)
        #expect(rolledUp[typeID] == .green)
        #expect(rolledUp[moduleID] == .green)
    }

    @Test func redLeafRollsUpAncestors() {
        let (trunk, moduleID, typeID, funcID) = makeTrunk()
        let leafStatus: [String: TrunkStatus] = [
            moduleID: .green,
            typeID: .green,
            funcID: .red
        ]
        let tree = TreeIndex.from(nodes: trunk.nodes)
        let engine = RollUpEngine(tree: tree, leafStatus: leafStatus)
        let rolledUp = engine.compute()

        #expect(rolledUp[funcID] == .red)
        #expect(rolledUp[typeID] == .red)
        #expect(rolledUp[moduleID] == .red)
    }

    @Test func unknownLeafBlocksGreen() {
        let (trunk, moduleID, typeID, funcID) = makeTrunk()
        let leafStatus: [String: TrunkStatus] = [
            moduleID: .green,
            typeID: .green,
            funcID: .unknown
        ]
        let tree = TreeIndex.from(nodes: trunk.nodes)
        let engine = RollUpEngine(tree: tree, leafStatus: leafStatus)
        let rolledUp = engine.compute()

        #expect(rolledUp[funcID] == .unknown)
        #expect(rolledUp[typeID] == .unknown)
        #expect(rolledUp[moduleID] == .unknown)
    }

    @Test func yellowLeafRollsUpYellow() {
        let (trunk, moduleID, typeID, funcID) = makeTrunk()
        let leafStatus: [String: TrunkStatus] = [
            moduleID: .green,
            typeID: .green,
            funcID: .yellow
        ]
        let tree = TreeIndex.from(nodes: trunk.nodes)
        let engine = RollUpEngine(tree: tree, leafStatus: leafStatus)
        let rolledUp = engine.compute()

        #expect(rolledUp[funcID] == .yellow)
        #expect(rolledUp[typeID] == .yellow)
        #expect(rolledUp[moduleID] == .yellow)
    }

    @Test func absentLeafStatusDefaultsToUnknown() {
        let (trunk, moduleID, typeID, funcID) = makeTrunk()
        let leafStatus: [String: TrunkStatus] = [:]
        let tree = TreeIndex.from(nodes: trunk.nodes)
        let engine = RollUpEngine(tree: tree, leafStatus: leafStatus)
        let rolledUp = engine.compute()

        #expect(rolledUp[funcID] == .unknown)
        #expect(rolledUp[typeID] == .unknown)
        #expect(rolledUp[moduleID] == .unknown)
    }

    @Test func edgePropagationRolledUp() {
        var trunk = CodeTrunk()
        let addCoord = TrunkCoordinate(path: ["Demo", "add"], kind: "func", truthKey: "add2")
        let calcCoord = TrunkCoordinate(path: ["Demo", "calculate"], kind: "func", truthKey: "calc0")
        trunk.add(TrunkNode(id: "add", coordinate: addCoord, channels: []))
        trunk.add(TrunkNode(id: "calc", coordinate: calcCoord, channels: []))

        let leafStatus: [String: TrunkStatus] = ["add": .red, "calc": .green]
        let bridge = TrunkBridge(edges: [
            TrunkEdge(source: "calc", target: "add", kind: .call)
        ])
        let tree = TreeIndex.from(nodes: trunk.nodes)
        let engine = RollUpEngine(tree: tree, leafStatus: leafStatus, bridge: bridge)
        let rolledUp = engine.compute()

        #expect(rolledUp["add"] == .red)
        #expect(rolledUp["calc"] == .red)
    }

    @Test func structuralAndEdgeTogether() {
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
        let tree = TreeIndex.from(nodes: trunk.nodes)
        let engine = RollUpEngine(tree: tree, leafStatus: leafStatus, bridge: bridge)
        let rolledUp = engine.compute()

        #expect(rolledUp["demo"] == .red)
        #expect(rolledUp["calc"] == .red)
        #expect(rolledUp["add"] == .red)
    }

    @Test func siblingNotAffectedByStructuralRollup() {
        var trunk = CodeTrunk()
        let coordA = TrunkCoordinate(path: ["Demo", "A"], kind: "struct", truthKey: "a")
        let coordAFunc = TrunkCoordinate(path: ["Demo", "A", "f"], kind: "func", truthKey: "af")
        let coordB = TrunkCoordinate(path: ["Demo", "B"], kind: "struct", truthKey: "b")

        trunk.add(TrunkNode(id: "a", coordinate: coordA, channels: []))
        trunk.add(TrunkNode(id: "a.f", coordinate: coordAFunc, channels: []))
        trunk.add(TrunkNode(id: "b", coordinate: coordB, channels: []))

        let leafStatus: [String: TrunkStatus] = ["a.f": .red, "a": .green, "b": .green]
        let tree = TreeIndex.from(nodes: trunk.nodes)
        let engine = RollUpEngine(tree: tree, leafStatus: leafStatus)
        let rolledUp = engine.compute()

        #expect(rolledUp["a"] == .red)
        #expect(rolledUp["b"] == .green)
    }

    @Test func emptyTrunkProducesEmptyRolledUp() {
        let tree = TreeIndex.from(nodes: [])
        let engine = RollUpEngine(tree: tree, leafStatus: [:])
        let rolledUp = engine.compute()
        #expect(rolledUp.isEmpty)
    }

    @Test func engineMatchesAtlasStatus() {
        let (trunk, moduleID, typeID, funcID) = makeTrunk()
        let leafStatus: [String: TrunkStatus] = [
            moduleID: .green,
            typeID: .green,
            funcID: .red
        ]
        let atlas = TrunkAtlas(trunk: trunk, leafStatus: leafStatus)

        #expect(atlas.status(for: moduleID) == .red)
        #expect(atlas.status(for: typeID) == .red)
        #expect(atlas.status(for: funcID) == .red)
        #expect(atlas.overall == .red)
    }

    @Test func engineMatchesAtlasWithBridge() {
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

        #expect(atlas.status(for: "calc") == .red)
        #expect(atlas.status(for: "add") == .red)
        #expect(atlas.overall == .red)
    }

    @Test func performanceBuildAndRollup10KNodes() {
        var trunk = CodeTrunk()
        var leafStatus: [String: TrunkStatus] = [:]

        // Build a balanced tree: 100 modules, each with 10 types, each with 10 functions
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
                    // Make last function red to force real rollup work
                    leafStatus[fID] = (f == funcCount - 1 && t == typeCount - 1 && m == moduleCount - 1) ? .red : .green
                }
            }
        }

        let totalNodes = moduleCount + moduleCount * typeCount + moduleCount * typeCount * funcCount

        let start = Date()
        let tree = TreeIndex.from(nodes: trunk.nodes)
        let engine = RollUpEngine(tree: tree, leafStatus: leafStatus)
        let rolledUp = engine.compute()
        let elapsed = Date().timeIntervalSince(start)

        #expect(rolledUp.count == totalNodes)
        #expect(elapsed < 2.0, "Build + rollup of \(totalNodes) nodes took \(elapsed * 1000) ms, expected < 2000 ms")
    }
}
