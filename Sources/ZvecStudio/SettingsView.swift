import AppKit
import SwiftUI
import Zvec
import ZvecStudioCore

struct SettingsView: View {
    @Bindable var model: StudioModel
    @State private var memoryLimitMB = ""
    @State private var queryThreads = ""
    @State private var optimizeThreads = ""
    @State private var logLevel: LogLevel = .warning
    @State private var loggingEnabled = true
    @State private var invertedRatio = ""
    @State private var bruteForceRatio = ""
    @State private var fullTextBruteForceRatio = ""
    @State private var jiebaPath = ""
    @State private var validationMessage: String?
    @State private var confirmingShutdown = false

    init(model: StudioModel) {
        self.model = model
        let profile = model.runtimeProfile
        _memoryLimitMB = State(initialValue: profile.memoryLimitBytes.map { String($0 / 1_048_576) } ?? "")
        _queryThreads = State(initialValue: profile.queryThreadCount.map(String.init) ?? "")
        _optimizeThreads = State(initialValue: profile.optimizeThreadCount.map(String.init) ?? "")
        _loggingEnabled = State(initialValue: profile.logLevelRawValue != nil)
        _logLevel = State(initialValue: profile.logLevelRawValue.flatMap(LogLevel.init(rawValue:)) ?? .warning)
        _invertedRatio = State(initialValue: profile.invertedToForwardScanRatio.map { String($0) } ?? "")
        _bruteForceRatio = State(initialValue: profile.bruteForceByKeysRatio.map { String($0) } ?? "")
        _fullTextBruteForceRatio = State(initialValue: profile.fullTextBruteForceByKeysRatio.map { String($0) } ?? "")
        _jiebaPath = State(initialValue: profile.jiebaDictionaryPath ?? "")
    }

    var body: some View {
        Form {
            Section("Runtime") {
                TextField("Memory limit (MB, optional)", text: $memoryLimitMB)
                TextField("Query threads (optional)", text: $queryThreads)
                TextField("Optimize threads (optional)", text: $optimizeThreads)
                Toggle("Console logging", isOn: $loggingEnabled)
                if loggingEnabled {
                    Picker("Log level", selection: $logLevel) {
                        ForEach(LogLevel.allCases, id: \.rawValue) {
                            Text(String(describing: $0)).tag($0)
                        }
                    }
                }
                TextField("Inverted-to-forward scan ratio (optional)", text: $invertedRatio)
                TextField("Brute-force by keys ratio (optional)", text: $bruteForceRatio)
                TextField("Full-text brute-force by keys ratio (optional)", text: $fullTextBruteForceRatio)
                LabeledContent("Jieba dictionary") {
                    HStack {
                        Text(jiebaPath.isEmpty ? "Bundled default" : jiebaPath).lineLimit(1)
                        Button("Choose…", action: chooseJieba)
                        if !jiebaPath.isEmpty { Button("Clear") { jiebaPath = "" } }
                    }
                }
            }
            Text("Runtime changes close all open collections when applied. Recent collections remain available.")
                .font(.caption).foregroundStyle(.secondary)
            if model.runtimeNeedsRestart {
                Label("Runtime restart required", systemImage: "arrow.clockwise.circle")
                    .foregroundStyle(.orange)
            }
            if let validationMessage { Text(validationMessage).foregroundStyle(.red) }
            HStack {
                Button("Shutdown Runtime", role: .destructive) { confirmingShutdown = true }
                    .disabled(!model.runtimeReady)
                Spacer()
                Button("Restart Runtime", action: restart)
                    .disabled(!model.runtimeReady)
            }
        }
        .padding()
        .frame(width: 620, height: 600)
        .onChange(of: memoryLimitMB) { model.markRuntimeNeedsRestart() }
        .onChange(of: queryThreads) { model.markRuntimeNeedsRestart() }
        .onChange(of: optimizeThreads) { model.markRuntimeNeedsRestart() }
        .onChange(of: logLevel) { model.markRuntimeNeedsRestart() }
        .onChange(of: loggingEnabled) { model.markRuntimeNeedsRestart() }
        .onChange(of: invertedRatio) { model.markRuntimeNeedsRestart() }
        .onChange(of: bruteForceRatio) { model.markRuntimeNeedsRestart() }
        .onChange(of: fullTextBruteForceRatio) { model.markRuntimeNeedsRestart() }
        .onChange(of: jiebaPath) { model.markRuntimeNeedsRestart() }
        .confirmationDialog(
            model.opened.isEmpty
                ? "Shutdown the Zvec runtime?"
                : "Shutdown requires closing \(model.opened.count) open collection(s). Continue?",
            isPresented: $confirmingShutdown,
            titleVisibility: .visible
        ) {
            Button("Close All and Shutdown", role: .destructive) {
                Task { await model.shutdownRuntime() }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func restart() {
        do {
            let memoryMB = try optionalUInt64(memoryLimitMB, name: "Memory limit")
            let query = try optionalUInt32(queryThreads, name: "Query threads")
            let optimize = try optionalUInt32(optimizeThreads, name: "Optimize threads")
            let profile = RuntimeConfigurationProfile(
                memoryLimitBytes: try memoryMB.map { try multiplied($0, by: 1_048_576) },
                logLevel: loggingEnabled ? logLevel : nil,
                queryThreadCount: query,
                optimizeThreadCount: optimize,
                invertedToForwardScanRatio: try optionalRatio(invertedRatio, name: "Inverted scan ratio"),
                bruteForceByKeysRatio: try optionalRatio(bruteForceRatio, name: "Brute-force ratio"),
                fullTextBruteForceByKeysRatio: try optionalRatio(
                    fullTextBruteForceRatio, name: "Full-text brute-force ratio"
                ),
                jiebaDictionaryPath: jiebaPath.isEmpty ? nil : jiebaPath
            )
            validationMessage = nil
            Task { await model.restartRuntime(profile: profile) }
        } catch { validationMessage = String(describing: error) }
    }

    private func optionalUInt64(_ text: String, name: String) throws -> UInt64? {
        guard !text.isEmpty else { return nil }
        guard let value = UInt64(text), value > 0 else { throw SettingsError.invalid(name) }
        return value
    }

    private func optionalUInt32(_ text: String, name: String) throws -> UInt32? {
        guard let value = try optionalUInt64(text, name: name) else { return nil }
        guard let result = UInt32(exactly: value) else { throw SettingsError.invalid(name) }
        return result
    }

    private func multiplied(_ value: UInt64, by multiplier: UInt64) throws -> UInt64 {
        let result = value.multipliedReportingOverflow(by: multiplier)
        guard !result.overflow else { throw SettingsError.invalid("Memory limit") }
        return result.partialValue
    }

    private func optionalRatio(_ text: String, name: String) throws -> Float? {
        guard !text.isEmpty else { return nil }
        guard let value = Float(text), value >= 0, value <= 1 else { throw SettingsError.invalid(name) }
        return value
    }

    private func chooseJieba() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        jiebaPath = url.standardizedFileURL.path
    }
}

private enum SettingsError: Error, CustomStringConvertible {
    case invalid(String)
    var description: String {
        switch self {
        case let .invalid(name): "\(name) must be a positive whole number in range"
        }
    }
}
