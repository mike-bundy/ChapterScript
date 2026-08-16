//
//  StoryBranchTests.swift
//  ChapterScriptTests
//
//  Conditional navigation: the priority rule, Otherwise, no-match, and the fact
//  that a branch is performed by the SAME navigator everything else uses.
//

import XCTest
@testable import ChapterScript

final class StoryBranchTests: XCTestCase {

    private let route = "sst_route"
    private let objects = "sst_objects"

    private func branchCase(_ comparison: StoryComparison,
                            on stateId: String,
                            to target: String,
                            id: String = StoryBranchCase.newID()) -> StoryBranchCase {
        StoryBranchCase(id: id,
                        conditions: .init(conditions: [
                            StoryCondition(stateId: stateId, comparison: comparison)
                        ]),
                        intent: .goTo(sequenceId: target))
    }

    // MARK: - Priority

    /// **THE RULE: the first matching authored case wins.** Two cases can be
    /// true at once, and order is the one tie-break an author can see and change.
    func testTheFirstMatchingCaseWins() {
        let intent = NavigationIntent.branch(cases: [
            branchCase(.number(.atLeast, 1), on: objects, to: "Some"),
            branchCase(.number(.atLeast, 3), on: objects, to: "Many"),
        ], otherwise: .goTo(sequenceId: "None"))

        XCTAssertEqual(intent.resolving(in: [objects: StoryStateValue.number(4)]),
                       .goTo(sequenceId: "Some"))
    }

    /// And reordering changes the answer, which is what makes the rule usable.
    func testReorderingTheCasesChangesTheOutcome() {
        let some = branchCase(.number(.atLeast, 1), on: objects, to: "Some")
        let many = branchCase(.number(.atLeast, 3), on: objects, to: "Many")
        let state: [String: StoryStateValue] = [objects: .number(4)]

        XCTAssertEqual(NavigationIntent.branch(cases: [some, many], otherwise: nil)
                        .resolving(in: state), .goTo(sequenceId: "Some"))
        XCTAssertEqual(NavigationIntent.branch(cases: [many, some], otherwise: nil)
                        .resolving(in: state), .goTo(sequenceId: "Many"))
    }

    // MARK: - Otherwise, and no match

    func testOtherwiseFiresOnlyWhenNothingElseMatches() {
        let intent = NavigationIntent.branch(cases: [
            branchCase(.choice(matches: true, optionId: "opt_radio"), on: route, to: "Radio Story"),
            branchCase(.choice(matches: true, optionId: "opt_camera"), on: route, to: "Camera Story"),
        ], otherwise: .goTo(sequenceId: "Main Ending"))

        XCTAssertEqual(intent.resolving(in: [route: StoryStateValue.choice(optionId: "opt_radio")]),
                       .goTo(sequenceId: "Radio Story"))
        XCTAssertEqual(intent.resolving(in: [route: StoryStateValue.choice(optionId: "opt_camera")]),
                       .goTo(sequenceId: "Camera Story"))
        XCTAssertEqual(intent.resolving(in: [route: StoryStateValue.choice(optionId: nil)]),
                       .goTo(sequenceId: "Main Ending"))
    }

    /// **NO MATCH AND NO OTHERWISE IS HOLD.** Nothing is invented, and this is
    /// exactly what `forCompletion` already returns for `.holdOnLastStep`.
    func testNoMatchAndNoOtherwiseIsHold() {
        let intent = NavigationIntent.branch(cases: [
            branchCase(.choice(matches: true, optionId: "opt_radio"), on: route, to: "Radio Story"),
        ], otherwise: nil)

        XCTAssertNil(intent.resolving(in: [route: StoryStateValue.choice(optionId: nil)]))
    }

    /// A branch whose conditions can never be answered — a deleted Story State —
    /// takes Otherwise, and takes NOTHING when there is no Otherwise. It never
    /// falls through to the first case.
    func testABranchOnADeletedStateNeverPicksTheFirstCase() {
        let intent = NavigationIntent.branch(cases: [
            branchCase(.yesNo(true), on: "sst_gone", to: "Radio Story"),
        ], otherwise: .goTo(sequenceId: "Main Ending"))
        XCTAssertEqual(intent.resolving(in: [String: StoryStateValue]()),
                       .goTo(sequenceId: "Main Ending"))

        let noFallback = NavigationIntent.branch(cases: [
            branchCase(.yesNo(true), on: "sst_gone", to: "Radio Story"),
        ], otherwise: nil)
        XCTAssertNil(noFallback.resolving(in: [String: StoryStateValue]()))
    }

    // MARK: - The full vocabulary, and termination

    /// A branch can reach every ending, not only Go To.
    func testABranchCanEndOrReturn() {
        let intent = NavigationIntent.branch(cases: [
            StoryBranchCase(conditions: .init(conditions: [
                StoryCondition(stateId: objects, comparison: .number(.atLeast, 1))
            ]), intent: .back(policy: .resume)),
        ], otherwise: .end)

        XCTAssertEqual(intent.resolving(in: [objects: StoryStateValue.number(1)]),
                       .back(policy: .resume))
        XCTAssertEqual(intent.resolving(in: [objects: StoryStateValue.number(0)]), .end)
    }

    /// Not authorable in the editor, but reachable by hand edit. It must
    /// terminate rather than recursing until the stack ends.
    func testANestedBranchTerminates() {
        let inner = NavigationIntent.branch(cases: [
            branchCase(.number(.atLeast, 1), on: objects, to: "Deep"),
        ], otherwise: nil)
        let outer = NavigationIntent.branch(cases: [
            StoryBranchCase(conditions: .init(conditions: [
                StoryCondition(stateId: objects, comparison: .number(.atLeast, 1))
            ]), intent: inner),
        ], otherwise: nil)

        XCTAssertEqual(outer.resolving(in: [objects: StoryStateValue.number(2)]),
                       .goTo(sequenceId: "Deep"))
        XCTAssertNil(outer.resolving(in: [objects: StoryStateValue.number(2)], depthLimit: 1))
    }

    // MARK: - Every destination is findable

    /// A reference inventory walks THIS. Phase 8A's lesson: a navigation nothing
    /// enumerates is a broken destination nothing can report or repair.
    func testEveryBranchDestinationIsEnumerated() {
        let intent = NavigationIntent.branch(cases: [
            branchCase(.choice(matches: true, optionId: "opt_radio"), on: route, to: "Radio Story"),
            branchCase(.choice(matches: true, optionId: "opt_camera"), on: route, to: "Camera Story"),
        ], otherwise: .goTo(sequenceId: "Main Ending"))

        XCTAssertEqual(intent.allExplicitTargets,
                       ["Radio Story", "Camera Story", "Main Ending"])
        XCTAssertNil(intent.explicitTarget,
                     "A branch names several Sequences, so it names no single one.")
    }

    func testUnsupportedNavigationInsideABranchIsFoundWithoutCondemningTheRest() {
        let intent = NavigationIntent.branch(cases: [
            branchCase(.number(.atLeast, 1), on: objects, to: "Radio Story"),
            StoryBranchCase(conditions: .init(), intent: .unsupported(kind: "chooseBranch",
                                                                     raw: nil)),
        ], otherwise: nil)
        XCTAssertFalse(intent.isUnsupported)
        XCTAssertEqual(intent.unsupportedKinds, ["chooseBranch"])
        XCTAssertEqual(intent.allExplicitTargets, ["Radio Story"])
    }

    // MARK: - Serialization

    func testABranchRoundTrips() throws {
        let intent = NavigationIntent.branch(cases: [
            branchCase(.choice(matches: true, optionId: "opt_radio"), on: route,
                       to: "Radio Story", id: "br_one"),
        ], otherwise: .end)
        let data = try JSONEncoder().encode(intent)
        XCTAssertEqual(try JSONDecoder().decode(NavigationIntent.self, from: data), intent)
    }

    func testABranchWithNoOtherwiseWritesNoOtherwiseKey() throws {
        let intent = NavigationIntent.branch(cases: [], otherwise: nil)
        let data = try JSONEncoder().encode(intent)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data)
                                   as? [String: Any])
        XCTAssertNil(object["otherwise"])
    }

    func testABranchSurvivesInsideACompletionAndAnInteraction() throws {
        let intent = NavigationIntent.branch(cases: [
            branchCase(.yesNo(true), on: "sst_radio", to: "Radio Story"),
        ], otherwise: .goTo(sequenceId: "Main Ending"))

        let completion = CompletionActionDTO.navigate(intent)
        let completionData = try JSONEncoder().encode(completion)
        XCTAssertEqual(try JSONDecoder().decode(CompletionActionDTO.self, from: completionData),
                       completion)

        let action = StepActionDTO.navigate(intent)
        let actionData = try JSONEncoder().encode(action)
        XCTAssertEqual(try JSONDecoder().decode(StepActionDTO.self, from: actionData), action)
    }

    // MARK: - The navigator performs it

    /// A conditional Go To and a plain one take the SAME path: the same visit is
    /// suspended, the same history is pushed, the same refusals apply.
    func testTheNavigatorPerformsABranchThroughTheOrdinaryPath() {
        var navigator = ExperienceNavigator()
        let exists: (String) -> Bool = { ["Gallery", "Radio Story"].contains($0) }
        let start: () -> String? = { "Gallery" }

        _ = navigator.handle(.init(intent: .goTo(sequenceId: "Gallery"), source: .host),
                             exists: exists, start: start)

        let intent = NavigationIntent.branch(cases: [
            branchCase(.choice(matches: true, optionId: "opt_radio"), on: route, to: "Radio Story"),
        ], otherwise: nil)
        let outcome = navigator.handle(.init(intent: intent, source: .host),
                                       exists: exists, start: start, currentPosition: 12,
                                       storyState: [route: StoryStateValue.choice(optionId: "opt_radio")])

        guard case .enter(let sequenceId, _, let resumingFrom) = outcome else {
            return XCTFail("A resolved branch enters its destination: \(outcome)")
        }
        XCTAssertEqual(sequenceId, "Radio Story")
        XCTAssertNil(resumingFrom, "A branch's Go To is a FRESH visit, like every other Go To.")
        XCTAssertTrue(navigator.canReturn, "The Sequence it left must be returnable.")
    }

    /// No match, no Otherwise: the navigator STAYS. It does not refuse, does not
    /// finish, and does not pick a destination.
    func testANavigatorHoldsWhenNothingMatches() {
        var navigator = ExperienceNavigator()
        let exists: (String) -> Bool = { ["Gallery", "Radio Story"].contains($0) }
        _ = navigator.handle(.init(intent: .goTo(sequenceId: "Gallery"), source: .host),
                             exists: exists, start: { "Gallery" })

        let intent = NavigationIntent.branch(cases: [
            branchCase(.choice(matches: true, optionId: "opt_radio"), on: route, to: "Radio Story"),
        ], otherwise: nil)
        let outcome = navigator.handle(.init(intent: intent, source: .host),
                                       exists: exists, start: { "Gallery" },
                                       storyState: [route: StoryStateValue.choice(optionId: nil)])
        XCTAssertEqual(outcome, .stay)
    }

    /// The whole point of Story State surviving navigation: a Chapter playback
    /// session is not a Sequence visit.
    func testStateSurvivesEveryNavigation() {
        var ledger = StoryStateLedger(definitions: [
            StoryStateDefinition(id: "sst_radio", name: "Radio Heard", kind: .yesNo)
        ])
        ledger.apply(.init(stateId: "sst_radio", operation: .setYesNo(true)))

        var navigator = ExperienceNavigator()
        let exists: (String) -> Bool = { ["Gallery", "Radio Story"].contains($0) }
        let start: () -> String? = { "Gallery" }

        _ = navigator.handle(.init(intent: .goTo(sequenceId: "Gallery"), source: .host),
                             exists: exists, start: start, storyState: ledger)
        _ = navigator.handle(.init(intent: .goTo(sequenceId: "Radio Story"), source: .host),
                             exists: exists, start: start, currentPosition: 8, storyState: ledger)
        _ = navigator.handle(.init(intent: .back(policy: .resume), source: .host),
                             exists: exists, start: start, storyState: ledger)
        _ = navigator.handle(.init(intent: .restart, source: .host),
                             exists: exists, start: start, storyState: ledger)

        XCTAssertEqual(ledger.storyStateValue("sst_radio"), .yesNo(true),
                       "Navigating must never reset what the story remembers.")
    }
}
