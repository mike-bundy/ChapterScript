//
//  MediaFade.swift
//  ChapterScript
//
//  THE CROSS-MEDIA FADE (FL-18 N12).
//
//  One authored intent — "this clip comes up and goes away" — expressed the
//  same way whether the clip is picture or sound, so a single corner drag on
//  a clip that carries both writes ONE shape and not two features that
//  happen to look alike.
//
//  The FIELDS are deliberately the smallest addition that can carry it:
//
//    - `AudioActionDTO.fadeIn`  already existed. Untouched.
//    - `AudioActionDTO.fadeOut` is new, and is its mirror.
//    - `VideoActionDTO.fadeIn` / `.fadeOut` are new, same names, same units
//      (seconds), same meaning.
//
//  No new wrapper type on the wire, and NO SECOND SPELLING of audio's
//  fade-in — a second way to say a fact the format already says is exactly
//  the drift this project keeps paying for.
//
//  WHERE THEY DIFFER, AND WHY THAT IS RIGHT. Sound fades through
//  `AudioGainComposition`, which is an ABSOLUTE level rule the runtime
//  already had; picture fades through this multiplier onto opacity. Two
//  media, two physical meanings, one authored gesture. Forcing them through
//  one number would have meant redefining what an audio fade IS.
//

import Foundation

/// The 0…1 multiplier a clip's own fades imply at an instant.
///
/// Pure, and shared: the editor's Viewer, the offline renderer and the
/// runtime all read this rather than each shaping a ramp of its own.
public enum MediaFadeCurve {

    /// The multiplier at `t` for a clip occupying `[start, end)`.
    ///
    /// LINEAR, on purpose. A shaped fade is a curve on a channel, and this
    /// is the handle-sized version of the idea; making it an ease here
    /// would mean an author could not reproduce it with keys.
    ///
    /// Outside the clip the shape is CLAMPED AT ITS ENDPOINTS rather than
    /// snapping back to 1. Before the start a faded-in clip reads 0 and
    /// after the end a faded-out one reads 0, which is what the author
    /// authored; a clip with no fades reads 1 everywhere. Whether the clip
    /// is on screen at all is the occurrence walk's answer, not this one's,
    /// and this must not contradict it at the boundary by rounding.
    public static func multiplier(
        at t: Double,
        start: Double,
        end: Double,
        fadeIn: Double?,
        fadeOut: Double?
    ) -> Double {
        let span = end - start
        guard span > 0 else { return 1 }
        let (rampIn, rampOut) = fitted(fadeIn: fadeIn, fadeOut: fadeOut, span: span)
        guard rampIn > 0 || rampOut > 0 else { return 1 }

        let t = min(max(t, start), end)
        var value = 1.0
        if rampIn > 0, t < start + rampIn {
            value = min(value, max(0, (t - start) / rampIn))
        }
        if rampOut > 0, t > end - rampOut {
            value = min(value, max(0, (end - t) / rampOut))
        }
        return min(1, max(0, value))
    }

    /// Two ramps that fit inside the clip.
    ///
    /// An author dragging both handles past the middle is expressing "fade
    /// the whole way through", and the honest reading of that is two ramps
    /// meeting — SCALED PROPORTIONALLY, never one of them silently winning.
    /// Clamping only the second would make the result depend on which
    /// handle was dragged last, which is the kind of thing that reads as a
    /// bug even when the number is defensible.
    public static func fitted(
        fadeIn: Double?,
        fadeOut: Double?,
        span: Double
    ) -> (in: Double, out: Double) {
        let wantIn = max(0, fadeIn ?? 0)
        let wantOut = max(0, fadeOut ?? 0)
        guard span > 0 else { return (0, 0) }
        let total = wantIn + wantOut
        guard total > span else { return (wantIn, wantOut) }
        let scale = span / total
        return (wantIn * scale, wantOut * scale)
    }

    /// The longest fade this clip can hold on one side, for an authoring
    /// surface that wants to clamp a drag rather than let it be scaled
    /// afterwards. The whole clip: two full-length ramps meeting in the
    /// middle is a legal thing to author.
    public static func maximumRamp(span: Double) -> Double { max(0, span) }
}
