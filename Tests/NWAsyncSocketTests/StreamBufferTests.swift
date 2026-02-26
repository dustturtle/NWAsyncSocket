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

    // MARK: - Additional edge cases

    func testMultipleAppendsBeforeRead() {
        let buf = StreamBuffer()
        buf.append(Data([1, 2]))
        buf.append(Data([3, 4]))
        buf.append(Data([5, 6]))
        XCTAssertEqual(buf.count, 6)
        let result = buf.readData(toLength: 6)
        XCTAssertEqual(result, Data([1, 2, 3, 4, 5, 6]))
    }

    func testReadToLengthZero() {
        let buf = StreamBuffer()
        buf.append(Data([1, 2, 3]))
        let result = buf.readData(toLength: 0)
        XCTAssertEqual(result, Data())
        XCTAssertEqual(buf.count, 3)
    }

    func testReadToDelimiterAtStart() {
        let buf = StreamBuffer()
        buf.append("\nhello".data(using: .utf8)!)
        let delimiter = "\n".data(using: .utf8)!
        let result = buf.readData(toDelimiter: delimiter)
        XCTAssertEqual(String(data: result!, encoding: .utf8), "\n")
        XCTAssertEqual(String(data: buf.readAllData(), encoding: .utf8), "hello")
    }

    func testReadToDelimiterMultipleOccurrences() {
        let buf = StreamBuffer()
        buf.append("a\nb\nc\n".data(using: .utf8)!)
        let delimiter = "\n".data(using: .utf8)!

        let r1 = buf.readData(toDelimiter: delimiter)
        XCTAssertEqual(String(data: r1!, encoding: .utf8), "a\n")
        let r2 = buf.readData(toDelimiter: delimiter)
        XCTAssertEqual(String(data: r2!, encoding: .utf8), "b\n")
        let r3 = buf.readData(toDelimiter: delimiter)
        XCTAssertEqual(String(data: r3!, encoding: .utf8), "c\n")
        XCTAssertTrue(buf.isEmpty)
    }

    func testUTF8SafeWithOnlyContinuationBytes() {
        // All continuation bytes with no leading byte
        let data = Data([0x80, 0x80, 0x80])
        XCTAssertEqual(StreamBuffer.utf8SafeByteCount(data), 0)
    }

    func testUTF8SafeWithTwoByteCharComplete() {
        // é = C3 A9 in UTF-8 (2-byte char)
        let data = Data([0x48, 0x69, 0xC3, 0xA9]) // "Hié"
        XCTAssertEqual(StreamBuffer.utf8SafeByteCount(data), 4)
    }

    func testUTF8SafeWithTwoByteCharIncomplete() {
        // First byte of 2-byte char only
        let data = Data([0x48, 0x69, 0xC3]) // "Hi" + partial é
        XCTAssertEqual(StreamBuffer.utf8SafeByteCount(data), 2)
    }

    func testReadUTF8SafeStringEmptyBuffer() {
        let buf = StreamBuffer()
        XCTAssertNil(buf.readUTF8SafeString())
    }

    func testReadUTF8SafeStringAllIncomplete() {
        let buf = StreamBuffer()
        // Only continuation bytes - no valid UTF-8
        buf.append(Data([0x80, 0x80]))
        XCTAssertNil(buf.readUTF8SafeString())
        XCTAssertEqual(buf.count, 2) // Data preserved
    }

    func testLargeDataAppendAndRead() {
        let buf = StreamBuffer()
        let largeData = Data(repeating: 0x41, count: 100000) // 100KB of 'A'
        buf.append(largeData)
        XCTAssertEqual(buf.count, 100000)
        let result = buf.readData(toLength: 100000)
        XCTAssertEqual(result?.count, 100000)
        XCTAssertTrue(buf.isEmpty)
    }

    func testMixedReadOperations() {
        let buf = StreamBuffer()
        buf.append("HEADER\nBODY_12345END".data(using: .utf8)!)

        // First: read to delimiter
        let header = buf.readData(toDelimiter: "\n".data(using: .utf8)!)
        XCTAssertEqual(String(data: header!, encoding: .utf8), "HEADER\n")

        // Then: read to length
        let body = buf.readData(toLength: 9)
        XCTAssertEqual(String(data: body!, encoding: .utf8), "BODY_1234")

        // Then: read remaining
        let rest = buf.readAllData()
        XCTAssertEqual(String(data: rest, encoding: .utf8), "5END")
    }
}
