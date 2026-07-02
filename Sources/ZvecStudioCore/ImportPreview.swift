import Foundation
import Zvec

public struct ImportValidationIssue: Sendable, Equatable, Identifiable {
    public let row: Int
    public let message: String
    public var id: String { "\(row):\(message)" }

    public init(row: Int, message: String) {
        self.row = row
        self.message = message
    }
}

public struct ImportPreview: Sendable, Equatable {
    public let documents: [Document]
    public let sample: [Document]
    public let issues: [ImportValidationIssue]
    public let totalRows: Int

    public init(
        documents: [Document],
        issues: [ImportValidationIssue],
        totalRows: Int,
        sampleLimit: Int = 20
    ) {
        self.documents = documents
        sample = Array(documents.prefix(sampleLimit))
        self.issues = issues
        self.totalRows = totalRows
    }

    public static func json(
        _ data: Data,
        schema: CollectionSchema,
        intent: DocumentWriteIntent
    ) throws -> ImportPreview {
        guard let rows = try JSONSerialization.jsonObject(with: data) as? [Any] else {
            throw CanonicalJSONError.invalidRoot
        }
        var documents: [Document] = []
        var issues: [ImportValidationIssue] = []
        for (index, row) in rows.enumerated() {
            do {
                let one = try JSONSerialization.data(withJSONObject: [row])
                let document = try CanonicalJSON.decode(one, schema: schema)[0]
                try schema.validate(document, for: intent)
                documents.append(document)
            } catch {
                issues.append(.init(row: index + 1, message: String(describing: error)))
            }
        }
        return ImportPreview(documents: documents, issues: issues, totalRows: rows.count)
    }

    public static func csv(
        _ data: Data,
        schema: CollectionSchema,
        intent: DocumentWriteIntent
    ) throws -> ImportPreview {
        let rows = try CSVCodec.parsedRows(data)
        let header = try CSVCodec.validatedHeader(rows, schema: schema)
        var valid: [Document] = []
        var issues: [ImportValidationIssue] = []
        for (index, row) in rows.dropFirst().enumerated() {
            do {
                guard
                    let document = try CSVCodec.decodeRow(
                        row, header: header, schema: schema, rowNumber: index + 2
                    )
                else { continue }
                try schema.validate(document, for: intent)
                valid.append(document)
            } catch {
                issues.append(.init(row: index + 2, message: String(describing: error)))
            }
        }
        return ImportPreview(documents: valid, issues: issues, totalRows: max(0, rows.count - 1))
    }
}
