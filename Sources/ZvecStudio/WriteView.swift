import AppKit
import SwiftUI
import Zvec
import ZvecStudioCore

struct WriteView: View {
    @Bindable var model: StudioModel
    let id: CollectionID
    let schema: CollectionSchema?

    var body: some View {
        if let schema {
            DocumentEditor(model: model, id: id, schema: schema)
                .id(id.rawValue + schema.fields.map(\.name).joined())
        } else {
            ProgressView()
        }
    }
}

private struct DocumentEditor: View {
    @Bindable var model: StudioModel
    let id: CollectionID
    let schema: CollectionSchema
    @State private var mode: WriteMode = .insert
    @State private var editorMode: EditorMode = .form
    @State private var draft: DocumentDraft
    @State private var rawJSON = ""
    @State private var validationMessage: String?
    @State private var importPreview: ImportPreview?
    @State private var showingImportPreview = false
    @State private var deleteDocumentID = ""
    @State private var deleteFilter = ""
    @State private var pendingDelete: DeleteRequest?
    @State private var activeImportTask: Task<Void, Never>?

    init(model: StudioModel, id: CollectionID, schema: CollectionSchema) {
        self.model = model
        self.id = id
        self.schema = schema
        _draft = State(initialValue: DocumentDraft(schema: schema))
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Picker("Operation", selection: $mode) {
                    ForEach(WriteMode.allCases, id: \.rawValue) { Text($0.rawValue.capitalized).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 330)
                Picker("Editor", selection: $editorMode) {
                    ForEach(EditorMode.allCases, id: \.rawValue) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 240)
                Spacer()
                Button("Import JSON/CSV…", action: chooseImport)
                Button(mode.rawValue.capitalized, action: submit)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal)

            if editorMode == .form {
                form
            } else {
                TextEditor(text: $rawJSON)
                    .font(.system(.body, design: .monospaced))
                    .padding(.horizontal)
            }

            if let validationMessage {
                Text(validationMessage)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
            } else if let operationMessage = model.operationMessage {
                Text(operationMessage)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
            }
            GroupBox("Danger Zone") {
                HStack {
                    TextField("Document ID", text: $deleteDocumentID)
                    Button("Delete by ID", role: .destructive) {
                        guard !deleteDocumentID.isEmpty else { return }
                        pendingDelete = .document(deleteDocumentID)
                    }
                    TextField("Filter expression", text: $deleteFilter)
                    Button("Filter Delete", role: .destructive) {
                        guard !deleteFilter.isEmpty else { return }
                        pendingDelete = .filter(deleteFilter)
                    }
                }
                .padding(6)
            }
            .padding(.horizontal)
        }
        .padding(.vertical)
        .onChange(of: editorMode) { previous, current in synchronize(from: previous, to: current) }
        .onAppear { loadForEditing(model.editingDocument) }
        .onChange(of: model.editingDocument) { _, document in loadForEditing(document) }
        .sheet(isPresented: $showingImportPreview) {
            if let importPreview {
                ImportPreviewView(
                    preview: importPreview,
                    mode: mode,
                    progress: model.importProgress,
                    isRunning: activeImportTask != nil,
                    cancel: {
                        if let activeImportTask { activeImportTask.cancel() } else { showingImportPreview = false }
                    },
                    commit: {
                        activeImportTask = Task {
                            await model.importDocuments(id, preview: importPreview, mode: mode)
                            activeImportTask = nil
                        }
                    }
                )
            }
        }
        .confirmationDialog(
            pendingDelete?.title ?? "Confirm Delete",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                guard let request = pendingDelete else { return }
                pendingDelete = nil
                switch request {
                case let .document(documentID): Task { await model.deleteDocument(id, documentID: documentID) }
                case let .filter(filter): Task { await model.deleteWhere(id, filter: filter) }
                }
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("This operation cannot be undone.")
        }
    }

    private var form: some View {
        Form {
            TextField("Document ID", text: $draft.id)
            Section("Fields") {
                ForEach($draft.fields) { $field in
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading) {
                            Text(field.name).font(.headline)
                            if let type = schema.field(named: field.name)?.dataType {
                                Text(String(describing: type)).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .frame(width: 150, alignment: .leading)
                        Picker("Presence", selection: $field.presence) {
                            ForEach(FieldPresence.allCases, id: \.rawValue) {
                                Text($0.rawValue.capitalized).tag($0)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 110)
                        if field.presence == .value {
                            if let schemaField = schema.field(named: field.name) {
                                FieldValueEditor(value: $field.jsonValue, field: schemaField)
                            }
                        } else if field.presence == .null,
                            schema.field(named: field.name)?.nullable == false
                        {
                            Text("Field is not nullable").foregroundStyle(.red)
                        }
                    }
                    .onChange(of: field.presence) { _, presence in
                        if presence == .value, field.jsonValue.isEmpty,
                            let schemaField = schema.field(named: field.name)
                        {
                            field.jsonValue = FieldValueEditor.defaultJSON(for: schemaField)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func synchronize(from previous: EditorMode, to current: EditorMode) {
        do {
            switch (previous, current) {
            case (.form, .raw):
                rawJSON = try draft.canonicalJSON(schema: schema, intent: mode.intent)
            case (.raw, .form):
                try draft.synchronize(fromCanonicalJSON: rawJSON, schema: schema)
            default: break
            }
            validationMessage = nil
        } catch {
            validationMessage = String(describing: error)
            editorMode = previous
        }
    }

    private func submit() {
        do {
            if editorMode == .raw {
                try draft.synchronize(fromCanonicalJSON: rawJSON, schema: schema)
            }
            let document = try draft.document(schema: schema, intent: mode.intent)
            validationMessage = nil
            Task { await model.write(id, documents: [document], mode: mode) }
        } catch { validationMessage = String(describing: error) }
    }

    private func loadForEditing(_ document: Document?) {
        guard let document else { return }
        do {
            draft = try DocumentDraft(document: document, schema: schema)
            mode = .update
            editorMode = .form
            rawJSON = ""
            validationMessage = nil
            model.editingDocument = nil
        } catch { validationMessage = String(describing: error) }
    }

    private func chooseImport() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try Data(contentsOf: url)
            switch url.pathExtension.lowercased() {
            case "json": importPreview = try .json(data, schema: schema, intent: mode.intent)
            case "csv": importPreview = try .csv(data, schema: schema, intent: mode.intent)
            default: throw ImportFileError.unsupportedExtension
            }
            model.importProgress = nil
            showingImportPreview = true
            validationMessage = nil
        } catch { validationMessage = String(describing: error) }
    }
}

private struct ImportPreviewView: View {
    let preview: ImportPreview
    let mode: WriteMode
    let progress: ImportProgress?
    let isRunning: Bool
    let cancel: () -> Void
    let commit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Import Preview").font(.title2).bold()
            Text("\(preview.totalRows) rows · \(preview.documents.count) valid · \(preview.issues.count) invalid")
            if !preview.issues.isEmpty {
                GroupBox("Validation errors") {
                    List(preview.issues) { issue in
                        Text("Row \(issue.row): \(issue.message)").textSelection(.enabled)
                    }
                }
            }
            GroupBox("First \(preview.sample.count) valid documents") {
                List(preview.sample) { Text($0.id) }
            }
            if let progress {
                ProgressView(
                    value: Double(progress.succeeded + progress.failed),
                    total: Double(progress.succeeded + progress.failed + progress.unprocessed)
                )
                Text(
                    "\(progress.succeeded) succeeded · \(progress.failed) failed · \(progress.unprocessed) unprocessed")
            }
            Text("Import uses batches of 500. There is no transaction rollback.")
                .font(.caption).foregroundStyle(.secondary)
            if !preview.issues.isEmpty {
                Text("Invalid rows are counted as failed and skipped; valid rows can still be imported.")
                    .font(.caption).foregroundStyle(.orange)
            }
            HStack {
                Spacer()
                Button(isRunning ? "Cancel Import" : "Close", action: cancel)
                Button("\(mode.rawValue.capitalized) \(preview.documents.count) Documents", action: commit)
                    .disabled(preview.documents.isEmpty || isRunning)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 680, minHeight: 500)
    }
}

private enum EditorMode: String, CaseIterable { case form = "Form", raw = "Raw JSON" }
private enum DeleteRequest {
    case document(String)
    case filter(String)
    var title: String {
        switch self {
        case let .document(id): "Delete document '\(id)'?"
        case let .filter(filter): "Delete every document matching '\(filter)'?"
        }
    }
}
private enum ImportFileError: Error, CustomStringConvertible {
    case unsupportedExtension
    var description: String { "Choose a .json or .csv file" }
}
