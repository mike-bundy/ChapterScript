import XCTest
@testable import ChapterScript

final class LogicalTimelineTrackTests: XCTestCase {
    func testTitleTrackAndOccurrenceMembershipRoundTrip() throws {
        let track = LogicalTimelineTrack(id: "track_titles", kind: .title, name: "Titles")
        let step = StepDefinitionDTO(
            id: "step", name: "One", duration: 10,
            authoredActions: [
                AuthoredAction(id: "open", at: 1,
                               action: .showEntity(name: "title_a"),
                               logicalTrackId: track.id),
                AuthoredAction(id: "close", at: 4,
                               action: .hideEntity(name: "title_a"),
                               logicalTrackId: track.id),
            ])
        let sequence = SequenceDefinitionDTO(
            id: "seq", name: "S", phase: "immersive", steps: [step],
            logicalTracks: [track])
        let data = try JSONEncoder().encode(sequence)
        let reopened = try JSONDecoder().decode(SequenceDefinitionDTO.self, from: data)

        XCTAssertEqual(reopened.logicalTracks, [track])
        XCTAssertEqual(reopened.steps[0].authoredActions.map(\.logicalTrackId),
                       [track.id, track.id])
        XCTAssertEqual(reopened.steps[0].authoredActions.map(\.action),
                       [.showEntity(name: "title_a"), .hideEntity(name: "title_a")])
    }

    func testLegacySequenceAndActionsDecodeWithoutLogicalTracks() throws {
        let json = #"{"id":"seq","name":"S","phase":"immersive","steps":[{"id":"step","name":"One","duration":5,"authoredActions":[{"id":"open","at":0,"action":{"kind":"showEntity","name":"title_a"}}]}],"animationTracks":[],"audioTracks":[],"stereoTracks":[],"backdropTrack":[],"storyRegions":[],"visibility":{},"onComplete":{"kind":"holdOnLastStep"}}"#.data(using: .utf8)!
        let sequence = try JSONDecoder().decode(SequenceDefinitionDTO.self, from: json)
        XCTAssertNil(sequence.logicalTracks)
        XCTAssertNil(sequence.steps[0].authoredActions[0].logicalTrackId)
    }

    func testUnknownLogicalTrackKindSurvivesRoundTrip() throws {
        let track = LogicalTimelineTrack(
            id: "track_future", kind: .init(rawValue: "future-lane"), name: "Future")
        let data = try JSONEncoder().encode(track)
        XCTAssertEqual(try JSONDecoder().decode(LogicalTimelineTrack.self, from: data), track)
    }

    func testCompatibilityViewRewritePreservesMembership() {
        var step = StepDefinitionDTO(
            id: "step", name: "One", duration: 5,
            authoredActions: [AuthoredAction(
                id: "open", at: 0, action: .showEntity(name: "old"),
                logicalTrackId: "track_titles")])
        step.actions = [.showEntity(name: "new")]
        XCTAssertEqual(step.authoredActions[0].id, "open")
        XCTAssertEqual(step.authoredActions[0].logicalTrackId, "track_titles")
    }
}
