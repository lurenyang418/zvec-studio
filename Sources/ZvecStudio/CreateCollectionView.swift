import AppKit
import SwiftUI
import Zvec
import ZvecStudioCore

struct CreateCollectionView: View {
    @Bindable var model: StudioModel
    @Binding var isPresented: Bool
    @State private var parentURL: URL?
    @State private var name = ""
    @State private var maximumDocumentsPerSegment: UInt64 = 10_000_000
    @State private var memoryMapping = true
    @State private var maximumBufferSize = ""
    @State private var fields = [FieldDefinitionDraft()]
    @State private var validationMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Create Collection").font(.title2).bold()
            Form {
                LabeledContent("Collection location") {
                    HStack {
                        Text(destinationURL?.path ?? "Not selected").lineLimit(1)
                        Button("Choose…", action: chooseLocation)
                    }
                }
                TextField("Collection name", text: $name)
                LabeledContent("Maximum documents per segment") {
                    TextField("10000000", value: $maximumDocumentsPerSegment, format: .number)
                        .frame(width: 160)
                }
                Toggle("Enable memory mapping", isOn: $memoryMapping)
                TextField("Maximum buffer size (optional bytes)", text: $maximumBufferSize)
            }

            HStack {
                Text("Fields").font(.headline)
                Spacer()
                Button("Add Field", systemImage: "plus") { fields.append(FieldDefinitionDraft()) }
            }
            List {
                ForEach($fields) { $field in
                    FieldDefinitionRow(field: $field) {
                        fields.removeAll { $0.id == field.id }
                    }
                }
            }
            .frame(minHeight: 220)
            Text(
                "Vamana/DiskANN is unavailable on Apple platforms. Sparse-vector fields are supported, but sparse indexes are disabled; sparse queries use brute force."
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            if let validationMessage {
                Text(validationMessage).foregroundStyle(.red).textSelection(.enabled)
            }
            HStack {
                Spacer()
                Button("Cancel") { isPresented = false }
                    .keyboardShortcut(.cancelAction)
                Button("Create") { create() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(
                        destinationURL == nil || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || fields.isEmpty)
            }
        }
        .padding(20)
        .frame(minWidth: 760, minHeight: 560)
    }

    private var destinationURL: URL? {
        guard let parentURL else { return nil }
        return parentURL.appending(
            path: name.trimmingCharacters(in: .whitespacesAndNewlines),
            directoryHint: .isDirectory
        )
    }

    private func chooseLocation() {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = name.isEmpty ? "New Collection" : name
        panel.title = "Choose New Collection Directory"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        parentURL = url.deletingLastPathComponent()
        name = url.lastPathComponent
    }

    private func create() {
        do {
            let schemas = try fields.map { try $0.schema }
            let schema = try CollectionSchema(
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                fields: schemas,
                maximumDocumentsPerSegment: maximumDocumentsPerSegment
            )
            let buffer = maximumBufferSize.isEmpty ? nil : Int(maximumBufferSize)
            if !maximumBufferSize.isEmpty, buffer == nil { throw CreateValidationError.invalidBufferSize }
            guard let url = destinationURL else { return }
            Task {
                await model.create(
                    at: url,
                    schema: schema,
                    options: CollectionOptions(enableMemoryMapping: memoryMapping, maximumBufferSize: buffer)
                )
                if model.error == nil { isPresented = false }
            }
        } catch {
            validationMessage = String(describing: error)
        }
    }
}

private struct FieldDefinitionRow: View {
    @Binding var field: FieldDefinitionDraft
    let remove: () -> Void
    @State private var showingIndexConfiguration = false

    var body: some View {
        HStack {
            TextField("Name", text: $field.name).frame(minWidth: 120)
            Picker("Type", selection: $field.dataType) {
                ForEach(DataType.allCases.filter { $0 != .undefined }, id: \.rawValue) {
                    Text(String(describing: $0)).tag($0)
                }
            }
            .labelsHidden()
            .frame(minWidth: 170)
            Toggle("Nullable", isOn: $field.nullable)
            if field.dataType.requiresDimensions {
                TextField("Dimensions", value: $field.dimensions, format: .number)
                    .frame(width: 90)
            }
            Picker("Index", selection: $field.indexKind) {
                ForEach(field.availableIndexes) { Text($0.label).tag($0) }
            }
            .frame(width: 130)
            .onChange(of: field.indexKind) { field.customIndex = nil }
            if field.indexKind != .none {
                Button("Configure…") { showingIndexConfiguration = true }
            }
            Button(role: .destructive, action: remove) { Image(systemName: "trash") }
                .buttonStyle(.borderless)
        }
        .sheet(isPresented: $showingIndexConfiguration) {
            if let schema = try? field.schema {
                IndexEditor(field: schema) { configuration in
                    field.customIndex = configuration
                    showingIndexConfiguration = false
                }
            }
        }
    }
}

private struct FieldDefinitionDraft: Identifiable {
    let id = UUID()
    var name = ""
    var dataType: DataType = .string
    var nullable = false
    var dimensions = 128
    var indexKind: IndexKind = .none
    var customIndex: IndexConfiguration?

    var availableIndexes: [IndexKind] {
        if dataType.isSparseVector { return [.none] }
        if dataType.isDenseVector { return [.none, .hnsw, .ivf, .flat] }
        if dataType == .string { return [.none, .inverted, .fullText] }
        if dataType.isScalar { return [.none, .inverted] }
        return [.none]
    }

    var schema: FieldSchema {
        get throws {
            guard availableIndexes.contains(indexKind) else { throw CreateValidationError.invalidIndex(name) }
            let defaultIndex: IndexConfiguration? =
                switch indexKind {
                case .none: nil
                case .hnsw: .hnsw()
                case .ivf: .ivf()
                case .flat: .flat()
                case .inverted: .inverted()
                case .fullText: .fullText()
                }
            return try FieldSchema(
                name.trimmingCharacters(in: .whitespacesAndNewlines),
                type: dataType,
                nullable: nullable,
                dimensions: dataType.requiresDimensions ? dimensions : 0,
                index: customIndex ?? defaultIndex
            )
        }
    }
}

private enum IndexKind: String, CaseIterable, Identifiable {
    case none, hnsw, ivf, flat, inverted, fullText
    var id: String { rawValue }
    var label: String { rawValue == "none" ? "None" : rawValue }
}

private enum CreateValidationError: Error, CustomStringConvertible {
    case invalidBufferSize
    case invalidIndex(String)
    var description: String {
        switch self {
        case .invalidBufferSize: "Maximum buffer size must be a whole number of bytes"
        case let .invalidIndex(field): "The selected index is not supported for field '\(field)'"
        }
    }
}
