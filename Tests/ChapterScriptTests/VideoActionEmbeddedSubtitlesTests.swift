import XCTest
@testable import ChapterScript

/// `embeddedSubtitles` is tolerant: absent decodes as nil (off), true
/// round-trips, and an older reader's JSON still decodes.
final class VideoActionEmbeddedSubtitlesTests: XCTestCase {
    func testAbsentIsNilAndTrueRoundTrips() throws {
        let legacy = Data(#"{"file":"a.mov","channel":"video/a"}"#.utf8)
        let decoded = try JSONDecoder().decode(VideoActionDTO.self, from: legacy)
        XCTAssertNil(decoded.embeddedSubtitles)

        var on = VideoActionDTO(file: "a.mov", channel: "video/a")
        on.embeddedSubtitles = true
        let data = try JSONEncoder().encode(on)
        XCTAssertEqual(try JSONDecoder().decode(VideoActionDTO.self, from: data).embeddedSubtitles, true)
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains("\"embeddedSubtitles\":true"))

        let off = try JSONEncoder().encode(VideoActionDTO(file: "a.mov", channel: "video/a"))
        XCTAssertFalse(String(decoding: off, as: UTF8.self).contains("embeddedSubtitles"),
                       "off is absent, so an older reader sees nothing new")
    }
}
