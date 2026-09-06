//
//  AudioGainComposition.swift
//  ChapterScript
//
//  THE ONE RULE FOR HOW LOUD A CLIP IS.
//
//  Before this existed there was no rule, and the two halves of the app
//  disagreed in different ways:
//
//    - The Mac preview computed `base × channelCurve × masterCurve` and never
//      looked at `fadeAudio` at all, so an authored fade was INAUDIBLE in the
//      editor.
//    - The runtime's `fadeAudio` mutated the channel's target level and ramped
//      `node.volume` on its own 30 Hz task, while the automation sampler wrote
//      the SAME property from its own 20 Hz task and cancelled that ramp. Two
//      writers, no order: whichever ran last won, so a fade crossing a volume
//      key produced a different result depending on timing.
//
//  Both are gone. There is one function, it is pure, and both hosts call it.
//
//  THE ORDER, and why each factor sits where it does:
//
//      authoredGain(t) = level(t)              the clip's level, as FADED
//                      × channelCurve(t)       this channel's ride
//                      × masterCurve(t)        the master ride
//
//  `level(t)` is the clip's base volume as rewritten by any `fadeAudio` in
//  force — an ABSOLUTE level, not a multiplier, because that is what the
//  runtime already meant by it: `fade(channel:to:)` replaced the channel's
//  target outright. Formalizing that rather than inventing a multiplicative
//  fade keeps every existing document sounding the same.
//
//  Automation multiplies ON TOP, which is what makes "duck the music under
//  this line" and "fade the music out at the end" independent operations
//  instead of two commands fighting over one number.
//
//  WHAT IS NOT HERE. Bus volume, category gain, master mixer volume and
//  ducking are MIXER state, not authored sequence data — they are not in a
//  document and they differ per playback session. The runtime applies them
//  outside this function:
//
//      node.volume = authoredGain(t) × bus × category × master × duck
//
//  Keeping them out is what lets this be pure and testable, and what lets the
//  editor — which has no buses — compute exactly the same authored number the
//  device does.
//
//  EVERYTHING IS ON THE AUTHORED CLOCK. `t` is absolute sequence seconds, the
//  same clock animation curves use, so a gate holds a fade exactly where it
//  holds a trajectory.
//

import Foundation

/// One authored fade in force on a channel.
///
/// Derived from the document, never stored: `playAudio.fadeIn` produces one
/// (silence → the clip's base level at its start) and each `fadeAudio` action
/// produces another. Callers build the list; this type only describes it.
public struct AudioFade: Equatable, Sendable {
    /// Absolute sequence seconds where the ramp begins.
    public var startTime: Double
    /// Seconds the ramp takes. Zero is legal and means an instant change.
    public var duration: Double
    /// The level the ramp ends at.
    public var to: Float
    /// The level the ramp begins at, when the author fixed it — a fade-in
    /// starts at silence regardless of what came before. `nil` means "start
    /// from whatever level was in force", which is what `fadeAudio` means.
    public var from: Float?

    public init(startTime: Double, duration: Double, to: Float, from: Float? = nil) {
        self.startTime = startTime
        self.duration = max(0, duration)
        self.to = to
        self.from = from
    }
}

public enum AudioGainComposition {

    /// THE AUTHORED GAIN of a clip at `time`. This is the number the editor
    /// preview and the device runtime must both use.
    public static func authoredGain(
        base: Float,
        fades: [AudioFade] = [],
        channel: String,
        at time: Double,
        in tracks: [AudioAutomationTrack]
    ,
        muted: Bool = false,
        trackGainDB: Float = 0
    ) -> Float {
        if muted { return 0 }
        let trackGain: Float = trackGainDB == 0 ? 1 : pow(10, trackGainDB / 20)
        let level = self.level(base: base, fades: fades, at: time)
        let ride = SequenceAudioAutomation.volumeMultiplier(for: channel, at: time, in: tracks)
        // Clamped once, at the end. Bezier handles overshoot past a key on
        // purpose, and a negative or >1 gain is a runtime error rather than a
        // louder sound.
        return trackGain * min(max(level * ride, 0), 1)
    }

    /// The clip's level at `time`, with every fade in force applied in order.
    ///
    /// Fades are applied in START ORDER and each one begins from the level the
    /// previous one left, so a fade-out followed by a fade-in does what it
    /// reads like. A fade with an explicit `from` ignores the running level —
    /// that is what makes a fade-in start from silence even when the clip was
    /// already loud.
    public static func level(base: Float, fades: [AudioFade], at time: Double) -> Float {
        guard !fades.isEmpty else { return base }
        var level = base
        for fade in fades.sorted(by: { $0.startTime < $1.startTime }) {
            let start = fade.from ?? level
            if time < fade.startTime {
                // This fade has not begun; nothing after it has either.
                return level
            }
            // AT the start instant the fade's own beginning level applies.
            // For a fade with no explicit `from` that IS the running level,
            // so this is the same answer it always gave. For one that fixes
            // its start - a fade-in from silence - it is the difference
            // between silence and a click: the clip's first instant used to
            // read at full level and drop on the next sample.
            if time >= fade.startTime + fade.duration || fade.duration <= 0 {
                level = fade.to
                continue
            }
            let progress = Float((time - fade.startTime) / fade.duration)
            return start + (fade.to - start) * progress
        }
        return level
    }

    /// The fades a clip's own authored fields imply.
    ///
    /// `playAudio.fadeIn` is a ramp from SILENCE to the clip's base level over
    /// `fadeIn` seconds, beginning when the clip starts. Expressed as a fade
    /// with an explicit `from: 0` so it cannot be confused with a `fadeAudio`
    /// that happens to start at the same instant.
    /// `clipEnd` is what lets the two ramps be FITTED together
    /// (`MediaFadeCurve.fitted`), so an author who drags both handles past
    /// the middle gets two ramps meeting rather than a result that depends
    /// on which handle moved last. Pass `nil` when the end is genuinely
    /// unknown and the fade-in stands on its own.
    public static func fadeIn(
        for action: AudioActionDTO,
        clipStart: Double,
        clipEnd: Double? = nil
    ) -> AudioFade? {
        guard let authored = action.fadeIn, authored > 0 else { return nil }
        let ramp: Double
        if let clipEnd {
            ramp = MediaFadeCurve.fitted(fadeIn: authored, fadeOut: action.fadeOut,
                                         span: clipEnd - clipStart).in
        } else {
            ramp = authored
        }
        guard ramp > 0 else { return nil }
        return AudioFade(startTime: clipStart, duration: ramp, to: action.volume, from: 0)
    }

    /// The fade a clip's own `fadeOut` implies (FL-18 N12).
    ///
    /// A ramp to SILENCE ending exactly at the clip's end, so the sound is
    /// gone at the same instant the picture is. Expressed through the same
    /// `AudioFade` every other fade uses — an absolute level ramp — rather
    /// than a second, multiplicative kind of fade, because the runtime and
    /// the editor both already agree on what one of these means.
    ///
    /// The two ramps are FITTED to the clip before either is used, so a
    /// fade-in and a fade-out longer than the clip meet in the middle
    /// instead of one silently overwriting the other. That is
    /// `MediaFadeCurve.fitted`, shared with the picture half.
    public static func fadeOut(
        for action: AudioActionDTO,
        clipStart: Double,
        clipEnd: Double
    ) -> AudioFade? {
        let span = clipEnd - clipStart
        let ramps = MediaFadeCurve.fitted(fadeIn: action.fadeIn,
                                          fadeOut: action.fadeOut, span: span)
        guard ramps.out > 0 else { return nil }
        return AudioFade(startTime: clipEnd - ramps.out, duration: ramps.out,
                         to: 0, from: action.volume)
    }

    /// THE OCCURRENCE SPAN RULE, for the one question this file has to ask
    /// about time: where does a clip end?
    ///
    /// A play runs until the same channel's next stop or play LATER in the
    /// Step — a same-instant action precedes it by authored order, so it
    /// does not end it — else until the Step's end. The identical rule the
    /// runtime's `SequenceEngine.occurrenceSpan` and the Kit's Timeline
    /// projection apply; stated here rather than approximated, because a
    /// fade-out that ends at the wrong instant is audible.
    public static func occurrenceEnd(
        ofChannel channel: String,
        firedAt offset: Double,
        in step: StepDefinitionDTO
    ) -> Double {
        var end = step.duration
        for authored in step.authoredActions where authored.at > offset + 1e-6 && authored.at < end {
            switch authored.action {
            case .stopAudio(let target) where target == channel: end = authored.at
            case .playAudio(let audio) where audio.channel == channel: end = authored.at
            default: break
            }
        }
        return max(offset, end)
    }

    /// Every fade affecting `channel`, gathered from a sequence in authored
    /// order — the clip's own `fadeIn` and `fadeOut` plus each `fadeAudio`
    /// targeting it.
    ///
    /// Walks the sequence once. Callers cache this per playback pass rather
    /// than calling it per frame; it is a document walk, and `PERFORMANCE.md`
    /// is explicit that those do not belong on a render path.
    public static func fades(
        forChannel channel: String,
        in sequence: SequenceDefinitionDTO
    ) -> [AudioFade] {
        var result: [AudioFade] = []
        var stepStart = 0.0
        for step in sequence.steps {
            for authored in step.authoredActions {
                let time = stepStart + authored.at
                switch authored.action {
                case .playAudio(let audio) where audio.channel == channel:
                    let end = stepStart + occurrenceEnd(ofChannel: channel,
                                                        firedAt: authored.at, in: step)
                    if let fade = fadeIn(for: audio, clipStart: time, clipEnd: end) {
                        result.append(fade)
                    }
                    if let fade = fadeOut(for: audio, clipStart: time, clipEnd: end) {
                        result.append(fade)
                    }
                case .fadeAudio(let target, let to, let duration) where target == channel:
                    result.append(AudioFade(startTime: time, duration: duration, to: to))
                default:
                    break
                }
            }
            stepStart += step.duration
        }
        return result.sorted { $0.startTime < $1.startTime }
    }
}
