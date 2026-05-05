# ChapterScript

> **An open data format for declarative immersive experiences — chapters of timed steps, each step a bag of actions (entity reveals, audio cues, video playback, motion curves, gates).**

ChapterScript is a Swift package containing only `Codable` value types. It has zero dependencies on RealityKit, UIKit, AppKit, or AVFoundation. The package builds on macOS, iOS, visionOS, tvOS, watchOS, and Linux.

The format is the public contract between authoring tools (e.g., the [Maestro](https://github.com/Shared-Visions/maestro) macOS editor) and players (e.g., the [SharedVisions](https://github.com/Shared-Visions/sharedvisions) visionOS reference player). Either side can be reimplemented — including in a different language — by following the JSON schema this package defines.

---

## ✨ What's in here

- **`ExperienceDocument`** — the top-level container with `formatVersion`, `id`, `displayName`, `entities`, `chapters`, `particlePresets`, `manifest`, `defaultChapterId`
- **`ChapterDefinitionDTO`** — chapter id, name, ordered steps, on-complete action (`holdOnLastStep` / `autoAdvance` / `dismissToHome` / `transitionTo`)
- **`StepDefinitionDTO`** — step id, name, duration, ordered actions, scheduled actions (time-offset within the step), optional `gate`
- **`StepActionDTO`** — externally-tagged sum type covering ~30 action variants (entity reveal/move/fade/scale, attachments, audio play/stop/fade/zones/buses, video play/prepare/stop, effects, gestures, system flags, custom escape hatch)
- **`MotionCurve`** — composable parametric motion: `constant`, `linear`, `orbit`, `spiral`, `oscillate`, `rotate`, `keyframes`, `sum`, `scaled` (recursive)
- **`EntityDefinition`** — declarative entity registry: primitive shapes, USDZ refs, text3D, lights, video panels, particle preset bindings, custom-factory escape hatch
- **`AssetManifest`** — `[AssetEntry]` with relative paths, byte sizes, SHA-256 hashes, durations, dimensions
- **`KeyframePoint`** + **`InterpolationMode`** — primitives reused inside `MotionCurve.keyframes`
- **`Migrator`** — JSON-to-JSON schema migrators that run before typed decoding so older documents stay loadable
- **Forward-compat** — unknown future `StepAction` cases parse into `.unknown(name:raw:)` rather than failing decode, so editors can preserve future fields and players can log + skip

---

## 📦 The on-disk format

A `.chapterscript` package is a Finder-visible directory bundle:

```
MyExperience.chapterscript/
├── experience.json          ← the ExperienceDocument JSON
└── assets/
    ├── audio/narration_01.m4a
    ├── video/skybox.mp4
    ├── usdz/spaceship.usdz
    └── images/poster.heic
```

`experience.json` is the top-level JSON document. Paths inside `assets/` are referenced from the `manifest.entries[].relativePath` field. The directory layout under `assets/` is up to the author.

---

## 🧪 Wire-format example

A minimal one-chapter experience:

```json
{
  "formatVersion": 1,
  "id": "minimal",
  "displayName": "Minimal Experience",
  "entities": [],
  "particlePresets": [],
  "manifest": { "entries": [] },
  "chapters": [
    {
      "id": "only",
      "name": "Only Chapter",
      "phase": "immersive",
      "visibility": {},
      "onComplete": { "kind": "holdOnLastStep" },
      "steps": [
        {
          "id": "step1",
          "name": "Reveal orb",
          "duration": 2.0,
          "scheduledActions": [],
          "actions": [
            {
              "kind": "revealEntity",
              "reveal": {
                "entity": "orb",
                "headRelativePosition": { "x": 0, "y": 1.6, "z": -1.5 },
                "headYOnly": true,
                "fadeIn": 0.5
              }
            }
          ]
        }
      ]
    }
  ]
}
```

Action variants are externally-tagged: each `actions[i]` carries a `"kind"` key and the rest of the keys carry the case-specific payload. See `Tests/ChapterScriptTests/Fixtures/representative.json` for a complete document exercising most action kinds.

---

## 🚀 Using the package

`Package.swift`:

```swift
.package(url: "https://github.com/Shared-Visions/chapterscript.git", from: "0.1.0")
```

Or as a sibling local package:

```swift
.package(path: "../ChapterScript")
```

Decode a document:

```swift
import ChapterScript

let url = URL(fileURLWithPath: "MyExperience.chapterscript/experience.json")
let data = try Data(contentsOf: url)
let migrated = try Migrator.migrate(data)                   // JSON-to-JSON forward migration
let doc = try ChapterScriptFormat.makeDecoder()
    .decode(ExperienceDocument.self, from: migrated)

print(doc.chapters.map(\.id))                               // ["chapter_01_…", "chapter_02_…", …]
```

Encode a document:

```swift
let encoder = ChapterScriptFormat.makeEncoder()             // pretty-printed, sorted keys, no escaped slashes
let data = try encoder.encode(doc)
try data.write(to: url)
```

---

## 🔁 Forward + backward compat

- **Unknown action variants** parse into `.unknown(name:raw:)`. Editors that don't recognize a future action kind can preserve and re-emit `raw` unchanged through round-trips. Players that don't understand it should log and skip.
- **Schema versioning** uses a single integer `formatVersion`. Migrators (registered in `Migrator.steps`) run JSON→JSON before typed decode. Players can advertise a `[minSupported, maxSupported]` range; editors refuse to export to a player they know can't read the document.

---

## 🧬 Extension points

The format is intentionally finite for the cases it covers, with two escape hatches for the long tail:

- **`StepActionDTO.custom(id:parameters:)`** — opaque actions identified by a custom id, with a free-form JSON parameter blob. Players register custom factories per id.
- **`EntityDefinition.kind: .custom`** with `customFactoryId` — opaque entities built by app-registered factories. Used by SharedVisions to ship hand-tuned procedural VFX (PulseRing, SparkBurst) that aren't yet declarative.

---

## 🧪 Tests + fixtures

```bash
swift test
```

Every DTO has round-trip tests. `Tests/Fixtures/` ships:

- **`minimal.json`** — smallest valid document
- **`representative.json`** — exercises 30+ action variants and most `MotionCurve` kinds
- **`documentary.json`** — the eight-chapter SharedVisions documentary as a fidelity gate; round-trips every action and validates the auto-advance chain

---

## 🏛️ Repo layout

```
ChapterScript/
├── Package.swift                              # multi-platform Swift package
├── README.md
├── Sources/ChapterScript/
│   ├── Primitives.swift                       # Vec3, ColorRGBA, TransformData, Quat, VisibilityKind
│   ├── Animation.swift                        # KeyframePoint, InterpolationMode, MotionCurve, Waveform
│   ├── Entity.swift                           # EntityDefinition, PrimitiveSpec, MaterialSpec, …
│   ├── Actions.swift                          # MoveActionDTO, FadeActionDTO, AudioActionDTO, …
│   ├── StepAction.swift                       # StepActionDTO + externally-tagged Codable
│   ├── Chapter.swift                          # ChapterDefinitionDTO, StepDefinitionDTO, …
│   ├── Document.swift                         # ExperienceDocument, AssetManifest, ChapterScriptFormat
│   └── Migrator.swift                         # JSON-to-JSON schema migrators
└── Tests/ChapterScriptTests/
    ├── RoundTripTests.swift
    ├── FixtureTests.swift
    └── Fixtures/
        ├── minimal.json
        ├── representative.json
        └── documentary.json
```

---

## 📌 Status

Pre-1.0. The schema may change. `formatVersion` is currently **1**. The first stable release will lock the wire format and start the strict back-compat regime.

---

## 🪪 License

MIT — see `LICENSE`.
