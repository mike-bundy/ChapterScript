//
//  InteractionFormatTests.swift
//  ChapterScriptTests
//
//  The format half of Phase 6. What is asserted here is compatibility, not
//  behaviour: an old document must be unchanged, a new one must survive a round
//  trip, and a document from a NEWER tool must still open.
//

import XCTest
@testable import ChapterScript

final class InteractionFormatTests: XCTestCase {

    private func roundTrip<T: Codable>(_ value: T) throws -> T {
        let data = try JSONEncoder().encode(value)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func json(_ value: some Encodable) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }

    // MARK: - Existing documents are untouched

    func testEntityWithNoInteractionsEmitsNoKeys() throws {
        let entity = EntityDefinition(id: "Door", kind: .usdz, usdzAssetId: "door.usdz")
        let text = try json(entity)
        XCTAssertFalse(text.contains("interactions"),
                       "An entity with no interactions must not gain a key — existing documents re-save byte-identically.")
        XCTAssertFalse(text.contains("interactionFeedback"))
    }

    func testEmptyInteractionListNormalizesToAbsent() throws {
        var entity = EntityDefinition(id: "Door", kind: .usdz, interactions: [])
        XCTAssertNil(entity.interactions, "An empty list passed to init must normalize to nil.")

        entity.interactions = [InteractionSpec()]
        entity.interactions = []
        XCTAssertNil(entity.interactions, "Removing the last interaction must clear the field, not leave [].")
        XCTAssertFalse(try json(entity).contains("interactions"))
    }

    func testEntityWithoutInteractionsDecodesFromALegacyDocument() throws {
        let legacy = """
        {"id":"Radio","kind":"usdz","transform":{"position":{"x":0,"y":0,"z":-2},\
        "rotation":{"x":0,"y":0,"z":0,"w":1},"scale":{"x":1,"y":1,"z":1}},\
        "initiallyEnabled":false,"gestureEnabled":false}
        """
        let entity = try JSONDecoder().decode(EntityDefinition.self, from: Data(legacy.utf8))
        XCTAssertNil(entity.interactions)
        XCTAssertFalse(entity.isInteractive)
        XCTAssertEqual(entity.resolvedInteractionFeedback, .automatic)
        XCTAssertTrue(entity.resolvedInteractions.isEmpty)
    }

    // MARK: - Round trips

    func testInteractionRoundTripsWithEveryTriggerShape() throws {
        let triggers: [InteractionTrigger] = [
            .tap, .grab,
            .viewerFacing(dwell: nil), .viewerFacing(dwell: 2.5),
            .approach(radius: nil), .approach(radius: 1.75)
        ]
        for trigger in triggers {
            let spec = InteractionSpec(trigger: trigger, lifetime: .once,
                                       actions: [.showEntity(name: "Label")])
            XCTAssertEqual(try roundTrip(spec), spec, "\(trigger) did not survive a round trip.")
        }
    }

    func testUnsetTriggerParameterEmitsNoKey() throws {
        XCTAssertFalse(try json(InteractionTrigger.viewerFacing(dwell: nil)).contains("dwell"),
                       "An unauthored dwell must not be written as the player's current default.")
        XCTAssertFalse(try json(InteractionTrigger.approach(radius: nil)).contains("radius"))
        XCTAssertTrue(try json(InteractionTrigger.viewerFacing(dwell: 1.5)).contains("dwell"))
    }

    func testStableIdSurvivesSaveAndReopen() throws {
        let spec = InteractionSpec(id: "ix_fixed", trigger: .tap,
                                   actions: [.playAudio(AudioActionDTO(file: "vo.wav", channel: "c"))])
        var entity = EntityDefinition(id: "Door", kind: .usdz)
        entity.interactions = [spec, InteractionSpec(id: "ix_second", trigger: .grab)]

        let reopened = try roundTrip(entity)
        XCTAssertEqual(reopened.resolvedInteractions.map(\.id), ["ix_fixed", "ix_second"])
        XCTAssertEqual(reopened.resolvedInteractions.first?.actions.count, 1)
    }

    func testMultipleInteractionsAndFeedbackRoundTrip() throws {
        var entity = EntityDefinition(id: "Door", kind: .usdz)
        entity.interactions = [
            InteractionSpec(id: "a", trigger: .tap, lifetime: .everyTime),
            InteractionSpec(id: "b", trigger: .viewerFacing(dwell: 1.2), lifetime: .once),
            InteractionSpec(id: "c", trigger: .approach(radius: 2), initiallyEnabled: false)
        ]
        entity.interactionFeedback = InteractionFeedbackSpec(style: .gentle, intensity: 0.4)

        let reopened = try roundTrip(entity)
        XCTAssertEqual(reopened, entity)
        XCTAssertEqual(reopened.resolvedInteractions.count, 3)
        XCTAssertEqual(reopened.interactionFeedback?.style, .gentle)
        XCTAssertEqual(reopened.resolvedInteractions[2].initiallyEnabled, false)
    }

    // MARK: - Tolerance

    func testUnknownTriggerKindDecodesAsTap() throws {
        let data = Data(#"{"kind":"telepathy","dwell":9}"#.utf8)
        XCTAssertEqual(try JSONDecoder().decode(InteractionTrigger.self, from: data), .tap)
    }

    func testUnknownLifetimeDecodesAsOnce() throws {
        let data = Data(#""whileOrbiting""#.utf8)
        XCTAssertEqual(try JSONDecoder().decode(InteractionLifetime.self, from: data), .once,
                       "The safer default: a beat that should have repeated is better than narration retriggering over itself.")
    }

    func testUnknownFeedbackStyleDecodesAsAutomatic() throws {
        let data = Data(#"{"style":"lensFlare","intensity":0.9}"#.utf8)
        let spec = try JSONDecoder().decode(InteractionFeedbackSpec.self, from: data)
        XCTAssertEqual(spec.style, .automatic)
        XCTAssertEqual(spec.intensity, 0.9)
    }

    func testInteractionMissingEveryOptionalFieldStillLoads() throws {
        let data = Data(#"{"id":"ix_1"}"#.utf8)
        let spec = try JSONDecoder().decode(InteractionSpec.self, from: data)
        XCTAssertEqual(spec.id, "ix_1")
        XCTAssertEqual(spec.trigger, .tap)
        XCTAssertEqual(spec.lifetime, .everyTime)
        XCTAssertTrue(spec.initiallyEnabled)
        XCTAssertTrue(spec.actions.isEmpty)
    }

    func testUnknownResponseActionSurvivesAsUnknown() throws {
        let data = Data("""
        {"id":"ix_1","actions":[{"kind":"summonDragon","fire":true}]}
        """.utf8)
        let spec = try JSONDecoder().decode(InteractionSpec.self, from: data)
        guard case .unknown(let name, _) = spec.actions.first else {
            return XCTFail("A response from a newer tool must land in .unknown, not fail the load.")
        }
        XCTAssertEqual(name, "summonDragon")
    }

    // MARK: - The enable/disable actions

    func testInteractionToggleActionsRoundTrip() throws {
        for action in [StepActionDTO.enableInteraction(entity: "Door", interactionId: "ix_1"),
                       .disableInteraction(entity: "Door", interactionId: "ix_1")] {
            XCTAssertEqual(try roundTrip(action), action)
        }
    }

    // MARK: - Semantics

    func testAccessibilityLabelPrefersDisplayNameOverEntityId() {
        let entity = EntityDefinition(id: "ent_9f2c41", displayName: "Door to Gallery", kind: .usdz)
        let spec = InteractionSpec(trigger: .tap, actions: [.playAudio(
            AudioActionDTO(file: "gallery-vo.wav", channel: "vo"))])
        XCTAssertEqual(InteractionSemantics.label(for: spec, entity: entity), "Door to Gallery")
        XCTAssertEqual(InteractionSemantics.hint(for: spec), "Tap to play gallery-vo.wav")
    }

    func testAccessibilityOverridesWin() {
        let entity = EntityDefinition(id: "ent_1", displayName: "Door", kind: .usdz)
        let spec = InteractionSpec(trigger: .tap, actions: [.hideEntity(name: "X")],
                                   accessibilityLabel: "Gallery entrance",
                                   accessibilityHint: "Opens the gallery")
        XCTAssertEqual(InteractionSemantics.label(for: spec, entity: entity), "Gallery entrance")
        XCTAssertEqual(InteractionSemantics.hint(for: spec), "Opens the gallery")
    }

    func testHintWithNoResponseStillNamesTheTrigger() {
        let spec = InteractionSpec(trigger: .approach(radius: 2))
        XCTAssertEqual(InteractionSemantics.hint(for: spec), "Approach")
    }
}
