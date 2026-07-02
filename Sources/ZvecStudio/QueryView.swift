import SwiftUI
import Zvec
import ZvecStudioCore

struct QueryView: View {
    @Bindable var model: StudioModel
    let id: CollectionID
    let schema: CollectionSchema?

    var body: some View {
        if let schema {
            QueryWorkbench(model: model, id: id, schema: schema)
                .id(id.rawValue + schema.fields.map(\.name).joined())
        } else {
            ProgressView()
        }
    }
}

private struct QueryWorkbench: View {
    @Bindable var model: StudioModel
    let id: CollectionID
    let schema: CollectionSchema
    @State private var mode: QueryMode = .vector
    @State private var vectorField = ""
    @State private var vectorSource: VectorSource = .vector
    @State private var vectorJSON = "[]"
    @State private var documentID = ""
    @State private var fullTextField = ""
    @State private var fullTextMode: FullTextMode = .match
    @State private var fullTextOperator: FullTextOperator = .or
    @State private var fullText = ""
    @State private var sparseField = ""
    @State private var sparseJSON = #"{"indices":[],"values":[]}"#
    @State private var secondSubquery: SecondSubquery = .fullText
    @State private var groupField = ""
    @State private var topK = 10
    @State private var filter = ""
    @State private var includeVector = false
    @State private var efSearch = 50
    @State private var probeCount = 10
    @State private var scaleFactor: Float = 1
    @State private var radius = ""
    @State private var linearSearch = false
    @State private var useRefiner = false
    @State private var groupCount: UInt32 = 10
    @State private var groupTopK: UInt32 = 3
    @State private var reranker: RerankerMode = .rrf
    @State private var firstWeight: Float = 0.5
    @State private var secondWeight: Float = 0.5
    @State private var validationMessage: String?
    @State private var exportError: String?
    @State private var outputFields = Set<String>()

    private var denseFields: [FieldSchema] { schema.fields.filter { $0.dataType.isDenseVector } }
    private var fullTextFields: [FieldSchema] {
        schema.fields.filter {
            guard case .fullText? = $0.index else { return false }
            return true
        }
    }
    private var sparseFields: [FieldSchema] { schema.fields.filter { $0.dataType == .sparseVectorFloat32 } }
    private var groupFields: [FieldSchema] { schema.fields.filter { $0.dataType.isScalar } }
    private var selectedVectorField: FieldSchema? { schema.field(named: vectorField) }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Picker("Query type", selection: $mode) {
                    ForEach(QueryMode.allCases, id: \.rawValue) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 520)
                Spacer()
                Menu("Export") {
                    Button("Current Results as JSON…") { export(.json) }
                    Button("Current Results as CSV…") { export(.csv) }
                }
                .disabled(mode == .groupBy ? model.groupResults.isEmpty : model.queryDocuments.isEmpty)
                Button("Search", action: run).keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal)

            GroupBox {
                Form {
                    switch mode {
                    case .vector: vectorEditor
                    case .fullText: fullTextEditor
                    case .multi: multiEditor
                    case .groupBy: groupEditor
                    }
                    Section("Result") {
                        TextField("Filter (optional)", text: $filter)
                        Stepper("Top K: \(topK)", value: $topK, in: 1...10_000)
                        Menu("Output fields") {
                            Button(outputFields.isEmpty ? "✓ All scalar fields" : "All scalar fields") {
                                outputFields = []
                            }
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
                        Toggle("Include vector fields", isOn: $includeVector)
                    }
                }
                .formStyle(.grouped)
            }
            .padding(.horizontal)

            if let validationMessage {
                Text(validationMessage).foregroundStyle(.red).textSelection(.enabled)
            }
            if mode == .groupBy {
                GroupResultList(groups: model.groupResults)
            } else {
                QueryDocumentTable(documents: model.queryDocuments)
            }
        }
        .padding(.vertical)
        .onAppear(perform: setDefaults)
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

    @ViewBuilder private var vectorEditor: some View {
        Section("Vector source") {
            Picker("Field", selection: $vectorField) {
                ForEach(denseFields, id: \.name) { Text($0.name).tag($0.name) }
            }
            Picker("Source", selection: $vectorSource) {
                Text("Vector").tag(VectorSource.vector)
                Text("Document ID").tag(VectorSource.documentID)
            }
            .pickerStyle(.segmented)
            if vectorSource == .vector {
                TextField(vectorPlaceholder, text: $vectorJSON)
                    .font(.system(.body, design: .monospaced))
            } else {
                TextField("Document ID", text: $documentID)
                Text("Document-ID query is enabled only for dense-vector fields.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            indexParameterEditor
        }
    }

    @ViewBuilder private var fullTextEditor: some View {
        Section("Full text") {
            Picker("Field", selection: $fullTextField) {
                ForEach(fullTextFields, id: \.name) { Text($0.name).tag($0.name) }
            }
            Picker("Expression", selection: $fullTextMode) {
                Text("Natural language Match").tag(FullTextMode.match)
                Text("Advanced Query syntax").tag(FullTextMode.query)
            }
            .pickerStyle(.segmented)
            TextField(fullTextMode == .match ? "Text to match" : "Advanced query expression", text: $fullText)
            Picker("Default operator", selection: $fullTextOperator) {
                Text("OR").tag(FullTextOperator.or)
                Text("AND").tag(FullTextOperator.and)
            }
            .pickerStyle(.segmented)
            Text(
                fullTextMode == .match
                    ? "Match mode treats the input as natural language."
                    : "Query mode passes advanced syntax directly to Zvec."
            )
            .font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var multiEditor: some View {
        Section("Dense subquery") {
            Picker("Vector field", selection: $vectorField) {
                ForEach(denseFields, id: \.name) { Text($0.name).tag($0.name) }
            }
            TextField(vectorPlaceholder, text: $vectorJSON)
                .font(.system(.body, design: .monospaced))
        }
        Section("Second subquery") {
            Picker("Second subquery", selection: $secondSubquery) {
                if !fullTextFields.isEmpty { Text("Full Text").tag(SecondSubquery.fullText) }
                if !sparseFields.isEmpty { Text("Sparse Float32").tag(SecondSubquery.sparse) }
            }
            .pickerStyle(.segmented)
            if secondSubquery == .fullText {
                Picker("Full-text field", selection: $fullTextField) {
                    ForEach(fullTextFields, id: \.name) { Text($0.name).tag($0.name) }
                }
                Picker("Expression", selection: $fullTextMode) {
                    Text("Match").tag(FullTextMode.match)
                    Text("Query").tag(FullTextMode.query)
                }
                TextField("Text", text: $fullText)
                Picker("Default operator", selection: $fullTextOperator) {
                    Text("OR").tag(FullTextOperator.or)
                    Text("AND").tag(FullTextOperator.and)
                }
            } else {
                Picker("Sparse field", selection: $sparseField) {
                    ForEach(sparseFields, id: \.name) { Text($0.name).tag($0.name) }
                }
                TextField(#"{"indices":[1,4],"values":[0.5,1.0]}"#, text: $sparseJSON)
                    .font(.system(.body, design: .monospaced))
                Text(
                    "Sparse indexes are disabled on Apple platforms; this subquery uses Zvec's brute-force sparse path."
                )
                .font(.caption).foregroundStyle(.secondary)
            }
        }
        Section("Reranker") {
            Picker("Mode", selection: $reranker) {
                Text("Reciprocal Rank Fusion").tag(RerankerMode.rrf)
                Text("Weighted").tag(RerankerMode.weighted)
            }
            if reranker == .weighted {
                HStack {
                    TextField("Dense weight", value: $firstWeight, format: .number)
                    TextField("Full-text weight", value: $secondWeight, format: .number)
                }
            }
        }
    }

    @ViewBuilder private var groupEditor: some View {
        vectorEditor
        Section("Grouping") {
            Picker("Group field", selection: $groupField) {
                ForEach(groupFields, id: \.name) { Text($0.name).tag($0.name) }
            }
            TextField("Group count", value: $groupCount, format: .number)
            TextField("Results per group", value: $groupTopK, format: .number)
        }
    }

    @ViewBuilder private var indexParameterEditor: some View {
        if let field = selectedVectorField {
            switch field.index {
            case .hnsw?: Stepper("HNSW efSearch: \(efSearch)", value: $efSearch, in: 1...100_000)
            case .ivf?:
                Stepper("IVF probes: \(probeCount)", value: $probeCount, in: 1...100_000)
                TextField("Scale factor", value: $scaleFactor, format: .number)
            case .flat?: TextField("Flat scale factor", value: $scaleFactor, format: .number)
            case .vamana?: Text("Vamana is unavailable on Apple platforms.").foregroundStyle(.secondary)
            default: Text("No vector index parameters for this field.").foregroundStyle(.secondary)
            }
            TextField("Radius (optional)", text: $radius)
            Toggle("Force linear search", isOn: $linearSearch)
            Toggle("Use refiner", isOn: $useRefiner)
        }
    }

    private var vectorPlaceholder: String {
        guard let field = selectedVectorField else { return "Canonical JSON vector" }
        if field.dataType == .vectorInt4 { return #"{"bytesBase64":"...","dimensions":128}"# }
        if field.dataType == .vectorBinary32 || field.dataType == .vectorBinary64 { return #""base64""# }
        return "[0.1, 0.2, ...] (\(field.dimensions) dimensions)"
    }

    private func setDefaults() {
        if vectorField.isEmpty { vectorField = denseFields.first?.name ?? "" }
        if fullTextField.isEmpty { fullTextField = fullTextFields.first?.name ?? "" }
        if sparseField.isEmpty { sparseField = sparseFields.first?.name ?? "" }
        if fullTextFields.isEmpty, !sparseFields.isEmpty { secondSubquery = .sparse }
        if groupField.isEmpty { groupField = groupFields.first?.name ?? "" }
    }

    private func run() {
        do {
            let normalizedFilter = filter.trimmingCharacters(in: .whitespacesAndNewlines)
            switch mode {
            case .vector:
                let query = try makeVectorQuery(filter: normalizedFilter)
                Task { await model.runQuery(id, query: query) }
            case .fullText:
                let query = try makeFullTextQuery(filter: normalizedFilter)
                Task { await model.runQuery(id, query: query) }
            case .multi:
                let query = try makeMultiQuery(filter: normalizedFilter)
                Task { await model.runQuery(id, query: query) }
            case .groupBy:
                let vector = try makeVectorQuery(filter: normalizedFilter)
                guard !groupField.isEmpty, groupCount > 0, groupTopK > 0 else { throw QueryEditorError.missingGroup }
                let query = GroupByVectorQuery(
                    vectorQuery: vector,
                    groupByField: groupField,
                    groupCount: groupCount,
                    groupTopK: groupTopK
                )
                Task { await model.runQuery(id, query: query) }
            }
            validationMessage = nil
        } catch { validationMessage = String(describing: error) }
    }

    private func export(_ format: ResultFileSaver.Format) {
        do {
            if mode == .groupBy {
                try ResultFileSaver.saveGroups(model.groupResults, schema: schema, format: format)
            } else {
                try ResultFileSaver.saveDocuments(
                    model.queryDocuments, schema: schema, format: format,
                    source: mode.rawValue, limitReached: false
                )
            }
        } catch { exportError = String(describing: error) }
    }

    private func makeVectorQuery(filter: String) throws -> VectorQuery {
        guard let field = selectedVectorField else { throw QueryEditorError.missingVectorField }
        let commonFilter = filter.isEmpty ? nil : filter
        if vectorSource == .documentID {
            guard !documentID.isEmpty else { throw QueryEditorError.missingDocumentID }
            return VectorQuery(
                field: field.name, documentID: documentID, topK: topK,
                filter: commonFilter, includeVector: includeVector,
                outputFields: outputFields.sorted(),
                indexParameters: try indexParameters(for: field)
            )
        }
        return VectorQuery(
            field: field.name,
            vector: try QueryInputParser.denseVector(vectorJSON, field: field),
            topK: topK,
            filter: commonFilter,
            includeVector: includeVector,
            outputFields: outputFields.sorted(),
            indexParameters: try indexParameters(for: field)
        )
    }

    private func makeFullTextQuery(filter: String) throws -> FullTextQuery {
        guard !fullTextField.isEmpty, !fullText.isEmpty else { throw QueryEditorError.missingFullText }
        let expression: FullTextExpression = fullTextMode == .match ? .match(fullText) : .query(fullText)
        return FullTextQuery(
            field: fullTextField, expression: expression, topK: topK,
            filter: filter.isEmpty ? nil : filter, includeVector: includeVector,
            outputFields: outputFields.sorted(), parameters: fullTextParameters
        )
    }

    private func makeMultiQuery(filter: String) throws -> MultiQuery {
        guard let field = selectedVectorField else { throw QueryEditorError.missingVectorField }
        let dense = try QueryInputParser.denseVector(vectorJSON, field: field)
        let second: SubQuery
        switch secondSubquery {
        case .fullText:
            guard !fullTextField.isEmpty, !fullText.isEmpty else { throw QueryEditorError.missingFullText }
            let expression: FullTextExpression = fullTextMode == .match ? .match(fullText) : .query(fullText)
            second = SubQuery(
                field: fullTextField, payload: .fullText(expression), topK: topK,
                fullTextParameters: fullTextParameters
            )
        case .sparse:
            guard let sparse = schema.field(named: sparseField) else { throw QueryEditorError.missingSparse }
            second = SubQuery(
                field: sparse.name,
                payload: .sparseFloat32(try QueryInputParser.sparseFloat32(sparseJSON, field: sparse)),
                topK: topK
            )
        }
        let queries = [
            SubQuery(
                field: field.name, payload: .dense(dense), topK: topK,
                indexParameters: try indexParameters(for: field)),
            second,
        ]
        let selectedReranker: Reranker =
            reranker == .rrf
            ? .reciprocalRankFusion()
            : .weighted([firstWeight, secondWeight])
        return MultiQuery(
            queries: queries, topK: topK, filter: filter.isEmpty ? nil : filter,
            includeVector: includeVector, outputFields: outputFields.sorted(),
            reranker: selectedReranker
        )
    }

    private var fullTextParameters: FullTextQueryParameters {
        FullTextQueryParameters(defaultOperator: fullTextOperator == .and ? .and : .or)
    }

    private func indexParameters(for field: FieldSchema) throws -> IndexQueryParameters? {
        let parsedRadius: Float?
        if radius.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parsedRadius = nil
        } else if let value = Float(radius) {
            parsedRadius = value
        } else {
            throw QueryEditorError.invalidRadius
        }
        return switch field.index {
        case .hnsw?:
            IndexQueryParameters.hnsw(
                HNSWQueryParameters(
                    efSearch: efSearch, radius: parsedRadius,
                    linearSearch: linearSearch, useRefiner: useRefiner))
        case .ivf?:
            IndexQueryParameters.ivf(
                IVFQueryParameters(
                    probeCount: probeCount, scaleFactor: scaleFactor, radius: parsedRadius,
                    linearSearch: linearSearch, useRefiner: useRefiner))
        case .flat?:
            IndexQueryParameters.flat(
                FlatQueryParameters(
                    scaleFactor: scaleFactor, radius: parsedRadius,
                    linearSearch: linearSearch, useRefiner: useRefiner))
        default: nil
        }
    }
}

private struct QueryDocumentTable: View {
    let documents: [Document]
    var body: some View {
        Table(documents) {
            TableColumn("ID") { Text($0.id) }
            TableColumn("Score") { Text($0.score.map { String(format: "%.5f", $0) } ?? "—") }
            TableColumn("Fields") { Text(DocumentDisplay.compactFields($0)).lineLimit(2) }
        }
    }
}

private struct GroupResultList: View {
    let groups: [GroupResult]
    var body: some View {
        List {
            ForEach(groups.indices, id: \.self) { index in
                GroupResultSection(group: groups[index])
            }
        }
    }
}

private struct GroupResultSection: View {
    let group: GroupResult
    var body: some View {
        Section("Group: \(group.value)") {
            ForEach(group.documents) { document in
                HStack {
                    Text(document.id)
                    Spacer()
                    Text(document.score.map { String($0) } ?? "—")
                    Text(DocumentDisplay.compactFields(document)).foregroundStyle(.secondary)
                }
            }
        }
    }
}

private enum QueryMode: String, CaseIterable {
    case vector, fullText, multi, groupBy
    var label: String {
        switch self {
        case .vector: "Vector";
        case .fullText: "Full Text";
        case .multi: "Multi";
        case .groupBy: "Group By"
        }
    }
}
private enum VectorSource: String { case vector, documentID }
private enum FullTextMode: String { case match, query }
private enum FullTextOperator: String { case and, or }
private enum RerankerMode: String { case rrf, weighted }
private enum SecondSubquery: String { case fullText, sparse }
private enum QueryEditorError: Error, CustomStringConvertible {
    case missingVectorField, missingDocumentID, missingFullText, missingSparse, missingGroup, invalidRadius
    var description: String {
        switch self {
        case .missingVectorField: "Choose a dense-vector field"
        case .missingDocumentID: "Enter a source document ID"
        case .missingFullText: "Choose a full-text field and enter an expression"
        case .missingSparse: "Choose a sparseVectorFloat32 field and enter a sparse vector"
        case .missingGroup: "Choose a group field and positive group limits"
        case .invalidRadius: "Radius must be a floating-point number"
        }
    }
}
