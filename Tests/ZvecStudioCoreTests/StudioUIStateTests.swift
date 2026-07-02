import XCTest
@testable import ZvecStudioCore

final class StudioUIStateTests: XCTestCase {
    func testLoadingCompletionFailureAndCancellation() {
        var state = StudioUIState()
        state.begin("Browse")
        XCTAssertTrue(state.isLoading)
        state.complete("Browse")
        XCTAssertEqual(state.phase, .completed(operation: "Browse"))
        XCTAssertFalse(state.isLoading)
        state.fail("Open", error: TestError.example)
        XCTAssertEqual(state.phase, .failed(operation: "Open", message: "example"))
        state.cancel("Import")
        XCTAssertEqual(state.phase, .cancelled(operation: "Import"))
    }

    func testCollectionSwitchClearsLimitReached() {
        var state = StudioUIState()
        let first = CollectionID(url: URL(fileURLWithPath: "/tmp/first"))
        let second = CollectionID(url: URL(fileURLWithPath: "/tmp/second"))
        state.select(first)
        state.setBrowseLimitReached(true)
        XCTAssertTrue(state.browseLimitReached)
        state.select(second)
        XCTAssertEqual(state.selectedCollection, second)
        XCTAssertFalse(state.browseLimitReached)
    }

    private enum TestError: Error, CustomStringConvertible {
        case example
        var description: String { "example" }
    }
}
