import XCTest
import Zvec
@testable import ZvecStudioCore

final class QueryInputParserTests: XCTestCase {
    func testDenseVectorParsingUsesSchemaDimensionsAndType() throws {
        let field = try FieldSchema("embedding", type: .vectorFloat32, dimensions: 3)
        XCTAssertEqual(try QueryInputParser.denseVector("[1,2,3]", field: field), .float32([1, 2, 3]))
        XCTAssertThrowsError(try QueryInputParser.denseVector("[1,2]", field: field))
    }

    func testSparseParsingRequiresStrictlyIncreasingIndices() throws {
        let field = try FieldSchema("sparse", type: .sparseVectorFloat32)
        let input = #"{"indices":[1,4],"values":[0.5,1]}"#
        XCTAssertEqual(
            try QueryInputParser.sparseFloat32(input, field: field),
            try SparseVector(indices: [1, 4], values: [0.5, 1])
        )
        XCTAssertThrowsError(
            try QueryInputParser.sparseFloat32(#"{"indices":[4,1],"values":[1,2]}"#, field: field)
        )
    }
}
