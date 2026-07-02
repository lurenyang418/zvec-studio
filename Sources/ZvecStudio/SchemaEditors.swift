import Foundation
import SwiftUI
import Zvec

extension FieldSchema: @retroactive Identifiable {
    public var id: String { name }
}

struct ColumnEditor: View {
    let title: String
    let original: FieldSchema?
    let commit: (FieldSchema, String?, String?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var dataType: DataType
    @State private var nullable: Bool
    @State private var dimensions: Int
    @State private var defaultExpression = ""
    @State private var validationMessage: String?

    init(
        title: String,
        original: FieldSchema?,
        commit: @escaping (FieldSchema, String?, String?) -> Void
    ) {
        self.title = title
        self.original = original
        self.commit = commit
        _name = State(initialValue: original?.name ?? "")
        _dataType = State(initialValue: original?.dataType ?? .int32)
        _nullable = State(initialValue: original?.nullable ?? false)
        _dimensions = State(initialValue: original?.dimensions ?? 128)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title).font(.title2).bold()
            Form {
                TextField("Name", text: $name)
                Picker("Data type", selection: $dataType) {
                    ForEach(availableDataTypes, id: \.rawValue) {
                        Text(String(describing: $0)).tag($0)
                    }
                }
                if original == nil {
                    Text(
                        "Zvec 0.5.1 add-column supports only basic numeric types. Define other types when creating the collection."
                    )
                    .font(.caption).foregroundStyle(.secondary)
                }
                Toggle("Nullable", isOn: $nullable)
                if dataType.requiresDimensions {
                    TextField("Dimensions", value: $dimensions, format: .number)
                }
                if original == nil {
                    TextField("Default expression (optional)", text: $defaultExpression)
                }
            }
            if let validationMessage { Text(validationMessage).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(title.replacingOccurrences(of: " Column", with: ""), action: save)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 520)
    }

    private var availableDataTypes: [DataType] {
        if original != nil { return DataType.allCases.filter { $0 != .undefined } }
        return [.int32, .int64, .uint32, .uint64, .float, .double]
    }

    private func save() {
        do {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            let field = try FieldSchema(
                original?.name ?? trimmed,
                type: dataType,
                nullable: nullable,
                dimensions: dataType.requiresDimensions ? dimensions : 0,
                index: original?.index
            )
            let newName: String? = if let original, original.name != trimmed { trimmed } else { nil }
            commit(field, newName, original == nil ? defaultExpression : nil)
        } catch { validationMessage = String(describing: error) }
    }
}

struct IndexEditor: View {
    let field: FieldSchema
    let commit: (IndexConfiguration) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var kind: IndexEditorKind
    @State private var metric: Metric = .cosine
    @State private var quantization: Quantization = .none
    @State private var m = 16
    @State private var efConstruction = 200
    @State private var listCount = 1_024
    @State private var iterations = 10
    @State private var useSOAR = false
    @State private var rangeOptimization = true
    @State private var wildcard = false
    @State private var tokenizer: TokenizerChoice = .standard
    @State private var tokenFilters = ""
    @State private var fullTextOptionsJSON = "{}"
    @State private var validationMessage: String?

    init(field: FieldSchema, commit: @escaping (IndexConfiguration) -> Void) {
        self.field = field
        self.commit = commit
        let initialKind: IndexEditorKind =
            switch field.index {
            case .hnsw?: .hnsw
            case .ivf?: .ivf
            case .flat?: .flat
            case .inverted?: .inverted
            case .fullText?: .fullText
            default: IndexEditorKind.available(for: field).first ?? .inverted
            }
        _kind = State(initialValue: initialKind)
        switch field.index {
        case let .hnsw(metric, quantization, m, efConstruction):
            _metric = State(initialValue: metric)
            _quantization = State(initialValue: quantization)
            _m = State(initialValue: m)
            _efConstruction = State(initialValue: efConstruction)
        case let .ivf(metric, quantization, listCount, iterations, useSOAR):
            _metric = State(initialValue: metric)
            _quantization = State(initialValue: quantization)
            _listCount = State(initialValue: listCount)
            _iterations = State(initialValue: iterations)
            _useSOAR = State(initialValue: useSOAR)
        case let .flat(metric, quantization):
            _metric = State(initialValue: metric)
            _quantization = State(initialValue: quantization)
        case let .inverted(enableRangeOptimization, enableWildcard):
            _rangeOptimization = State(initialValue: enableRangeOptimization)
            _wildcard = State(initialValue: enableWildcard)
        case let .fullText(tokenizer, filters, options):
            _tokenizer = State(initialValue: TokenizerChoice(tokenizer))
            _tokenFilters = State(initialValue: filters.joined(separator: ", "))
            if let data = try? JSONSerialization.data(withJSONObject: options, options: [.sortedKeys]) {
                _fullTextOptionsJSON = State(initialValue: String(decoding: data, as: UTF8.self))
            }
        default: break
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Create Index for \(field.name)").font(.title2).bold()
            if field.dataType.isSparseVector {
                Label(
                    "Sparse-vector indexes are unavailable on Apple platforms. Use brute-force sparse queries.",
                    systemImage: "exclamationmark.triangle"
                )
                .foregroundStyle(.orange)
            } else {
                Form {
                    Picker("Index", selection: $kind) {
                        ForEach(IndexEditorKind.available(for: field)) { Text($0.label).tag($0) }
                    }
                    if kind.isVector {
                        Picker("Metric", selection: $metric) {
                            ForEach(Metric.allCases.filter { $0 != .undefined }, id: \.rawValue) {
                                Text(String(describing: $0)).tag($0)
                            }
                        }
                        Picker("Quantization", selection: $quantization) {
                            ForEach(Quantization.allCases, id: \.rawValue) {
                                Text(String(describing: $0)).tag($0)
                            }
                        }
                    }
                    switch kind {
                    case .hnsw:
                        TextField("M", value: $m, format: .number)
                        TextField("efConstruction", value: $efConstruction, format: .number)
                    case .ivf:
                        TextField("List count", value: $listCount, format: .number)
                        TextField("Iterations", value: $iterations, format: .number)
                        Toggle("Use SOAR", isOn: $useSOAR)
                    case .inverted:
                        Toggle("Range optimization", isOn: $rangeOptimization)
                        Toggle("Wildcard", isOn: $wildcard)
                    case .fullText:
                        Picker("Tokenizer", selection: $tokenizer) {
                            ForEach(TokenizerChoice.allCases, id: \.rawValue) { Text($0.rawValue).tag($0) }
                        }
                        TextField("Token filters (comma separated)", text: $tokenFilters)
                        TextField("Options JSON", text: $fullTextOptionsJSON)
                            .font(.system(.body, design: .monospaced))
                    case .flat: EmptyView()
                    }
                }
            }
            if let validationMessage { Text(validationMessage).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Create", action: create)
                    .disabled(field.dataType.isSparseVector)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 540)
    }

    private func create() {
        do {
            let configuration: IndexConfiguration =
                switch kind {
                case .hnsw:
                    .hnsw(metric: metric, quantization: quantization, m: m, efConstruction: efConstruction)
                case .ivf:
                    .ivf(
                        metric: metric, quantization: quantization, listCount: listCount,
                        iterations: iterations, useSOAR: useSOAR
                    )
                case .flat: .flat(metric: metric, quantization: quantization)
                case .inverted: .inverted(enableRangeOptimization: rangeOptimization, enableWildcard: wildcard)
                case .fullText:
                    .fullText(
                        tokenizer: tokenizer.value,
                        tokenFilters: tokenFilters.split(separator: ",").map {
                            $0.trimmingCharacters(in: .whitespacesAndNewlines)
                        }.filter { !$0.isEmpty },
                        options: try decodeOptions()
                    )
                }
            validationMessage = nil
            commit(configuration)
        } catch { validationMessage = String(describing: error) }
    }

    private func decodeOptions() throws -> [String: String] {
        guard let data = fullTextOptionsJSON.data(using: .utf8),
            let options = try JSONSerialization.jsonObject(with: data) as? [String: String]
        else { throw IndexEditorError.invalidFullTextOptions }
        return options
    }
}

private enum IndexEditorError: Error, CustomStringConvertible {
    case invalidFullTextOptions
    var description: String { "Full-text options must be a JSON object whose values are strings" }
}

private enum IndexEditorKind: String, Identifiable {
    case hnsw, ivf, flat, inverted, fullText
    var id: String { rawValue }
    var label: String { rawValue }
    var isVector: Bool { self == .hnsw || self == .ivf || self == .flat }

    static func available(for field: FieldSchema) -> [IndexEditorKind] {
        if field.dataType.isSparseVector { return [] }
        if field.dataType.isDenseVector { return [.hnsw, .ivf, .flat] }
        if field.dataType == .string { return [.inverted, .fullText] }
        if field.dataType.isScalar { return [.inverted] }
        return []
    }
}

private enum TokenizerChoice: String, CaseIterable {
    case standard, whitespace, jieba

    init(_ tokenizer: FullTextTokenizer) {
        switch tokenizer {
        case .standard: self = .standard
        case .whitespace: self = .whitespace
        case .jieba: self = .jieba
        }
    }

    var value: FullTextTokenizer {
        switch self {
        case .standard: .standard;
        case .whitespace: .whitespace;
        case .jieba: .jieba
        }
    }
}
