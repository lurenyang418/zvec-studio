import Foundation
import XCTest
import Zvec
@testable import ZvecStudioCore

final class StudioServiceIntegrationTests: XCTestCase {
    func testCreateWriteBrowseFetchCloseAndDestroy() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "zvec-studio-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        let collectionURL = root.appending(path: "people", directoryHint: .isDirectory)
        let recentURL = root.appending(path: "recents.json")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let schema = try CollectionSchema(
            name: "people",
            fields: [
                FieldSchema("name", type: .string, index: .fullText(tokenizer: .standard)),
                FieldSchema("age", type: .int32, index: .inverted()),
                FieldSchema("embedding", type: .vectorFloat32, dimensions: 3, index: .flat()),
            ])
        let service = StudioService(recentStore: RecentCollectionStore(fileURL: recentURL))
        try await service.initialize()
        let created = try await service.create(at: collectionURL, schema: schema)
        XCTAssertEqual(created.schema.name, "people")
        _ = try await service.open(
            at: collectionURL.appending(path: "..", directoryHint: .isDirectory)
                .appending(path: "people", directoryHint: .isDirectory))
        let openIDs = await service.openCollectionIDs()
        XCTAssertEqual(openIDs, [created.id])

        try await service.addColumn(
            created.id,
            field: FieldSchema("city", type: .int32, nullable: true)
        )
        var ddlSnapshot = try await service.snapshot(for: created.id)
        XCTAssertNotNil(ddlSnapshot.schema.field(named: "city"))
        try await service.createIndex(created.id, field: "city", index: .inverted())
        ddlSnapshot = try await service.snapshot(for: created.id)
        XCTAssertNotNil(ddlSnapshot.schema.field(named: "city")?.index)
        try await service.dropIndex(created.id, field: "city")
        try await service.alterColumn(created.id, name: "city", newName: "location")
        ddlSnapshot = try await service.snapshot(for: created.id)
        XCTAssertNil(ddlSnapshot.schema.field(named: "city"))
        XCTAssertNotNil(ddlSnapshot.schema.field(named: "location"))
        try await service.dropColumn(created.id, name: "location")

        let documents = [
            Document(
                id: "alice",
                fields: [
                    "name": .string("Alice"), "age": .int32(30), "embedding": .vectorFloat32([1, 0, 0]),
                ]),
            Document(
                id: "bob",
                fields: [
                    "name": .string("Bob"), "age": .int32(40), "embedding": .vectorFloat32([0, 1, 0]),
                ]),
        ]
        let writes = try await service.write(created.id, documents: documents, mode: .insert)
        XCTAssertTrue(writes.allSatisfy(\.succeeded))

        let partial = try await service.importDocuments(
            created.id,
            documents: [
                documents[0],
                Document(
                    id: "charlie",
                    fields: [
                        "name": .string("Charlie"), "age": .int32(25), "embedding": .vectorFloat32([0, 0, 1]),
                    ]),
            ],
            mode: .insert,
            batchSize: 1
        )
        XCTAssertEqual(partial.succeeded, 1)
        XCTAssertEqual(partial.failed, 1)
        XCTAssertEqual(partial.unprocessed, 0)

        let updated = try await service.write(
            created.id,
            documents: [Document(id: "alice", fields: ["age": .int32(31)])],
            mode: .update
        )
        XCTAssertTrue(updated[0].succeeded)
        let upserted = try await service.write(
            created.id,
            documents: [
                Document(
                    id: "dave",
                    fields: [
                        "name": .string("Dave"), "age": .int32(40), "embedding": .vectorFloat32([0, 1, 1]),
                    ])
            ],
            mode: .upsert
        )
        XCTAssertTrue(upserted[0].succeeded)
        let deleted = try await service.delete(created.id, documentID: "bob")
        XCTAssertTrue(deleted.succeeded)

        let browse = try await service.browse(created.id, query: BrowseQuery(limit: 1))
        XCTAssertEqual(browse.documents.count, 1)
        XCTAssertTrue(browse.limitReached)

        let fetched = try await service.fetch(created.id, ids: ["alice", "missing"])
        XCTAssertEqual(fetched.count, 2)
        XCTAssertEqual(fetched[0].document?.id, "alice")
        XCTAssertNil(fetched[1].document)

        let query = VectorQuery(field: "embedding", documentID: "alice", topK: 2)
        let queried = try await service.query(created.id, query)
        XCTAssertFalse(queried.isEmpty)

        let fullText = try await service.query(
            created.id,
            FullTextQuery(field: "name", expression: .match("Alice"), topK: 3)
        )
        XCTAssertEqual(fullText.first?.id, "alice")

        let multi = try await service.query(
            created.id,
            MultiQuery(
                queries: [
                    SubQuery(
                        field: "embedding", payload: .dense(.float32([1, 0, 0])), topK: 3,
                        indexParameters: .flat(.init())
                    ),
                    SubQuery(field: "name", payload: .fullText(.match("Alice")), topK: 3),
                ],
                topK: 3
            )
        )
        XCTAssertFalse(multi.isEmpty)

        let grouped = try await service.query(
            created.id,
            GroupByVectorQuery(
                vectorQuery: VectorQuery(field: "embedding", vector: .float32([1, 0, 0]), topK: 3),
                groupByField: "age",
                groupCount: 3,
                groupTopK: 1
            )
        )
        XCTAssertFalse(grouped.isEmpty)
        XCTAssertTrue(grouped.allSatisfy { $0.documents.count <= 1 })

        let snapshot = try await service.snapshot(for: created.id)
        XCTAssertEqual(snapshot.statistics.documentCount, 3)
        let recents = await service.recentCollections()
        XCTAssertEqual(recents.first?.id, created.id)
        XCTAssertEqual(recents.count, 1)

        try await service.delete(created.id, where: "age = 25")
        let afterFilterDelete = try await service.browse(created.id, query: BrowseQuery(filter: "age = 25"))
        XCTAssertTrue(afterFilterDelete.documents.isEmpty)

        try await service.destroy(created.id, confirmationName: "people")
        XCTAssertFalse(FileManager.default.fileExists(atPath: collectionURL.path))
        try await service.shutdown()
    }

    func testRestartClosesAllCollectionsWithoutReopeningThem() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "zvec-studio-restart-\(UUID().uuidString)", directoryHint: .isDirectory)
        let recentURL = root.appending(path: "recents.json")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let schema = try CollectionSchema(
            name: "restart",
            fields: [
                FieldSchema("value", type: .string)
            ])
        let service = StudioService(recentStore: RecentCollectionStore(fileURL: recentURL))
        try await service.initialize()
        let created = try await service.create(at: root.appending(path: "restart"), schema: schema)
        try await service.restartRuntime(configuration: Configuration(queryThreadCount: 1))
        let openIDs = await service.openCollectionIDs()
        let recents = await service.recentCollections()
        XCTAssertTrue(openIDs.isEmpty)
        XCTAssertEqual(recents.first?.id, created.id)

        _ = try await service.open(at: created.id.url)
        try await service.destroy(created.id, confirmationName: "restart")
        try await service.shutdown()
    }

    func testImportCancellationStopsAtBatchBoundaryAndReportsUnprocessed() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "zvec-studio-cancel-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let schema = try CollectionSchema(name: "cancel", fields: [FieldSchema("value", type: .int32)])
        let service = StudioService(
            recentStore: RecentCollectionStore(fileURL: root.appending(path: "recents.json"))
        )
        try await service.initialize()
        let collection = try await service.create(at: root.appending(path: "cancel"), schema: schema)
        let documents = (0..<3).map { Document(id: "\($0)", fields: ["value": .int32(Int32($0))]) }

        let task = Task {
            try await service.importDocuments(
                collection.id, documents: documents, mode: .insert, batchSize: 1
            ) { progress in
                if progress.succeeded == 1 {
                    withUnsafeCurrentTask { $0?.cancel() }
                }
            }
        }
        let result = try await task.value
        XCTAssertEqual(result, ImportProgress(succeeded: 1, failed: 0, unprocessed: 2))
        try await service.destroy(collection.id, confirmationName: "cancel")
        try await service.shutdown()
    }
}
