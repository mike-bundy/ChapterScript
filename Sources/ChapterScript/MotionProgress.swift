import Foundation

/// HOW FAR THROUGH A TIMED ACTION WE ARE — the one definition, shared by the
/// editor's scrub compositor and the player's motion sampler.
///
/// These two had drifted, and the drift was invisible:
///
///   * `ScrubCompositor` (editor, Mac and Vision) measured progress from the
///     ACTION's own absolute start:  `(time - t0) / duration`.
///   * `EntityActionExecutor` (runtime) measured it from the SEGMENT's start:
///     `segmentElapsed / duration`.
///
/// Those agree only for an action that fires exactly at a segment boundary. For
/// anything scheduled mid-segment the runtime started the motion ALREADY PARTWAY
/// THROUGH — a motion scheduled 5s into a 10s segment began life at 50%, while the
/// editor drew it from the beginning. The author saw one thing and the headset
/// did another.
///
/// Measuring from the action's own start is also what makes a motion immune to
/// segment structure, which Timeline 3.0 requires: Segments are a runtime concern and
/// merging two of them must not change what an animation looks like.
///
/// Kept in ChapterScript rather than in either consumer precisely so neither
/// can quietly re-derive it.
public enum MotionProgress {

    /// Minimum duration used as a divisor. A zero-duration action is an instant
    /// state change, not a division by zero.
    public static let minimumDuration: Double = 0.001

    /// Normalized progress through an action, clamped to `0...1`.
    ///
    /// - Parameters:
    ///   - startTime: when the action began, on the AUTHORED sequence clock.
    ///   - now: the current authored sequence time.
    ///   - duration: the action's authored duration.
    ///
    /// Both times must come from the same clock — the authored one, which gates
    /// and pauses hold. Using wall time here would let a motion keep advancing
    /// while the story waits at a gate.
    public static func progress(startTime: Double,
                                now: Double,
                                duration: Double) -> Float {
        Float(min(max((now - startTime) / max(duration, minimumDuration), 0), 1))
    }

    /// True once the action has run its course. Callers that release resources
    /// at completion should ask this rather than comparing floats themselves.
    public static func isComplete(startTime: Double, now: Double, duration: Double) -> Bool {
        now - startTime >= max(duration, minimumDuration)
    }
}
