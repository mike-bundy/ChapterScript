//
//  VirtualCameraTests.swift
//  ChapterScriptTests
//
//  FL-23: the virtual camera's format guarantees, and the default still
//  duration's absence discipline.
//

import XCTest
@testable import ChapterScript

final class VirtualCameraTests: XCTestCase {

    func testVirtualCameraRoundTripsOnTheOccurrence() throws {
        var video = VideoActionDTO(file: "dome.mov", channel: "v1")
        video.virtualCamera = VirtualCameraSpec(
            yaw: 45, pitch: -10, roll: 0, fovDegrees: 72, sampling: .bicubic)
        let back = try JSONDecoder().decode(
            VideoActionDTO.self, from: JSONEncoder().encode(video))
        XCTAssertEqual(back.virtualCamera, video.virtualCamera)
    }

    func testAbsentVirtualCameraStaysAbsent() throws {
        let video = VideoActionDTO(file: "flat.mov", channel: "v1")
        let json = String(data: try JSONEncoder().encode(video), encoding: .utf8)!
        XCTAssertFalse(json.contains("virtualCamera"),
                       "today's reroute, unchanged - no key appears by accident")
    }

    func testUnknownSamplingDecodesAsBilinear() throws {
        let json = """
        {"yaw":0,"pitch":0,"roll":0,"fovDegrees":65,"sampling":"quantum"}
        """
        let spec = try JSONDecoder().decode(VirtualCameraSpec.self, from: Data(json.utf8))
        XCTAssertEqual(spec.sampling, .bilinear,
                       "the CHEAPER mode - an unknown future never costs playback")
    }

    func testPartialSpecDecodesWithDefaults() throws {
        let spec = try JSONDecoder().decode(
            VirtualCameraSpec.self, from: Data("{\"yaw\":30}".utf8))
        XCTAssertEqual(spec.yaw, 30)
        XCTAssertEqual(spec.fovDegrees, 65)
    }

    func testDefaultStillDurationAbsenceDiscipline() throws {
        var metadata = EditorMetadata()
        XCTAssertTrue(metadata.isEmpty)
        metadata.defaultStillDuration = 7
        XCTAssertFalse(metadata.isEmpty,
                       "a stated default makes the metadata worth writing")
        let back = try JSONDecoder().decode(
            EditorMetadata.self, from: JSONEncoder().encode(metadata))
        XCTAssertEqual(back.defaultStillDuration, 7)
    }
}
