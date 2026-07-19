import Testing
@testable import CreatureSpine

@Test func feelingIntensityClamped() {
    let f = Feeling(kind: .warmth, intensity: 1.5, source: CreatureID(), coordinate: .origin)
    #expect(f.intensity == 1.0)

    let f2 = Feeling(kind: .warmth, intensity: -0.3, source: CreatureID(), coordinate: .origin)
    #expect(f2.intensity == 0.0)
}

@Test func feelingKindEquality() {
    let a = FeelingKind.warmth
    let b = FeelingKind.warmth
    #expect(a == b)

    let c = FeelingKind.unease
    #expect(a != c)
}

@Test func feelingVectorMagnitude() {
    let v = FeelingVector()
    #expect(v.magnitude < 0.001)

    var v2 = FeelingVector()
    v2[.warmth] = 0.6
    v2[.novelty] = 0.8
    #expect(abs(v2.magnitude - 1.0) < 0.01)
}

@Test func feelingVectorAddition() {
    var a = FeelingVector()
    a[.warmth] = 0.5
    var b = FeelingVector()
    b[.warmth] = 0.3
    b[.friction] = 0.4

    let sum = a + b
    #expect(abs(sum[.warmth] - 0.8) < 0.001)
    #expect(abs(sum[.friction] - 0.4) < 0.001)
}
