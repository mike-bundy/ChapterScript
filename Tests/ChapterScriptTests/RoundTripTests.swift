import XCTest
@testable import ChapterScript

final class RoundTripTests: XCTestCase {

    // MARK: - Helpers

    private func roundTrip<T: Codable & Equatable>(_ value: T, file: StaticString = #filePath, line: UInt = #line) throws {
        let data = try ChapterScriptFormat.makeEncoder().encode(value)
        let decoded = try ChapterScriptFormat.makeDecoder().decode(T.self, from: data)
        XCTAssertEqual(value, decoded, "round-trip diverged", file: file, line: line)
    }

    // MARK: - Primitives

    func testVec3RoundTrip() throws {
        try roundTrip(Vec3(1.5, -2.0, 0))
        try roundTrip(Vec3.zero)
    }

    func testColorRGBARoundTrip() throws {
        try roundTrip(ColorRGBA(r: 0.1, g: 0.2, b: 0.3, a: 0.4))
        try roundTrip(ColorRGBA.clear)
    }

    func testTransformRoundTrip() throws {
        try roundTrip(TransformData.identity)
        try roundTrip(TransformData(
            position: Vec3(1, 2, 3),
            rotation: Quat(x: 0, y: 0.7071, z: 0, w: 0.7071),
            scale: Vec3(2, 2, 2)
        ))
    }

    // MARK: - MotionCurve

    func testMotionCurveLeafRoundTrips() throws {
        try roundTrip(MotionCurve.constant(Vec3(1, 0, 0)))
        try roundTrip(MotionCurve.linear(from: Vec3.zero, to: Vec3(0, 1, 0)))
        try roundTrip(MotionCurve.orbit(center: Vec3.zero, radius: 1.0, axis: Vec3(0, 1, 0), revolutions: 2.0, phase: 0.25))
        try roundTrip(MotionCurve.spiral(center: Vec3.zero, startRadius: 1.0, endRadius: 0.1, axis: Vec3(0, 1, 0), revolutions: 3, yRise: 1.0))
        try roundTrip(MotionCurve.oscillate(axis: Vec3(0, 1, 0), amplitude: 0.3, frequency: 2.0, waveform: .sine))
        try roundTrip(MotionCurve.rotate(axis: Vec3(0, 1, 0), revolutions: 1))
        try roundTrip(MotionCurve.keyframes([
            KeyframePoint(time: 0, value: Vec3.zero, interpolation: .linear),
            KeyframePoint(time: 1, value: Vec3(1, 0, 0), interpolation: .easeInOut)
        ]))
    }

    func testMotionCurveCompositeRoundTrip() throws {
        let cube = MotionCurve.sum([
            .orbit(center: Vec3(0, 1.5, -2), radius: 0.6, axis: Vec3(0, 1, 0), revolutions: 1, phase: 0),
            .oscillate(axis: Vec3(0, 1, 0), amplitude: 0.15, frequency: 0.5, waveform: .sine),
            .scaled(.rotate(axis: Vec3(1, 0, 0), revolutions: 0.5), by: 1.0)
        ])
        try roundTrip(cube)
    }

    // MARK: - StepAction

    func testStepActionEntityCases() throws {
        try roundTrip(StepActionDTO.showEntity(name: "orb"))
        try roundTrip(StepActionDTO.hideEntity(name: "cube"))
        try roundTrip(StepActionDTO.persistEntity(name: "cone"))
        try roundTrip(StepActionDTO.unpersistEntity(name: "cone"))
        try roundTrip(StepActionDTO.scaleEntity(name: "orb", multiplier: 2.0, duration: 1.0, timing: .easeInOut))
    }

    func testStepActionRichCases() throws {
        try roundTrip(StepActionDTO.moveEntity(MoveActionDTO(
            entity: "orb",
            absolutePosition: Vec3(0, 1.5, -2),
            duration: 2.0
        )))
        try roundTrip(StepActionDTO.fadeEntity(FadeActionDTO(entity: "orb", opacity: 0.5)))
        try roundTrip(StepActionDTO.revealEntity(RevealActionDTO(
            entity: "cube",
            headRelativePosition: Vec3(0, 1.6, -1.5),
            headYOnly: true,
            scale: Vec3(0.3, 0.3, 0.3),
            fadeIn: 0.4
        )))
        try roundTrip(StepActionDTO.animateMotion(AnimateMotionActionDTO(
            entity: "cube",
            position: .orbit(center: Vec3(0, 1.5, -2), radius: 0.6, axis: Vec3(0, 1, 0), revolutions: 1, phase: 0),
            duration: 4.0
        )))
    }

    func testStepActionAudioVideo() throws {
        try roundTrip(StepActionDTO.playAudio(AudioActionDTO(
            file: "narration/intro",
            channel: "narration",
            scope: .ambient,
            volume: 0.8
        )))
        try roundTrip(StepActionDTO.fadeAudio(channel: "ambient", to: 0.0, duration: 2.0))
        try roundTrip(StepActionDTO.playVideo(VideoActionDTO(
            file: "skybox/main",
            channel: "skybox",
            presentation: .entity(name: "skybox", width: 12, height: 6)
        )))
        try roundTrip(StepActionDTO.onAudioComplete(channel: "narration", then: [
            .stopAudio(channel: "narration"),
            .showEntity(name: "cone")
        ]))
    }

    // MARK: - VideoLayout / ImmersiveField (Phase 5.2B)

    func testVideoLayoutVariants() throws {
        for layout in [VideoLayout.mono, .sideBySide, .overUnder, .multiviewHEVC] {
            try roundTrip(VideoActionDTO(
                file: "spatial",
                channel: "skybox",
                layout: layout
            ))
        }
    }

    func testImmersiveVideoPresentation() throws {
        try roundTrip(StepActionDTO.playVideo(VideoActionDTO(
            file: "test",
            channel: "skybox",
            presentation: .immersive(radius: 1000, field: .equirect360),
            layout: .mono
        )))
        try roundTrip(StepActionDTO.playVideo(VideoActionDTO(
            file: "spatial-180",
            channel: "skybox",
            presentation: .immersive(radius: 50, field: .equirect180),
            layout: .multiviewHEVC
        )))
    }

    func testVideoActionBackwardsCompat() throws {
        // Documents written before Phase 5.2B don't carry `layout`.
        let legacy = """
        { "file": "old", "channel": "skybox", "volume": 1, "loop": false,
          "presentation": { "kind": "attachment", "id": "video" } }
        """.data(using: .utf8)!
        let decoded = try ChapterScriptFormat.makeDecoder().decode(VideoActionDTO.self, from: legacy)
        XCTAssertEqual(decoded.layout, .mono)
        XCTAssertEqual(decoded.file, "old")
        // Pre-trim documents carry no source window or crop.
        XCTAssertNil(decoded.sourceIn)
        XCTAssertNil(decoded.sourceOut)
        XCTAssertNil(decoded.crop)
    }

    func testVideoActionSourceTrimRoundTrip() throws {
        try roundTrip(StepActionDTO.playVideo(VideoActionDTO(
            file: "master.mov",
            channel: "video-master",
            volume: 0.8,
            loop: true,
            presentation: .entity(name: "master.mov", width: 1.6, height: 0.9),
            layout: .mono,
            sourceIn: 12.5,
            sourceOut: 47.25,
            crop: VideoCropRect(x: 0.1, y: 0.0, width: 0.8, height: 1.0)
        )))
    }

    func testVideoActionSourceWindowDuration() {
        let trimmed = VideoActionDTO(
            file: "m.mov", channel: "c", sourceIn: 10, sourceOut: 25.5
        )
        XCTAssertEqual(trimmed.sourceWindowDuration ?? -1, 15.5, accuracy: 0.0001)
        // In-only trim: duration unknown until the player probes the asset.
        let inOnly = VideoActionDTO(file: "m.mov", channel: "c", sourceIn: 10)
        XCTAssertNil(inOnly.sourceWindowDuration)
        // Untrimmed: nil window.
        XCTAssertNil(VideoActionDTO(file: "m.mov", channel: "c").sourceWindowDuration)
    }

    func testStepActionMixCases() throws {
        try roundTrip(StepActionDTO.setBusVolume(busId: "narration", volume: 0.6))
        try roundTrip(StepActionDTO.setBusEffect(busId: "narration", effect: .reverb(wetDryMix: 0.3)))
        try roundTrip(StepActionDTO.setBusEffect(busId: "fx", effect: .compressor(threshold: -12, ratio: 4)))
    }

    func testStepActionVisibilityAndCustom() throws {
        try roundTrip(StepActionDTO.setUpperLimbVisibility(.hidden))
        try roundTrip(StepActionDTO.setKeyboardPassthrough(true))
        try roundTrip(StepActionDTO.custom(id: "vfx.shockwave", parameters: [
            "intensity": .double(0.8),
            "color": .string("#ff0033")
        ]))
    }

    func testStepActionUnknownForwardCompat() throws {
        // Hand-craft a JSON object with a kind not in the current enum.
        let json = """
        { "kind": "futureFeatureXYZ", "magic": 42, "label": "tomorrow" }
        """.data(using: .utf8)!
        let decoded = try ChapterScriptFormat.makeDecoder().decode(StepActionDTO.self, from: json)
        if case .unknown(let name, let raw) = decoded {
            XCTAssertEqual(name, "futureFeatureXYZ")
            if case .object(let dict) = raw {
                XCTAssertEqual(dict["magic"], .int(42))
                XCTAssertEqual(dict["label"], .string("tomorrow"))
            } else {
                XCTFail("expected object payload")
            }
        } else {
            XCTFail("expected .unknown case, got \(decoded)")
        }
    }

    // MARK: - Sequence / Step

    func testSequenceRoundTrip() throws {
        let sequence = SequenceDefinitionDTO(
            id: "voyage-prologue.intro",
            name: "Intro",
            phase: "immersive",
            steps: [
                StepDefinitionDTO(
                    id: "orb-reveal",
                    name: "Orb reveal",
                    duration: 4.0,
                    actions: [
                        .revealEntity(RevealActionDTO(
                            entity: "orb",
                            headRelativePosition: Vec3(0, 1.6, -2),
                            headYOnly: true,
                            scale: Vec3(0.3, 0.3, 0.3),
                            fadeIn: 0.5
                        )),
                        .playAudio(AudioActionDTO(file: "ambience/wind", channel: "ambient", scope: .ambient))
                    ],
                    scheduledActions: [
                        ScheduledActionDTO(at: 2.0, action: .showPulseRing(PulseRingConfigDTO()))
                    ],
                    gate: StepGateDTO(type: .tap, timeout: 30, prompt: "Tap to begin")
                )
            ],
            visibility: VisibilityStateDTO(["orb": true]),
            onComplete: .autoAdvance(nextSequenceId: "voyage-prologue.act-one")
        )
        try roundTrip(sequence)
    }

    // MARK: - Document

    func testMinimalDocumentRoundTrip() throws {
        let doc = ChapterDocument(
            id: "minimal",
            displayName: "Minimal Experience",
            entities: [
                EntityDefinition(
                    id: "orb",
                    kind: .primitive,
                    transform: TransformData(),
                    initiallyEnabled: false,
                    primitive: PrimitiveSpec(shape: .sphere, size: Vec3(0.15, 0.15, 0.15))
                )
            ],
            sequences: [
                SequenceDefinitionDTO(
                    id: "only",
                    name: "Only Sequence",
                    phase: "immersive",
                    steps: [StepDefinitionDTO(
                        id: "step1",
                        name: "Step 1",
                        duration: 2.0,
                        actions: [.showEntity(name: "orb")]
                    )]
                )
            ],
            manifest: AssetManifest(),
            defaultSequenceId: "only"
        )
        try roundTrip(doc)
    }

    func testEnvironmentRoundTrip() throws {
        let doc = ChapterDocument(
            id: "env",
            displayName: "Environment Experience",
            environment: EnvironmentSpec(lighting: "sunset", fogEnabled: true, fogDensity: 0.08)
        )
        try roundTrip(doc)
        try roundTrip(EnvironmentSpec())
    }

    func testLegacyDocumentWithoutEnvironmentDecodes() throws {
        // A pre-environment document: key not present.
        let json = """
        {
            "formatVersion": \(ChapterScriptFormat.currentFormatVersion),
            "id": "legacy",
            "displayName": "Legacy",
            "entities": [],
            "sequences": [],
            "particlePresets": [],
            "manifest": { "entries": [] }
        }
        """.data(using: .utf8)!
        let doc = try ChapterScriptFormat.makeDecoder().decode(ChapterDocument.self, from: json)
        XCTAssertNil(doc.environment)

        // Partially-specified environment falls back to field defaults.
        let spec = try ChapterScriptFormat.makeDecoder().decode(
            EnvironmentSpec.self, from: "{\"lighting\": \"night\"}".data(using: .utf8)!)
        XCTAssertEqual(spec.lighting, "night")
        XCTAssertFalse(spec.fogEnabled)
        XCTAssertEqual(spec.fogDensity, 0.02, accuracy: 0.0001)
    }

    // MARK: - Migrator

    func testMigratorReadsFormatVersion() throws {
        let json = "{\"formatVersion\": 1, \"id\": \"x\"}".data(using: .utf8)!
        XCTAssertEqual(try Migrator.readFormatVersion(from: json), 1)
    }

    func testMigratorIsIdentityForCurrentVersion() throws {
        let doc = ChapterDocument(id: "x", displayName: "X")
        let data = try ChapterScriptFormat.makeEncoder().encode(doc)
        let migrated = try Migrator.migrate(data, to: ChapterScriptFormat.currentFormatVersion)
        // Decoding both yields equal documents (data bytes may not be identical due to ordering).
        let a = try ChapterScriptFormat.makeDecoder().decode(ChapterDocument.self, from: data)
        let b = try ChapterScriptFormat.makeDecoder().decode(ChapterDocument.self, from: migrated)
        XCTAssertEqual(a, b)
    }

    func testMigratorRejectsNewerSourceVersion() throws {
        let json = "{\"formatVersion\": 9999}".data(using: .utf8)!
        XCTAssertThrowsError(try Migrator.migrate(json)) { error in
            guard case Migrator.MigrationError.sourceVersionTooNew(let v, _) = error else {
                XCTFail("expected sourceVersionTooNew, got \(error)"); return
            }
            XCTAssertEqual(v, 9999)
        }
    }
}
