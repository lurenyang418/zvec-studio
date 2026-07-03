import AppKit
import SwiftUI
import Zvec
import ZvecStudioCore

struct SettingsView: View {
    private let contentWidth: CGFloat = 680

    @Bindable var model: StudioModel
    @AppStorage(AppLanguage.defaultsKey) private var appLanguage = AppLanguage.system
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
        _fullTextBruteForceRatio = State(
            initialValue: profile.fullTextBruteForceByKeysRatio.map { String($0) } ?? ""
        )
        _jiebaPath = State(initialValue: profile.jiebaDictionaryPath ?? "")
    }

    var body: some View {
        runtimePane
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .frame(minWidth: 760, minHeight: 560)
            .onChange(of: memoryLimitMB) { model.markRuntimeNeedsRestart() }
            .onChange(of: queryThreads) { model.markRuntimeNeedsRestart() }
            .onChange(of: optimizeThreads) { model.markRuntimeNeedsRestart() }
            .onChange(of: logLevel) { model.markRuntimeNeedsRestart() }
            .onChange(of: loggingEnabled) { model.markRuntimeNeedsRestart() }
            .onChange(of: invertedRatio) { model.markRuntimeNeedsRestart() }
            .onChange(of: bruteForceRatio) { model.markRuntimeNeedsRestart() }
            .onChange(of: fullTextBruteForceRatio) { model.markRuntimeNeedsRestart() }
            .onChange(of: jiebaPath) { model.markRuntimeNeedsRestart() }
            .confirmationDialog(shutdownPrompt, isPresented: $confirmingShutdown, titleVisibility: .visible) {
                Button("Close All and Shutdown", role: .destructive) {
                    Task { await model.shutdownRuntime() }
                }
                Button("Cancel", role: .cancel) {}
            }
    }

    private var runtimePane: some View {
        VStack(alignment: .leading, spacing: 18) {
            paneTitle("Runtime", subtitle: "Configure memory, concurrency, logging, and search behavior.")
                .frame(width: contentWidth, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 28)
                .padding(.top, 28)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    settingsGroup("Resources") {
                        settingField("Memory limit", hint: "MB · Optional", text: $memoryLimitMB)
                        settingField("Query threads", hint: "Optional", text: $queryThreads)
                        settingField("Optimize threads", hint: "Optional", text: $optimizeThreads)
                    }

                    settingsGroup("Logging") {
                        Toggle("Enable console logging", isOn: $loggingEnabled)
                        if loggingEnabled {
                            HStack(spacing: 12) {
                                Text("Log level")
                                    .frame(width: 250, alignment: .leading)
                                Picker("Log level", selection: $logLevel) {
                                    ForEach(LogLevel.allCases, id: \.rawValue) {
                                        Text(String(describing: $0)).tag($0)
                                    }
                                }
                                .labelsHidden()
                                .frame(width: 180)
                                Spacer()
                            }
                        }
                    }

                    settingsGroup("Search thresholds") {
                        settingField("Inverted-to-forward scan ratio", hint: "0–1 · Optional", text: $invertedRatio)
                        settingField("Brute-force by keys ratio", hint: "0–1 · Optional", text: $bruteForceRatio)
                        settingField(
                            "Full-text brute-force by keys ratio", hint: "0–1 · Optional",
                            text: $fullTextBruteForceRatio
                        )
                    }

                    settingsGroup("Chinese tokenizer") {
                        HStack(spacing: 12) {
                            Text("Jieba dictionary")
                                .frame(width: 250, alignment: .leading)
                            Group {
                                if jiebaPath.isEmpty { Text("Bundled default") } else { Text(jiebaPath) }
                            }
                            .foregroundStyle(jiebaPath.isEmpty ? .secondary : .primary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            Button("Choose…", action: chooseJieba)
                            if !jiebaPath.isEmpty { Button("Clear") { jiebaPath = "" } }
                            Spacer()
                        }
                    }
                }
                .frame(width: contentWidth)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 28)
            }

            Divider()
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    if model.runtimeNeedsRestart {
                        Label("Unsaved runtime changes", systemImage: "arrow.clockwise.circle")
                            .foregroundStyle(.orange)
                    }
                    Text("Restarting closes open collections; recent collections remain available.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Shut Down…", role: .destructive) { confirmingShutdown = true }
                    .disabled(!model.runtimeReady)
                Button("Apply and Restart", action: restart)
                    .buttonStyle(.borderedProminent)
                    .disabled(!model.runtimeReady || !model.runtimeNeedsRestart)
            }
            .frame(width: contentWidth)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 28)
            if let validationMessage {
                Text(validationMessage).font(.caption).foregroundStyle(.red)
                    .frame(width: contentWidth, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 28)
            }
        }
        .padding(.bottom, 28)
    }

    private func paneTitle(_ title: LocalizedStringKey, subtitle: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.title2).bold()
            Text(subtitle).foregroundStyle(.secondary)
        }
    }

    private func settingsGroup<Content: View>(
        _ title: LocalizedStringKey, @ViewBuilder content: () -> Content
    ) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) { content() }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
        } label: {
            Text(title).font(.headline)
        }
        .frame(width: contentWidth, alignment: .leading)
    }

    private func settingField(
        _ title: LocalizedStringKey, hint: LocalizedStringKey, text: Binding<String>
    ) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .frame(width: 250, alignment: .leading)
            TextField("", text: text)
                .textFieldStyle(.roundedBorder)
                .frame(width: 180)
            Text(hint)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 105, alignment: .leading)
            Spacer()
        }
    }

    private var shutdownPrompt: String {
        if model.opened.isEmpty {
            return String(localized: "Shutdown the Zvec runtime?", locale: appLanguage.locale)
        }
        return String(
            localized: "Shutdown requires closing \(model.opened.count) open collection(s). Continue?",
            locale: appLanguage.locale
        )
    }

    private func restart() {
        do {
            let memoryMB = try optionalUInt64(
                memoryLimitMB, name: String(localized: "Memory limit", locale: appLanguage.locale)
            )
            let query = try optionalUInt32(
                queryThreads, name: String(localized: "Query threads", locale: appLanguage.locale)
            )
            let optimize = try optionalUInt32(
                optimizeThreads, name: String(localized: "Optimize threads", locale: appLanguage.locale)
            )
            let profile = RuntimeConfigurationProfile(
                memoryLimitBytes: try memoryMB.map { try multiplied($0, by: 1_048_576) },
                logLevel: loggingEnabled ? logLevel : nil,
                queryThreadCount: query,
                optimizeThreadCount: optimize,
                invertedToForwardScanRatio: try optionalRatio(
                    invertedRatio, name: String(localized: "Inverted scan ratio", locale: appLanguage.locale)
                ),
                bruteForceByKeysRatio: try optionalRatio(
                    bruteForceRatio, name: String(localized: "Brute-force ratio", locale: appLanguage.locale)
                ),
                fullTextBruteForceByKeysRatio: try optionalRatio(
                    fullTextBruteForceRatio,
                    name: String(localized: "Full-text brute-force ratio", locale: appLanguage.locale)
                ),
                jiebaDictionaryPath: jiebaPath.isEmpty ? nil : jiebaPath
            )
            validationMessage = nil
            Task { await model.restartRuntime(profile: profile) }
        } catch { validationMessage = String(describing: error) }
    }

    private func optionalUInt64(_ text: String, name: String) throws -> UInt64? {
        guard !text.isEmpty else { return nil }
        guard let value = UInt64(text), value > 0 else {
            throw SettingsError.invalid(name, locale: appLanguage.locale)
        }
        return value
    }

    private func optionalUInt32(_ text: String, name: String) throws -> UInt32? {
        guard let value = try optionalUInt64(text, name: name) else { return nil }
        guard let result = UInt32(exactly: value) else {
            throw SettingsError.invalid(name, locale: appLanguage.locale)
        }
        return result
    }

    private func multiplied(_ value: UInt64, by multiplier: UInt64) throws -> UInt64 {
        let result = value.multipliedReportingOverflow(by: multiplier)
        guard !result.overflow else {
            throw SettingsError.invalid(
                String(localized: "Memory limit", locale: appLanguage.locale), locale: appLanguage.locale
            )
        }
        return result.partialValue
    }

    private func optionalRatio(_ text: String, name: String) throws -> Float? {
        guard !text.isEmpty else { return nil }
        guard let value = Float(text), value >= 0, value <= 1 else {
            throw SettingsError.invalidRatio(name, locale: appLanguage.locale)
        }
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
    case invalid(String, locale: Locale)
    case invalidRatio(String, locale: Locale)

    var description: String {
        switch self {
        case let .invalid(name, locale):
            String(
                format: String(
                    localized: "%@ must be a positive whole number in range", locale: locale
                ),
                name
            )
        case let .invalidRatio(name, locale):
            String(
                format: String(localized: "%@ must be a number from 0 to 1", locale: locale),
                name
            )
        }
    }
}
