import Foundation
import Zvec

public struct RuntimeConfigurationProfile: Codable, Sendable, Equatable {
    public var memoryLimitBytes: UInt64?
    public var logLevelRawValue: Int32?
    public var queryThreadCount: UInt32?
    public var optimizeThreadCount: UInt32?
    public var invertedToForwardScanRatio: Float?
    public var bruteForceByKeysRatio: Float?
    public var fullTextBruteForceByKeysRatio: Float?
    public var jiebaDictionaryPath: String?

    public init(
        memoryLimitBytes: UInt64? = nil,
        logLevel: LogLevel? = .warning,
        queryThreadCount: UInt32? = nil,
        optimizeThreadCount: UInt32? = nil,
        invertedToForwardScanRatio: Float? = nil,
        bruteForceByKeysRatio: Float? = nil,
        fullTextBruteForceByKeysRatio: Float? = nil,
        jiebaDictionaryPath: String? = nil
    ) {
        self.memoryLimitBytes = memoryLimitBytes
        logLevelRawValue = logLevel?.rawValue
        self.queryThreadCount = queryThreadCount
        self.optimizeThreadCount = optimizeThreadCount
        self.invertedToForwardScanRatio = invertedToForwardScanRatio
        self.bruteForceByKeysRatio = bruteForceByKeysRatio
        self.fullTextBruteForceByKeysRatio = fullTextBruteForceByKeysRatio
        self.jiebaDictionaryPath = jiebaDictionaryPath
    }

    public var configuration: Configuration {
        Configuration(
            memoryLimitBytes: memoryLimitBytes,
            log: logLevelRawValue.flatMap(LogLevel.init(rawValue:)).map { .console(level: $0) },
            queryThreadCount: queryThreadCount,
            optimizeThreadCount: optimizeThreadCount,
            invertedToForwardScanRatio: invertedToForwardScanRatio,
            bruteForceByKeysRatio: bruteForceByKeysRatio,
            fullTextBruteForceByKeysRatio: fullTextBruteForceByKeysRatio,
            jiebaDictionaryDirectory: jiebaDictionaryPath.map { URL(fileURLWithPath: $0, isDirectory: true) }
        )
    }
}

public struct RuntimeConfigurationStore: Sendable {
    public let fileURL: URL

    public init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultURL()
    }

    public func load() throws -> RuntimeConfigurationProfile {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return .init() }
        return try JSONDecoder().decode(RuntimeConfigurationProfile.self, from: Data(contentsOf: fileURL))
    }

    public func save(_ profile: RuntimeConfigurationProfile) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(profile).write(to: fileURL, options: .atomic)
    }

    private static func defaultURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appending(path: "ZvecStudio", directoryHint: .isDirectory)
            .appending(path: "runtime-configuration.json")
    }
}
