import Foundation
import Zvec

public enum CSVCodecError: Error, Equatable, CustomStringConvertible {
    case malformed(String)
    case missingIDColumn
    case unknownColumn(String)

    public var description: String {
        switch self {
        case let .malformed(reason): "Malformed CSV: \(reason)"
        case .missingIDColumn: "The first CSV column must be id"
        case let .unknownColumn(column): "Unknown CSV column '\(column)'"
        }
    }
}

public enum CSVCodec {
    public static func encode(documents: [Document], schema: CollectionSchema) throws -> Data {
        try encode(records: documents.map { ($0, nil) }, schema: schema, includeGroup: false)
    }

    public static func encode(groups: [GroupResult], schema: CollectionSchema) throws -> Data {
        let records = groups.flatMap { group in group.documents.map { ($0, Optional(group.value)) } }
        return try encode(records: records, schema: schema, includeGroup: true)
    }

    private static func encode(
        records: [(Document, String?)],
        schema: CollectionSchema,
        includeGroup: Bool
    ) throws -> Data {
        var header = ["id"] + schema.fields.map(\.name) + ["_score", "_documentID"]
        if includeGroup { header.append("_group") }
        var rows = [header]
        for (document, group) in records {
            var row = [document.id]
            for field in schema.fields {
                if let value = document.fields[field.name] {
                    let data = try JSONSerialization.data(
                        withJSONObject: CanonicalJSON.encodeValue(value),
                        options: [.sortedKeys, .withoutEscapingSlashes, .fragmentsAllowed]
                    )
                    row.append(String(decoding: data, as: UTF8.self))
                } else {
                    row.append("")
                }
            }
            row.append(document.score.map { String($0) } ?? "")
            row.append(document.documentID.map { String($0) } ?? "")
            if includeGroup { row.append(group ?? "") }
            rows.append(row)
        }
        let text = rows.map { $0.map(escape).joined(separator: ",") }.joined(separator: "\r\n") + "\r\n"
        return Data(text.utf8)
    }

    public static func decode(_ data: Data, schema: CollectionSchema) throws -> [Document] {
        let rows = try parsedRows(data)
        let header = try validatedHeader(rows, schema: schema)
        return try rows.dropFirst().enumerated().compactMap { rowIndex, row in
            try decodeRow(row, header: header, schema: schema, rowNumber: rowIndex + 2)
        }
    }

    static func parsedRows(_ data: Data) throws -> [[String]] {
        guard let text = String(data: data, encoding: .utf8) else {
            throw CSVCodecError.malformed("input is not UTF-8")
        }
        return try parse(text)
    }

    static func validatedHeader(_ rows: [[String]], schema: CollectionSchema) throws -> [String] {
        guard let header = rows.first, header.first == "id" else { throw CSVCodecError.missingIDColumn }
        let names = Array(header.dropFirst())
        for name in names where !name.hasPrefix("_") && schema.field(named: name) == nil {
            throw CSVCodecError.unknownColumn(name)
        }
        return header
    }

    static func decodeRow(
        _ row: [String],
        header: [String],
        schema: CollectionSchema,
        rowNumber: Int
    ) throws -> Document? {
        if row.allSatisfy(\.isEmpty) { return nil }
        guard row.count <= header.count else {
            throw CSVCodecError.malformed("row \(rowNumber) has too many columns")
        }
        let names = Array(header.dropFirst())
        var fields: [String: ZvecValue] = [:]
        for (offset, name) in names.enumerated() where !name.hasPrefix("_") {
            let cell = offset + 1 < row.count ? row[offset + 1] : ""
            guard !cell.isEmpty else { continue }
            let value = try JSONSerialization.jsonObject(with: Data(cell.utf8), options: [.fragmentsAllowed])
            guard let field = schema.field(named: name) else { continue }
            fields[name] = try CanonicalJSON.decodeValue(value, field: field)
        }
        return Document(id: row[0], fields: fields)
    }

    private static func escape(_ field: String) -> String {
        guard field.contains(",") || field.contains("\"") || field.contains("\r") || field.contains("\n") else {
            return field
        }
        return "\"\(field.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    private static func parse(_ text: String) throws -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var quoted = false
        var index = text.startIndex

        while index < text.endIndex {
            let character = text[index]
            let next = text.index(after: index)
            if quoted {
                if character == "\"" {
                    if next < text.endIndex, text[next] == "\"" {
                        field.append("\"")
                        index = text.index(after: next)
                        continue
                    }
                    quoted = false
                } else {
                    field.append(character)
                }
            } else {
                switch character {
                case "\"":
                    guard field.isEmpty else { throw CSVCodecError.malformed("quote inside an unquoted field") }
                    quoted = true
                case ",":
                    row.append(field)
                    field = ""
                case "\r\n":
                    row.append(field)
                    rows.append(row)
                    row = []
                    field = ""
                case "\r":
                    if next < text.endIndex, text[next] == "\n" { index = next }
                    row.append(field)
                    rows.append(row)
                    row = []
                    field = ""
                case "\n":
                    row.append(field)
                    rows.append(row)
                    row = []
                    field = ""
                default: field.append(character)
                }
            }
            index = text.index(after: index)
        }
        guard !quoted else { throw CSVCodecError.malformed("unterminated quoted field") }
        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }
        return rows
    }
}
