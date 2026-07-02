import Foundation

public struct RecentCollectionStore: Sendable {
    public let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultURL()
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    public func load() throws -> [RecentCollection] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        return try decoder.decode([RecentCollection].self, from: Data(contentsOf: fileURL))
            .sorted { $0.lastOpenedAt > $1.lastOpenedAt }
    }

    public func save(_ recents: [RecentCollection]) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try encoder.encode(recents).write(to: fileURL, options: .atomic)
    }

    private static func defaultURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appending(path: "ZvecStudio", directoryHint: .isDirectory)
            .appending(path: "recent-collections.json")
    }
}
