import Foundation

/// A stored logical Timeline lane. Unlike a video destination, this is not an
/// Entity and has no runtime identity: occurrences name it only for editorial
/// layout and collision rules while their actions keep targeting real Objects.
public struct LogicalTimelineTrack: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var kind: Kind
    public var name: String

    public init(id: String = LogicalTimelineTrack.newID(), kind: Kind, name: String) {
        self.id = id
        self.kind = kind
        self.name = name
    }

    public static func newID() -> String {
        "track_" + UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(16)
    }

    /// A tolerant wire value: a newer logical lane remains round-trippable in
    /// an older build rather than making the whole Sequence unreadable.
    public struct Kind: RawRepresentable, Codable, Sendable, Equatable, Hashable {
        public var rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public static let title = Kind(rawValue: "title")
    }
}
