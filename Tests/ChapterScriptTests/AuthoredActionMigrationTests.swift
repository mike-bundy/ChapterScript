import XCTest
@testable import ChapterScript

/// v3 → v4: two action buckets become one authored list with stable ids.
///
/// The contract is SEMANTIC IDENTITY, and for this migration that means one
/// thing above all others: **execution order must not change**. v3 awaited
/// every `actions` entry in array order before the timing loop began, then
/// fired `scheduledActions` as their `at` elapsed. A migration that shuffled
/// two actions at t = 0 would still decode, still play, and be wrong.
final class AuthoredActionMigrationTests: XCTestCase {

    // MARK: - Helpers

    private func v3Step(id: String,
                        duration: Double,
                        immediate: [String],
                        scheduled: [(Double, String)],
                        gate: [String: Any]? = nil) -> [String: Any] {
        var step: [String: Any] = [
            "id": id, "name": id, "duration": duration,
            "actions": immediate.map { ["kind": "showEntity", "name": $0] },
            "scheduledActions": scheduled.map {
                ["at": $0.0, "action": ["kind": "showEntity", "name": $0.1]]
            }
        ]
        if let gate { step["gate"] = gate }
        return step
    }

    private func v3Document(steps: [[String: Any]]) -> [String: Any] {
        [
            "formatVersion": 3,
            "id": "doc", "displayName": "Doc",
            "entities": [], "particlePresets": [],
            "manifest": ["entries": []],
            "sequences": [[
                "id": "seq", "name": "Seq", "phase": "immersive",
                "presentation": "immersive",
                "steps": steps,
                "visibility": [:],
                "onComplete": ["kind": "holdOnLastStep"]
            ]]
        ]
    }

    private func migrate(_ document: [String: Any]) throws -> ChapterDocument {
        let data = try JSONSerialization.data(withJSONObject: document)
        let migrated = try Migrator.migrate(data)
        return try ChapterScriptFormat.makeDecoder().decode(ChapterDocument.self, from: migrated)
    }

    private func names(_ step: StepDefinitionDTO) -> [String] {
        step.authoredActions.map {
            if case .showEntity(let name) = $0.action { return name }
            return "?"
        }
    }

    // MARK: - Ordering is the contract

    /// Immediate actions run BEFORE scheduled ones at the same instant, and
    /// each group keeps its authored order.
    func testExecutionOrderAtTimeZeroIsPreserved() throws {
        let doc = v3Document(steps: [
            v3Step(id: "s1", duration: 10,
                   immediate: ["A", "B", "C"],
                   scheduled: [(0, "D"), (0, "E")])
        ])
        let step = try migrate(doc).sequences[0].steps[0]
        XCTAssertEqual(names(step), ["A", "B", "C", "D", "E"],
                       "immediate first, in order, then scheduled at +0, in order")
        XCTAssertEqual(step.authoredActions.map(\.at), [0, 0, 0, 0, 0])
    }

    func testScheduledTimesArePreservedExactly() throws {
        let doc = v3Document(steps: [
            v3Step(id: "s1", duration: 20,
                   immediate: ["A"],
                   scheduled: [(2.5, "B"), (7.25, "C"), (19.999, "D")])
        ])
        let step = try migrate(doc).sequences[0].steps[0]
        XCTAssertEqual(step.authoredActions.map(\.at), [0, 2.5, 7.25, 19.999])
        XCTAssertEqual(names(step), ["A", "B", "C", "D"])
    }

    /// Out-of-order scheduled entries keep their authored order in the array;
    /// time ordering is applied at execution, not by rewriting the document.
    func testOutOfOrderScheduledEntriesAreNotResorted() throws {
        let doc = v3Document(steps: [
            v3Step(id: "s1", duration: 20, immediate: [],
                   scheduled: [(9, "late"), (1, "early")])
        ])
        let step = try migrate(doc).sequences[0].steps[0]
        XCTAssertEqual(names(step), ["late", "early"], "stored order is authored order")
        XCTAssertEqual(step.authoredActions.map(\.at), [9, 1])
    }

    // MARK: - Ids

    func testEveryMigratedActionGetsAnId() throws {
        let doc = v3Document(steps: [
            v3Step(id: "s1", duration: 10, immediate: ["A"], scheduled: [(1, "B")])
        ])
        let step = try migrate(doc).sequences[0].steps[0]
        XCTAssertTrue(step.authoredActions.allSatisfy { !$0.id.isEmpty })
    }

    func testIdsAreUniqueWithinAStep() throws {
        let doc = v3Document(steps: [
            v3Step(id: "s1", duration: 10,
                   immediate: ["A", "B", "C"], scheduled: [(1, "D"), (2, "E")])
        ])
        let step = try migrate(doc).sequences[0].steps[0]
        XCTAssertEqual(Set(step.authoredActions.map(\.id)).count, 5)
    }

    func testIdsAreUniqueAcrossSteps() throws {
        let doc = v3Document(steps: [
            v3Step(id: "s1", duration: 10, immediate: ["A"], scheduled: []),
            v3Step(id: "s2", duration: 10, immediate: ["B"], scheduled: [])
        ])
        let sequence = try migrate(doc).sequences[0]
        let all = sequence.steps.flatMap { $0.authoredActions.map(\.id) }
        XCTAssertEqual(Set(all).count, all.count)
    }

    /// DETERMINISM. Two machines migrating the same document independently must
    /// produce identical ids, or a tethered peer and the Mac would hold
    /// different identities for the same authored action and every op between
    /// them would miss.
    func testMigrationIsDeterministic() throws {
        let doc = v3Document(steps: [
            v3Step(id: "s1", duration: 10, immediate: ["A", "B"], scheduled: [(1, "C")])
        ])
        let first = try migrate(doc).sequences[0].steps[0].authoredActions.map(\.id)
        let second = try migrate(doc).sequences[0].steps[0].authoredActions.map(\.id)
        XCTAssertEqual(first, second)
    }

    /// The JSON migrator and the typed decoder's tolerant path both run in the
    /// wild — a document migrated on disk and the same document arriving over
    /// live sync must agree.
    func testJSONMigratorAndTolerantDecoderProduceTheSameIds() throws {
        let stepJSON = v3Step(id: "s1", duration: 10,
                              immediate: ["A", "B"], scheduled: [(1, "C")])
        let viaMigrator = try migrate(v3Document(steps: [stepJSON]))
            .sequences[0].steps[0].authoredActions.map(\.id)

        let data = try JSONSerialization.data(withJSONObject: stepJSON)
        let viaDecoder = try JSONDecoder()
            .decode(StepDefinitionDTO.self, from: data).authoredActions.map(\.id)

        XCTAssertEqual(viaMigrator, viaDecoder)
    }

    // MARK: - Idempotence

    func testMigratingAnAlreadyMigratedDocumentChangesNothing() throws {
        let doc = v3Document(steps: [
            v3Step(id: "s1", duration: 10, immediate: ["A"], scheduled: [(1, "B")])
        ])
        let once = try migrate(doc)
        let onceData = try ChapterScriptFormat.makeEncoder().encode(once)
        let twice = try Migrator.migrate(onceData)
        let decoded = try ChapterScriptFormat.makeDecoder()
            .decode(ChapterDocument.self, from: twice)
        XCTAssertEqual(decoded, once)
    }

    // MARK: - One persisted truth

    /// v4 must not write the legacy arrays at all. Two persisted
    /// representations of one fact is the failure this repository has already
    /// paid for once.
    func testV4EncodesOnlyAuthoredActions() throws {
        let step = StepDefinitionDTO(id: "s", name: "S", duration: 5,
                                     authoredActions: [
                                        AuthoredAction(at: 0, action: .showEntity(name: "A"))
                                     ])
        let data = try JSONEncoder().encode(step)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNotNil(object["authoredActions"])
        XCTAssertNil(object["actions"], "the legacy bucket must never be written")
        XCTAssertNil(object["scheduledActions"])
    }

    func testMigratedDocumentDropsTheLegacyArrays() throws {
        let doc = v3Document(steps: [
            v3Step(id: "s1", duration: 10, immediate: ["A"], scheduled: [(1, "B")])
        ])
        let data = try JSONSerialization.data(withJSONObject: doc)
        let migrated = try Migrator.migrate(data)
        let text = String(decoding: migrated, as: UTF8.self)
        XCTAssertTrue(text.contains("authoredActions"))
        XCTAssertFalse(text.contains("\"scheduledActions\""))
    }

    // MARK: - Everything else is untouched

    func testGatesSurviveMigration() throws {
        let doc = v3Document(steps: [
            v3Step(id: "s1", duration: 10, immediate: ["A"], scheduled: [],
                   gate: ["type": "gaze", "targetEntity": "Radio", "timeout": 12.0])
        ])
        let step = try migrate(doc).sequences[0].steps[0]
        XCTAssertEqual(step.gate?.type, .gaze)
        XCTAssertEqual(step.gate?.targetEntity, "Radio")
        XCTAssertEqual(step.gate?.timeout, 12)
    }

    func testStepIdsAndDurationsAreUntouched() throws {
        let doc = v3Document(steps: [
            v3Step(id: "segment_1_step_3", duration: 17.5, immediate: [], scheduled: [])  // LEGACY-VOCAB: an opaque authored id, deliberately never rewritten
        ])
        let step = try migrate(doc).sequences[0].steps[0]
        XCTAssertEqual(step.id, "segment_1_step_3", "opaque ids are never rewritten")  // LEGACY-VOCAB: the point of the test
        XCTAssertEqual(step.duration, 17.5)
    }

    func testEmptyStepMigratesToAnEmptyList() throws {
        let doc = v3Document(steps: [v3Step(id: "s1", duration: 5, immediate: [], scheduled: [])])
        XCTAssertEqual(try migrate(doc).sequences[0].steps[0].authoredActions, [])
    }

    // MARK: - Tolerant decode (live-sync payloads never see the migrator)

    func testStepFromAV3PeerStillDecodes() throws {
        let json = #"""
        {"id":"s1","name":"Step","duration":10,
         "actions":[{"kind":"showEntity","name":"A"}],
         "scheduledActions":[{"at":2,"action":{"kind":"hideEntity","name":"A"}}]}
        """#
        let step = try JSONDecoder().decode(StepDefinitionDTO.self, from: Data(json.utf8))
        XCTAssertEqual(step.authoredActions.count, 2)
        XCTAssertEqual(step.authoredActions.map(\.at), [0, 2])
    }

    func testStepWithBothShapesPrefersAuthoredActions() throws {
        // Should never occur, but if it does the canonical field wins rather
        // than the two silently merging into duplicates.
        let json = #"""
        {"id":"s1","name":"Step","duration":10,
         "authoredActions":[{"id":"act_x","at":0,"action":{"kind":"showEntity","name":"NEW"}}],
         "actions":[{"kind":"showEntity","name":"OLD"}]}
        """#
        let step = try JSONDecoder().decode(StepDefinitionDTO.self, from: Data(json.utf8))
        XCTAssertEqual(step.authoredActions.count, 1)
        XCTAssertEqual(step.authoredActions[0].id, "act_x")
    }

    // MARK: - Identity is not position

    func testInsertingAnActionDoesNotChangeItsNeighboursIds() {
        var step = StepDefinitionDTO(id: "s", name: "S", duration: 10, authoredActions: [
            AuthoredAction(id: "act_a", at: 0, action: .showEntity(name: "A")),
            AuthoredAction(id: "act_b", at: 5, action: .showEntity(name: "B"))
        ])
        step.authoredActions.insert(
            AuthoredAction(id: "act_new", at: 2, action: .showEntity(name: "N")), at: 1)
        XCTAssertEqual(step.authoredActions.map(\.id), ["act_a", "act_new", "act_b"])
    }

    func testSortingDoesNotChangeIdentity() {
        let actions = [
            AuthoredAction(id: "act_a", at: 9, action: .showEntity(name: "A")),
            AuthoredAction(id: "act_b", at: 1, action: .showEntity(name: "B"))
        ]
        let sorted = actions.sorted { $0.at < $1.at }
        XCTAssertEqual(sorted.map(\.id), ["act_b", "act_a"])
        XCTAssertEqual(Set(sorted.map(\.id)), Set(actions.map(\.id)))
    }

    func testANewActionGetsAFreshIdEveryTime() {
        let a = AuthoredAction(at: 0, action: .showEntity(name: "X"))
        let b = AuthoredAction(at: 0, action: .showEntity(name: "X"))
        XCTAssertNotEqual(a.id, b.id,
                          "two identical actions at one instant are two authored things")
    }
}
