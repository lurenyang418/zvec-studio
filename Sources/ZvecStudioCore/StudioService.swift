import Foundation
import Zvec

public actor StudioService {
    private var collections: [CollectionID: Collection] = [:]
    private var recents: [RecentCollection]
    private let recentStore: RecentCollectionStore

    public init(recentStore: RecentCollectionStore = .init()) {
        self.recentStore = recentStore
        recents = (try? recentStore.load()) ?? []
    }

    public func initialize(configuration: Configuration? = nil) async throws {
        try await ZvecRuntime.initialize(configuration: configuration)
    }

    public func recentCollections() -> [RecentCollection] { recents }
    public func openCollectionIDs() -> [CollectionID] { Array(collections.keys) }

    @discardableResult
    public func open(at url: URL, options: CollectionOptions? = nil) async throws -> CollectionSnapshot {
        let requestedID = CollectionID(url: url)
        if collections[requestedID] != nil { return try await snapshot(for: requestedID) }
        let collection = try await Collection.open(at: requestedID.url, options: options)
        let id = CollectionID(url: collection.location)
        collections[id] = collection
        try recordRecent(id)
        return try await snapshot(for: id)
    }

    @discardableResult
    public func create(
        at url: URL,
        schema: CollectionSchema,
        options: CollectionOptions? = nil
    ) async throws -> CollectionSnapshot {
        let collection = try await Collection.create(at: url, schema: schema, options: options)
        let id = CollectionID(url: collection.location)
        if let existing = collections[id], !existing.isClosed {
            try await collection.close()
            return try await snapshot(for: id)
        }
        collections[id] = collection
        try recordRecent(id)
        return try await snapshot(for: id)
    }

    public func snapshot(for id: CollectionID) async throws -> CollectionSnapshot {
        let collection = try requireCollection(id)
        async let options = collection.options()
        async let statistics = collection.statistics()
        return try await CollectionSnapshot(
            id: id,
            schema: collection.schema,
            options: options,
            statistics: statistics,
            isClosed: collection.isClosed
        )
    }

    public func close(_ id: CollectionID) async throws {
        guard let collection = collections.removeValue(forKey: id) else { return }
        try await collection.close()
    }

    public func closeAll() async throws {
        let current = collections
        collections.removeAll()
        for (_, collection) in current { try await collection.close() }
    }

    public func restartRuntime(configuration: Configuration? = nil) async throws {
        try await closeAll()
        try await ZvecRuntime.shutdown()
        try await ZvecRuntime.initialize(configuration: configuration)
    }

    public func shutdown() async throws {
        try await closeAll()
        try await ZvecRuntime.shutdown()
    }

    public func destroy(_ id: CollectionID, confirmationName: String) async throws {
        let collection = try requireCollection(id)
        guard confirmationName == collection.schema.name else {
            throw ServiceError.destroyConfirmationMismatch
        }
        try await collection.destroy()
        collections[id] = nil
        recents.removeAll { $0.id == id }
        try recentStore.save(recents)
    }

    public func flush(_ id: CollectionID) async throws { try await requireCollection(id).flush() }
    public func optimize(_ id: CollectionID) async throws { try await requireCollection(id).optimize() }

    public func browse(_ id: CollectionID, query: BrowseQuery) async throws -> BrowseResult {
        try await requireCollection(id).browse(query)
    }

    public func fetch(
        _ id: CollectionID,
        ids: [String],
        outputFields: [String] = [],
        includeVector: Bool = true
    ) async throws -> [DocumentFetchResult] {
        try await requireCollection(id).fetchResults(
            ids: ids, outputFields: outputFields, includeVector: includeVector
        )
    }

    public func write(
        _ id: CollectionID,
        documents: [Document],
        mode: WriteMode
    ) async throws -> [DocumentWriteResult] {
        let collection = try requireCollection(id)
        for document in documents { try collection.schema.validate(document, for: mode.intent) }
        switch mode {
        case .insert: return try await collection.insertWithResults(documents)
        case .update: return try await collection.updateWithResults(documents)
        case .upsert: return try await collection.upsertWithResults(documents)
        }
    }

    public func importDocuments(
        _ id: CollectionID,
        documents: [Document],
        mode: WriteMode,
        batchSize: Int = 500,
        progress: @Sendable (ImportProgress) async -> Void = { _ in }
    ) async throws -> ImportProgress {
        guard batchSize > 0 else { throw ServiceError.invalidBatchSize }
        var state = ImportProgress(unprocessed: documents.count)
        for start in stride(from: 0, to: documents.count, by: batchSize) {
            if Task.isCancelled {
                await progress(state)
                return state
            }
            let end = min(start + batchSize, documents.count)
            let results = try await write(id, documents: Array(documents[start..<end]), mode: mode)
            state.succeeded += results.lazy.filter(\.succeeded).count
            state.failed += results.lazy.filter { !$0.succeeded }.count
            state.unprocessed -= results.count
            await progress(state)
        }
        return state
    }

    public func delete(_ id: CollectionID, documentID: String) async throws -> DocumentWriteResult {
        try await requireCollection(id).delete(id: documentID)
    }

    public func delete(_ id: CollectionID, where filter: String) async throws {
        try await requireCollection(id).delete(where: filter)
    }

    public func query(_ id: CollectionID, _ query: VectorQuery) async throws -> [Document] {
        try await requireCollection(id).query(query)
    }

    public func query(_ id: CollectionID, _ query: FullTextQuery) async throws -> [Document] {
        try await requireCollection(id).query(query)
    }

    public func query(_ id: CollectionID, _ query: MultiQuery) async throws -> [Document] {
        try await requireCollection(id).query(query)
    }

    public func query(_ id: CollectionID, _ query: GroupByVectorQuery) async throws -> [GroupResult] {
        try await requireCollection(id).query(query)
    }

    public func addColumn(_ id: CollectionID, field: FieldSchema, defaultExpression: String? = nil) async throws {
        try await requireCollection(id).addColumn(field, defaultExpression: defaultExpression)
    }

    public func alterColumn(
        _ id: CollectionID, name: String, newName: String? = nil, schema: FieldSchema? = nil
    ) async throws {
        try await requireCollection(id).alterColumn(name, newName: newName, schema: schema)
    }

    public func dropColumn(_ id: CollectionID, name: String) async throws {
        try await requireCollection(id).dropColumn(name)
    }

    public func createIndex(_ id: CollectionID, field: String, index: IndexConfiguration) async throws {
        try await requireCollection(id).createIndex(index, for: field)
    }

    public func dropIndex(_ id: CollectionID, field: String) async throws {
        try await requireCollection(id).dropIndex(for: field)
    }

    private func requireCollection(_ id: CollectionID) throws -> Collection {
        guard let collection = collections[id], !collection.isClosed else { throw ServiceError.collectionNotOpen(id) }
        return collection
    }

    private func recordRecent(_ id: CollectionID) throws {
        recents.removeAll { $0.id == id }
        recents.insert(RecentCollection(id: id), at: 0)
        if recents.count > 30 { recents.removeLast(recents.count - 30) }
        try recentStore.save(recents)
    }
}

public enum ServiceError: Error, Equatable, CustomStringConvertible {
    case collectionNotOpen(CollectionID)
    case destroyConfirmationMismatch
    case invalidBatchSize

    public var description: String {
        switch self {
        case let .collectionNotOpen(id): "Collection is not open: \(id)"
        case .destroyConfirmationMismatch: "Destroy confirmation must exactly match the collection name"
        case .invalidBatchSize: "Import batch size must be greater than zero"
        }
    }
}
