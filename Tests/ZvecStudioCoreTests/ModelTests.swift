import XCTest
import Zvec
@testable import ZvecStudioCore

final class ModelTests: XCTestCase {
    func testErrorPresentationRetainsStructuredZvecErrorAndContext() {
        let native = ZvecError(code: .invalidArgument, message: "bad filter")
        let presentation = StudioErrorPresentation(
            operation: "Browse", collectionPath: "/tmp/example", underlying: native
        )
        XCTAssertEqual(presentation.zvecError, native)
        XCTAssertTrue(presentation.message.contains("Browse"))
        XCTAssertTrue(presentation.message.contains("/tmp/example"))
    }
}
