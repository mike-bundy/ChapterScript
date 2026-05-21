# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

ChapterScript is the open, platform-pure data format for declarative immersive experiences consumed by [SharedVisions](https://github.com/Shared-Visions/SharedVisionsProject) (visionOS player) and authored by [Maestro](https://github.com/mike-bundy/Maestro) (macOS editor). The package is a Swift Package Manager target containing only `Codable` value types — zero dependencies on RealityKit, UIKit, AppKit, AVFoundation. Builds on macOS, iOS, visionOS, tvOS, watchOS, and Linux.

**Tech:** Swift 5.9+, SwiftPM, Codable. No runtime dependencies.

## Build Commands

```bash
swift build              # compile
swift test               # 22 round-trip + fixture tests
```

No Xcode project — pure SwiftPM. Consumers add this as either a remote package dependency (pinned by tag) or a local-path package.

## Release process

Consumers (SharedVisions, Maestro) pin ChapterScript via `XCRemoteSwiftPackageReference` in their pbxproj with `requirement = upToNextMajorVersion(from: "0.x.y")`. To ship a new ChapterScript change:

1. Make the change on `main`. Keep it backward-compatible (`decodeIfPresent` for new fields, fall through for unknown enum raw values).
2. Bump version in your head — tags are the source of truth.
3. `git tag vX.Y.Z`
4. `git push origin main && git push origin vX.Y.Z`
5. In each consumer, edit `<project>.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved` to bump the `revision` (the tag's commit SHA) and `version` strings. `xcodebuild -resolvePackageDependencies` won't pick up a new version through `upToNextMajor` unless Package.resolved is bumped or deleted.

`git auth status` should be `mike-bundy` for pushes; the alt `shellcorpnet` account doesn't have write access to this repo. `gh auth switch --user mike-bundy` if needed.

## Architecture

### The document

```
ExperienceDocument
├── formatVersion: Int                              ← currently 1
├── id, displayName, description
├── entities: [EntityDefinition]                    ← declarative entity registry
├── chapters: [ChapterDefinitionDTO]                ← ordered chapter list
├── particlePresets: [ParticleEmitterPresetDTO]
├── manifest: AssetManifest                         ← SHA-256 + byteSize per asset
└── defaultChapterId: String?
```

### Chapter / step / action shape

```
ChapterDefinitionDTO
├── id, name, phase                                 ← phase is a free-form routing tag (legacy)
├── presentation: ChapterPresentation               ← v0.3.x — typed mode
│     .immersive / .mixed / .windowed
├── immersiveBackdrop: ImmersiveBackdropSpec?       ← v0.3.x — optional ambient backdrop
│     .video(file, layout, field, radius, loop) | .usdz(assetId)
├── steps: [StepDefinitionDTO]
│     ├── id, name, duration
│     ├── actions: [StepActionDTO]                  ← fire at step start
│     ├── scheduledActions: [ScheduledActionDTO]    ← fire at step start + at offset
│     └── gate: StepGateDTO?                        ← block step until satisfied
├── visibility: VisibilityStateDTO                  ← legacy fixed-keys map (rarely used)
└── onComplete: CompletionActionDTO
      .holdOnLastStep | .autoAdvance(nextChapterId) | .transitionTo(...) | .dismissToHome
```

### StepActionDTO (sum type)

Externally-tagged Codable — every JSON `actions[i]` carries `"kind": "<case>"` and case-specific payload keys. ~30 variants:

- **Entity**: `showEntity`, `hideEntity`, `revealEntity`, `moveEntity`, `scaleEntity`, `fadeEntity`, `persistEntity`, `unpersistEntity`, `animateMotion`
- **Attachment**: `showAttachment`, `hideAttachment`, `fadeAttachment`, `setAttachmentView`, `positionAttachment`
- **Audio**: `playAudio`, `stopAudio`, `fadeAudio`, `onAudioComplete`, `setMasterVolume`, `setCategoryVolume`, `addAudioZone`, `removeAudioZone`, `removeAllAudioZones`, `setBusVolume`, `setBusEffect`, `removeBusEffect`
- **Video**: `playVideo`, `prepareVideo`, `stopVideo`
- **Effects**: `showPulseRing`, `hidePulseRing`, `startSparkBurst`, `stopSparkBurst`
- **Gesture / system**: `enableGesture`, `disableGesture`, `setUpperLimbVisibility`, `setKeyboardPassthrough`
- **Escape hatch**: `custom(id:, parameters:)`
- **Forward-compat**: any unknown kind decodes into `unknown(name:, raw:)` for round-trip preservation

### VideoPresentation + VideoLayout

```
VideoPresentation
├── .attachment(id:)                  ← SwiftUI overlay
├── .entity(name:, width:, height:)   ← scene panel (RealityKit ModelComponent + VideoMaterial)
└── .immersive(radius:, field:)       ← skybox sphere
       field: .equirect360 | .equirect180

VideoLayout
.mono | .sideBySide | .overUnder | .multiviewHEVC
```

### MotionCurve (animateMotion payload)

Recursive sum type:

- `.constant(Vec3)`
- `.linear(from:Vec3, to:Vec3)`
- `.orbit(center, radius, axis, revolutions, phase)`
- `.spiral(center, startRadius, endRadius, axis, revolutions, yRise)`
- `.oscillate(axis, amplitude, frequency, waveform)` — waveform: `.sine`, `.absSine`, `.triangle`, `.square`
- `.rotate(axis, revolutions)`
- `.keyframes([KeyframePoint])` with per-segment `InterpolationMode`
- `.sum([MotionCurve])` — superpose children
- `.scaled(by:, _ MotionCurve)` — uniformly scale a child curve

Players sample with `(progress: Float, absoluteTime: Float)` to support both step-relative animation and wall-clock-driven oscillation.

### EntityDefinition

```
EntityDefinition
├── id, kind, transform, initiallyEnabled, gestureEnabled
└── one of:
    ├── primitive: PrimitiveSpec       (shape: .sphere/.box/.cylinder/.cone/.plane)
    ├── usdzAssetId: String            (references AssetManifest entry)
    ├── text: TextSpec
    ├── light: LightSpec
    ├── videoPanel: VideoPanelSpec
    ├── particlePresetId: String       (references ParticleEmitterPresetDTO)
    └── customFactoryId: String + customParameters: [String: AnyCodableValue]?
```

### Compat strategy

- **Schema versioning**: single integer `formatVersion`. `Migrator.steps` runs JSON→JSON before typed decode. Players advertise `[minSupported, maxSupported]`; editors refuse to export below the player's floor.
- **Unknown action kinds**: parse into `.unknown(name:, raw:)`. Editors preserve `raw` through round-trips so they don't strip forward fields they don't know yet.
- **Unknown enum raw values**: `ChapterPresentation` decoder falls back to `.immersive` for unknown raw strings so a future `.standalone` case (or whatever) doesn't fail decode on older players — it just gets interpreted as "needs 3D space."
- **decodeIfPresent for new fields**: every new field on `ChapterDefinitionDTO` (presentation, immersiveBackdrop) and on inner DTOs uses `decodeIfPresent` with sensible defaults so v0.2 docs continue to load against v0.3+ code.

## File layout

```
ChapterScript/
├── Package.swift                      # SwiftPM manifest (multi-platform, swift-tools-version 5.9)
├── README.md
├── CLAUDE.md                          # this file
├── Sources/ChapterScript/
│   ├── Primitives.swift               # Vec3, ColorRGBA, TransformData, Quat, VisibilityKind, AnyCodableValue
│   ├── Animation.swift                # KeyframePoint, InterpolationMode, MotionCurve, Waveform
│   ├── Entity.swift                   # EntityDefinition, PrimitiveSpec, MaterialSpec, TextSpec, LightSpec, VideoPanelSpec
│   ├── Actions.swift                  # Move/Fade/Reveal/Audio/Video action DTOs + VideoPresentation/Layout/ImmersiveField
│   ├── StepAction.swift               # StepActionDTO + externally-tagged Codable + unknown round-trip helper
│   ├── Chapter.swift                  # ChapterDefinitionDTO, StepDefinitionDTO, ScheduledActionDTO, StepGateDTO,
│   │                                  # ChapterPresentation, ImmersiveBackdropSpec, CompletionActionDTO, VisibilityStateDTO
│   ├── Document.swift                 # ExperienceDocument, AssetManifest, ChapterScriptFormat (encoder/decoder factories)
│   └── Migrator.swift                 # JSON-to-JSON schema migrators (currently empty pipeline; ready for future bumps)
└── Tests/ChapterScriptTests/
    ├── RoundTripTests.swift           # encode→decode equality for every DTO + every StepAction variant
    ├── FixtureTests.swift             # documentary.json + representative.json + minimal.json load + round-trip
    └── Fixtures/
        ├── minimal.json
        ├── representative.json        # exercises 30+ action variants + most MotionCurve kinds
        └── documentary.json           # SharedVisions's 8-chapter documentary as a fidelity gate
```

## Adding a new StepActionDTO case

1. Add the case to the `StepActionDTO` enum in `StepAction.swift`.
2. Add a `Kind` raw value matching the case name.
3. Add encode + decode branches for the new kind.
4. If the case carries a complex payload, define its DTO struct in `Actions.swift`.
5. Add a round-trip test in `RoundTripTests.swift`.
6. (Optional) Add it to `representative.json` so the fixture exercises the case.
7. Bump `formatVersion` ONLY if the case's *absence* is observable to readers. New cases that older players don't understand should fall through `.unknown` — that's not a format bump.

## Adding a new ChapterDefinitionDTO field

1. Add the property to the struct.
2. Add a `CodingKey` for it.
3. In the explicit `init(from:)`, use `decodeIfPresent` with a sensible default so older documents still decode.
4. In `init(...)`, give the new parameter a default value so existing constructor call sites still compile.
5. Add round-trip coverage in tests.
6. Bump the version and tag — consumers will need to update Package.resolved to see the field.

## Known quirks

- `MotionCurve` is `indirect enum` because of `.sum` and `.scaled`. Watch for retain cycles only if you stuff curves into runtime caches that hold references — DTOs themselves are value types and fine.
- `AnyCodableValue` is the JSON-shaped value wrapper used for `custom.parameters` and `unknown.raw`. Don't sneak typed values through it — use a real DTO for anything you want to type-check at the format layer.
- `MaterialBlending.alpha` is a rendering hint; players honor it via their material setup. `MaterialSpec.emissiveIntensity` is in arbitrary engine units and gets mapped per-player.
- `VisibilityStateDTO` is a legacy fixed-keys-per-app concept. The `entities` dict can carry arbitrary keys; players just consult the ones they recognize. New chapter authoring should rely on `revealEntity` / `hideEntity` rather than this snapshot map.
