import Foundation
import XCTest
import Zvec
@testable import ZvecStudioCore

final class DocumentDraftTests: XCTestCase {
    func testFormAndRawJSONSynchronizeWithoutCollapsingMissingAndNull() throws {
        let schema = try CollectionSchema(
            name: "draft",
            fields: [
                FieldSchema("title", type: .string),
                FieldSchema("note", type: .string, nullable: true),
                FieldSchema("embedding", type: .vectorFloat32, dimensions: 2),
            ])
        var draft = DocumentDraft(id: "one", schema: schema)
        draft.fields[0].presence = .value
        draft.fields[0].jsonValue = #""hello""#
        draft.fields[1].presence = .null
        draft.fields[2].presence = .value
        draft.fields[2].jsonValue = "[1,2]"

        let raw = try draft.canonicalJSON(schema: schema, intent: .insert)
        var synchronized = DocumentDraft(schema: schema)
        try synchronized.synchronize(fromCanonicalJSON: raw, schema: schema)
        XCTAssertEqual(synchronized.id, "one")
        XCTAssertEqual(synchronized.fields[1].presence, .null)

        let missingRaw = #"[{"id":"two","fields":{"title":"x","embedding":[0,1]}}]"#
        try synchronized.synchronize(fromCanonicalJSON: missingRaw, schema: schema)
        XCTAssertEqual(synchronized.fields[1].presence, .missing)
    }

    func testImportPreviewCollectsAllJSONRowErrors() throws {
        let schema = try CollectionSchema(
            name: "preview",
            fields: [
                FieldSchema("count", type: .int32)
            ])
        let data = Data(
            #"""
            [
              {"id":"ok","fields":{"count":1}},
              {"id":"bad-type","fields":{"count":"1"}},
              {"id":"bad-field","fields":{"other":1}}
            ]
            """#.utf8)
        let preview = try ImportPreview.json(data, schema: schema, intent: .insert)
        XCTAssertEqual(preview.totalRows, 3)
        XCTAssertEqual(preview.documents.map(\.id), ["ok"])
        XCTAssertEqual(preview.issues.count, 2)
    }

    func testImportPreviewCollectsAllCSVRowErrors() throws {
        let schema = try CollectionSchema(
            name: "preview",
            fields: [
                FieldSchema("count", type: .int32)
            ])
        let data = Data(
            #"""
            id,count
            ok,1
            bad-type,"""one"""
            bad-json,{

            """#.utf8)
        let preview = try ImportPreview.csv(data, schema: schema, intent: .insert)
        XCTAssertEqual(preview.totalRows, 3)
        XCTAssertEqual(preview.documents.map(\.id), ["ok"])
        XCTAssertEqual(preview.issues.map(\.row), [3, 4])
    }
}
