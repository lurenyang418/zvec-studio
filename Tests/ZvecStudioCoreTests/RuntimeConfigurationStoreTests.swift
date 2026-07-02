import Foundation
import XCTest
import Zvec
@testable import ZvecStudioCore

final class RuntimeConfigurationStoreTests: XCTestCase {
    func testProfileRoundTripsAndBuildsConfiguration() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "zvec-settings-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = RuntimeConfigurationStore(fileURL: root.appending(path: "settings.json"))
        let profile = RuntimeConfigurationProfile(
            memoryLimitBytes: 512 * 1_048_576,
            logLevel: .info,
            queryThreadCount: 2,
            optimizeThreadCount: 1,
            invertedToForwardScanRatio: 0.2,
            bruteForceByKeysRatio: 0.3,
            fullTextBruteForceByKeysRatio: 0.4,
            jiebaDictionaryPath: "/tmp/jieba"
        )
        try store.save(profile)
        let loaded = try store.load()
        XCTAssertEqual(loaded, profile)
        XCTAssertEqual(loaded.configuration.memoryLimitBytes, 512 * 1_048_576)
        XCTAssertEqual(loaded.configuration.queryThreadCount, 2)
        XCTAssertEqual(loaded.configuration.jiebaDictionaryDirectory?.path, "/tmp/jieba")
    }
}
