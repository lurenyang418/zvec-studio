import Foundation
import SwiftUI
import Zvec

struct FieldValueEditor: View {
    @Binding var value: String
    let field: FieldSchema

    var body: some View {
        switch field.dataType {
        case .string:
            TextField("Text", text: stringBinding)
        case .bool:
            Toggle("Value", isOn: boolBinding)
        case .binary, .vectorBinary32, .vectorBinary64:
            TextField("Base64", text: stringBinding)
                .font(.system(.body, design: .monospaced))
        case .vectorInt4:
            Int4ValueEditor(json: $value, dimensions: field.dimensions)
        case .sparseVectorFloat16, .sparseVectorFloat32:
            SparseValueEditor(json: $value)
        case .arrayBinary, .arrayString, .arrayBool, .arrayInt32, .arrayInt64,
            .arrayUInt32, .arrayUInt64, .arrayFloat, .arrayDouble,
            .vectorFloat16, .vectorFloat32, .vectorFloat64, .vectorInt8, .vectorInt16:
            JSONListEditor(json: $value, dataType: field.dataType, expectedCount: field.dimensions)
        case .int32, .int64, .uint32, .uint64, .float, .double:
            TextField("Value", text: $value)
                .font(.system(.body, design: .monospaced))
        case .undefined:
            Text("Undefined is unsupported").foregroundStyle(.red)
        }
    }

    static func defaultJSON(for field: FieldSchema) -> String {
        switch field.dataType {
        case .string, .binary, .vectorBinary32, .vectorBinary64: #""""#
        case .bool: "false"
        case .int64, .uint64: #""0""#
        case .int32, .uint32, .float, .double: "0"
        case .vectorInt4: #"{"bytesBase64":"","dimensions":#(field.dimensions)}"#
        case .sparseVectorFloat16, .sparseVectorFloat32: #"{"indices":[],"values":[]}"#
        case .arrayBinary, .arrayString, .arrayBool, .arrayInt32, .arrayInt64,
            .arrayUInt32, .arrayUInt64, .arrayFloat, .arrayDouble,
            .vectorFloat16, .vectorFloat32, .vectorFloat64, .vectorInt8, .vectorInt16:
            "[]"
        case .undefined: ""
        }
    }

    private var stringBinding: Binding<String> {
        Binding(
            get: {
                guard let data = value.data(using: .utf8),
                    let decoded = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) as? String
                else { return "" }
                return decoded
            },
            set: { value = Self.quote($0) }
        )
    }

    private var boolBinding: Binding<Bool> {
        Binding(get: { value == "true" }, set: { value = $0 ? "true" : "false" })
    }

    fileprivate static func quote(_ string: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: string, options: [.fragmentsAllowed]) else {
            return #""""#
        }
        return String(decoding: data, as: UTF8.self)
    }
}

private struct JSONListEditor: View {
    @Binding var json: String
    let dataType: DataType
    let expectedCount: Int

    private var tokens: [String] {
        guard let data = json.data(using: .utf8),
            let values = try? JSONSerialization.jsonObject(with: data) as? [Any]
        else { return [] }
        return values.map(display)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(tokens.indices, id: \.self) { index in
                HStack {
                    Text("\(index)").foregroundStyle(.secondary).frame(width: 32, alignment: .trailing)
                    TextField("Value", text: tokenBinding(index))
                        .font(.system(.body, design: .monospaced))
                    Button(role: .destructive) {
                        remove(index)
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                }
            }
            HStack {
                Button("Add Element", systemImage: "plus") { append() }
                if expectedCount > 0 {
                    Text("\(tokens.count) / \(expectedCount) dimensions")
                        .font(.caption)
                        .foregroundStyle(tokens.count == expectedCount ? Color.secondary : Color.red)
                }
            }
        }
    }

    private func tokenBinding(_ index: Int) -> Binding<String> {
        Binding(
            get: { index < tokens.count ? tokens[index] : "" },
            set: { newValue in
                var updated = tokens
                guard index < updated.count else { return }
                updated[index] = newValue
                rebuild(updated)
            }
        )
    }

    private func append() {
        var updated = tokens
        updated.append(isStringElement ? "" : dataType == .arrayBool ? "false" : "0")
        rebuild(updated)
    }

    private func remove(_ index: Int) {
        var updated = tokens
        guard index < updated.count else { return }
        updated.remove(at: index)
        rebuild(updated)
    }

    private var isStringElement: Bool { dataType == .arrayString || dataType == .arrayBinary }

    private func rebuild(_ values: [String]) {
        let encoded = values.map { token -> String in
            if isStringElement { return FieldValueEditor.quote(token) }
            if dataType == .arrayInt64 || dataType == .arrayUInt64 { return FieldValueEditor.quote(token) }
            if [.arrayFloat, .arrayDouble, .vectorFloat16, .vectorFloat32, .vectorFloat64].contains(dataType),
                ["NaN", "Infinity", "-Infinity"].contains(token)
            {
                return FieldValueEditor.quote(token)
            }
            return token
        }
        json = "[\(encoded.joined(separator: ","))]"
    }

    private func display(_ value: Any) -> String {
        if let string = value as? String { return string }
        if let bool = value as? Bool { return bool ? "true" : "false" }
        return String(describing: value)
    }
}

private struct Int4ValueEditor: View {
    @Binding var json: String
    let dimensions: Int

    var body: some View {
        HStack {
            TextField("Packed bytes (Base64)", text: bytesBinding)
                .font(.system(.body, design: .monospaced))
            Text("\(dimensions) dimensions").foregroundStyle(.secondary)
        }
    }

    private var bytesBinding: Binding<String> {
        Binding(
            get: { object["bytesBase64"] as? String ?? "" },
            set: { bytes in
                json = #"{"bytesBase64":#(FieldValueEditor.quote(bytes)),"dimensions":#(dimensions)}"#
            })
    }

    private var object: [String: Any] {
        guard let data = json.data(using: .utf8) else { return [:] }
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }
}

private struct SparseValueEditor: View {
    @Binding var json: String

    private var indices: [String] { array(named: "indices") }
    private var values: [String] { array(named: "values") }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(0..<max(indices.count, values.count), id: \.self) { index in
                HStack {
                    TextField("Index", text: sparseBinding(index, indices: true))
                    TextField("Value", text: sparseBinding(index, indices: false))
                    Button(role: .destructive) {
                        remove(index)
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                }
            }
            Button("Add Sparse Entry", systemImage: "plus") { append() }
            Text("Indices must be strictly increasing.").font(.caption).foregroundStyle(.secondary)
        }
        .font(.system(.body, design: .monospaced))
    }

    private func sparseBinding(_ index: Int, indices isIndex: Bool) -> Binding<String> {
        Binding(
            get: {
                let source = isIndex ? indices : values
                return index < source.count ? source[index] : ""
            },
            set: { newValue in
                var newIndices = indices
                var newValues = values
                while newIndices.count <= index { newIndices.append("0") }
                while newValues.count <= index { newValues.append("0") }
                if isIndex { newIndices[index] = newValue } else { newValues[index] = newValue }
                rebuild(newIndices, newValues)
            }
        )
    }

    private func append() {
        var newIndices = indices
        var newValues = values
        newIndices.append(newIndices.last.flatMap(UInt32.init).map { String($0 + 1) } ?? "0")
        newValues.append("0")
        rebuild(newIndices, newValues)
    }

    private func remove(_ index: Int) {
        var newIndices = indices
        var newValues = values
        if index < newIndices.count { newIndices.remove(at: index) }
        if index < newValues.count { newValues.remove(at: index) }
        rebuild(newIndices, newValues)
    }

    private func rebuild(_ indices: [String], _ values: [String]) {
        json = #"{"indices":[#(indices.joined(separator: ","))],"values":[#(values.joined(separator: ","))]}"#
    }

    private func array(named key: String) -> [String] {
        guard let data = json.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let array = object[key] as? [Any]
        else { return [] }
        return array.map { String(describing: $0) }
    }
}
