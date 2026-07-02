import AppKit
import Foundation
import Zvec
import ZvecStudioCore

@MainActor
enum ResultFileSaver {
    enum Format { case json, csv }

    static func saveDocuments(
        _ documents: [Document],
        schema: CollectionSchema,
        format: Format,
        source: String,
        limitReached: Bool
    ) throws {
        let data: Data
        let fileName: String
        switch format {
        case .json:
            data = try CanonicalJSON.encode(documents: documents)
            fileName = "zvec-\(source)-results.json"
        case .csv:
            data = try CSVCodec.encode(documents: documents, schema: schema)
            fileName = "zvec-\(source)-results.csv"
        }
        try save(
            data,
            suggestedName: fileName,
            metadata: ResultExportMetadata(
                source: source, documentCount: documents.count, limitReached: limitReached
            )
        )
    }

    static func saveGroups(
        _ groups: [GroupResult],
        schema: CollectionSchema,
        format: Format
    ) throws {
        let data: Data
        let fileName: String
        switch format {
        case .json:
            data = try CanonicalJSON.encode(groups: groups)
            fileName = "zvec-group-results.json"
        case .csv:
            data = try CSVCodec.encode(groups: groups, schema: schema)
            fileName = "zvec-group-results.csv"
        }
        try save(
            data,
            suggestedName: fileName,
            metadata: ResultExportMetadata(
                source: "groupBy",
                documentCount: groups.reduce(0) { $0 + $1.documents.count },
                limitReached: false
            )
        )
    }

    private static func save(
        _ data: Data,
        suggestedName: String,
        metadata: ResultExportMetadata
    ) throws {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedName
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try data.write(to: url, options: .atomic)
        let metadataURL = url.deletingPathExtension().appendingPathExtension("metadata.json")
        try metadata.encoded().write(to: metadataURL, options: .atomic)
    }
}
