import Foundation
import Zvec
import ZvecStudioCore

enum DocumentDisplay {
    static func compactFields(_ document: Document) -> String {
        do {
            let object = try document.fields.mapValues(CanonicalJSON.encodeValue)
            let data = try JSONSerialization.data(
                withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes]
            )
            return String(decoding: data, as: UTF8.self)
        } catch {
            return document.fields.keys.sorted().joined(separator: ", ")
        }
    }
}
