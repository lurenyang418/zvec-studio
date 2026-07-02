import Foundation
import XCTest
import Zvec
@testable import ZvecStudioCore

final class CanonicalJSONTests: XCTestCase {
    func testRoundTripAllValueFamilies() throws {
        let schema = try makeSchema()
        let values: [String: ZvecValue] = [
            "binary": .binary(Data([0, 1, 255])),
            "string": .string("你好, \"Zvec\""),
            "bool": .bool(true),
            "int32": .int32(.min),
            "int64": .int64(.min),
            "uint32": .uint32(.max),
            "uint64": .uint64(.max),
            "float": .float(.infinity),
            "double": .double(.nan),
            "vector": .vectorFloat32([1, -.infinity, 3]),
            "vectorBinary32": .vectorBinary32(Data([0xA5])),
            "vectorBinary64": .vectorBinary64(Data([0x5A, 0xC3])),
            "vectorFloat16": .vectorFloat16([1, 2]),
            "vectorFloat64": .vectorFloat64([1, 2]),
            "int4": .vectorInt4(try PackedInt4Vector(bytes: Data([0x12, 0x30]), dimensions: 3)),
            "vectorInt8": .vectorInt8([-1, 2]),
            "vectorInt16": .vectorInt16([-1, 2]),
            "sparse16": .sparseVectorFloat16(try SparseVector(indices: [2, 8], values: [0.5, 1.5])),
            "sparse": .sparseVectorFloat32(try SparseVector(indices: [1, 9], values: [0.5, 2])),
            "strings": .arrayString(["a", "b"]),
            "bools": .arrayBool([true, false]),
            "int32s": .arrayInt32([.min, .max]),
            "int64s": .arrayInt64([.min, .max]),
            "uint32s": .arrayUInt32([.min, .max]),
            "uint64s": .arrayUInt64([.min, .max]),
            "floats": .arrayFloat([1, .infinity]),
            "doubles": .arrayDouble([1, -.infinity]),
            "binaries": .arrayBinary([Data([1]), Data([2, 3])]),
        ]
        let document = Document(id: "doc-1", fields: values)
        let encoded = try CanonicalJSON.encode(documents: [document])
        let decoded = try CanonicalJSON.decode(encoded, schema: schema)
        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded[0].id, document.id)
        for (key, value) in values where key != "double" {
            XCTAssertEqual(decoded[0].fields[key], value)
        }
        guard case .double(let nan)? = decoded[0].fields["double"] else { return XCTFail("missing double") }
        XCTAssertTrue(nan.isNaN)
    }

    func testMissingAndNullRemainDistinct() throws {
        let schema = try CollectionSchema(
            name: "nulls",
            fields: [
                FieldSchema("value", type: .string, nullable: true)
            ])
        let data = Data(#"[{"id":"a","fields":{}},{"id":"b","fields":{"value":null}}]"#.utf8)
        let documents = try CanonicalJSON.decode(data, schema: schema)
        XCTAssertNil(documents[0].fields["value"])
        XCTAssertEqual(documents[1].fields["value"], .null)
    }

    func testCSVHandlesRFC4180AndMissingFields() throws {
        let schema = try CollectionSchema(
            name: "csv",
            fields: [
                FieldSchema("text", type: .string), FieldSchema("optional", type: .string, nullable: true),
            ])
        let original = [Document(id: "id,\"1", fields: ["text": .string("line 1\nline 2")])]
        let data = try CSVCodec.encode(documents: original, schema: schema)
        let decoded = try CSVCodec.decode(data, schema: schema)
        XCTAssertEqual(decoded, original)
        XCTAssertNil(decoded[0].fields["optional"])
    }

    func testGroupExportsPreserveGroupMetadata() throws {
        let schema = try CollectionSchema(name: "groups", fields: [FieldSchema("name", type: .string)])
        let groups = [
            GroupResult(
                value: "team-a",
                documents: [
                    Document(id: "one", fields: ["name": .string("Alice")], score: 0.9)
                ])
        ]
        let json = try JSONSerialization.jsonObject(with: CanonicalJSON.encode(groups: groups)) as? [[String: Any]]
        let groupValue = json?.first?["_group"] as? String
        XCTAssertEqual(groupValue, "team-a")
        let csv = String(decoding: try CSVCodec.encode(groups: groups, schema: schema), as: UTF8.self)
        XCTAssertTrue(csv.contains("_group"))
        XCTAssertTrue(csv.contains("team-a"))
    }

    func testExportMetadataNeverClaimsCompleteBackup() throws {
        let metadata = ResultExportMetadata(
            source: "browse", documentCount: 100, limitReached: true,
            generatedAt: Date(timeIntervalSince1970: 0)
        )
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(ResultExportMetadata.self, from: metadata.encoded())
        XCTAssertTrue(decoded.limitReached)
        XCTAssertFalse(decoded.completeCollectionBackup)
    }

    private func makeSchema() throws -> CollectionSchema {
        try CollectionSchema(
            name: "all",
            fields: [
                FieldSchema("binary", type: .binary), FieldSchema("string", type: .string),
                FieldSchema("bool", type: .bool), FieldSchema("int32", type: .int32),
                FieldSchema("int64", type: .int64), FieldSchema("uint32", type: .uint32),
                FieldSchema("uint64", type: .uint64), FieldSchema("float", type: .float),
                FieldSchema("double", type: .double),
                FieldSchema("vector", type: .vectorFloat32, dimensions: 3),
                FieldSchema("vectorBinary32", type: .vectorBinary32, dimensions: 8),
                FieldSchema("vectorBinary64", type: .vectorBinary64, dimensions: 16),
                FieldSchema("vectorFloat16", type: .vectorFloat16, dimensions: 2),
                FieldSchema("vectorFloat64", type: .vectorFloat64, dimensions: 2),
                FieldSchema("int4", type: .vectorInt4, dimensions: 3),
                FieldSchema("vectorInt8", type: .vectorInt8, dimensions: 2),
                FieldSchema("vectorInt16", type: .vectorInt16, dimensions: 2),
                FieldSchema("sparse16", type: .sparseVectorFloat16),
                FieldSchema("sparse", type: .sparseVectorFloat32),
                FieldSchema("strings", type: .arrayString), FieldSchema("bools", type: .arrayBool),
                FieldSchema("int32s", type: .arrayInt32), FieldSchema("int64s", type: .arrayInt64),
                FieldSchema("uint32s", type: .arrayUInt32), FieldSchema("uint64s", type: .arrayUInt64),
                FieldSchema("floats", type: .arrayFloat), FieldSchema("doubles", type: .arrayDouble),
                FieldSchema("binaries", type: .arrayBinary),
            ])
    }
}
