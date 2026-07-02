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
        Form {
            LabeledContent("Location", value: snapshot?.id.rawValue ?? "—")
            LabeledContent("Documents", value: snapshot.map { String($0.statistics.documentCount) } ?? "—")
            LabeledContent(
                "Memory mapping", value: snapshot?.options.enableMemoryMapping == true ? "Enabled" : "Disabled")
            LabeledContent("Read only", value: snapshot?.options.readOnly == true ? "Yes" : "No")
            if let indexes = snapshot?.statistics.indexStatistics, !indexes.isEmpty {
                Section("Index completeness") {
                    ForEach(indexes, id: \.name) { index in
                        LabeledContent(
                            index.name, value: index.completeness.formatted(.percent.precision(.fractionLength(1))))
                    }
                }
            }
            Section("Danger Zone") {
                Button("Destroy Collection…", role: .destructive) { showingDestroy = true }
            }
        }.padding()
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

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Schema").font(.headline)
                Spacer()
                Button("Add Column", systemImage: "plus") { showingAdd = true }
            }
            .padding()
            List(snapshot?.schema.fields ?? [], id: \.name) { field in
                HStack {
                    Grid(alignment: .leading, horizontalSpacing: 16) {
                        GridRow {
                            Text(field.name).font(.headline).gridColumnAlignment(.leading)
                            Text(String(describing: field.dataType)).gridColumnAlignment(.leading)
                            Text(field.nullable ? "Nullable" : "Required")
                            Text(field.dimensions == 0 ? "" : "\(field.dimensions) dimensions")
                        }
                        if let index = field.index {
                            GridRow {
                                Text("Index").foregroundStyle(.secondary);
                                Text(String(describing: index)).gridCellColumns(3)
                            }
                        }
                    }
                    Spacer()
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
}
