//
//  GateActivationTests.swift
//  ChapterScriptTests
//
//  PHASE 7.1 — CAN A VOICEOVER USER FINISH THE CHAPTER?
//
//  A gate BLOCKS progression. Before this rule existed, an accessible
//  activation reached an object's Interaction and stopped there, so a viewer
//  using assistive technology could make the radio crackle and never leave the
//  room. These pin the routing that fixes it, and — just as importantly — pin
//  Phase 6's rule that touching an unrelated prop must NOT advance the film.
//
//  The tests below are about the DECISION only. Whether a headset senses a
//  facing dwell, an approach or a grab is device behaviour and is asserted
//  nowhere in this file.
//

import XCTest
@testable import ChapterScript

final class GateActivationTests: XCTestCase {

    // MARK: - Trigger mapping

    func testEveryGateTypeMapsToAnActivation() {
        XCTAssertTrue(GateActivation.sameKind(GateActivation.trigger(for: .tap), .tap))
        XCTAssertTrue(GateActivation.sameKind(GateActivation.trigger(for: .viewerFacing),
                                              .viewerFacing(dwell: 1)))
        XCTAssertTrue(GateActivation.sameKind(GateActivation.trigger(for: .proximity),
                                              .approach(radius: 2)))
        XCTAssertTrue(GateActivation.sameKind(GateActivation.trigger(for: .grab), .grab))
    }

    func testKindComparisonIgnoresParameters() {
        // A gate's dwell and an interaction's dwell are separate authored
        // values. They must not have to match for the act to be the same act.
        XCTAssertTrue(GateActivation.sameKind(.viewerFacing(dwell: 1), .viewerFacing(dwell: 4)))
        XCTAssertTrue(GateActivation.sameKind(.approach(radius: 1), .approach(radius: nil)))
        XCTAssertFalse(GateActivation.sameKind(.tap, .grab))
    }

    // MARK: - Phase 6's rule, preserved

    func testAnUntargetedGateIsSatisfiedByAPlainTap() {
        let gate = StepGateDTO(type: .tap)
        XCTAssertTrue(GateActivation.satisfies(
            gate: gate, activation: .init(entityName: "Floor", trigger: .tap)))
    }

    func testAnUntargetedGateIsNotSatisfiedByTouchingAProp() {
        // THE PHASE 6 RULE. The radio has its own behaviour; making it crackle
        // is not permission for the film to continue.
        let gate = StepGateDTO(type: .tap)
        XCTAssertFalse(GateActivation.satisfies(
            gate: gate,
            activation: .init(entityName: "Radio", trigger: .tap, interactionRan: true)))
    }

    func testATargetedGateIsSatisfiedEvenWhenAnInteractionAlsoRan() {
        // "Continue when Tap Radio" means tapping the Radio continues — the
        // author named it, so both things happening is what they asked for.
        let gate = StepGateDTO(type: .tap, targetEntity: "Radio")
        XCTAssertTrue(GateActivation.satisfies(
            gate: gate,
            activation: .init(entityName: "Radio", trigger: .tap, interactionRan: true)))
    }

    func testATargetedGateIgnoresActivationOnAnotherObject() {
        let gate = StepGateDTO(type: .tap, targetEntity: "Radio")
        XCTAssertFalse(GateActivation.satisfies(
            gate: gate, activation: .init(entityName: "Lamp", trigger: .tap)))
        XCTAssertFalse(GateActivation.satisfies(
            gate: gate, activation: .init(entityName: nil, trigger: .tap)))
    }

    func testAGateIgnoresADifferentKindOfActivation() {
        let gate = StepGateDTO(type: .grab, targetEntity: "Handle")
        XCTAssertFalse(GateActivation.satisfies(
            gate: gate, activation: .init(entityName: "Handle", trigger: .tap)))
        XCTAssertTrue(GateActivation.satisfies(
            gate: gate, activation: .init(entityName: "Handle", trigger: .grab)))
    }

    func testAnAnyGateAcceptsEitherRoute() {
        let gate = StepGateDTO(type: .any, targetEntity: "Door")
        for trigger: InteractionTrigger in [.tap, .grab, .viewerFacing(dwell: 1), .approach(radius: 1)] {
            XCTAssertTrue(GateActivation.satisfies(
                gate: gate, activation: .init(entityName: "Door", trigger: trigger)),
                "`.any` has always accepted any supported route.")
        }
    }

    // MARK: - The accessible route reaches the same answer

    /// THE HEADLINE. For every trigger, an activation that arrived through
    /// assistive technology gets exactly the outcome the physical one gets.
    func testAccessibilityChangesNoOutcome() {
        let cases: [(GateType, InteractionTrigger)] = [
            (.tap, .tap),
            (.viewerFacing, .viewerFacing(dwell: 1)),
            (.proximity, .approach(radius: 1.5)),
            (.grab, .grab),
        ]
        for (type, trigger) in cases {
            for target in [nil, "Radio"] as [String?] {
                for interactionRan in [true, false] {
                    let gate = StepGateDTO(type: type, targetEntity: target)
                    let physical = SemanticActivation(
                        entityName: "Radio", trigger: trigger,
                        interactionRan: interactionRan, isAccessible: false)
                    let accessible = SemanticActivation(
                        entityName: "Radio", trigger: trigger,
                        interactionRan: interactionRan, isAccessible: true)
                    XCTAssertEqual(
                        GateActivation.satisfies(gate: gate, activation: physical),
                        GateActivation.satisfies(gate: gate, activation: accessible),
                        "\(type)/\(trigger.kindName)/target=\(target ?? "—")/ran=\(interactionRan): the route must not change the answer.")
                }
            }
        }
    }

    /// The three non-Tap gates are the ones a viewer may be physically unable
    /// to satisfy — the whole reason the accessible equivalent exists.
    func testTheThreeSpatialGatesAreReachableWithoutMoving() {
        for type: GateType in [.viewerFacing, .proximity, .grab] {
            let gate = StepGateDTO(type: type, targetEntity: "Plinth")
            guard let trigger = GateActivation.trigger(for: type) else {
                return XCTFail("\(type) must name the act that satisfies it.")
            }
            let activation = SemanticActivation(
                entityName: "Plinth", trigger: trigger,
                interactionRan: false, isAccessible: true)
            XCTAssertTrue(GateActivation.satisfies(gate: gate, activation: activation),
                          "A viewer who cannot walk to the plinth must still be able to continue.")
        }
    }

    /// A disabled or absent Interaction is not a reason a gate stops working.
    /// The two are separate consumers; conflating them would make progression
    /// depend on an unrelated object's enablement.
    func testAGateDoesNotConsultInteractionState() {
        let gate = StepGateDTO(type: .tap, targetEntity: "Radio")
        XCTAssertTrue(GateActivation.satisfies(
            gate: gate,
            activation: .init(entityName: "Radio", trigger: .tap, interactionRan: false)))
    }

    // MARK: - What the viewer hears

    func testTheAccessibleLabelPrefersTheAuthorsPrompt() {
        XCTAssertEqual(
            GateActivation.accessibleLabel(for: StepGateDTO(type: .proximity, prompt: "Step up to the plinth")),
            "Step up to the plinth")
    }

    func testTheAccessibleLabelNeverNamesTheTrigger() {
        // "Approach" is useless to somebody who cannot approach. The fallback
        // names the OUTCOME.
        for type: GateType in [.tap, .viewerFacing, .proximity, .grab] {
            XCTAssertEqual(GateActivation.accessibleLabel(for: StepGateDTO(type: type)), "Continue")
        }
        XCTAssertEqual(GateActivation.accessibleLabel(for: StepGateDTO(type: .grab, prompt: "")), "Continue")
    }

    // MARK: - Runtime state stays out of the format

    func testSemanticActivationIsNotCodable() {
        // Same guard as `InteractionLedger`: this describes a moment, not
        // authored content, and nothing may serialize it into a document.
        XCTAssertFalse((SemanticActivation.self as Any) is any Codable.Type)
    }
}
