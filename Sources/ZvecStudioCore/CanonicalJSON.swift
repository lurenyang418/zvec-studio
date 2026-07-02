import Foundation
import Zvec

public enum CanonicalJSONError: Error, Equatable, CustomStringConvertible {
    case invalidRoot
    case invalidDocument(Int, String)
    case invalidField(String, String)

    public var description: String {
        switch self {
        case .invalidRoot: "The JSON root must be an array of documents"
        case let .invalidDocument(index, reason): "Document \(index): \(reason)"
        case let .invalidField(field, reason): "Field '\(field)': \(reason)"
        }
    }
}

public enum CanonicalJSON {
    public static func encode(documents: [Document], prettyPrinted: Bool = true) throws -> Data {
        let objects = try documents.map(encodeDocument)
        var options: JSONSerialization.WritingOptions = [.sortedKeys]
        if prettyPrinted { options.insert(.prettyPrinted) }
        return try JSONSerialization.data(withJSONObject: objects, options: options)
    }

    public static func encode(groups: [GroupResult], prettyPrinted: Bool = true) throws -> Data {
        let objects = try groups.flatMap { group in
            try group.documents.map { document in
                var object = try encodeDocument(document)
                object["_group"] = group.value
                return object
            }
        }
        var options: JSONSerialization.WritingOptions = [.sortedKeys]
        if prettyPrinted { options.insert(.prettyPrinted) }
        return try JSONSerialization.data(withJSONObject: objects, options: options)
    }

    public static func decode(_ data: Data, schema: CollectionSchema) throws -> [Document] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [Any] else {
            throw CanonicalJSONError.invalidRoot
        }
        return try root.enumerated().map { index, item in
            guard let object = item as? [String: Any],
                let id = object["id"] as? String,
                let fields = object["fields"] as? [String: Any]
            else {
                throw CanonicalJSONError.invalidDocument(index, "requires string id and object fields")
            }
            var values: [String: ZvecValue] = [:]
            for (name, json) in fields {
                guard let field = schema.field(named: name) else {
                    throw CanonicalJSONError.invalidField(name, "unknown field")
                }
                values[name] = try decodeValue(json, field: field)
            }
            return Document(id: id, fields: values)
        }
    }

    public static func encodeValue(_ value: ZvecValue) throws -> Any {
        switch value {
        case .null: NSNull()
        case let .binary(v), let .vectorBinary32(v), let .vectorBinary64(v): v.base64EncodedString()
        case let .string(v): v
        case let .bool(v): v
        case let .int32(v): Int(v)
        case let .int64(v): String(v)
        case let .uint32(v): UInt(v)
        case let .uint64(v): String(v)
        case let .float(v): encodeFloat(v)
        case let .double(v): encodeFloat(v)
        case let .vectorFloat16(v): v.map { encodeFloat($0) }
        case let .vectorFloat32(v): v.map { encodeFloat($0) }
        case let .vectorFloat64(v): v.map { encodeFloat($0) }
        case let .vectorInt4(v): ["bytesBase64": v.bytes.base64EncodedString(), "dimensions": v.dimensions]
        case let .vectorInt8(v): v.map(Int.init)
        case let .vectorInt16(v): v.map(Int.init)
        case let .sparseVectorFloat16(v): ["indices": v.indices, "values": v.values.map { encodeFloat($0) }]
        case let .sparseVectorFloat32(v): ["indices": v.indices, "values": v.values.map { encodeFloat($0) }]
        case let .arrayBinary(v): v.map { $0.base64EncodedString() }
        case let .arrayString(v): v
        case let .arrayBool(v): v
        case let .arrayInt32(v): v.map(Int.init)
        case let .arrayInt64(v): v.map(String.init)
        case let .arrayUInt32(v): v.map(UInt.init)
        case let .arrayUInt64(v): v.map(String.init)
        case let .arrayFloat(v): v.map { encodeFloat($0) }
        case let .arrayDouble(v): v.map { encodeFloat($0) }
        }
    }

    public static func decodeValue(_ json: Any, field: FieldSchema) throws -> ZvecValue {
        if json is NSNull { return .null }
        do {
            switch field.dataType {
            case .undefined: throw CanonicalJSONError.invalidField(field.name, "undefined is unsupported")
            case .binary: return .binary(try data(json))
            case .string: return .string(try cast(json))
            case .bool: return .bool(try bool(json))
            case .int32: return .int32(try integer(json))
            case .int64: return .int64(try integerString(json))
            case .uint32: return .uint32(try integer(json))
            case .uint64: return .uint64(try integerString(json))
            case .float: return .float(try floating(json))
            case .double: return .double(try floating(json))
            case .vectorBinary32: return .vectorBinary32(try data(json))
            case .vectorBinary64: return .vectorBinary64(try data(json))
            case .vectorFloat16: return .vectorFloat16(try array(json).map { try floating($0) })
            case .vectorFloat32: return .vectorFloat32(try array(json).map { try floating($0) })
            case .vectorFloat64: return .vectorFloat64(try array(json).map { try floating($0) })
            case .vectorInt4:
                let object: [String: Any] = try cast(json)
                return .vectorInt4(
                    try PackedInt4Vector(
                        bytes: try data(object["bytesBase64"] as Any),
                        dimensions: try integer(object["dimensions"] as Any)
                    ))
            case .vectorInt8: return .vectorInt8(try array(json).map { try integer($0) })
            case .vectorInt16: return .vectorInt16(try array(json).map { try integer($0) })
            case .sparseVectorFloat16:
                let pair = try sparse(json)
                return .sparseVectorFloat16(try SparseVector(indices: pair.0, values: pair.1.map(Float16.init)))
            case .sparseVectorFloat32:
                let pair = try sparse(json)
                return .sparseVectorFloat32(try SparseVector(indices: pair.0, values: pair.1))
            case .arrayBinary: return .arrayBinary(try array(json).map(data))
            case .arrayString: return .arrayString(try array(json).map { try cast($0) })
            case .arrayBool: return .arrayBool(try array(json).map(bool))
            case .arrayInt32: return .arrayInt32(try array(json).map { try integer($0) })
            case .arrayInt64: return .arrayInt64(try array(json).map { try integerString($0) })
            case .arrayUInt32: return .arrayUInt32(try array(json).map { try integer($0) })
            case .arrayUInt64: return .arrayUInt64(try array(json).map { try integerString($0) })
            case .arrayFloat: return .arrayFloat(try array(json).map(floating))
            case .arrayDouble: return .arrayDouble(try array(json).map(floating))
            }
        } catch let error as CanonicalJSONError { throw error } catch {
            throw CanonicalJSONError.invalidField(field.name, String(describing: error))
        }
    }

    static func encodeDocument(_ document: Document) throws -> [String: Any] {
        var object: [String: Any] = [
            "id": document.id,
            "fields": try document.fields.mapValues(encodeValue),
        ]
        if let score = document.score { object["score"] = encodeFloat(score) }
        if let documentID = document.documentID { object["documentID"] = String(documentID) }
        return object
    }

    private static func encodeFloat<T: BinaryFloatingPoint>(_ value: T) -> Any {
        if value.isNaN { return "NaN" }
        if value == .infinity { return "Infinity" }
        if value == -.infinity { return "-Infinity" }
        return Double(value)
    }

    private static func cast<T>(_ value: Any) throws -> T {
        guard let value = value as? T else { throw ValueError.type }
        return value
    }

    private static func array(_ value: Any) throws -> [Any] { try cast(value) }

    private static func bool(_ value: Any) throws -> Bool {
        guard let number = value as? NSNumber,
            String(cString: number.objCType) == "c"
        else { throw ValueError.type }
        return number.boolValue
    }

    private static func data(_ value: Any) throws -> Data {
        let string: String = try cast(value)
        guard let data = Data(base64Encoded: string) else { throw ValueError.base64 }
        return data
    }

    private static func integer<T: FixedWidthInteger>(_ value: Any) throws -> T {
        guard let number = value as? NSNumber, !isBoolean(number),
            let result = T(exactly: number.int64Value)
        else { throw ValueError.integer }
        return result
    }

    private static func integerString<T: FixedWidthInteger>(_ value: Any) throws -> T {
        guard let string = value as? String, let result = T(string) else { throw ValueError.integer }
        return result
    }

    private static func floating<T: BinaryFloatingPoint>(_ value: Any) throws -> T {
        if let string = value as? String {
            switch string {
            case "NaN": return .nan
            case "Infinity": return .infinity
            case "-Infinity": return -.infinity
            default: throw ValueError.float
            }
        }
        guard let number = value as? NSNumber, !isBoolean(number) else { throw ValueError.float }
        return T(number.doubleValue)
    }

    private static func isBoolean(_ number: NSNumber) -> Bool {
        String(cString: number.objCType) == "c"
    }

    private static func sparse(_ value: Any) throws -> ([UInt32], [Float]) {
        let object: [String: Any] = try cast(value)
        let indices = try array(object["indices"] as Any).map { try integer($0) as UInt32 }
        let values = try array(object["values"] as Any).map { try floating($0) as Float }
        return (indices, values)
    }

    private enum ValueError: Error { case type, base64, integer, float }
}
