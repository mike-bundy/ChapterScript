//
//  StoryConditionTests.swift
//  ChapterScriptTests
//
//  The one condition evaluator, and the gate integration built on it.
//

import XCTest
@testable import ChapterScript

final class StoryConditionTests: XCTestCase {

    private let radioHeard = "sst_radio"
    private let objectsFound = "sst_objects"
    private let selectedRoute = "sst_route"

    // MARK: - Yes / No

    func testYesNoComparisons() {
        let state: [String: StoryStateValue] = [radioHeard: .yesNo(true)]
        XCTAssertTrue(satisfied(.yesNo(true), on: radioHeard, in: state))
        XCTAssertFalse(satisfied(.yesNo(false), on: radioHeard, in: state))
    }

    // MARK: - Number

    func testNumberComparisons() {
        let state: [String: StoryStateValue] = [objectsFound: .number(2)]
        XCTAssertTrue(satisfied(.number(.equals, 2), on: objectsFound, in: state))
        XCTAssertFalse(satisfied(.number(.equals, 3), on: objectsFound, in: state))
        XCTAssertTrue(satisfied(.number(.atLeast, 2), on: objectsFound, in: state))
        XCTAssertTrue(satisfied(.number(.atLeast, 1), on: objectsFound, in: state))
        XCTAssertFalse(satisfied(.number(.atLeast, 3), on: objectsFound, in: state))
        XCTAssertTrue(satisfied(.number(.atMost, 2), on: objectsFound, in: state))
        XCTAssertFalse(satisfied(.number(.atMost, 1), on: objectsFound, in: state))
    }

    // MARK: - Choice

    func testChoiceComparisons() {
        let state: [String: StoryStateValue] = [selectedRoute: .choice(optionId: "opt_radio")]
        XCTAssertTrue(satisfied(.choice(matches: true, optionId: "opt_radio"),
                                on: selectedRoute, in: state))
        XCTAssertFalse(satisfied(.choice(matches: true, optionId: "opt_camera"),
                                 on: selectedRoute, in: state))
        XCTAssertTrue(satisfied(.choice(matches: false, optionId: "opt_camera"),
                                on: selectedRoute, in: state))
    }

    /// Before the viewer chooses, the route is not Radio — and it IS “not
    /// Radio”. Both readings are the honest one.
    func testAnUnchosenChoiceMatchesNoOptionAndIsNotEveryOption() {
        let state: [String: StoryStateValue] = [selectedRoute: .choice(optionId: nil)]
        XCTAssertFalse(satisfied(.choice(matches: true, optionId: "opt_radio"),
                                 on: selectedRoute, in: state))
        XCTAssertTrue(satisfied(.choice(matches: false, optionId: "opt_radio"),
                                on: selectedRoute, in: state))
    }

    // MARK: - What cannot be answered is false, and is reported

    /// A condition naming a deleted Story State must NEVER read as true — a gate
    /// that silently opens and a branch that silently fires are the two worst
    /// outcomes available here.
    func testAConditionOnAnUnknownStateIsFalseAndReported() {
        let outcome = StoryConditionEvaluator.evaluate(
            StoryCondition(stateId: "sst_gone", comparison: .yesNo(true)),
            in: [String: StoryStateValue]())
        XCTAssertFalse(outcome.satisfied)
        XCTAssertEqual(outcome.problem, .unknownState("sst_gone"))
    }

    func testAComparisonForTheWrongKindIsFalseAndReported() {
        let outcome = StoryConditionEvaluator.evaluate(
            StoryCondition(stateId: objectsFound, comparison: .yesNo(true)),
            in: [objectsFound: StoryStateValue.number(2)])
        XCTAssertFalse(outcome.satisfied)
        XCTAssertEqual(outcome.problem, .kindMismatch(stateId: objectsFound, held: .number))
    }

    /// An unrecognised NUMBER comparison becomes unsupported rather than
    /// defaulting to `.equals`: “at least 2” quietly read as “exactly 2” is a
    /// gate that never opens.
    func testAnUnknownNumberComparisonIsUnsupportedNotEquals() throws {
        let json = #"{"kind":"number","comparison":"isPrime","number":2}"#
        let decoded = try JSONDecoder().decode(StoryComparison.self, from: Data(json.utf8))
        guard case .unsupported(let kind, _) = decoded else {
            return XCTFail("An unknown comparison must not be read as one this build has.")
        }
        XCTAssertEqual(kind, "number")

        let outcome = StoryConditionEvaluator.evaluate(
            StoryCondition(stateId: objectsFound, comparison: decoded),
            in: [objectsFound: StoryStateValue.number(2)])
        XCTAssertFalse(outcome.satisfied)
    }

    // MARK: - Match All / Match Any

    func testMatchAllNeedsEveryCondition() {
        let group = StoryConditionGroup(match: .all, conditions: [
            StoryCondition(stateId: radioHeard, comparison: .yesNo(true)),
            StoryCondition(stateId: "sst_camera", comparison: .yesNo(true)),
        ])
        XCTAssertFalse(StoryConditionEvaluator.evaluate(
            group, in: [radioHeard: StoryStateValue.yesNo(true),
                        "sst_camera": StoryStateValue.yesNo(false)]))
        XCTAssertTrue(StoryConditionEvaluator.evaluate(
            group, in: [radioHeard: StoryStateValue.yesNo(true),
                        "sst_camera": StoryStateValue.yesNo(true)]))
    }

    func testMatchAnyNeedsOnlyOne() {
        let group = StoryConditionGroup(match: .any, conditions: [
            StoryCondition(stateId: radioHeard, comparison: .yesNo(true)),
            StoryCondition(stateId: "sst_camera", comparison: .yesNo(true)),
        ])
        XCTAssertTrue(StoryConditionEvaluator.evaluate(
            group, in: [radioHeard: StoryStateValue.yesNo(true),
                        "sst_camera": StoryStateValue.yesNo(false)]))
        XCTAssertTrue(StoryConditionEvaluator.evaluate(
            group, in: [radioHeard: StoryStateValue.yesNo(false),
                        "sst_camera": StoryStateValue.yesNo(true)]))
        XCTAssertFalse(StoryConditionEvaluator.evaluate(
            group, in: [radioHeard: StoryStateValue.yesNo(false),
                        "sst_camera": StoryStateValue.yesNo(false)]))
    }

    /// A group with nothing in it imposes no requirement, in BOTH modes.
    /// “Match Any of nothing” blocking forever would turn removing the last
    /// condition into a deadlock.
    func testAnEmptyGroupImposesNothing() {
        for match in StoryConditionGroup.Match.allCases {
            XCTAssertTrue(StoryConditionEvaluator.evaluate(
                StoryConditionGroup(match: match), in: [String: StoryStateValue]()))
        }
    }

    /// An unknown match mode falls back to the STRICTER reading: a story that
    /// pauses is recoverable, a story that runs ahead of the author's check is
    /// not.
    func testAnUnknownMatchModeFallsBackToAll() throws {
        let json = #"{"match":"exactlyTwoOf","conditions":[]}"#
        let group = try JSONDecoder().decode(StoryConditionGroup.self, from: Data(json.utf8))
        XCTAssertEqual(group.match, .all)
    }

    // MARK: - Gates

    /// A gate carrying no conditions behaves exactly as it always has.
    func testAGateWithNoConditionsIsUnchanged() {
        let gate = StepGateDTO(type: .tap, targetEntity: "Radio")
        XCTAssertTrue(GateActivation.satisfies(
            gate: gate,
            activation: .init(entityName: "Radio", trigger: .tap),
            state: [String: StoryStateValue]()))
    }

    /// A story-condition gate is continued by what the Chapter remembers, and by
    /// NO act. A stray tap must not release it.
    func testAStoryConditionGateIsSatisfiedByStateAndNeverByAnAct() {
        let gate = StepGateDTO(type: .storyCondition, storyConditions: .init(conditions: [
            StoryCondition(stateId: radioHeard, comparison: .yesNo(true))
        ]))
        XCTAssertFalse(GateActivation.satisfiedByStory(
            gate, in: [radioHeard: StoryStateValue.yesNo(false)]))
        XCTAssertTrue(GateActivation.satisfiedByStory(
            gate, in: [radioHeard: StoryStateValue.yesNo(true)]))

        // No activation of any kind opens it.
        for trigger: InteractionTrigger in [.tap, .grab, .viewerFacing(dwell: 1),
                                            .approach(radius: 1)] {
            XCTAssertFalse(GateActivation.satisfies(
                gate: gate,
                activation: .init(entityName: nil, trigger: trigger),
                state: [radioHeard: StoryStateValue.yesNo(true)]),
                "A story-condition gate waits for the story, not for \(trigger.kindName).")
        }
        XCTAssertNil(GateActivation.trigger(for: .storyCondition))
    }

    /// MIXED, and it falls out of one field: tap the door, once you have the
    /// key. The tap alone is not enough.
    func testAConditionOnATapGateIsAnAdditionalRequirement() {
        let gate = StepGateDTO(type: .tap, targetEntity: "Door",
                               storyConditions: .init(conditions: [
                                   StoryCondition(stateId: radioHeard, comparison: .yesNo(true))
                               ]))
        let tap = SemanticActivation(entityName: "Door", trigger: .tap)
        XCTAssertFalse(GateActivation.satisfies(
            gate: gate, activation: tap, state: [radioHeard: StoryStateValue.yesNo(false)]))
        XCTAssertTrue(GateActivation.satisfies(
            gate: gate, activation: tap, state: [radioHeard: StoryStateValue.yesNo(true)]))
        // And the state alone does not open a gate that asked for an act.
        XCTAssertFalse(GateActivation.satisfiedByStory(
            gate, in: [radioHeard: StoryStateValue.yesNo(true)]))
    }

    func testAGateCarriesItsConditionsThroughARoundTrip() throws {
        let gate = StepGateDTO(type: .storyCondition, prompt: "Find the objects",
                               storyConditions: .init(match: .any, conditions: [
                                   StoryCondition(stateId: objectsFound,
                                                  comparison: .number(.atLeast, 2))
                               ]))
        let data = try JSONEncoder().encode(gate)
        XCTAssertEqual(try JSONDecoder().decode(StepGateDTO.self, from: data), gate)
    }

    /// An EMPTY group is not written: a key that imposes nothing is a key a
    /// future reader has to make a decision about.
    func testAnEmptyConditionGroupIsNotWritten() throws {
        let gate = StepGateDTO(type: .tap, storyConditions: StoryConditionGroup())
        let data = try JSONEncoder().encode(gate)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data)
                                   as? [String: Any])
        XCTAssertNil(object["storyConditions"])
    }

    /// The wire spelling every existing Chapter carries is untouched.
    func testExistingGateTypesAreUnchangedOnTheWire() throws {
        // LEGACY-INTERACTION-VOCAB: `"gaze"` is the WIRE spelling every existing
        // Chapter carries, asserted here precisely so adding a gate type cannot
        // change it. Nothing in this build reads it as a claim about the eyes.
        for (type, raw) in [(GateType.tap, "tap"), (.viewerFacing, "gaze"),   // LEGACY-INTERACTION-VOCAB
                            (.proximity, "proximity"), (.grab, "grab"),
                            (.storyCondition, "storyCondition")] as [(GateType, String)] {
            let data = try JSONEncoder().encode(type)
            XCTAssertEqual(String(data: data, encoding: .utf8), "\"\(raw)\"")
        }
    }

    // MARK: - Helpers

    private func satisfied(_ comparison: StoryComparison, on stateId: String,
                           in state: [String: StoryStateValue]) -> Bool {
        StoryConditionEvaluator.evaluate(
            StoryCondition(stateId: stateId, comparison: comparison), in: state).satisfied
    }
}
