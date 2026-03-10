import XCTest
@testable import NWAsyncSocket

final class ChunkedDecoderTests: XCTestCase {

    // MARK: - Basic decoding

    func testSingleChunk() {
        let decoder = ChunkedDecoder()
        // "Hello" is 5 bytes → hex "5"
        let input = "5\r\nHello\r\n0\r\n\r\n".data(using: .utf8)!
        let output = decoder.decode(input)
        XCTAssertEqual(String(data: output, encoding: .utf8), "Hello")
        XCTAssertTrue(decoder.isComplete)
    }

    func testMultipleChunks() {
        let decoder = ChunkedDecoder()
        let input = "5\r\nHello\r\n6\r\n World\r\n0\r\n\r\n".data(using: .utf8)!
        let output = decoder.decode(input)
        XCTAssertEqual(String(data: output, encoding: .utf8), "Hello World")
        XCTAssertTrue(decoder.isComplete)
    }

    func testEmptyChunk() {
        let decoder = ChunkedDecoder()
        let input = "0\r\n\r\n".data(using: .utf8)!
        let output = decoder.decode(input)
        XCTAssertEqual(output.count, 0)
        XCTAssertTrue(decoder.isComplete)
    }

    // MARK: - Incremental / split delivery

    func testChunkSplitAcrossSegments() {
        let decoder = ChunkedDecoder()

        // First TCP segment: partial size line
        let out1 = decoder.decode("5\r\nHe".data(using: .utf8)!)
        XCTAssertEqual(String(data: out1, encoding: .utf8), "He")
        XCTAssertFalse(decoder.isComplete)

        // Second TCP segment: rest of data + trailer + final chunk
        let out2 = decoder.decode("llo\r\n0\r\n\r\n".data(using: .utf8)!)
        XCTAssertEqual(String(data: out2, encoding: .utf8), "llo")
        XCTAssertTrue(decoder.isComplete)
    }

    func testSizeLineSplitAcrossSegments() {
        let decoder = ChunkedDecoder()

        // Hex size line split in the middle
        let out1 = decoder.decode("1".data(using: .utf8)!)
        XCTAssertEqual(out1.count, 0) // No CRLF yet

        let out2 = decoder.decode("0\r\n".data(using: .utf8)!)
        // "10" hex = 16 bytes → need more data
        XCTAssertEqual(out2.count, 0)

        // Provide 16 bytes of data
        let payload = String(repeating: "A", count: 16)
        let out3 = decoder.decode("\(payload)\r\n0\r\n\r\n".data(using: .utf8)!)
        XCTAssertEqual(String(data: out3, encoding: .utf8), payload)
        XCTAssertTrue(decoder.isComplete)
    }

    func testTrailerSplitAcrossSegments() {
        let decoder = ChunkedDecoder()

        // Send complete chunk data but split the \r\n trailer
        let out1 = decoder.decode("3\r\nABC".data(using: .utf8)!)
        XCTAssertEqual(String(data: out1, encoding: .utf8), "ABC")

        // Only \r arrives
        let out2 = decoder.decode("\r".data(using: .utf8)!)
        XCTAssertEqual(out2.count, 0)

        // \n completes the trailer
        let out3 = decoder.decode("\n0\r\n\r\n".data(using: .utf8)!)
        XCTAssertEqual(out3.count, 0) // No more data
        XCTAssertTrue(decoder.isComplete)
    }

    // MARK: - SSE over chunked encoding

    func testSSEDataInChunkedEncoding() {
        let decoder = ChunkedDecoder()
        let parser = SSEParser()

        // SSE event wrapped in chunked encoding
        let ssePayload = "data: hello\n\n"
        let hexLen = String(ssePayload.utf8.count, radix: 16)
        let chunked = "\(hexLen)\r\n\(ssePayload)\r\n0\r\n\r\n".data(using: .utf8)!

        let decoded = decoder.decode(chunked)
        let events = parser.parse(decoded)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].data, "hello")
    }

    func testMultipleSSEEventsInMultipleChunks() {
        let decoder = ChunkedDecoder()
        let parser = SSEParser()

        // First chunk: one SSE event
        let sse1 = "data: first\n\n"
        let hex1 = String(sse1.utf8.count, radix: 16)
        let chunk1 = "\(hex1)\r\n\(sse1)\r\n".data(using: .utf8)!

        let decoded1 = decoder.decode(chunk1)
        var events = parser.parse(decoded1)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].data, "first")

        // Second chunk: another SSE event
        let sse2 = "data: second\n\n"
        let hex2 = String(sse2.utf8.count, radix: 16)
        let chunk2 = "\(hex2)\r\n\(sse2)\r\n0\r\n\r\n".data(using: .utf8)!

        let decoded2 = decoder.decode(chunk2)
        events = parser.parse(decoded2)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].data, "second")
    }

    // MARK: - Chunk extensions

    func testChunkExtensionIgnored() {
        let decoder = ChunkedDecoder()
        // Chunk extension after size (separated by ';')
        let input = "5;ext=val\r\nHello\r\n0\r\n\r\n".data(using: .utf8)!
        let output = decoder.decode(input)
        XCTAssertEqual(String(data: output, encoding: .utf8), "Hello")
        XCTAssertTrue(decoder.isComplete)
    }

    // MARK: - Uppercase hex

    func testUppercaseHexSize() {
        let decoder = ChunkedDecoder()
        // "1A" hex = 26 bytes
        let payload = String(repeating: "Z", count: 26)
        let input = "1A\r\n\(payload)\r\n0\r\n\r\n".data(using: .utf8)!
        let output = decoder.decode(input)
        XCTAssertEqual(String(data: output, encoding: .utf8), payload)
    }

    func testLowercaseHexSize() {
        let decoder = ChunkedDecoder()
        let payload = String(repeating: "z", count: 26)
        let input = "1a\r\n\(payload)\r\n0\r\n\r\n".data(using: .utf8)!
        let output = decoder.decode(input)
        XCTAssertEqual(String(data: output, encoding: .utf8), payload)
    }

    // MARK: - Reset

    func testReset() {
        let decoder = ChunkedDecoder()
        _ = decoder.decode("5\r\nHello\r\n0\r\n\r\n".data(using: .utf8)!)
        XCTAssertTrue(decoder.isComplete)

        decoder.reset()
        XCTAssertFalse(decoder.isComplete)

        let output = decoder.decode("3\r\nNew\r\n0\r\n\r\n".data(using: .utf8)!)
        XCTAssertEqual(String(data: output, encoding: .utf8), "New")
        XCTAssertTrue(decoder.isComplete)
    }

    // MARK: - Empty decode

    func testDecodeEmptyData() {
        let decoder = ChunkedDecoder()
        let output = decoder.decode(Data())
        XCTAssertEqual(output.count, 0)
        XCTAssertFalse(decoder.isComplete)
    }

    // MARK: - Large chunk

    func testLargeChunk() {
        let decoder = ChunkedDecoder()
        let size = 10000
        let payload = String(repeating: "X", count: size)
        let hexSize = String(size, radix: 16)
        let input = "\(hexSize)\r\n\(payload)\r\n0\r\n\r\n".data(using: .utf8)!
        let output = decoder.decode(input)
        XCTAssertEqual(output.count, size)
        XCTAssertTrue(decoder.isComplete)
    }

    // MARK: - Byte-by-byte delivery

    func testByteByteFeed() {
        let decoder = ChunkedDecoder()
        let input = "5\r\nHello\r\n0\r\n\r\n"
        let inputData = input.data(using: .utf8)!
        var accumulated = Data()

        for i in 0..<inputData.count {
            let byte = Data([inputData[inputData.startIndex + i]])
            accumulated.append(decoder.decode(byte))
        }

        XCTAssertEqual(String(data: accumulated, encoding: .utf8), "Hello")
        XCTAssertTrue(decoder.isComplete)
    }

    // MARK: - Data after complete is ignored

    func testDataAfterCompleteIsIgnored() {
        let decoder = ChunkedDecoder()
        _ = decoder.decode("0\r\n\r\n".data(using: .utf8)!)
        XCTAssertTrue(decoder.isComplete)

        let output = decoder.decode("extra data".data(using: .utf8)!)
        XCTAssertEqual(output.count, 0)
    }
}
