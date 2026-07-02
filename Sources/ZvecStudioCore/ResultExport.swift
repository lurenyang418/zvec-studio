import Foundation

public struct ResultExportMetadata: Codable, Sendable, Equatable {
    public let source: String
    public let documentCount: Int
    public let limitReached: Bool
    public let completeCollectionBackup: Bool
    public let generatedAt: Date

    public init(source: String, documentCount: Int, limitReached: Bool, generatedAt: Date = .now) {
        self.source = source
        self.documentCount = documentCount
        self.limitReached = limitReached
        completeCollectionBackup = false
        self.generatedAt = generatedAt
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }
}
