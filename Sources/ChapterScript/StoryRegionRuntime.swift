//
//  StoryRegionRuntime.swift
//  ChapterScript
//
//  THE TWO CLOCKS, AS A PURE STATE MACHINE.
//
//  Everything about Explore that is arithmetic lives here, off-device and
//  testable: which region is active, whether its exit has resolved, whether the
//  authored first pass is still running or the story is holding at the
//  boundary, and how far into the region the runtime actually is.
//
//  Everything about Explore that needs a headset — a tap landing, a video
//  looping, an entity holding its pose — lives in `ChapterPlayer`. The same
//  split as `InteractionLedger`, for the same reason: two implementations of
//  "has this resolved?" would be two chances to be wrong, and only one of them
//  would ever be tested.
//
//  THE FOUR RULES, IN ORDER OF HOW EASY THEY ARE TO GET WRONG:
//
//  1. THE FIRST PASS ALWAYS PLAYS. Entering a region does not freeze anything.
//     Authored time runs through the whole preview span, every action fires at
//     its normal second, Animation 2.0 evaluates normally, media plays.
//
//  2. RESOLVING EARLY DOES NOT SKIP CONTENT. A viewer who satisfies the exit at
//     14s of a 10–20s region still sees 14→20. The response happens at once;
//     the story simply does not stall when it reaches the boundary. Jumping
//     ahead would make the authored Timeline non-deterministic.
//
//  3. UNRESOLVED AT THE BOUNDARY HOLDS. Authored time parks exactly at the
//     region end. It does NOT rewind, and the Sequence clock never runs
//     backward — looping is a sampling overlay on top of a held clock, never a
//     rewind of the clock itself.
//
//  4. THE FALLBACK TIMER RUNS FROM REGION ENTRY, not from the hold. Ten seconds
//     spent watching the first pass are ten seconds of a thirty-second
//     fallback. And it advances on the RUNTIME's pause-aware playback clock —
//     never on wall time, so a suspended app cannot come back to find the
//     region already expired.
//

import Foundation

/// Where one execution of one Explore region has got to.
public enum StoryRegionPhase: String, Sendable, Equatable {
    /// Authored time is running through the preview span, normally.
    case firstPass
    /// The authored first pass reached the boundary with the exit unresolved.
    /// Authored time is parked; runtime dwell continues.
    case held
    /// The exit is satisfied. If this happened during the first pass, authored
    /// time simply continues to the boundary and out; if during the hold, the
    /// story resumes now.
    case resolved
}

/// Why an Explore region's exit resolved. Kept because "nothing happened" and
/// "the timer ran out" are different facts to a QA pass and to an author.
public enum StoryRegionResolution: String, Sendable, Equatable {
    case exitCondition
    case fallbackTimer
    /// Playback left the region for a reason outside the region's own rules
    /// (stop, a jump, a sequence change).
    case interrupted
}

/// The live state of ONE Explore region execution.
///
/// Owned by a Sequence Visit and destroyed with it. Never serialized: a test
/// asserts it is not `Codable`, exactly as `InteractionLedger` does.
public struct StoryRegionRuntime: Sendable, Equatable {

    public let region: StoryRegion

    /// The runtime playback time at which the region was entered, on the
    /// RUNTIME's own pause-aware clock — not wall time, and not authored time
    /// (which stops advancing at the boundary and so cannot measure dwell).
    private let entryRuntimeTime: TimeInterval

    private(set) public var resolution: StoryRegionResolution?
    /// Runtime clock at the moment the exit resolved, for reporting.
    private(set) public var resolvedAtRuntimeTime: TimeInterval?

    public init(region: StoryRegion, enteredAtRuntimeTime: TimeInterval) {
        self.region = region
        self.entryRuntimeTime = enteredAtRuntimeTime
    }

    // MARK: - The runtime clock

    /// RUNTIME REGION ELAPSED — how long this execution has been going, on the
    /// runtime's pause-aware playback clock.
    ///
    /// It keeps advancing during the hold, which is precisely what makes it a
    /// different clock from authored time.
    public func elapsed(atRuntimeTime now: TimeInterval) -> TimeInterval {
        max(0, now - entryRuntimeTime)
    }

    // MARK: - Phase

    /// Where this execution is, given both clocks.
    ///
    /// - Parameter authoredTime: the Sequence clock. During the hold the engine
    ///   clamps it at the region end, which is what "the story is parked" means.
    public func phase(authoredTime: Double) -> StoryRegionPhase {
        if resolution != nil { return .resolved }
        // HALF-OPEN, like every other boundary in this format: reaching the end
        // exactly is being AT the boundary, which is the hold.
        return authoredTime < region.endTime ? .firstPass : .held
    }

    /// Is the authored clock allowed to leave the region?
    ///
    /// The one question the engine asks at the boundary. `true` while the first
    /// pass is still running — leaving is not a decision until the boundary is
    /// reached — and `true` once resolved.
    public func mayAdvance(authoredTime: Double) -> Bool {
        phase(authoredTime: authoredTime) != .held
    }

    // MARK: - Resolution

    /// The exit condition was satisfied — a tap, a facing dwell, an approach, a
    /// grab, or an accessible activation of the same interaction.
    ///
    /// Idempotent: a second satisfaction of an already-resolved region changes
    /// nothing, so a detector that fires twice at a boundary cannot double-resolve.
    public mutating func resolve(
        _ reason: StoryRegionResolution = .exitCondition,
        atRuntimeTime now: TimeInterval
    ) {
        guard resolution == nil else { return }
        resolution = reason
        resolvedAtRuntimeTime = now
    }

    /// Has the fallback timer expired?
    ///
    /// Measured from REGION ENTRY. Pure — the caller polls it on the runtime
    /// clock it already has, so there is no second timer, no `Task.sleep` that
    /// keeps running while paused, and nothing to leak.
    public func fallbackExpired(atRuntimeTime now: TimeInterval) -> Bool {
        guard let timeout = region.fallbackTimeout, timeout > 0 else { return false }
        return elapsed(atRuntimeTime: now) >= timeout
    }

    /// Apply the fallback if it is due. Returns true when this call resolved it.
    public mutating func applyFallbackIfDue(atRuntimeTime now: TimeInterval) -> Bool {
        guard resolution == nil, fallbackExpired(atRuntimeTime: now) else { return false }
        resolve(.fallbackTimer, atRuntimeTime: now)
        return true
    }

    // MARK: - Continuation sampling

    /// The authored time a LOOPING target should be sampled at during the hold.
    ///
    /// The Sequence clock stays parked at the region end; this is an overlay for
    /// the few targets explicitly authored to loop. It never moves a key, never
    /// rewinds the authored clock, and never becomes anybody's animation time
    /// but the sampler's.
    ///
    ///     loopLocal  = dwell modulo previewDuration
    ///     sampleTime = regionStart + loopLocal
    ///
    /// Returns nil during the first pass — there is nothing to overlay while
    /// authored time is doing the job itself.
    public func loopSampleTime(authoredTime: Double, atRuntimeTime now: TimeInterval) -> Double? {
        guard phase(authoredTime: authoredTime) == .held else { return nil }
        let span = region.previewDuration
        guard span > 0.0001 else { return region.startTime }
        let dwell = max(0, elapsed(atRuntimeTime: now) - span)
        return region.startTime + dwell.truncatingRemainder(dividingBy: span)
    }

    /// How long the story has been parked at the boundary. What a runtime
    /// indicator shows; never serialized, never authored.
    public func dwell(authoredTime: Double, atRuntimeTime now: TimeInterval) -> TimeInterval {
        guard phase(authoredTime: authoredTime) != .firstPass else { return 0 }
        return max(0, elapsed(atRuntimeTime: now) - region.previewDuration)
    }
}
