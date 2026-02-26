import XCTest
@testable import NWAsyncSocket

final class StreamBufferTests: XCTestCase {

    // MARK: - Basic operations

    func testEmptyBuffer() {
        let buf = StreamBuffer()
        XCTAssertTrue(buf.isEmpty)
        XCTAssertEqual(buf.count, 0)
    }

    func testAppendAndCount() {
        let buf = StreamBuffer()
        buf.append(Data([1, 2, 3]))
        XCTAssertFalse(buf.isEmpty)
        XCTAssertEqual(buf.count, 3)
    }

    func testReadAllData() {
        let buf = StreamBuffer()
        buf.append(Data([0xAA, 0xBB, 0xCC]))
        let result = buf.readAllData()
        XCTAssertEqual(result, Data([0xAA, 0xBB, 0xCC]))
        XCTAssertTrue(buf.isEmpty)
    }

    func testPeekDoesNotConsume() {
        let buf = StreamBuffer()
        buf.append(Data([1, 2, 3]))
        let peek = buf.peekAllData()
        XCTAssertEqual(peek, Data([1, 2, 3]))
        XCTAssertEqual(buf.count, 3) // Still there
    }

    func testReset() {
        let buf = StreamBuffer()
        buf.append(Data([1, 2, 3, 4, 5]))
        buf.reset()
        XCTAssertTrue(buf.isEmpty)
    }

    // MARK: - readData(toLength:)

    func testReadToLengthExact() {
        let buf = StreamBuffer()
        buf.append(Data([10, 20, 30, 40, 50]))
        let result = buf.readData(toLength: 3)
        XCTAssertEqual(result, Data([10, 20, 30]))
        XCTAssertEqual(buf.count, 2)
    }

    func testReadToLengthInsufficient() {
        let buf = StreamBuffer()
        buf.append(Data([10, 20]))
        let result = buf.readData(toLength: 5)
        XCTAssertNil(result)
        XCTAssertEqual(buf.count, 2) // Unchanged
    }

    func testReadToLengthMultipleCalls() {
        let buf = StreamBuffer()
        buf.append(Data([1, 2, 3, 4, 5, 6]))
        let first = buf.readData(toLength: 2)
        let second = buf.readData(toLength: 2)
        let third = buf.readData(toLength: 2)
        XCTAssertEqual(first, Data([1, 2]))
        XCTAssertEqual(second, Data([3, 4]))
        XCTAssertEqual(third, Data([5, 6]))
        XCTAssertTrue(buf.isEmpty)
    }

    // MARK: - readData(toDelimiter:)

    func testReadToDelimiterFound() {
        let buf = StreamBuffer()
        // "hello\nworld"
        buf.append("hello\nworld".data(using: .utf8)!)
        let delimiter = "\n".data(using: .utf8)!
        let result = buf.readData(toDelimiter: delimiter)
        XCTAssertEqual(String(data: result!, encoding: .utf8), "hello\n")
        XCTAssertEqual(String(data: buf.readAllData(), encoding: .utf8), "world")
    }

    func testReadToDelimiterNotFound() {
        let buf = StreamBuffer()
        buf.append("no newline here".data(using: .utf8)!)
        let delimiter = "\n".data(using: .utf8)!
        let result = buf.readData(toDelimiter: delimiter)
        XCTAssertNil(result)
        XCTAssertEqual(buf.count, 15) // Unchanged
    }

    func testReadToMultiByteDelimiter() {
        let buf = StreamBuffer()
        buf.append("data\r\nmore".data(using: .utf8)!)
        let delimiter = "\r\n".data(using: .utf8)!
        let result = buf.readData(toDelimiter: delimiter)
        XCTAssertEqual(String(data: result!, encoding: .utf8), "data\r\n")
    }

    // MARK: - Sticky packet simulation (粘包)

    func testStickyPacketReassembly() {
        // Simulate Linux server sending two messages in one TCP packet
        let buf = StreamBuffer()
        let combined = "data: {\"text\":\"hello\"}\n\ndata: {\"text\":\"world\"}\n\n"
        buf.append(combined.data(using: .utf8)!)

        let delimiter = "\n\n".data(using: .utf8)!

        // First message
        let msg1 = buf.readData(toDelimiter: delimiter)
        XCTAssertNotNil(msg1)
        XCTAssertEqual(String(data: msg1!, encoding: .utf8), "data: {\"text\":\"hello\"}\n\n")

        // Second message
        let msg2 = buf.readData(toDelimiter: delimiter)
        XCTAssertNotNil(msg2)
        XCTAssertEqual(String(data: msg2!, encoding: .utf8), "data: {\"text\":\"world\"}\n\n")

        XCTAssertTrue(buf.isEmpty)
    }

    // MARK: - Split packet simulation (拆包)

    func testSplitPacketReassembly() {
        // Simulate a message split across two TCP segments
        let buf = StreamBuffer()
        let delimiter = "\n\n".data(using: .utf8)!

        // First TCP segment: partial message
        buf.append("data: {\"text\":\"he".data(using: .utf8)!)
        let result1 = buf.readData(toDelimiter: delimiter)
        XCTAssertNil(result1) // Not complete yet

        // Second TCP segment: rest of message
        buf.append("llo\"}\n\n".data(using: .utf8)!)
        let result2 = buf.readData(toDelimiter: delimiter)
        XCTAssertNotNil(result2)
        XCTAssertEqual(String(data: result2!, encoding: .utf8), "data: {\"text\":\"hello\"}\n\n")
    }

    // MARK: - UTF-8 safety

    func testUTF8SafeCountWithASCII() {
        let data = "Hello".data(using: .utf8)!
        XCTAssertEqual(StreamBuffer.utf8SafeByteCount(data), 5)
    }

    func testUTF8SafeCountWithCompleteMultibyte() {
        // "你好" = 6 bytes in UTF-8
        let data = "你好".data(using: .utf8)!
        XCTAssertEqual(data.count, 6)
        XCTAssertEqual(StreamBuffer.utf8SafeByteCount(data), 6)
    }

    func testUTF8SafeCountWithIncompleteMultibyte() {
        // "你" = E4 BD A0 in UTF-8
        // Simulate receiving only the first 2 bytes of a 3-byte character
        let data = Data([0xE4, 0xBD])
        XCTAssertEqual(StreamBuffer.utf8SafeByteCount(data), 0)
    }

    func testUTF8SafeCountMixedASCIIAndIncomplete() {
        // "Hi" + first byte of a 3-byte UTF-8 char
        let data = Data([0x48, 0x69, 0xE4])
        XCTAssertEqual(StreamBuffer.utf8SafeByteCount(data), 2) // Only "Hi" is safe
    }

    func testUTF8SafeCountWith4ByteCharIncomplete() {
        // 😀 = F0 9F 98 80 in UTF-8
        // Send only 3 of 4 bytes
        let data = Data([0x48, 0x69, 0xF0, 0x9F, 0x98])
        XCTAssertEqual(StreamBuffer.utf8SafeByteCount(data), 2) // Only "Hi" is safe
    }

    func testUTF8SafeCountWith4ByteCharComplete() {
        // 😀 = F0 9F 98 80
        let data = Data([0x48, 0x69, 0xF0, 0x9F, 0x98, 0x80])
        XCTAssertEqual(StreamBuffer.utf8SafeByteCount(data), 6) // All safe
    }

    func testReadUTF8SafeString() {
        let buf = StreamBuffer()
        // "Hello" + first 2 bytes of "你" (E4 BD A0)
        buf.append(Data([0x48, 0x65, 0x6C, 0x6C, 0x6F, 0xE4, 0xBD]))
        let str = buf.readUTF8SafeString()
        XCTAssertEqual(str, "Hello")
        XCTAssertEqual(buf.count, 2) // Incomplete bytes remain
    }

    func testReadUTF8SafeStringCompleteCharLater() {
        let buf = StreamBuffer()
        // First chunk: "Hi" + partial 你
        buf.append(Data([0x48, 0x69, 0xE4, 0xBD]))
        let str1 = buf.readUTF8SafeString()
        XCTAssertEqual(str1, "Hi")

        // Second chunk: remaining byte of 你
        buf.append(Data([0xA0]))
        let str2 = buf.readUTF8SafeString()
        XCTAssertEqual(str2, "你")
        XCTAssertTrue(buf.isEmpty)
    }

    func testEmptyData() {
        XCTAssertEqual(StreamBuffer.utf8SafeByteCount(Data()), 0)
    }
}
