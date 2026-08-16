//
//  StoryStateTests.swift
//  ChapterScriptTests
//
//  The authored half of Story State: identity, kinds, values, mutations and the
//  arithmetic both runtimes share.
//

import XCTest
@testable import ChapterScript

final class StoryStateTests: XCTestCase {

    // MARK: - Identity

    /// THE HEADLINE OF THE WHOLE FEATURE. Renaming a Story State changes what
    /// the author reads and nothing a mutation or condition stores.
    func testRenamingAStateBreaksNoReference() {
        var radioHeard = StoryStateDefinition(name: "Radio Heard", kind: .yesNo)
        let mutation = StoryStateMutation(stateId: radioHeard.id, operation: .setYesNo(true))
        let condition = StoryCondition(stateId: radioHeard.id, comparison: .yesNo(true))

        radioHeard.name = "Recording Heard"

        XCTAssertEqual(mutation.stateId, radioHeard.id)
        XCTAssertEqual(condition.stateId, radioHeard.id)
        XCTAssertEqual(radioHeard.resolvedName, "Recording Heard")
    }

    /// The same, for a Choice option: “Radio” becoming “Broadcast” must leave
    /// `Selected Route is Radio` pointing at the very same option.
    func testRenamingAChoiceOptionBreaksNoReference() {
        var radio = StoryChoiceOption(name: "Radio")
        var route = StoryStateDefinition(name: "Selected Route", kind: .choice,
                                         options: [radio, StoryChoiceOption(name: "Camera")])
        let condition = StoryCondition(stateId: route.id,
                                       comparison: .choice(matches: true, optionId: radio.id))

        radio.name = "Broadcast"
        route.options[0] = radio

        guard case .choice(_, let optionId) = condition.comparison else {
            return XCTFail("The comparison must still name an option.")
        }
        XCTAssertEqual(optionId, radio.id)
        XCTAssertEqual(route.option(optionId)?.name, "Broadcast")
    }

    func testIdsAreOpaqueAndUnique() {
        let a = StoryStateDefinition(name: "One", kind: .yesNo)
        let b = StoryStateDefinition(name: "One", kind: .yesNo)
        XCTAssertNotEqual(a.id, b.id, "Two states with the same NAME are two states.")
        XCTAssertTrue(a.id.hasPrefix("sst_"))
    }

    // MARK: - Kinds and initial values

    func testEachKindHasAnHonestDefault() {
        XCTAssertEqual(StoryStateValue.default(for: .yesNo), .yesNo(false))
        XCTAssertEqual(StoryStateValue.default(for: .number), .number(0))
        XCTAssertEqual(StoryStateValue.default(for: .choice), .choice(optionId: nil))
    }

    /// A Choice starts with NOTHING chosen unless the author picks one. Before
    /// the viewer decides, “Selected Route is Radio” is false, which is what
    /// gives Otherwise something to do.
    func testAChoiceStartsUnchosen() {
        let route = StoryStateDefinition(name: "Selected Route", kind: .choice,
                                         options: [StoryChoiceOption(name: "Radio")])
        XCTAssertEqual(route.seedValue, .choice(optionId: nil))
    }

    /// Only reachable by a hand edit or a newer tool. The value is REPLACED by
    /// the kind's default, never coerced into a narrative fact nobody wrote.
    func testAMismatchedInitialValueSeedsTheKindsDefault() {
        let counter = StoryStateDefinition(name: "Objects Found", kind: .number,
                                           initialValue: .yesNo(true))
        XCTAssertEqual(counter.seedValue, .number(0))
    }

    /// A Choice whose initial option was deleted starts unset rather than
    /// starting somewhere impossible.
    func testAnInitialChoicePointingAtANonexistentOptionStartsUnset() {
        let route = StoryStateDefinition(name: "Selected Route", kind: .choice,
                                         options: [StoryChoiceOption(id: "opt_a", name: "Radio")],
                                         initialValue: .choice(optionId: "opt_gone"))
        XCTAssertEqual(route.seedValue, .choice(optionId: nil))
    }

    func testOptionsAreDroppedForNonChoiceKinds() {
        let state = StoryStateDefinition(name: "Radio Heard", kind: .yesNo,
                                         options: [StoryChoiceOption(name: "Radio")])
        XCTAssertTrue(state.options.isEmpty)
    }

    // MARK: - Arithmetic

    func testYesNoIsSet() {
        let state = StoryStateDefinition(name: "Radio Heard", kind: .yesNo)
        let result = StoryStateArithmetic.apply(.setYesNo(true), to: .yesNo(false),
                                                definition: state)
        XCTAssertEqual(try result.get(), .yesNo(true))
    }

    func testNumberIsSetAndStepped() {
        let state = StoryStateDefinition(name: "Objects Found", kind: .number)
        XCTAssertEqual(try StoryStateArithmetic.apply(.setNumber(4), to: .number(0),
                                                      definition: state).get(), .number(4))
        XCTAssertEqual(try StoryStateArithmetic.apply(.changeNumber(by: 1), to: .number(1),
                                                      definition: state).get(), .number(2))
        // Decrease is a negative step. One case, so “by how much” lives in one
        // place rather than in two mirror-image ones.
        XCTAssertEqual(try StoryStateArithmetic.apply(.changeNumber(by: -1), to: .number(2),
                                                      definition: state).get(), .number(1))
    }

    /// A counter is a narrative device. Stepping it past the end of the number
    /// line holds rather than trapping and taking the experience with it.
    func testSteppingANumberSaturatesRatherThanTrapping() {
        let state = StoryStateDefinition(name: "Attempts", kind: .number)
        XCTAssertEqual(try StoryStateArithmetic.apply(.changeNumber(by: 1), to: .number(Int.max),
                                                      definition: state).get(), .number(Int.max))
        XCTAssertEqual(try StoryStateArithmetic.apply(.changeNumber(by: -1), to: .number(Int.min),
                                                      definition: state).get(), .number(Int.min))
    }

    func testChoiceIsSetOnlyToAnOptionThatExists() {
        let radio = StoryChoiceOption(name: "Radio")
        let state = StoryStateDefinition(name: "Selected Route", kind: .choice, options: [radio])
        XCTAssertEqual(try StoryStateArithmetic.apply(.setChoice(optionId: radio.id),
                                                      to: .choice(optionId: nil),
                                                      definition: state).get(),
                       .choice(optionId: radio.id))

        let refused = StoryStateArithmetic.apply(.setChoice(optionId: "opt_gone"),
                                                 to: .choice(optionId: nil), definition: state)
        guard case .failure(let refusal) = refused else {
            return XCTFail("An option that is not on the state must be refused.")
        }
        XCTAssertEqual(refusal, .unknownOption(stateId: state.id, optionId: "opt_gone"))
    }

    /// The kinds are not interchangeable, and a mismatch is refused rather than
    /// coerced into whichever value looks closest.
    func testAMutationForTheWrongKindIsRefused() {
        let counter = StoryStateDefinition(name: "Objects Found", kind: .number)
        let refused = StoryStateArithmetic.apply(.setYesNo(true), to: .number(0),
                                                 definition: counter)
        guard case .failure(let refusal) = refused else {
            return XCTFail("Yes/No cannot be applied to a Number.")
        }
        XCTAssertEqual(refusal, .kindMismatch(stateId: counter.id, expected: .number))
    }

    // MARK: - Forward compatibility

    /// A kind written by a newer tool is INERT and PRESERVED, never mapped onto
    /// one of the three. The `NavigationIntent` rule: a fallback that parses is
    /// not the same as a fallback that means the right thing.
    func testAnUnknownKindIsUnsupportedAndSurvivesARoundTrip() throws {
        let json = #"{"id":"sst_x","name":"Mood","kind":"colour","initialValue":{"kind":"colour"}}"#
        let decoded = try JSONDecoder().decode(StoryStateDefinition.self,
                                               from: Data(json.utf8))
        XCTAssertEqual(decoded.kind, .unsupported(raw: "colour"))
        XCTAssertTrue(decoded.kind.isUnsupported)

        let reencoded = try JSONEncoder().encode(decoded)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: reencoded)
                                   as? [String: Any])
        XCTAssertEqual(object["kind"] as? String, "colour",
                       "An older build must not downgrade a newer build's Chapter.")
    }

    /// And nothing can be applied to it, so it cannot silently behave like a
    /// Yes/No that happens to be false.
    func testAnUnsupportedKindAcceptsNoMutation() {
        let state = StoryStateDefinition(name: "Mood", kind: .unsupported(raw: "colour"))
        let refused = StoryStateArithmetic.apply(.setYesNo(true),
                                                 to: .unsupported(kind: "colour", raw: nil),
                                                 definition: state)
        guard case .failure(.unsupported(let kind)) = refused else {
            return XCTFail("An unsupported kind must refuse every operation.")
        }
        XCTAssertEqual(kind, "colour")
    }

    func testAnUnknownOperationIsUnsupportedAndInert() throws {
        let json = #"{"stateId":"sst_x","operation":{"kind":"multiplyBy","by":3}}"#
        let decoded = try JSONDecoder().decode(StoryStateMutation.self, from: Data(json.utf8))
        guard case .unsupported(let kind, _) = decoded.operation else {
            return XCTFail("An operation this build cannot perform must not be read as one it can.")
        }
        XCTAssertEqual(kind, "multiplyBy")

        let state = StoryStateDefinition(id: "sst_x", name: "Objects Found", kind: .number)
        guard case .failure(.unsupported) = StoryStateArithmetic.apply(decoded.operation,
                                                                       to: .number(1),
                                                                       definition: state) else {
            return XCTFail("It must do nothing.")
        }
    }

    // MARK: - Serialization

    func testDefinitionsRoundTrip() throws {
        let radio = StoryChoiceOption(name: "Radio")
        let camera = StoryChoiceOption(name: "Camera")
        let states = [
            StoryStateDefinition(name: "Radio Heard", kind: .yesNo),
            StoryStateDefinition(name: "Objects Found", kind: .number,
                                 initialValue: .number(0)),
            StoryStateDefinition(name: "Selected Route", kind: .choice,
                                 options: [radio, camera]),
        ]
        let data = try JSONEncoder().encode(states)
        XCTAssertEqual(try JSONDecoder().decode([StoryStateDefinition].self, from: data), states)
    }

    /// A Yes/No state carries no empty options array, so the JSON says only what
    /// the author authored.
    func testANonChoiceStateEmitsNoOptionsKey() throws {
        let data = try JSONEncoder().encode(StoryStateDefinition(name: "Radio Heard",
                                                                 kind: .yesNo))
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data)
                                   as? [String: Any])
        XCTAssertNil(object["options"])
    }

    /// A Chapter with no Story State must re-save byte-identically. The key is
    /// absent, not present and empty.
    func testAChapterWithNoStoryStateEmitsNoKey() throws {
        let document = ChapterDocument(id: "c", displayName: "Chapter")
        let data = try JSONEncoder().encode(document)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data)
                                   as? [String: Any])
        XCTAssertNil(object["storyState"])
        XCTAssertTrue(try JSONDecoder().decode(ChapterDocument.self, from: data)
                        .storyState.isEmpty)
    }

    func testAChapterCarriesItsStoryStateThroughARoundTrip() throws {
        var document = ChapterDocument(id: "c", displayName: "Chapter")
        document.storyState = [StoryStateDefinition(name: "Radio Heard", kind: .yesNo)]
        let data = try JSONEncoder().encode(document)
        let reopened = try JSONDecoder().decode(ChapterDocument.self, from: data)
        XCTAssertEqual(reopened.storyState, document.storyState)
    }

    // MARK: - The action

    func testTheMutationActionRoundTrips() throws {
        let action = StepActionDTO.setStoryState(
            .init(stateId: "sst_radio", operation: .changeNumber(by: 1)))
        let data = try JSONEncoder().encode(action)
        XCTAssertEqual(try JSONDecoder().decode(StepActionDTO.self, from: data), action)
    }

    /// An Interaction row must never read “Run action” for something this
    /// consequential — the defect Phase 8A found for navigation, checked here
    /// before it can happen again.
    func testAStateChangeIsNamedInPlainLanguage() {
        XCTAssertEqual(
            InteractionSemantics.responsePhrase(
                .setStoryState(.init(stateId: "Radio Heard", operation: .setYesNo(true)))),
            "Remember Radio Heard")
        XCTAssertEqual(
            InteractionSemantics.responsePhrase(
                .setStoryState(.init(stateId: "Objects Found", operation: .changeNumber(by: 1)))),
            "Increase Objects Found")
        XCTAssertEqual(
            InteractionSemantics.responsePhrase(
                .setStoryState(.init(stateId: "Objects Found", operation: .changeNumber(by: -1)))),
            "Decrease Objects Found")
    }
}
