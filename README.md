# ChapterScript

An open data format for declarative immersive experiences — chapters of timed steps, each step a bag of actions (entity reveals, audio cues, video playback, motion curves, gates).

ChapterScript is a Swift package containing only `Codable` value types. It has zero dependencies on RealityKit, UIKit, AppKit, or AVFoundation. The package builds on macOS, iOS, visionOS, tvOS, watchOS, and Linux.

The format is the public contract between authoring tools (e.g., a macOS editor) and players (e.g., the SharedVisions visionOS reference player). Either side can be reimplemented — including in a different language — by following the JSON schema this package defines.

## Status

Pre-1.0. The schema may change. `formatVersion` is currently `1`.

## Document shape

```
ExperienceDocument
├── formatVersion: Int
├── id, displayName: String
├── entities: [EntityDefinition]
├── chapters: [ChapterDefinition]
│   └── steps: [StepDefinition]
│       └── actions: [StepAction]      // externally-tagged JSON
├── particlePresets: [ParticleEmitterPreset]
└── manifest: AssetManifest
```

A `.chapterscript` package is a directory bundle:

```
MyExperience.chapterscript/
├── experience.json     ← ExperienceDocument
└── assets/
    ├── audio/
    ├── video/
    ├── usdz/
    └── images/
```

## Forward compatibility

Unknown `StepAction` cases parse into `StepAction.unknown(name:raw:)` rather than failing decode. Players can choose to log + skip; editors can round-trip them.

## Versioning

A single `formatVersion: Int`, monotonically increasing. JSON-to-JSON migrations live in `Migrator`. Players advertise a supported range; tools refuse to export to a player that can't read the document.

## License

To be set on first publication.
