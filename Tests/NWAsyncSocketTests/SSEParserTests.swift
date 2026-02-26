import XCTest
@testable import NWAsyncSocket

final class SSEParserTests: XCTestCase {

    // MARK: - Basic parsing

    func testSingleEvent() {
        let parser = SSEParser()
        let input = "data: hello\n\n"
        let events = parser.parse(input)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].data, "hello")
        XCTAssertEqual(events[0].event, "message")
    }

    func testEventWithType() {
        let parser = SSEParser()
        let input = "event: update\ndata: world\n\n"
        let events = parser.parse(input)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].event, "update")
        XCTAssertEqual(events[0].data, "world")
    }

    func testMultipleDataLines() {
        let parser = SSEParser()
        let input = "data: line1\ndata: line2\ndata: line3\n\n"
        let events = parser.parse(input)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].data, "line1\nline2\nline3")
    }

    func testEventWithId() {
        let parser = SSEParser()
        let input = "id: 42\ndata: payload\n\n"
        let events = parser.parse(input)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].id, "42")
        XCTAssertEqual(events[0].data, "payload")
        XCTAssertEqual(parser.lastEventId, "42")
    }

    func testEventWithRetry() {
        let parser = SSEParser()
        let input = "retry: 3000\ndata: reconnect test\n\n"
        let events = parser.parse(input)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].retry, 3000)
    }

    // MARK: - Multiple events (sticky packet / 粘包)

    func testMultipleEventsInOneChunk() {
        let parser = SSEParser()
        let input = "data: first\n\ndata: second\n\ndata: third\n\n"
        let events = parser.parse(input)
        XCTAssertEqual(events.count, 3)
        XCTAssertEqual(events[0].data, "first")
        XCTAssertEqual(events[1].data, "second")
        XCTAssertEqual(events[2].data, "third")
    }

    // MARK: - Split packet (拆包)

    func testSplitAcrossChunks() {
        let parser = SSEParser()

        // First chunk: partial event
        let events1 = parser.parse("data: hel")
        XCTAssertEqual(events1.count, 0) // No complete event yet

        // Second chunk: rest of event
        let events2 = parser.parse("lo\n\n")
        XCTAssertEqual(events2.count, 1)
        XCTAssertEqual(events2[0].data, "hello")
    }

    func testSplitInMiddleOfField() {
        let parser = SSEParser()

        let events1 = parser.parse("dat")
        XCTAssertEqual(events1.count, 0)

        let events2 = parser.parse("a: content\n\n")
        XCTAssertEqual(events2.count, 1)
        XCTAssertEqual(events2[0].data, "content")
    }

    func testSplitAtNewline() {
        let parser = SSEParser()

        let events1 = parser.parse("data: test\n")
        XCTAssertEqual(events1.count, 0) // Need empty line to dispatch

        let events2 = parser.parse("\n")
        XCTAssertEqual(events2.count, 1)
        XCTAssertEqual(events2[0].data, "test")
    }

    // MARK: - Comments

    func testCommentsIgnored() {
        let parser = SSEParser()
        let input = ": this is a comment\ndata: real data\n\n"
        let events = parser.parse(input)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].data, "real data")
    }

    // MARK: - CRLF handling

    func testCRLFLineEndings() {
        let parser = SSEParser()
        let input = "data: crlf test\r\n\r\n"
        let events = parser.parse(input)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].data, "crlf test")
    }

    func testCROnlyLineEndings() {
        let parser = SSEParser()
        let input = "data: cr test\r\r"
        let events = parser.parse(input)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].data, "cr test")
    }

    // MARK: - Empty data dispatch rule

    func testEmptyLineWithoutDataDoesNotDispatch() {
        let parser = SSEParser()
        // Two empty lines with no data fields should not produce events
        let events = parser.parse("\n\n")
        XCTAssertEqual(events.count, 0)
    }

    func testEventWithEmptyData() {
        let parser = SSEParser()
        let input = "data:\n\n"
        let events = parser.parse(input)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].data, "")
    }

    // MARK: - LLM streaming simulation

    func testLLMStreamingSSE() {
        let parser = SSEParser()

        // Simulate a streaming LLM response arriving in multiple TCP segments
        var allEvents: [SSEEvent] = []

        // Segment 1: Multiple complete SSE events packed together
        let seg1 = "data: {\"choices\":[{\"delta\":{\"content\":\"Hello\"}}]}\n\ndata: {\"choices\":[{\"delta\":{\"content\":\" world\"}}]}\n\n"
        allEvents.append(contentsOf: parser.parse(seg1))

        // Segment 2: Split event
        let seg2 = "data: {\"choices\":[{\"delta\":{\"conte"
        allEvents.append(contentsOf: parser.parse(seg2))

        // Segment 3: Rest of split event
        let seg3 = "nt\":\"!\"}}]}\n\n"
        allEvents.append(contentsOf: parser.parse(seg3))

        // Segment 4: Done marker
        let seg4 = "data: [DONE]\n\n"
        allEvents.append(contentsOf: parser.parse(seg4))

        XCTAssertEqual(allEvents.count, 4)
        XCTAssertEqual(allEvents[0].data, "{\"choices\":[{\"delta\":{\"content\":\"Hello\"}}]}")
        XCTAssertEqual(allEvents[1].data, "{\"choices\":[{\"delta\":{\"content\":\" world\"}}]}")
        XCTAssertEqual(allEvents[2].data, "{\"choices\":[{\"delta\":{\"content\":\"!\"}}]}")
        XCTAssertEqual(allEvents[3].data, "[DONE]")
    }

    // MARK: - Unknown fields

    func testUnknownFieldsIgnored() {
        let parser = SSEParser()
        let input = "foo: bar\ndata: actual\n\n"
        let events = parser.parse(input)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].data, "actual")
    }

    // MARK: - No colon line

    func testFieldWithoutValue() {
        let parser = SSEParser()
        let input = "data\n\n"
        let events = parser.parse(input)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].data, "")
    }

    // MARK: - Data via Data type

    func testParseFromData() {
        let parser = SSEParser()
        let input = "data: binary test\n\n".data(using: .utf8)!
        let events = parser.parse(input)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].data, "binary test")
    }

    // MARK: - Reset

    func testReset() {
        let parser = SSEParser()
        _ = parser.parse("data: partial")
        parser.reset()

        let events = parser.parse("data: fresh\n\n")
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].data, "fresh")
    }

    // MARK: - Id with null character

    func testIdWithNullIsIgnored() {
        let parser = SSEParser()
        let input = "id: test\0value\ndata: payload\n\n"
        let events = parser.parse(input)
        XCTAssertEqual(events.count, 1)
        XCTAssertNil(events[0].id)
    }

    // MARK: - Retry with non-integer

    func testRetryWithNonInteger() {
        let parser = SSEParser()
        let input = "retry: abc\ndata: test\n\n"
        let events = parser.parse(input)
        XCTAssertEqual(events.count, 1)
        XCTAssertNil(events[0].retry)
    }

    // MARK: - Space after colon

    func testSpaceAfterColon() {
        let parser = SSEParser()
        let input1 = "data: with space\n\n"
        let events1 = parser.parse(input1)
        XCTAssertEqual(events1[0].data, "with space")

        let input2 = "data:without space\n\n"
        let events2 = parser.parse(input2)
        XCTAssertEqual(events2[0].data, "without space")

        let input3 = "data:  two spaces\n\n"
        let events3 = parser.parse(input3)
        XCTAssertEqual(events3[0].data, " two spaces") // Only first space stripped
    }

    // MARK: - Additional edge cases

    func testMultipleEventsWithDifferentTypes() {
        let parser = SSEParser()
        let input = "event: start\ndata: begin\n\nevent: progress\ndata: 50%\n\nevent: end\ndata: done\n\n"
        let events = parser.parse(input)
        XCTAssertEqual(events.count, 3)
        XCTAssertEqual(events[0].event, "start")
        XCTAssertEqual(events[0].data, "begin")
        XCTAssertEqual(events[1].event, "progress")
        XCTAssertEqual(events[1].data, "50%")
        XCTAssertEqual(events[2].event, "end")
        XCTAssertEqual(events[2].data, "done")
    }

    func testEventTypeResetsToDefault() {
        let parser = SSEParser()
        // First event has custom type
        let events1 = parser.parse("event: custom\ndata: first\n\n")
        XCTAssertEqual(events1[0].event, "custom")
        // Second event should default back to "message"
        let events2 = parser.parse("data: second\n\n")
        XCTAssertEqual(events2[0].event, "message")
    }

    func testLastEventIdPersists() {
        let parser = SSEParser()
        _ = parser.parse("id: 1\ndata: first\n\n")
        XCTAssertEqual(parser.lastEventId, "1")
        // Event without id should not change lastEventId
        _ = parser.parse("data: second\n\n")
        XCTAssertEqual(parser.lastEventId, "1")
        // New id should update
        _ = parser.parse("id: 2\ndata: third\n\n")
        XCTAssertEqual(parser.lastEventId, "2")
    }

    func testConsecutiveEmptyLines() {
        let parser = SSEParser()
        let events = parser.parse("data: test\n\n\n\n\n")
        // Only one event dispatched, subsequent empty lines without data are ignored
        XCTAssertEqual(events.count, 1)
    }

    func testCommentOnly() {
        let parser = SSEParser()
        let events = parser.parse(": just a comment\n\n")
        XCTAssertEqual(events.count, 0)
    }

    func testMixedCRLFAndLF() {
        let parser = SSEParser()
        let input = "data: mixed\r\n\n"
        let events = parser.parse(input)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].data, "mixed")
    }

    func testVeryLongDataLine() {
        let parser = SSEParser()
        let longString = String(repeating: "x", count: 100000)
        let input = "data: \(longString)\n\n"
        let events = parser.parse(input)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].data, longString)
    }

    func testByteSplitAcrossMultipleChunks() {
        let parser = SSEParser()
        var allEvents: [SSEEvent] = []
        // Split "data: hello\n\n" into individual characters
        for char in "data: hello\n\n" {
            allEvents.append(contentsOf: parser.parse(String(char)))
        }
        XCTAssertEqual(allEvents.count, 1)
        XCTAssertEqual(allEvents[0].data, "hello")
    }

    func testEmptyStringInput() {
        let parser = SSEParser()
        let events = parser.parse("")
        XCTAssertEqual(events.count, 0)
    }

    func testSSEEventEquatable() {
        let event1 = SSEEvent(event: "message", data: "hello")
        let event2 = SSEEvent(event: "message", data: "hello")
        let event3 = SSEEvent(event: "other", data: "hello")
        XCTAssertEqual(event1, event2)
        XCTAssertNotEqual(event1, event3)
    }

    func testMultipleDataFieldsWithEventType() {
        let parser = SSEParser()
        let input = "event: chat\ndata: line1\ndata: line2\nid: 99\n\n"
        let events = parser.parse(input)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].event, "chat")
        XCTAssertEqual(events[0].data, "line1\nline2")
        XCTAssertEqual(events[0].id, "99")
    }

    func testColonInDataValue() {
        let parser = SSEParser()
        let input = "data: key: value: extra\n\n"
        let events = parser.parse(input)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].data, "key: value: extra")
    }

    func testJSONDataPayload() {
        let parser = SSEParser()
        let json = "{\"model\":\"gpt-4\",\"choices\":[{\"delta\":{\"content\":\"Hello\"},\"index\":0}]}"
        let input = "data: \(json)\n\n"
        let events = parser.parse(input)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].data, json)
    }
}
