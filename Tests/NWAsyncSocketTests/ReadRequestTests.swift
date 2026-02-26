import XCTest
@testable import NWAsyncSocket

final class ReadRequestTests: XCTestCase {

    func testAvailableRequest() {
        let req = ReadRequest(type: .available, timeout: -1, tag: 0)
        if case .available = req.type {
            // OK
        } else {
            XCTFail("Expected .available type")
        }
        XCTAssertEqual(req.tag, 0)
        XCTAssertEqual(req.timeout, -1)
    }

    func testToLengthRequest() {
        let req = ReadRequest(type: .toLength(1024), timeout: 30, tag: 42)
        if case .toLength(let len) = req.type {
            XCTAssertEqual(len, 1024)
        } else {
            XCTFail("Expected .toLength type")
        }
        XCTAssertEqual(req.tag, 42)
        XCTAssertEqual(req.timeout, 30)
    }

    func testToDelimiterRequest() {
        let delimiter = "\n\n".data(using: .utf8)!
        let req = ReadRequest(type: .toDelimiter(delimiter), timeout: 10, tag: 7)
        if case .toDelimiter(let d) = req.type {
            XCTAssertEqual(d, delimiter)
        } else {
            XCTFail("Expected .toDelimiter type")
        }
        XCTAssertEqual(req.tag, 7)
    }
}
