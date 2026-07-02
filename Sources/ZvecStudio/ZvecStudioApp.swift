import AppKit
import SwiftUI
import Zvec
import ZvecStudioCore

@main
struct ZvecStudioApp: App {
    @NSApplicationDelegateAdaptor(ApplicationDelegate.self) private var applicationDelegate
    @State private var model = StudioModel()

    var body: some Scene {
        Window("Zvec Studio", id: "main") {
            ContentView(model: model)
                .frame(minWidth: 960, minHeight: 640)
                .task {
                    applicationDelegate.shutdownHandler = { await model.shutdownForTermination() }
                    await model.start()
                }
        }
        .defaultSize(width: 1180, height: 760)

        Settings {
            SettingsView(model: model)
        }
    }
}

struct ContentView: View {
    @Bindable var model: StudioModel
    @State private var showingCreate = false

    var body: some View {
        NavigationSplitView {
            List(selection: $model.destination) {
                Label("Dashboard", systemImage: "square.grid.2x2").tag(StudioModel.Destination.dashboard)
                if !model.opened.isEmpty {
                    Section("Open") {
                        ForEach(model.opened) { item in
                            Label(item.schema.name, systemImage: "cylinder")
                                .tag(StudioModel.Destination.collection(item.id))
                        }
                    }
                }
                if !model.recents.isEmpty {
                    Section("Recent") {
                        ForEach(model.recents) { recent in
                            Button {
                                Task { await model.open(recent.id.url) }
                            } label: {
                                Label(recent.id.url.lastPathComponent, systemImage: "clock")
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 240)
            .safeAreaInset(edge: .bottom) {
                HStack {
                    Button("Open…", systemImage: "folder") { chooseCollection() }
                    Button("Create…", systemImage: "plus") { showingCreate = true }
                    Spacer()
                    if model.isBusy { ProgressView().controlSize(.small) }
                }
                .padding(12)
            }
        } detail: {
            switch model.destination {
            case .collection(let id): CollectionView(model: model, id: id)
            case .dashboard, .none: DashboardView(model: model)
            }
        }
        .alert(item: $model.error) { error in
            Alert(title: Text(error.operation), message: Text(error.message), dismissButton: .default(Text("OK")))
        }
        .sheet(isPresented: $showingCreate) {
            CreateCollectionView(model: model, isPresented: $showingCreate)
        }
        .onChange(of: model.destination) { _, destination in
            switch destination {
            case let .collection(id):
                model.uiState.select(id)
                model.queryDocuments = []
                model.groupResults = []
                Task { await model.browse(id) }
            case .dashboard, .none:
                model.uiState.select(nil)
            }
        }
    }

    private func chooseCollection() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await model.open(url) }
    }
}

struct DashboardView: View {
    @Bindable var model: StudioModel

    var body: some View {
        ContentUnavailableView {
            Label("Zvec Studio", systemImage: "cylinder.split.1x2")
        } description: {
            Text(model.runtimeReady ? "Open a Zvec collection to inspect and manage it." : "Initializing Zvec runtime…")
        } actions: {
            if !model.runtimeReady {
                Button("Retry Runtime Initialization") { Task { await model.start() } }
            }
        }
    }
}

struct CollectionView: View {
    @Bindable var model: StudioModel
    let id: CollectionID
    @State private var filter = ""
    @State private var selectedTab: CollectionTab = .browse

    private var snapshot: CollectionSnapshot? { model.opened.first { $0.id == id } }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(snapshot?.schema.name ?? id.url.lastPathComponent).font(.title2).bold()
                Spacer()
                Button("Flush") { Task { await model.flush(id) } }
                Button("Optimize") { Task { await model.optimize(id) } }
                Button("Close") { Task { await model.close(id) } }
            }
            .padding()

            TabView(selection: $selectedTab) {
                BrowseView(
                    model: model, id: id, schema: snapshot?.schema, filter: $filter,
                    edit: { document in
                        model.editingDocument = document
                        selectedTab = .write
                    }
                )
                .tabItem { Label("Browse", systemImage: "tablecells") }
                .tag(CollectionTab.browse)
                WriteView(model: model, id: id, schema: snapshot?.schema)
                    .tabItem { Label("Write", systemImage: "square.and.pencil") }
                    .tag(CollectionTab.write)
                QueryView(model: model, id: id, schema: snapshot?.schema)
                    .tabItem { Label("Query", systemImage: "magnifyingglass") }
                    .tag(CollectionTab.query)
                OverviewView(model: model, id: id, snapshot: snapshot)
                    .tabItem { Label("Overview", systemImage: "info.circle") }
                    .tag(CollectionTab.overview)
                SchemaView(model: model, id: id, snapshot: snapshot)
                    .tabItem { Label("Schema", systemImage: "list.bullet.rectangle") }
                    .tag(CollectionTab.schema)
            }
        }
    }
}

struct BrowseView: View {
    @Bindable var model: StudioModel
    let id: CollectionID
    let schema: CollectionSchema?
    @Binding var filter: String
    let edit: (Document) -> Void
    @State private var exportError: String?
    @State private var mode: BrowseMode = .browse
    @State private var fetchIDs = ""
    @State private var limit = 100
    @State private var includeVector = false
    @State private var outputFields = Set<String>()
    @State private var selectedDocumentID: String?

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Picker("Mode", selection: $mode) {
                    Text("Browse").tag(BrowseMode.browse)
                    Text("Fetch by ID").tag(BrowseMode.fetch)
                }
                .pickerStyle(.segmented)
                .frame(width: 220)
                if mode == .browse {
                    TextField("Filter expression", text: $filter)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(run)
                    Stepper("Limit \(limit)", value: $limit, in: 1...100_000)
                } else {
                    TextField("Document IDs (comma or newline separated)", text: $fetchIDs)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(run)
                }
                Menu("Fields") {
                    Button(outputFields.isEmpty ? "✓ All scalar fields" : "All scalar fields") { outputFields = [] }
                    if let schema {
                        ForEach(schema.fields, id: \.name) { field in
                            Button(outputFields.contains(field.name) ? "✓ \(field.name)" : field.name) {
                                if outputFields.contains(field.name) {
                                    outputFields.remove(field.name)
                                } else {
                                    outputFields.insert(field.name)
                                }
                            }
                        }
                    }
                    Divider()
                    Toggle("Include vectors", isOn: $includeVector)
                }
                Button("Run", action: run)
                Button("Edit Selected") {
                    if let document = model.documents.first(where: { $0.id == selectedDocumentID }) {
                        edit(document)
                    }
                }
                .disabled(selectedDocumentID == nil)
                Menu("Export") {
                    Button("Current Results as JSON…") { exportJSON() }
                    Button("Current Results as CSV…") { exportCSV() }
                }
            }
            .padding(.horizontal)
            if model.browseLimitReached {
                Label(
                    "Result limit reached — more documents may exist. This is not a page cursor.",
                    systemImage: "exclamationmark.triangle"
                )
                .foregroundStyle(.orange)
            }
            if let message = model.operationMessage, mode == .fetch {
                Text(message).foregroundStyle(.secondary)
            }
            Table(model.documents, selection: $selectedDocumentID) {
                TableColumn("ID") { Text($0.id) }
                TableColumn("Score") { Text($0.score.map { String(format: "%.4f", $0) } ?? "—") }
                TableColumn("Fields") { Text(DocumentDisplay.compactFields($0)).lineLimit(2) }
            }
        }
        .alert(
            "Export Failed",
            isPresented: Binding(
                get: { exportError != nil },
                set: { if !$0 { exportError = nil } }
            )
        ) {
            Button("OK") { exportError = nil }
        } message: {
            Text(exportError ?? "")
        }
        .padding(.top, 12)
    }

    private func run() {
        let fields = outputFields.sorted()
        if mode == .browse {
            Task {
                await model.browse(
                    id, filter: filter, limit: limit,
                    outputFields: fields, includeVector: includeVector
                )
            }
        } else {
            let ids =
                fetchIDs
                .components(separatedBy: CharacterSet(charactersIn: ",\n"))
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            Task { await model.fetch(id, documentIDs: ids, outputFields: fields, includeVector: includeVector) }
        }
    }

    private func exportJSON() {
        do {
            guard let schema else { return }
            try ResultFileSaver.saveDocuments(
                model.documents, schema: schema, format: .json,
                source: mode == .browse ? "browse" : "fetch",
                limitReached: model.browseLimitReached
            )
        } catch { exportError = String(describing: error) }
    }

    private func exportCSV() {
        do {
            guard let schema else { return }
            try ResultFileSaver.saveDocuments(
                model.documents, schema: schema, format: .csv,
                source: mode == .browse ? "browse" : "fetch",
                limitReached: model.browseLimitReached
            )
        } catch { exportError = String(describing: error) }
    }
}

private enum BrowseMode: String { case browse, fetch }
private enum CollectionTab: Hashable { case browse, write, query, overview, schema }

struct OverviewView: View {
    @Bindable var model: StudioModel
    let id: CollectionID
    let snapshot: CollectionSnapshot?
    @State private var showingDestroy = false
    @State private var confirmationName = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Overview")
                        .font(.title2.bold())
                    Text("Collection status and storage configuration")
                        .foregroundStyle(.secondary)
                }

                GroupBox {
                    Grid(alignment: .leading, horizontalSpacing: 32, verticalSpacing: 12) {
                        overviewRow("Location") {
                            Text(snapshot?.id.rawValue ?? "—")
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .textSelection(.enabled)
                                .help(snapshot?.id.rawValue ?? "")
                        }
                        overviewRow("Documents") {
                            Text(snapshot.map { $0.statistics.documentCount.formatted() } ?? "—")
                                .monospacedDigit()
                        }
                        overviewRow("Memory mapping") {
                            statusLabel(
                                snapshot?.options.enableMemoryMapping == true ? "Enabled" : "Disabled",
                                enabled: snapshot?.options.enableMemoryMapping == true
                            )
                        }
                        overviewRow("Access") {
                            statusLabel(
                                snapshot?.options.readOnly == true ? "Read only" : "Read and write",
                                enabled: snapshot?.options.readOnly != true
                            )
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                } label: {
                    Label("Collection", systemImage: "cylinder")
                        .font(.headline)
                }

                if let indexes = snapshot?.statistics.indexStatistics, !indexes.isEmpty {
                    GroupBox {
                        VStack(spacing: 0) {
                            ForEach(Array(indexes.enumerated()), id: \.element.name) { offset, index in
                                HStack(spacing: 16) {
                                    Text(index.name)
                                        .fontWeight(.medium)
                                    Spacer()
                                    ProgressView(value: Double(index.completeness))
                                        .frame(width: 160)
                                    Text(index.completeness.formatted(.percent.precision(.fractionLength(1))))
                                        .monospacedDigit()
                                        .frame(width: 64, alignment: .trailing)
                                }
                                .padding(.vertical, 10)
                                if offset < indexes.count - 1 { Divider() }
                            }
                        }
                        .padding(.horizontal, 8)
                    } label: {
                        Label("Index completeness", systemImage: "chart.bar.fill")
                            .font(.headline)
                    }
                }

                GroupBox {
                    HStack(spacing: 20) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Permanently delete this collection")
                                .fontWeight(.medium)
                            Text("This removes all collection data and cannot be undone.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Destroy Collection…", role: .destructive) { showingDestroy = true }
                    }
                    .padding(8)
                } label: {
                    Label("Danger Zone", systemImage: "exclamationmark.triangle")
                        .font(.headline)
                        .foregroundStyle(.red)
                }
            }
            .frame(maxWidth: 760, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .sheet(isPresented: $showingDestroy) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Destroy Collection").font(.title2).bold()
                Text("This permanently removes all collection data at:")
                Text(id.rawValue).font(.system(.body, design: .monospaced)).textSelection(.enabled)
                Text("Type **\(snapshot?.schema.name ?? "")** to confirm.")
                TextField("Collection name", text: $confirmationName)
                HStack {
                    Spacer()
                    Button("Cancel") { showingDestroy = false }
                    Button("Destroy", role: .destructive) {
                        Task {
                            await model.destroy(id, confirmationName: confirmationName)
                            showingDestroy = false
                        }
                    }
                    .disabled(confirmationName != snapshot?.schema.name)
                }
            }
            .padding(20)
            .frame(width: 580)
        }
    }

    private func overviewRow<Content: View>(
        _ label: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 120, alignment: .leading)
            content()
                .gridColumnAlignment(.leading)
        }
    }

    private func statusLabel(_ text: String, enabled: Bool) -> some View {
        Label(text, systemImage: enabled ? "checkmark.circle.fill" : "minus.circle")
            .foregroundStyle(enabled ? .green : .secondary)
    }
}

struct SchemaView: View {
    @Bindable var model: StudioModel
    let id: CollectionID
    let snapshot: CollectionSnapshot?
    @State private var showingAdd = false
    @State private var editingField: FieldSchema?
    @State private var indexingField: FieldSchema?
    @State private var dropField: FieldSchema?
    @State private var dropIndexField: FieldSchema?

    private var fields: [FieldSchema] { snapshot?.schema.fields ?? [] }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Schema")
                        .font(.title2.bold())
                    Text("\(fields.count) column\(fields.count == 1 ? "" : "s")")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Add Column", systemImage: "plus") { showingAdd = true }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)

            Divider()

            if fields.isEmpty {
                ContentUnavailableView(
                    "No Columns",
                    systemImage: "rectangle.split.3x1",
                    description: Text("Add a column to define this collection's schema.")
                )
            } else {
                Table(fields) {
                    TableColumn("Name") { field in
                        Text(field.name)
                            .fontWeight(.semibold)
                            .textSelection(.enabled)
                    }
                    .width(min: 140, ideal: 180, max: 260)

                    TableColumn("Type") { field in
                        Text(field.dataType.schemaDisplayName)
                    }
                    .width(min: 120, ideal: 150, max: 200)

                    TableColumn("Requirement") { field in
                        Text(field.nullable ? "Nullable" : "Required")
                            .foregroundStyle(field.nullable ? .secondary : .primary)
                    }
                    .width(min: 90, ideal: 100, max: 120)

                    TableColumn("Dimensions") { field in
                        Text(field.dimensions == 0 ? "—" : field.dimensions.formatted())
                            .monospacedDigit()
                    }
                    .width(min: 80, ideal: 90, max: 110)

                    TableColumn("Index") { field in
                        if let index = field.index {
                            VStack(alignment: .leading, spacing: 2) {
                                Label(index.schemaDisplayName, systemImage: "bolt.horizontal.circle.fill")
                                    .fontWeight(.medium)
                                Text(index.schemaDisplayDescription)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            .help(index.schemaDisplayDescription)
                        } else {
                            Text("None")
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .width(min: 160, ideal: 240, max: 380)

                    TableColumn("") { field in
                        fieldActions(field)
                    }
                    .width(36)
                }
            }
        }
        .sheet(isPresented: $showingAdd) {
            ColumnEditor(title: "Add Column", original: nil) { field, _, defaultExpression in
                Task { await model.addColumn(id, field: field, defaultExpression: defaultExpression) }
                showingAdd = false
            }
        }
        .sheet(item: $editingField) { field in
            ColumnEditor(title: "Alter Column", original: field) { replacement, newName, _ in
                Task { await model.alterColumn(id, name: field.name, newName: newName, schema: replacement) }
                editingField = nil
            }
        }
        .sheet(item: $indexingField) { field in
            IndexEditor(field: field) { index in
                Task { await model.createIndex(id, field: field.name, index: index) }
                indexingField = nil
            }
        }
        .confirmationDialog(
            "Drop column '\(dropField?.name ?? "")'? This cannot be undone.",
            isPresented: Binding(get: { dropField != nil }, set: { if !$0 { dropField = nil } }),
            titleVisibility: .visible
        ) {
            Button("Drop Column", role: .destructive) {
                if let field = dropField { Task { await model.dropColumn(id, name: field.name) } }
                dropField = nil
            }
            Button("Cancel", role: .cancel) { dropField = nil }
        }
        .confirmationDialog(
            "Drop index on '\(dropIndexField?.name ?? "")'?",
            isPresented: Binding(get: { dropIndexField != nil }, set: { if !$0 { dropIndexField = nil } }),
            titleVisibility: .visible
        ) {
            Button("Drop Index", role: .destructive) {
                if let field = dropIndexField { Task { await model.dropIndex(id, field: field.name) } }
                dropIndexField = nil
            }
            Button("Cancel", role: .cancel) { dropIndexField = nil }
        }
    }

    private func fieldActions(_ field: FieldSchema) -> some View {
        Menu {
            Button("Alter Column…") { editingField = field }
            if field.index == nil {
                Button("Create Index…") { indexingField = field }
            } else {
                Button("Drop Index…", role: .destructive) { dropIndexField = field }
            }
            Divider()
            Button("Drop Column…", role: .destructive) { dropField = field }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .menuStyle(.borderlessButton)
        .help("Column actions")
    }
}

private extension DataType {
    var schemaDisplayName: String {
        switch self {
        case .undefined: "Undefined"
        case .binary: "Binary"
        case .string: "String"
        case .bool: "Boolean"
        case .int32: "Int32"
        case .int64: "Int64"
        case .uint32: "UInt32"
        case .uint64: "UInt64"
        case .float: "Float32"
        case .double: "Float64"
        case .vectorBinary32: "Binary32 vector"
        case .vectorBinary64: "Binary64 vector"
        case .vectorFloat16: "Float16 vector"
        case .vectorFloat32: "Float32 vector"
        case .vectorFloat64: "Float64 vector"
        case .vectorInt4: "Int4 vector"
        case .vectorInt8: "Int8 vector"
        case .vectorInt16: "Int16 vector"
        case .sparseVectorFloat16: "Sparse Float16 vector"
        case .sparseVectorFloat32: "Sparse Float32 vector"
        case .arrayBinary: "Binary array"
        case .arrayString: "String array"
        case .arrayBool: "Boolean array"
        case .arrayInt32: "Int32 array"
        case .arrayInt64: "Int64 array"
        case .arrayUInt32: "UInt32 array"
        case .arrayUInt64: "UInt64 array"
        case .arrayFloat: "Float32 array"
        case .arrayDouble: "Float64 array"
        }
    }
}

private extension IndexConfiguration {
    var schemaDisplayName: String {
        switch self {
        case .hnsw: "HNSW"
        case .ivf: "IVF"
        case .flat: "Flat"
        case .vamana: "Vamana"
        case .inverted: "Inverted"
        case .fullText: "Full text"
        }
    }

    var schemaDisplayDescription: String {
        switch self {
        case let .hnsw(metric, quantization, m, efConstruction):
            "HNSW · \(metric.label) · \(quantization.label) · M \(m) · efConstruction \(efConstruction)"
        case let .ivf(metric, quantization, listCount, iterations, useSOAR):
            "IVF · \(metric.label) · \(quantization.label) · \(listCount) lists · \(iterations) iterations\(useSOAR ? " · SOAR" : "")"
        case let .flat(metric, quantization):
            "Flat · \(metric.label) · \(quantization.label)"
        case let .vamana(metric, maxDegree, buildListSize, alpha):
            "Vamana · \(metric.label) · degree \(maxDegree) · build list \(buildListSize) · alpha \(alpha)"
        case let .inverted(rangeOptimization, wildcard):
            "Inverted · range \(rangeOptimization ? "on" : "off") · wildcard \(wildcard ? "on" : "off")"
        case let .fullText(tokenizer, filters, options):
            "Full text · \(tokenizer.label) tokenizer · \(filters.count) filter\(filters.count == 1 ? "" : "s") · \(options.count) option\(options.count == 1 ? "" : "s")"
        }
    }
}

private extension Metric {
    var label: String {
        switch self {
        case .undefined: "Undefined"
        case .l2: "L2"
        case .innerProduct: "Inner product"
        case .cosine: "Cosine"
        case .mipsL2: "MIPS L2"
        }
    }
}

private extension Quantization {
    var label: String {
        switch self {
        case .none: "No quantization"
        case .float16: "Float16"
        case .int8: "Int8"
        case .int4: "Int4"
        }
    }
}

private extension FullTextTokenizer {
    var label: String {
        switch self {
        case .standard: "Standard"
        case .whitespace: "Whitespace"
        case .jieba: "Jieba"
        }
    }
}
