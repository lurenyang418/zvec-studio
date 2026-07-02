import Foundation
import Zvec

public struct DocumentDraft: Sendable, Equatable {
    public var id: String
    public var fields: [FieldDraft]

    public init(id: String = "", schema: CollectionSchema) {
        self.id = id
        fields = schema.fields.map { FieldDraft(name: $0.name) }
    }

    public init(document: Document, schema: CollectionSchema) throws {
        id = document.id
        fields = try schema.fields.map { field in
            guard let value = document.fields[field.name] else { return FieldDraft(name: field.name) }
            if value == .null { return FieldDraft(name: field.name, presence: .null) }
            let object = try CanonicalJSON.encodeValue(value)
            let data = try JSONSerialization.data(withJSONObject: object, options: [.fragmentsAllowed, .sortedKeys])
            return FieldDraft(
                name: field.name,
                presence: .value,
                jsonValue: String(decoding: data, as: UTF8.self)
            )
        }
    }

    public func document(schema: CollectionSchema, intent: DocumentWriteIntent) throws -> Document {
        var values: [String: ZvecValue] = [:]
        for fieldDraft in fields {
            guard let schemaField = schema.field(named: fieldDraft.name) else { continue }
            switch fieldDraft.presence {
            case .missing: continue
            case .null: values[fieldDraft.name] = .null
            case .value:
                let object = try JSONSerialization.jsonObject(
                    with: Data(fieldDraft.jsonValue.utf8), options: [.fragmentsAllowed]
                )
                values[fieldDraft.name] = try CanonicalJSON.decodeValue(object, field: schemaField)
            }
        }
        let document = Document(id: id, fields: values)
        try schema.validate(document, for: intent)
        return document
    }

    public func canonicalJSON(schema: CollectionSchema, intent: DocumentWriteIntent) throws -> String {
        let data = try CanonicalJSON.encode(documents: [document(schema: schema, intent: intent)])
        return String(decoding: data, as: UTF8.self)
    }

    public mutating func synchronize(fromCanonicalJSON text: String, schema: CollectionSchema) throws {
        let documents = try CanonicalJSON.decode(Data(text.utf8), schema: schema)
        guard documents.count == 1 else { throw DocumentDraftError.requiresOneDocument }
        self = try DocumentDraft(document: documents[0], schema: schema)
    }
}

public struct FieldDraft: Sendable, Equatable, Identifiable {
    public var id: String { name }
    public let name: String
    public var presence: FieldPresence
    public var jsonValue: String

    public init(name: String, presence: FieldPresence = .missing, jsonValue: String = "") {
        self.name = name
        self.presence = presence
        self.jsonValue = jsonValue
    }
}

public enum FieldPresence: String, CaseIterable, Sendable {
    case missing
    case null
    case value
}

public enum DocumentDraftError: Error, Equatable, CustomStringConvertible {
    case requiresOneDocument

    public var description: String { "Raw JSON must contain exactly one document" }
}
