//
//  StoryStateLedgerTests.swift
//  ChapterScriptTests
//
//  The runtime half: what a Chapter playback session remembers, what resets it,
//  and what must never be able to write it into a document.
//

import XCTest
@testable import ChapterScript

final class StoryStateLedgerTests: XCTestCase {

    private let radio = StoryChoiceOption(id: "opt_radio", name: "Radio")
    private let camera = StoryChoiceOption(id: "opt_camera", name: "Camera")

    private func definitions() -> [StoryStateDefinition] {
        [
            StoryStateDefinition(id: "sst_radio", name: "Radio Heard", kind: .yesNo),
            StoryStateDefinition(id: "sst_camera", name: "Camera Examined", kind: .yesNo),
            StoryStateDefinition(id: "sst_objects", name: "Objects Found", kind: .number),
            StoryStateDefinition(id: "sst_route", name: "Selected Route", kind: .choice,
                                 options: [radio, camera]),
        ]
    }

    // MARK: - The lifetime rule

    /// RUNTIME VALUES ARE NOT DOCUMENT STATE. Asserted structurally, the same
    /// way `SequenceVisit` is, because a `Codable` conformance added by habit is
    /// how a viewer's progress ends up inside somebody's `chapter.json`.
    func testTheLedgerIsNotCodable() {
        XCTAssertFalse((StoryStateLedger.self as Any) is any Codable.Type)
    }

    func testASessionStartsFromTheAuthoredInitialValues() {
        let ledger = StoryStateLedger(definitions: definitions())
        XCTAssertEqual(ledger.storyStateValue("sst_radio"), .yesNo(false))
        XCTAssertEqual(ledger.storyStateValue("sst_objects"), .number(0))
        XCTAssertEqual(ledger.storyStateValue("sst_route"), .choice(optionId: nil))
    }

    func testAFreshSessionResetsEverything() {
        var ledger = StoryStateLedger(definitions: definitions())
        ledger.apply(.init(stateId: "sst_radio", operation: .setYesNo(true)))
        ledger.apply(.init(stateId: "sst_objects", operation: .changeNumber(by: 3)))
        ledger.apply(.init(stateId: "sst_route", operation: .setChoice(optionId: radio.id)))

        ledger.beginFreshSession()

        XCTAssertEqual(ledger.storyStateValue("sst_radio"), .yesNo(false))
        XCTAssertEqual(ledger.storyStateValue("sst_objects"), .number(0))
        XCTAssertEqual(ledger.storyStateValue("sst_route"), .choice(optionId: nil))
    }

    // MARK: - Mutation

    func testMutationsAccumulateAcrossTheSession() {
        var ledger = StoryStateLedger(definitions: definitions())
        ledger.apply(.init(stateId: "sst_objects", operation: .changeNumber(by: 1)))
        ledger.apply(.init(stateId: "sst_objects", operation: .changeNumber(by: 1)))
        XCTAssertEqual(ledger.storyStateValue("sst_objects"), .number(2))
    }

    /// A refusal changes nothing and SAYS SO. A silent no-op is how a story
    /// stops advancing for reasons nobody can find.
    func testAMutationForAnUnknownStateIsRefusedAndChangesNothing() {
        var ledger = StoryStateLedger(definitions: definitions())
        let result = ledger.apply(.init(stateId: "sst_gone", operation: .setYesNo(true)))
        guard case .failure(.unknownState(let id)) = result else {
            return XCTFail("An unknown state must be refused, not created.")
        }
        XCTAssertEqual(id, "sst_gone")
        XCTAssertNil(ledger.storyStateValue("sst_gone"),
                     "A mutation must never bring a Story State into existence.")
    }

    func testAMismatchedMutationIsRefusedAndChangesNothing() {
        var ledger = StoryStateLedger(definitions: definitions())
        let result = ledger.apply(.init(stateId: "sst_objects", operation: .setYesNo(true)))
        guard case .failure(.kindMismatch) = result else {
            return XCTFail("A Yes/No change cannot be applied to a Number.")
        }
        XCTAssertEqual(ledger.storyStateValue("sst_objects"), .number(0))
    }

    // MARK: - Reading

    /// The ledger IS the reading the evaluator takes, so a gate and a branch ask
    /// the running session rather than a copy of it.
    func testTheLedgerEvaluatesConditionsDirectly() {
        var ledger = StoryStateLedger(definitions: definitions())
        let group = StoryConditionGroup(conditions: [
            StoryCondition(stateId: "sst_objects", comparison: .number(.atLeast, 2))
        ])
        XCTAssertFalse(StoryConditionEvaluator.evaluate(group, in: ledger))
        ledger.apply(.init(stateId: "sst_objects", operation: .changeNumber(by: 2)))
        XCTAssertTrue(StoryConditionEvaluator.evaluate(group, in: ledger))
    }

    func testTheSnapshotFollowsAuthoredOrder() {
        let ledger = StoryStateLedger(definitions: definitions())
        XCTAssertEqual(ledger.snapshot.map(\.definition.name),
                       ["Radio Heard", "Camera Examined", "Objects Found", "Selected Route"])
    }

    func testEndingASessionForgetsEverything() {
        var ledger = StoryStateLedger(definitions: definitions())
        ledger.end()
        XCTAssertTrue(ledger.isEmpty)
        XCTAssertNil(ledger.storyStateValue("sst_radio"))
    }
}
