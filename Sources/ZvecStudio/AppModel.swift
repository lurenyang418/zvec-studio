import Foundation
import Observation
import Zvec
import ZvecStudioCore

@MainActor
@Observable
final class StudioModel {
    enum Destination: Hashable {
        case dashboard
        case collection(CollectionID)
    }

    let service: StudioService
    let runtimeConfigurationStore: RuntimeConfigurationStore
    var runtimeProfile: RuntimeConfigurationProfile
    var destination: Destination? = .dashboard
    var recents: [RecentCollection] = []
    var opened: [CollectionSnapshot] = []
    var documents: [Document] = []
    var queryDocuments: [Document] = []
    var groupResults: [GroupResult] = []
    var editingDocument: Document?
    var uiState = StudioUIState()
    var browseLimitReached: Bool { uiState.browseLimitReached }
    var operationMessage: String?
    var importProgress: ImportProgress?
    var isBusy: Bool { uiState.isLoading }
    var runtimeReady = false
    var runtimeNeedsRestart = false
    var error: StudioErrorPresentation?

    init(
        service: StudioService = StudioService(),
        runtimeConfigurationStore: RuntimeConfigurationStore = .init()
    ) {
        self.service = service
        self.runtimeConfigurationStore = runtimeConfigurationStore
        runtimeProfile = (try? runtimeConfigurationStore.load()) ?? .init()
    }

    func start() async {
        await perform("Initialize Runtime") {
            try await service.initialize(configuration: runtimeProfile.configuration)
            runtimeReady = true
            recents = await service.recentCollections()
        }
    }

    func open(_ url: URL) async {
        await perform("Open Collection", path: url.path) {
            let snapshot = try await service.open(at: url)
            opened.removeAll { $0.id == snapshot.id }
            opened.append(snapshot)
            recents = await service.recentCollections()
            destination = .collection(snapshot.id)
            uiState.select(snapshot.id)
            editingDocument = nil
            await browse(snapshot.id)
        }
    }

    func create(at url: URL, schema: CollectionSchema, options: CollectionOptions = .init()) async {
        await perform("Create Collection", path: url.path) {
            let snapshot = try await service.create(at: url, schema: schema, options: options)
            opened.removeAll { $0.id == snapshot.id }
            opened.append(snapshot)
            recents = await service.recentCollections()
            destination = .collection(snapshot.id)
            uiState.select(snapshot.id)
            documents = []
            editingDocument = nil
            uiState.setBrowseLimitReached(false)
        }
    }

    func close(_ id: CollectionID) async {
        await perform("Close Collection", path: id.rawValue) {
            try await service.close(id)
            opened.removeAll { $0.id == id }
            documents = []
            editingDocument = nil
            destination = .dashboard
            uiState.select(nil)
        }
    }

    func restartRuntime(profile: RuntimeConfigurationProfile) async {
        await perform("Restart Runtime") {
            try await service.restartRuntime(configuration: profile.configuration)
            try runtimeConfigurationStore.save(profile)
            runtimeProfile = profile
            opened = []
            documents = []
            queryDocuments = []
            groupResults = []
            editingDocument = nil
            destination = .dashboard
            uiState.select(nil)
            runtimeReady = true
            runtimeNeedsRestart = false
        }
    }

    func markRuntimeNeedsRestart() { runtimeNeedsRestart = runtimeReady }

    func destroy(_ id: CollectionID, confirmationName: String) async {
        await perform("Destroy Collection", path: id.rawValue) {
            try await service.destroy(id, confirmationName: confirmationName)
            opened.removeAll { $0.id == id }
            recents = await service.recentCollections()
            documents = []
            queryDocuments = []
            groupResults = []
            editingDocument = nil
            destination = .dashboard
            uiState.select(nil)
        }
    }

    func shutdownForTermination() async {
        do { try await service.shutdown() } catch {
            self.error = StudioErrorPresentation(operation: "Shutdown", underlying: error)
        }
        runtimeReady = false
    }

    func shutdownRuntime() async {
        await perform("Shutdown Runtime") {
            try await service.shutdown()
            opened = []
            documents = []
            queryDocuments = []
            groupResults = []
            editingDocument = nil
            destination = .dashboard
            uiState.select(nil)
            runtimeReady = false
        }
    }

    func browse(
        _ id: CollectionID,
        filter: String? = nil,
        limit: Int = 100,
        outputFields: [String] = [],
        includeVector: Bool = false
    ) async {
        await perform("Browse", path: id.rawValue) {
            let result = try await service.browse(
                id,
                query: BrowseQuery(
                    filter: filter?.nilIfBlank,
                    limit: limit,
                    outputFields: outputFields,
                    includeVector: includeVector
                )
            )
            documents = result.documents
            uiState.setBrowseLimitReached(result.limitReached)
        }
    }

    func fetch(
        _ id: CollectionID,
        documentIDs: [String],
        outputFields: [String],
        includeVector: Bool
    ) async {
        await perform("Fetch", path: id.rawValue) {
            let results = try await service.fetch(
                id, ids: documentIDs, outputFields: outputFields, includeVector: includeVector
            )
            documents = results.compactMap(\.document)
            let missing = results.lazy.filter { $0.document == nil }.count
            operationMessage = "Fetched \(documents.count); \(missing) IDs not found"
            uiState.setBrowseLimitReached(false)
        }
    }

    func deleteDocument(_ id: CollectionID, documentID: String) async {
        await perform("Delete Document", path: id.rawValue) {
            let result = try await service.delete(id, documentID: documentID)
            operationMessage =
                result.succeeded
                ? "Deleted \(documentID)" : "Delete failed: \(result.error?.description ?? "unknown error")"
            await browse(id)
        }
    }

    func deleteWhere(_ id: CollectionID, filter: String) async {
        await perform("Filter Delete", path: id.rawValue) {
            try await service.delete(id, where: filter)
            operationMessage = "Filter delete completed"
            await browse(id)
        }
    }

    func flush(_ id: CollectionID) async {
        await perform("Flush", path: id.rawValue) { try await service.flush(id) }
    }

    func optimize(_ id: CollectionID) async {
        await perform("Optimize", path: id.rawValue) { try await service.optimize(id) }
    }

    func write(_ id: CollectionID, documents newDocuments: [Document], mode: WriteMode) async {
        await perform(mode.rawValue.capitalized, path: id.rawValue) {
            let results = try await service.write(id, documents: newDocuments, mode: mode)
            let succeeded = results.lazy.filter(\.succeeded).count
            operationMessage = "\(succeeded) succeeded, \(results.count - succeeded) failed"
            await browse(id)
        }
    }

    func importDocuments(_ id: CollectionID, preview: ImportPreview, mode: WriteMode) async {
        await perform("Import", path: id.rawValue) {
            importProgress = ImportProgress(failed: preview.issues.count, unprocessed: preview.documents.count)
            let result = try await service.importDocuments(
                id, documents: preview.documents, mode: mode
            ) { progress in
                await MainActor.run {
                    self.importProgress = ImportProgress(
                        succeeded: progress.succeeded,
                        failed: progress.failed + preview.issues.count,
                        unprocessed: progress.unprocessed
                    )
                }
            }
            let totalFailed = result.failed + preview.issues.count
            importProgress = ImportProgress(
                succeeded: result.succeeded, failed: totalFailed, unprocessed: result.unprocessed
            )
            let wasCancelled = result.unprocessed > 0 && Task.isCancelled
            operationMessage =
                "Import \(wasCancelled ? "cancelled" : "complete"): \(result.succeeded) succeeded, \(totalFailed) failed, \(result.unprocessed) unprocessed"
            await browse(id)
            if wasCancelled { throw CancellationError() }
        }
    }

    func runQuery(_ id: CollectionID, query: VectorQuery) async {
        await perform("Vector Query", path: id.rawValue) {
            queryDocuments = try await service.query(id, query)
            groupResults = []
        }
    }

    func runQuery(_ id: CollectionID, query: FullTextQuery) async {
        await perform("Full Text Query", path: id.rawValue) {
            queryDocuments = try await service.query(id, query)
            groupResults = []
        }
    }

    func runQuery(_ id: CollectionID, query: MultiQuery) async {
        await perform("Multi Query", path: id.rawValue) {
            queryDocuments = try await service.query(id, query)
            groupResults = []
        }
    }

    func runQuery(_ id: CollectionID, query: GroupByVectorQuery) async {
        await perform("Group By Query", path: id.rawValue) {
            groupResults = try await service.query(id, query)
            queryDocuments = []
        }
    }

    func addColumn(_ id: CollectionID, field: FieldSchema, defaultExpression: String?) async {
        await perform("Add Column", path: id.rawValue) {
            try await service.addColumn(id, field: field, defaultExpression: defaultExpression?.nilIfBlank)
            try await refresh(id)
        }
    }

    func alterColumn(_ id: CollectionID, name: String, newName: String?, schema: FieldSchema?) async {
        await perform("Alter Column", path: id.rawValue) {
            try await service.alterColumn(id, name: name, newName: newName?.nilIfBlank, schema: schema)
            try await refresh(id)
        }
    }

    func dropColumn(_ id: CollectionID, name: String) async {
        await perform("Drop Column", path: id.rawValue) {
            try await service.dropColumn(id, name: name)
            try await refresh(id)
        }
    }

    func createIndex(_ id: CollectionID, field: String, index: IndexConfiguration) async {
        await perform("Create Index", path: id.rawValue) {
            try await service.createIndex(id, field: field, index: index)
            try await refresh(id)
        }
    }

    func dropIndex(_ id: CollectionID, field: String) async {
        await perform("Drop Index", path: id.rawValue) {
            try await service.dropIndex(id, field: field)
            try await refresh(id)
        }
    }

    private func refresh(_ id: CollectionID) async throws {
        let snapshot = try await service.snapshot(for: id)
        opened.removeAll { $0.id == id }
        opened.append(snapshot)
    }

    private func perform(
        _ operation: String,
        path: String? = nil,
        action: () async throws -> Void
    ) async {
        error = nil
        uiState.begin(operation)
        do {
            try await action()
            uiState.complete(operation)
        } catch is CancellationError {
            uiState.cancel(operation)
        } catch {
            uiState.fail(operation, error: error)
            self.error = StudioErrorPresentation(operation: operation, collectionPath: path, underlying: error)
        }
    }
}

private extension String {
    var nilIfBlank: String? { trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self }
}
