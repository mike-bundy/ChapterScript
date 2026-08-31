//
//  ImageInterpretation.swift
//  ChapterScript
//
//  THE AUTHOR'S READING OF AN IMAGE SOURCE, KEPT WITH THE PROJECT.
//
//  An image is an IMAGE. That is what the source IS, and nothing about a
//  file's shape may change it. How the author chooses to PRESENT that image —
//  on a panel, or wrapped around the viewer as an environment — is a separate
//  fact, and conflating the two is what made every imported still turn into a
//  skybox the moment it landed in the Library.
//
//  So, exactly as `VideoInterpretation` splits stereo / layout / projection:
//
//      KIND        Image. Read from the bytes, never stored, never decided.
//      PROJECTION  What the pixels MEAN — flat, or a horizontal sweep.
//                  A DECISION, because no inspection can recover it.
//      PLACEMENT   Where the author wants it — panel or environment.
//
//  NOTHING GUESSES PROJECTION. A 2:1 image may be an equirectangular 360, and
//  it may equally be a panorama, a scan, a contact sheet or a title card. An
//  aspect ratio is not projection metadata; a projection a trustworthy
//  container DECLARES outranks this, and silence means flat.
//
//  ABSENT MEANS AUTOMATIC, exactly as it does for audio and video, and an
//  empty record is never written — so a chapter that has never been told
//  anything about its images re-saves byte-identically.
//

import Foundation

/// Where the author wants an image presented.
///
/// The image sibling of `VideoPlacementPreference`, and deliberately its own
/// type: an image has no `.immersive` clip form distinct from an environment
/// today, and borrowing the video enum would import a case that means nothing
/// here.
public enum ImagePlacementPreference: String, Codable, Sendable, Equatable, Hashable {
    /// A flat plate in the scene, at the source's own aspect ratio. The
    /// default for every image, and the reading that shows the picture
    /// undistorted.
    case panel
    /// Wrapped around the viewer as the Sequence's environment.
    case environment

    public var displayName: String {
        switch self {
        case .panel:       return "Image Panel"
        case .environment: return "Environment"
        }
    }
}

/// One image source's authored interpretation. Every field absent means
/// "Automatic": defer entirely to what the file itself says.
public struct ImageInterpretation: Codable, Sendable, Equatable {

    /// WHAT THE PIXELS MEAN, when the container does not say.
    ///
    /// `nil` is FLAT — a rectilinear photograph, which is what almost every
    /// image is. A value here is an author saying "this is a 180°/190°/…/360°
    /// map", and it is stored for the same reason `VideoInterpretation.layout`
    /// is: the fact is unrecoverable by inspection.
    ///
    /// A projection the container DECLARES still wins. This is consulted only
    /// when the file is silent.
    public var projection: ImmersiveField?

    /// Where the author wants this source presented. Absent means `.panel`.
    ///
    /// SEPARATE FROM PROJECTION ON PURPOSE. A 220° image may sit on a panel
    /// (a flat map of a wide capture) and a flat image may never be an
    /// environment usefully — the two answer different questions and one must
    /// never be derived from the other.
    public var placement: ImagePlacementPreference?

    /// HOW THE COLOUR RELATES TO THE COVERAGE (FL-04), when the container
    /// does not say. Same rule as video: a declared alpha info wins, absent
    /// means Automatic, and nothing guesses it from a channel count.
    public var alpha: SourceAlpha?

    public init(projection: ImmersiveField? = nil,
                placement: ImagePlacementPreference? = nil,
                alpha: SourceAlpha? = nil) {
        self.projection = projection
        self.placement = placement
        self.alpha = alpha
    }

    /// True when the author has decided nothing — so the record can be dropped
    /// rather than written as an empty object.
    public var isEmpty: Bool { projection == nil && placement == nil && alpha == nil }

    // Tolerant by hand — see `VideoInterpretation`: an unrecognised future
    // `alpha` decodes as absent (Automatic), never as a failed document.
    private enum CodingKeys: String, CodingKey { case projection, placement, alpha }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.projection = try c.decodeIfPresent(ImmersiveField.self, forKey: .projection)
        self.placement = try c.decodeIfPresent(ImagePlacementPreference.self, forKey: .placement)
        self.alpha = (try? c.decodeIfPresent(String.self, forKey: .alpha))
            .flatMap { SourceAlpha(rawValue: $0) }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(projection, forKey: .projection)
        try c.encodeIfPresent(placement, forKey: .placement)
        try c.encodeIfPresent(alpha, forKey: .alpha)
    }
}

// MARK: - The coverages Maestro offers

extension ImmersiveField {

    /// THE HORIZONTAL SWEEPS AN AUTHOR MAY CHOOSE FOR AN IMAGE.
    ///
    /// A LIST, not a range, for the reason `validatedAppleImmersiveFieldsOfView`
    /// is a list: each entry is a coverage Maestro can actually build a shell
    /// for and has been looked at. 190–220 ride on `.custom`, because they are
    /// ordinary equirectangular maps of a wider sweep — `.appleImmersive` is a
    /// different PROJECTION (a calibrated parametric lens), not a wider one,
    /// and an image never carries one.
    public static let authorableImageProjections: [ImmersiveField] = [
        .equirect180,
        .custom(degrees: 190),
        .custom(degrees: 200),
        .custom(degrees: 210),
        .custom(degrees: 220),
        .equirect360
    ]

    /// How a coverage reads in a picker. Whole degrees, because every
    /// authorable coverage is one.
    public var coverageLabel: String {
        let degrees = horizontalDegrees
        let rounded = degrees.rounded()
        let text = abs(degrees - rounded) < 0.05
            ? String(Int(rounded))
            : String(format: "%.1f", degrees)
        return "\(text)\u{00B0}"
    }
}
