import XCTest
@testable import ChapterScript

/// v2 → v3 is the Segment → Sequence rename. The contract is **semantic identity**:
/// a document authored before the rename must describe the same experience after it,
/// frame for frame, id for id.
///
/// The load-bearing test here is `testMigrationIsSemanticIdentity`, and it is written
/// as a *property* rather than as a list of field assertions. Enumerating fields by
/// hand only ever proves the fields someone remembered to enumerate — and the fields
/// most likely to be silently mangled by a rename are the ones nobody thinks to list.
/// So instead: build a rich v3 document, mechanically DOWNGRADE it to v2, migrate it
/// forward again, and require the result to be `==` the original. Any field the
/// migration disturbs — including one added to the format years from now — fails this
/// test without anyone having to remember it exists.
///
/// The explicit assertions that follow are not redundant with it. They pin the four
/// things whose *breakage would be silent rather than loud*: absolute animation key
/// times, opaque authored ids, media source ranges, and the `AudioScope` raw value.
final class SequenceMigrationTests: XCTestCase {

    // MARK: - Building a document that actually exercises the format

    /// A document deliberately loaded with everything the migration could plausibly
    /// damage: absolute-time animation keys with tangents, a gate with a spatial
    /// target, scheduled actions at non-zero offsets, media source ranges on video
    /// AND audio, a backdrop cue with its own range, audio automation, and an
    /// `autoAdvance` chain (whose payload key is one of the four the step renames).
    private func makeRichDocument() -> ChapterDocument {
        let curve = AnimationCurve(keys: [
            AnimationKey(time: 0.0,  value: 0),
            // Deliberately awkward absolute times: not on a frame boundary, not
            // round. If anything ever "helpfully" re-quantises animation during a
            // migration, these are the values that catch it.
            AnimationKey(time: 12.5, value: 1.75),
            AnimationKey(time: 41.333333, value: -3.25)
        ])

        let track = EntityAnimationTrack(
            entity: "hero",
            rotationOrder: .zxy,
            curves: [.tx: curve, .opacity: curve]
        )

        let video = VideoActionDTO(
            file: "interview.mov",
            channel: "video_1",
            volume: 0.8,
            loop: false,
            sourceIn: 3.5,
            sourceOut: 19.25
        )

        let audio = AudioActionDTO(
            file: "score.wav",
            channel: "music",
            scope: .sequence,        // the raw value that was spelled "segment" in v2
            volume: 0.6,
            loop: true,
            sourceIn: 1.5,
            sourceOut: 30.0
        )

        let stepOne = StepDefinitionDTO(
            id: "step_a",
            name: "Open",
            duration: 8.0,
            actions: [.playVideo(video)],
            scheduledActions: [ScheduledActionDTO(at: 2.25, action: .playAudio(audio))],
            gate: StepGateDTO(type: .proximity, timeout: 12, prompt: "Step closer", targetEntity: "hero", radius: 1.5)
        )

        let stepTwo = StepDefinitionDTO(
            id: "step_b",
            name: "Hold",
            duration: 5.5,
            actions: [],
            scheduledActions: []
        )

        let first = SequenceDefinitionDTO(
            id: "segment_01_opening",   // an id authored UNDER THE OLD NAME — see below
            name: "Opening",
            phase: "immersive",
            presentation: .immersive,
            steps: [stepOne, stepTwo],
            animationTracks: [track],
            audioTracks: [AudioAutomationTrack(channel: "music", curves: [.volume: curve])],
            backdropTrack: [BackdropCue(id: "cue_1", startTime: 4.0, spec: nil, sourceIn: 2.0, sourceOut: 22.0)],
            onComplete: .autoAdvance(nextSequenceId: "segment_02_closing"),
            editorColorIndex: 3
        )

        let second = SequenceDefinitionDTO(
            id: "segment_02_closing",
            name: "Closing",
            phase: "mixed",
            presentation: .mixed,
            steps: [stepTwo],
            onComplete: .holdOnLastStep
        )

        return ChapterDocument(
            id: "migration-subject",
            displayName: "Migration Subject",
            sequences: [first, second],
            defaultSequenceId: "segment_01_opening"
        )
    }

    // MARK: - The inverse transform

    /// Rewrite a v3 document's JSON back into v2 vocabulary. This is the exact
    /// inverse of `Migrator`'s v2 → v3 step, written independently so the two are
    /// not the same code checking itself.
    private func downgradeToV2(_ node: Any) -> Any {
        let renames = [
            "sequences": "segments",
            "defaultSequenceId": "defaultSegmentId",
            "nextSequenceId": "nextSegmentId"
        ]
        if let object = node as? [String: Any] {
            var result: [String: Any] = [:]
            for (key, value) in object {
                let newKey = renames[key] ?? key
                if key == "scope", let raw = value as? String, raw == "sequence" {
                    result[newKey] = "segment"
                    continue
                }
                if key == "formatVersion" {
                    result[newKey] = 2
                    continue
                }
                result[newKey] = downgradeToV2(value)
            }
            return result
        }
        if let array = node as? [Any] { return array.map(downgradeToV2) }
        return node
    }

    private func v2Data(from document: ChapterDocument) throws -> Data {
        let encoded = try ChapterScriptFormat.makeEncoder().encode(document)
        let tree = try JSONSerialization.jsonObject(with: encoded)
        return try JSONSerialization.data(withJSONObject: downgradeToV2(tree))
    }

    // MARK: - The property

    func testMigrationIsSemanticIdentity() throws {
        let original = makeRichDocument()
        let asV2 = try v2Data(from: original)

        // Precondition: we really did produce a v2 document, not a v3 one in disguise.
        XCTAssertEqual(try Migrator.readFormatVersion(from: asV2), 2)
        let v2Text = String(decoding: asV2, as: UTF8.self)
        XCTAssertTrue(v2Text.contains("\"segments\""), "downgrade should emit v2 vocabulary")
        XCTAssertFalse(v2Text.contains("\"sequences\""))

        let migrated = try Migrator.migrate(asV2)
        XCTAssertEqual(try Migrator.readFormatVersion(from: migrated), 3)

        let decoded = try ChapterScriptFormat.makeDecoder().decode(ChapterDocument.self, from: migrated)

        // formatVersion is the ONE field the migration is supposed to change.
        var expected = original
        expected.formatVersion = ChapterScriptFormat.currentFormatVersion

        XCTAssertEqual(decoded, expected, "v2 → v3 must be a pure rename; some field was altered")
    }

    // MARK: - The four silent-breakage risks, pinned explicitly

    /// Animation keys sit at ABSOLUTE sequence seconds. A migration that rebuilt or
    /// re-quantised curves would still decode, still play, and be wrong by a frame
    /// in a way no one notices until a cut lands late.
    func testAnimationKeyTimesSurviveExactly() throws {
        let migrated = try Migrator.migrate(try v2Data(from: makeRichDocument()))
        let doc = try ChapterScriptFormat.makeDecoder().decode(ChapterDocument.self, from: migrated)

        let track = try XCTUnwrap(doc.sequences.first?.animationTracks.first)
        XCTAssertEqual(track.entity, "hero")
        XCTAssertEqual(track.rotationOrder, .zxy)

        let keys = try XCTUnwrap(track.curves[.tx]).keys
        XCTAssertEqual(keys.map(\.time), [0.0, 12.5, 41.333333])
        XCTAssertEqual(keys.map(\.value), [0, 1.75, -3.25])
    }

    /// Ids are opaque authored strings. A document written before the rename keeps
    /// `segment_*` ids forever — and everything that REFERENCES a sequence by id
    /// (here, the `autoAdvance` chain) has to keep pointing at the same string.
    func testAuthoredIdsAreNeverRewritten() throws {
        let migrated = try Migrator.migrate(try v2Data(from: makeRichDocument()))
        let doc = try ChapterScriptFormat.makeDecoder().decode(ChapterDocument.self, from: migrated)

        XCTAssertEqual(doc.sequences.map(\.id), ["segment_01_opening", "segment_02_closing"])
        XCTAssertEqual(doc.defaultSequenceId, "segment_01_opening")

        guard case .autoAdvance(let next) = doc.sequences[0].onComplete else {
            return XCTFail("expected autoAdvance")
        }
        XCTAssertEqual(next, "segment_02_closing", "autoAdvance target must still resolve")
    }

    /// Source ranges are the author's trim decisions. They live on three different
    /// carriers (video action, audio action, backdrop cue) and all three must survive.
    func testSourceRangesSurviveOnEveryCarrier() throws {
        let migrated = try Migrator.migrate(try v2Data(from: makeRichDocument()))
        let doc = try ChapterScriptFormat.makeDecoder().decode(ChapterDocument.self, from: migrated)
        let step = try XCTUnwrap(doc.sequences.first?.steps.first)

        guard case .playVideo(let video) = step.actions.first else { return XCTFail("expected playVideo") }
        XCTAssertEqual(video.sourceIn, 3.5)
        XCTAssertEqual(video.sourceOut, 19.25)

        guard case .playAudio(let audio) = step.scheduledActions.first?.action else {
            return XCTFail("expected scheduled playAudio")
        }
        XCTAssertEqual(audio.sourceIn, 1.5)
        XCTAssertEqual(audio.sourceOut, 30.0)
        XCTAssertEqual(step.scheduledActions.first?.at, 2.25, "scheduled offset must not move")

        let cue = try XCTUnwrap(doc.sequences.first?.backdropTrack.first)
        XCTAssertEqual(cue.id, "cue_1")
        XCTAssertEqual(cue.startTime, 4.0)
        XCTAssertEqual(cue.sourceIn, 2.0)
        XCTAssertEqual(cue.sourceOut, 22.0)
    }

    /// Gates carry a spatial target and radius. A gate whose `targetEntity` got lost
    /// can never be satisfied — the step would hang until its timeout.
    func testGatesSurviveIntact() throws {
        let migrated = try Migrator.migrate(try v2Data(from: makeRichDocument()))
        let doc = try ChapterScriptFormat.makeDecoder().decode(ChapterDocument.self, from: migrated)

        let gate = try XCTUnwrap(doc.sequences.first?.steps.first?.gate)
        XCTAssertEqual(gate.type, .proximity)
        XCTAssertEqual(gate.targetEntity, "hero")
        XCTAssertEqual(gate.radius, 1.5)
        XCTAssertEqual(gate.timeout, 12)
        XCTAssertEqual(gate.prompt, "Step closer")
    }

    // MARK: - Raw v2 data, not synthesised

    /// `AudioScope` was a String raw-value enum, so v2 baked the old vocabulary into
    /// the DATA as `"scope": "segment"`. Both routes must handle it: the migrator
    /// (documents) and tolerant decode (live-sync op payloads, which never migrate).
    func testAudioScopeSegmentRawValue() throws {
        let v2Action = #"{"kind":"playAudio","audio":{"file":"a.wav","channel":"music","scope":"segment","volume":1,"loop":false}}"#
            .data(using: .utf8)!
        let action = try ChapterScriptFormat.makeDecoder().decode(StepActionDTO.self, from: v2Action)
        guard case .playAudio(let audio) = action else { return XCTFail("expected playAudio") }
        XCTAssertEqual(audio.scope, .sequence, "v2 \"segment\" scope must decode as .sequence")

        // And it must re-encode in the new vocabulary, so the value converges.
        let reencoded = try ChapterScriptFormat.makeEncoder().encode(action)
        let text = String(decoding: reencoded, as: UTF8.self)
        XCTAssertTrue(text.contains("\"sequence\""))
        XCTAssertFalse(text.contains("\"segment\""))
    }

    /// An unknown scope must not fail a whole document load — same forward-compat
    /// rule `GateType` follows.
    func testUnknownAudioScopeDegradesRatherThanThrowing() throws {
        let future = #"{"kind":"playAudio","audio":{"file":"a.wav","channel":"m","scope":"holodeck","volume":1,"loop":false}}"#
            .data(using: .utf8)!
        let action = try ChapterScriptFormat.makeDecoder().decode(StepActionDTO.self, from: future)
        guard case .playAudio(let audio) = action else { return XCTFail("expected playAudio") }
        XCTAssertEqual(audio.scope, .sequence)
    }

    // MARK: - Forward direction

    func testNewSavesWriteSequenceVocabulary() throws {
        let encoded = try ChapterScriptFormat.makeEncoder().encode(makeRichDocument())
        let text = String(decoding: encoded, as: UTF8.self)

        XCTAssertTrue(text.contains("\"sequences\""))
        XCTAssertTrue(text.contains("\"defaultSequenceId\""))
        XCTAssertTrue(text.contains("\"nextSequenceId\""))
        XCTAssertFalse(text.contains("\"segments\""), "new saves must not emit v2 keys")
        XCTAssertFalse(text.contains("\"defaultSegmentId\""))
        XCTAssertFalse(text.contains("\"nextSegmentId\""))
    }

    /// A v3 document must pass through the migrator untouched — migrating an
    /// already-current document should be a no-op, not a second rename pass.
    func testMigratingACurrentDocumentIsANoOp() throws {
        let encoded = try ChapterScriptFormat.makeEncoder().encode(makeRichDocument())
        let migrated = try Migrator.migrate(encoded)
        XCTAssertEqual(
            try ChapterScriptFormat.makeDecoder().decode(ChapterDocument.self, from: migrated),
            try ChapterScriptFormat.makeDecoder().decode(ChapterDocument.self, from: encoded)
        )
    }
}
