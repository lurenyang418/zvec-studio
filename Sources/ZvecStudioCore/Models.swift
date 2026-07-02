import Foundation
import Zvec

public struct CollectionID: Hashable, Codable, Sendable, Identifiable, CustomStringConvertible {
    public let rawValue: String
    public var id: String { rawValue }
    public var description: String { rawValue }

    public init(url: URL) {
        rawValue = url.standardizedFileURL.resolvingSymlinksInPath().path
    }

    public var url: URL { URL(fileURLWithPath: rawValue, isDirectory: true) }
}

public struct CollectionSnapshot: Sendable, Identifiable {
    public let id: CollectionID
    public let schema: CollectionSchema
    public let options: CollectionOptions
    public let statistics: CollectionStatistics
    public let isClosed: Bool

    public init(
        id: CollectionID,
        schema: CollectionSchema,
        options: CollectionOptions,
        statistics: CollectionStatistics,
        isClosed: Bool
    ) {
        self.id = id
        self.schema = schema
        self.options = options
        self.statistics = statistics
        self.isClosed = isClosed
    }
}

public struct RecentCollection: Codable, Hashable, Sendable, Identifiable {
    public let id: CollectionID
    public var lastOpenedAt: Date

    public init(id: CollectionID, lastOpenedAt: Date = .now) {
        self.id = id
        self.lastOpenedAt = lastOpenedAt
    }
}

public struct StudioErrorPresentation: Error, Identifiable, Sendable {
    public let id = UUID()
    public let operation: String
    public let collectionPath: String?
    public let underlying: String
    public let zvecError: ZvecError?

    public init(operation: String, collectionPath: String? = nil, underlying: any Error) {
        self.operation = operation
        self.collectionPath = collectionPath
        self.underlying = String(describing: underlying)
        zvecError = underlying as? ZvecError
    }

    public var message: String {
        if let collectionPath {
            return "\(operation) failed for \(collectionPath): \(underlying)"
        }
        return "\(operation) failed: \(underlying)"
    }
}

public enum WriteMode: String, CaseIterable, Sendable {
    case insert
    case update
    case upsert

    public var intent: DocumentWriteIntent {
        switch self {
        case .insert: .insert
        case .update: .update
        case .upsert: .upsert
        }
    }
}

public struct ImportProgress: Sendable, Equatable {
    public var succeeded = 0
    public var failed = 0
    public var unprocessed = 0

    public init(succeeded: Int = 0, failed: Int = 0, unprocessed: Int = 0) {
        self.succeeded = succeeded
        self.failed = failed
        self.unprocessed = unprocessed
    }
}
