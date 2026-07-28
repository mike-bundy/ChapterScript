import XCTest
@testable import ChapterScript

/// Full-fidelity `ParticleEmitterPreset` coverage: additive-field defaults,
/// legacy 14-field documents decoding unchanged, tolerant enum decode, and
/// round-trips of fully-populated presets including the spawned emitter.
final class ParticlePresetTests: XCTestCase {

    private func roundTrip<T: Codable & Equatable>(_ value: T, file: StaticString = #filePath, line: UInt = #line) throws {
        let data = try ChapterScriptFormat.makeEncoder().encode(value)
        let decoded = try ChapterScriptFormat.makeDecoder().decode(T.self, from: data)
        XCTAssertEqual(value, decoded, "round-trip diverged", file: file, line: line)
    }

    // MARK: - Legacy documents decode unchanged

    /// A preset JSON exactly as written before the full-fidelity expansion
    /// (only the original 14 fields) must decode, keep the original values,
    /// and land every new field on its Afterburn default.
    func testLegacy14FieldPresetDecodesWithAfterburnDefaults() throws {
        let legacy = """
        {
          "id": "sparks",
          "displayName": "Sparks",
          "birthRate": 300,
          "lifeSpan": 0.8,
          "speed": 0.3,
          "emitterShape": "point",
          "spreadAngle": 57,
          "color": {"r": 1, "g": 1, "b": 0.8, "a": 1},
          "startSize": 0.015,
          "endSize": 0,
          "startOpacity": 1,
          "endOpacity": 0,
          "blending": "additive",
          "gravity": {"x": 0, "y": -3, "z": 0},
          "loops": true
        }
        """.data(using: .utf8)!

        let p = try ChapterScriptFormat.makeDecoder().decode(ParticleEmitterPreset.self, from: legacy)

        // Original values preserved
        XCTAssertEqual(p.id, "sparks")
        XCTAssertEqual(p.birthRate, 300)
        XCTAssertEqual(p.spreadAngle, 57)
        XCTAssertEqual(p.gravity, Vec3(0, -3, 0))
        XCTAssertTrue(p.loops)

        // New fields default to Afterburn EmitterSettings defaults
        XCTAssertEqual(p.birthRateVariation, 0)
        XCTAssertEqual(p.emitterShapeSize, Vec3(0.1, 0.1, 0.1))
        XCTAssertEqual(p.birthDirection, .normal)
        XCTAssertEqual(p.birthLocation, .surface)
        XCTAssertEqual(p.emissionDirection, Vec3(0, 1, 0))
        XCTAssertEqual(p.radialAmount, 6.283)
        XCTAssertEqual(p.torusInnerRadius, 0.5)
        XCTAssertNil(p.burstCount)
        XCTAssertFalse(p.particlesInheritTransform)
        XCTAssertEqual(p.lifeSpanVariation, 0)
        XCTAssertEqual(p.sizeVariation, 0)
        XCTAssertEqual(p.sizeMultiplierAtEndOfLifespanPower, 1.0)
        XCTAssertEqual(p.mass, 1.0)
        XCTAssertEqual(p.massVariation, 0)
        XCTAssertEqual(p.angle, 0)
        XCTAssertEqual(p.angleVariation, 0)
        XCTAssertEqual(p.angularSpeed, 0)
        XCTAssertEqual(p.angularSpeedVariation, 0)
        XCTAssertEqual(p.dampingFactor, 0)
        XCTAssertEqual(p.stretchFactor, 0)
        XCTAssertEqual(p.colorSetting, .constant)   // legacy opacity-ramp rendering
        XCTAssertEqual(p.color2, ColorRGBA(r: 1, g: 1, b: 1))
        XCTAssertEqual(p.colorEvolutionPower, 1.0)
        XCTAssertEqual(p.opacityCurve, .constant)
        XCTAssertEqual(p.billboardMode, .billboard)
        XCTAssertFalse(p.isLightingEnabled)
        XCTAssertEqual(p.sortOrder, .unsorted)
        XCTAssertNil(p.mainImage)
        XCTAssertEqual(p.noiseStrength, 0)
        XCTAssertEqual(p.noiseScale, 1.0)
        XCTAssertEqual(p.noiseAnimationSpeed, 0)
        XCTAssertEqual(p.attractionStrength, 0)
        XCTAssertEqual(p.attractionCenter, Vec3(0, 0, 0))
        XCTAssertEqual(p.vortexStrength, 0)
        XCTAssertEqual(p.vortexDirection, Vec3(0, 1, 0))
        XCTAssertNil(p.spawn)
    }

    /// A legacy preset must equal the memberwise init that passes only the
    /// original 14 values — i.e. decode defaults and init defaults agree.
    func testLegacyDecodeMatchesMemberwiseDefaults() throws {
        let legacy = """
        {
          "id": "magic", "displayName": "Magic",
          "birthRate": 50, "lifeSpan": 3.0, "speed": 0.05,
          "emitterShape": "sphere", "spreadAngle": 86,
          "color": {"r": 0.5, "g": 0.8, "b": 1, "a": 1},
          "startSize": 0.04, "endSize": 0,
          "startOpacity": 1, "endOpacity": 0,
          "blending": "additive", "gravity": {"x": 0, "y": 0.2, "z": 0},
          "loops": true
        }
        """.data(using: .utf8)!
        let decoded = try ChapterScriptFormat.makeDecoder().decode(ParticleEmitterPreset.self, from: legacy)
        let built = ParticleEmitterPreset(
            id: "magic", displayName: "Magic",
            birthRate: 50, lifeSpan: 3.0, speed: 0.05,
            emitterShape: .sphere, spreadAngle: 86,
            color: ColorRGBA(r: 0.5, g: 0.8, b: 1),
            startSize: 0.04, endSize: 0,
            startOpacity: 1, endOpacity: 0,
            blending: .additive, gravity: Vec3(0, 0.2, 0), loops: true
        )
        XCTAssertEqual(decoded, built)
    }

    // MARK: - Round-trips

    func testDefaultPresetRoundTrip() throws {
        try roundTrip(ParticleEmitterPreset(id: "default", displayName: "Default"))
    }

    func testFullyPopulatedPresetRoundTrip() throws {
        try roundTrip(Self.fullPreset)
    }

    func testDocumentWithFullPresetRoundTrip() throws {
        let doc = ChapterDocument(
            id: "exp",
            displayName: "Experience",
            particlePresets: [Self.fullPreset]
        )
        try roundTrip(doc)
    }

    // MARK: - Tolerant enum decode

    func testUnknownEnumStringsFallBackToDefaults() throws {
        let weird = """
        {
          "id": "x", "displayName": "X",
          "emitterShape": "dodecahedron",
          "blending": "hologram",
          "birthDirection": "sideways",
          "birthLocation": "everywhere",
          "colorSetting": "plaid",
          "opacityCurve": "wavy",
          "billboardMode": "spinny",
          "sortOrder": "chaotic",
          "spawn": {"spawnOccasion": "onTuesday"}
        }
        """.data(using: .utf8)!
        let p = try ChapterScriptFormat.makeDecoder().decode(ParticleEmitterPreset.self, from: weird)
        XCTAssertEqual(p.emitterShape, .point)
        XCTAssertEqual(p.blending, .additive)
        XCTAssertEqual(p.birthDirection, .normal)
        XCTAssertEqual(p.birthLocation, .surface)
        XCTAssertEqual(p.colorSetting, .constant)
        XCTAssertEqual(p.opacityCurve, .constant)
        XCTAssertEqual(p.billboardMode, .billboard)
        XCTAssertEqual(p.sortOrder, .unsorted)
        XCTAssertEqual(p.spawn?.spawnOccasion, .onBirth)
    }

    func testNewShapeCasesRoundTrip() throws {
        try roundTrip(ParticleEmitterPreset(id: "t", displayName: "T", emitterShape: .torus, torusInnerRadius: 0.25))
        try roundTrip(ParticleEmitterPreset(id: "c", displayName: "C", emitterShape: .cylinder))
    }

    // MARK: - Spawned emitter

    /// An empty spawn object decodes to the full Afterburn secondary-emitter
    /// default set (presence alone enables secondary particles).
    func testEmptySpawnSpecDecodesToDefaults() throws {
        let json = """
        {"id": "s", "displayName": "S", "spawn": {}}
        """.data(using: .utf8)!
        let p = try ChapterScriptFormat.makeDecoder().decode(ParticleEmitterPreset.self, from: json)
        let spawn = try XCTUnwrap(p.spawn)
        XCTAssertEqual(spawn, ParticleEmitterPreset.SpawnedEmitterSpec())
        XCTAssertEqual(spawn.birthRate, 50)
        XCTAssertEqual(spawn.lifeSpan, 1.0)
        XCTAssertEqual(spawn.size, 0.03)
        XCTAssertEqual(spawn.sizeMultiplierAtEndOfLifespan, 1.0)
        XCTAssertEqual(spawn.colorSetting, .constant)
        XCTAssertEqual(spawn.blending, .additive)
        XCTAssertEqual(spawn.spawnOccasion, .onBirth)
        XCTAssertNil(spawn.image)
        XCTAssertEqual(spawn.vortexDirection, Vec3(0, 1, 0))
    }

    func testBurstCountAbsentMeansDerived() throws {
        let json = """
        {"id": "b", "displayName": "B", "loops": false}
        """.data(using: .utf8)!
        let p = try ChapterScriptFormat.makeDecoder().decode(ParticleEmitterPreset.self, from: json)
        XCTAssertNil(p.burstCount, "absent burstCount must stay nil so players derive birthRate × lifeSpan")

        let explicit = ParticleEmitterPreset(id: "b", displayName: "B", loops: false, burstCount: 640)
        let data = try ChapterScriptFormat.makeEncoder().encode(explicit)
        let back = try ChapterScriptFormat.makeDecoder().decode(ParticleEmitterPreset.self, from: data)
        XCTAssertEqual(back.burstCount, 640)
    }

    // MARK: - Fixture

    static let fullPreset = ParticleEmitterPreset(
        id: "inferno",
        displayName: "Inferno",
        birthRate: 800,
        lifeSpan: 2.5,
        speed: 0.9,
        emitterShape: .torus,
        spreadAngle: 45,
        color: ColorRGBA(r: 1, g: 0.4, b: 0.1),
        startSize: 0.03,
        endSize: 0.005,
        startOpacity: 1,
        endOpacity: 0,
        blending: .additive,
        gravity: Vec3(0, 1.2, 0),
        loops: false,
        birthRateVariation: 150,
        emitterShapeSize: Vec3(0.4, 0.2, 0.4),
        birthDirection: .world,
        birthLocation: .volume,
        emissionDirection: Vec3(0, 1, 0.2),
        radialAmount: 3.14,
        torusInnerRadius: 0.3,
        burstCount: 500,
        particlesInheritTransform: true,
        lifeSpanVariation: 0.5,
        sizeVariation: 0.01,
        sizeMultiplierAtEndOfLifespanPower: 2.0,
        mass: 0.8,
        massVariation: 0.2,
        angle: 0.5,
        angleVariation: 0.25,
        angularSpeed: 1.5,
        angularSpeedVariation: 0.5,
        dampingFactor: 0.1,
        stretchFactor: 2.0,
        colorSetting: .evolving,
        color2: ColorRGBA(r: 0.2, g: 0, b: 0, a: 1),
        colorEvolutionPower: 1.8,
        opacityCurve: .fadeInOut,
        billboardMode: .billboardYAligned,
        isLightingEnabled: true,
        sortOrder: .depthDescending,
        mainImage: "flame.fill",
        noiseStrength: 2.0,
        noiseScale: 1.5,
        noiseAnimationSpeed: 0.7,
        attractionStrength: -1.0,
        attractionCenter: Vec3(0, 2, 0),
        vortexStrength: 3.0,
        vortexDirection: Vec3(0, 1, 0.1),
        spawn: ParticleEmitterPreset.SpawnedEmitterSpec(
            spawnOccasion: .onDeath,
            spawnSpreadFactor: 0.4,
            spawnVelocityFactor: 0.6,
            spawnInheritsParentColor: true,
            image: "sparkle",
            birthRate: 120,
            birthRateVariation: 20,
            lifeSpan: 0.6,
            lifeSpanVariation: 0.1,
            size: 0.01,
            sizeVariation: 0.002,
            sizeMultiplierAtEndOfLifespan: 0.2,
            sizeMultiplierAtEndOfLifespanPower: 1.5,
            mass: 0.5,
            massVariation: 0.1,
            acceleration: Vec3(0, -2, 0),
            angle: 0.1,
            angleVariation: 0.05,
            angularSpeed: 2.0,
            angularSpeedVariation: 0.3,
            dampingFactor: 0.05,
            spreadAngle: 90,
            stretchFactor: 1.0,
            colorSetting: .evolving,
            color: ColorRGBA(r: 1, g: 0.9, b: 0.5),
            color2: ColorRGBA(r: 1, g: 0.2, b: 0, a: 0),
            colorEvolutionPower: 2.0,
            opacityCurve: .linearFadeOut,
            billboardMode: .billboard,
            blending: .additive,
            isLightingEnabled: false,
            sortOrder: .ageAscending,
            noiseStrength: 0.5,
            noiseScale: 2.0,
            noiseAnimationSpeed: 0.2,
            attractionStrength: 0.3,
            attractionCenter: Vec3(0, 1, 0),
            vortexStrength: 0.4,
            vortexDirection: Vec3(0.1, 1, 0)
        )
    )
}
