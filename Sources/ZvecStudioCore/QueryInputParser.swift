import Foundation
import Zvec

public enum QueryInputParser {
    public static func denseVector(_ text: String, field: FieldSchema) throws -> DenseQueryVector {
        guard field.dataType.isDenseVector else { throw QueryInputError.requiresDenseVectorField }
        let json = try JSONSerialization.jsonObject(with: Data(text.utf8), options: [.fragmentsAllowed])
        let vector: DenseQueryVector
        switch try CanonicalJSON.decodeValue(json, field: field) {
        case let .vectorBinary32(value), let .vectorBinary64(value): vector = .binary(value)
        case let .vectorFloat16(value): vector = .float16(value)
        case let .vectorFloat32(value): vector = .float32(value)
        case let .vectorFloat64(value): vector = .float64(value)
        case let .vectorInt4(value): vector = .int4(value)
        case let .vectorInt8(value): vector = .int8(value)
        case let .vectorInt16(value): vector = .int16(value)
        default: throw QueryInputError.requiresDenseVectorField
        }
        let actualDimensions: Int =
            switch vector {
            case let .binary(value): value.count * 8
            case let .float16(value): value.count
            case let .float32(value): value.count
            case let .float64(value): value.count
            case let .int4(value): value.dimensions
            case let .int8(value): value.count
            case let .int16(value): value.count
            }
        guard actualDimensions == field.dimensions else {
            throw QueryInputError.dimensionMismatch(expected: field.dimensions, actual: actualDimensions)
        }
        return vector
    }

    public static func sparseFloat32(_ text: String, field: FieldSchema) throws -> SparseVector<Float> {
        guard field.dataType == .sparseVectorFloat32 else { throw QueryInputError.requiresSparseFloat32Field }
        let json = try JSONSerialization.jsonObject(with: Data(text.utf8), options: [.fragmentsAllowed])
        guard case let .sparseVectorFloat32(value) = try CanonicalJSON.decodeValue(json, field: field) else {
            throw QueryInputError.requiresSparseFloat32Field
        }
        return value
    }
}

public enum QueryInputError: Error, Equatable, CustomStringConvertible {
    case requiresDenseVectorField
    case requiresSparseFloat32Field
    case dimensionMismatch(expected: Int, actual: Int)

    public var description: String {
        switch self {
        case .requiresDenseVectorField: "Document-ID and dense vector queries require a dense-vector field"
        case .requiresSparseFloat32Field: "Sparse query input requires a sparseVectorFloat32 field"
        case let .dimensionMismatch(expected, actual):
            "Query vector requires \(expected) dimensions, received \(actual)"
        }
    }
}
