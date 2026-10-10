//
//  RetiredNames.swift
//  ChapterScript
//
//  API-COMPAT. The runtime's old word for a Segment was retired on 2026-10-10
//  (docs/TERMINOLOGY.md in chapterengine). Apps that build against this
//  package's `main` (the SharedVisions player) still read the old list name,
//  so it forwards to `segments` as deprecated, with a `renamed:` fix-it. The
//  saved format is unaffected (it never stopped spelling the key the old way).
//  Delete this file once no client calls it. Nothing else may use it.
//

extension SequenceDefinitionDTO {
    @available(*, deprecated, renamed: "segments")  // API-COMPAT
    public var steps: [SegmentDefinitionDTO] {  // API-COMPAT
        get { segments }
        set { segments = newValue }
    }
}
