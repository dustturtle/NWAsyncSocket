//
//  NWSSEParserTests.m
//  NWAsyncSocketObjCTests
//
//  Comprehensive tests for NWSSEParser.
//

#import <XCTest/XCTest.h>
#import "NWSSEParser.h"

@interface NWSSEParserTests : XCTestCase
@end

@implementation NWSSEParserTests

#pragma mark - Basic parsing

- (void)testSingleEvent {
    NWSSEParser *parser = [[NWSSEParser alloc] init];
    NSArray<NWSSEEvent *> *events = [parser parseString:@"data: hello\n\n"];
    XCTAssertEqual(events.count, 1u);
    XCTAssertEqualObjects(events[0].data, @"hello");
    XCTAssertEqualObjects(events[0].event, @"message");
}

- (void)testEventWithType {
    NWSSEParser *parser = [[NWSSEParser alloc] init];
    NSArray *events = [parser parseString:@"event: update\ndata: world\n\n"];
    XCTAssertEqual(events.count, 1u);
    XCTAssertEqualObjects(events[0].event, @"update");
    XCTAssertEqualObjects(events[0].data, @"world");
}

- (void)testMultipleDataLines {
    NWSSEParser *parser = [[NWSSEParser alloc] init];
    NSArray *events = [parser parseString:@"data: line1\ndata: line2\ndata: line3\n\n"];
    XCTAssertEqual(events.count, 1u);
    XCTAssertEqualObjects(events[0].data, @"line1\nline2\nline3");
}

- (void)testEventWithId {
    NWSSEParser *parser = [[NWSSEParser alloc] init];
    NSArray *events = [parser parseString:@"id: 42\ndata: payload\n\n"];
    XCTAssertEqual(events.count, 1u);
    XCTAssertEqualObjects(events[0].eventId, @"42");
    XCTAssertEqualObjects(events[0].data, @"payload");
    XCTAssertEqualObjects(parser.lastEventId, @"42");
}

- (void)testEventWithRetry {
    NWSSEParser *parser = [[NWSSEParser alloc] init];
    NSArray *events = [parser parseString:@"retry: 3000\ndata: reconnect test\n\n"];
    XCTAssertEqual(events.count, 1u);
    XCTAssertEqual(events[0].retry, 3000);
}

#pragma mark - Multiple events (sticky packet / 粘包)

- (void)testMultipleEventsInOneChunk {
    NWSSEParser *parser = [[NWSSEParser alloc] init];
    NSArray *events = [parser parseString:@"data: first\n\ndata: second\n\ndata: third\n\n"];
    XCTAssertEqual(events.count, 3u);
    XCTAssertEqualObjects(events[0].data, @"first");
    XCTAssertEqualObjects(events[1].data, @"second");
    XCTAssertEqualObjects(events[2].data, @"third");
}

#pragma mark - Split packet (拆包)

- (void)testSplitAcrossChunks {
    NWSSEParser *parser = [[NWSSEParser alloc] init];
    NSArray *events1 = [parser parseString:@"data: hel"];
    XCTAssertEqual(events1.count, 0u);

    NSArray *events2 = [parser parseString:@"lo\n\n"];
    XCTAssertEqual(events2.count, 1u);
    XCTAssertEqualObjects(events2[0].data, @"hello");
}

- (void)testSplitInMiddleOfField {
    NWSSEParser *parser = [[NWSSEParser alloc] init];
    NSArray *events1 = [parser parseString:@"dat"];
    XCTAssertEqual(events1.count, 0u);

    NSArray *events2 = [parser parseString:@"a: content\n\n"];
    XCTAssertEqual(events2.count, 1u);
    XCTAssertEqualObjects(events2[0].data, @"content");
}

- (void)testSplitAtNewline {
    NWSSEParser *parser = [[NWSSEParser alloc] init];
    NSArray *events1 = [parser parseString:@"data: test\n"];
    XCTAssertEqual(events1.count, 0u);

    NSArray *events2 = [parser parseString:@"\n"];
    XCTAssertEqual(events2.count, 1u);
    XCTAssertEqualObjects(events2[0].data, @"test");
}

#pragma mark - Comments

- (void)testCommentsIgnored {
    NWSSEParser *parser = [[NWSSEParser alloc] init];
    NSArray *events = [parser parseString:@": this is a comment\ndata: real data\n\n"];
    XCTAssertEqual(events.count, 1u);
    XCTAssertEqualObjects(events[0].data, @"real data");
}

#pragma mark - CRLF handling

- (void)testCRLFLineEndings {
    NWSSEParser *parser = [[NWSSEParser alloc] init];
    NSArray *events = [parser parseString:@"data: crlf test\r\n\r\n"];
    XCTAssertEqual(events.count, 1u);
    XCTAssertEqualObjects(events[0].data, @"crlf test");
}

- (void)testCROnlyLineEndings {
    NWSSEParser *parser = [[NWSSEParser alloc] init];
    NSArray *events = [parser parseString:@"data: cr test\r\r"];
    XCTAssertEqual(events.count, 1u);
    XCTAssertEqualObjects(events[0].data, @"cr test");
}

#pragma mark - Empty data dispatch rule

- (void)testEmptyLineWithoutDataDoesNotDispatch {
    NWSSEParser *parser = [[NWSSEParser alloc] init];
    NSArray *events = [parser parseString:@"\n\n"];
    XCTAssertEqual(events.count, 0u);
}

- (void)testEventWithEmptyData {
    NWSSEParser *parser = [[NWSSEParser alloc] init];
    NSArray *events = [parser parseString:@"data:\n\n"];
    XCTAssertEqual(events.count, 1u);
    XCTAssertEqualObjects(events[0].data, @"");
}

#pragma mark - LLM streaming simulation

- (void)testLLMStreamingSSE {
    NWSSEParser *parser = [[NWSSEParser alloc] init];
    NSMutableArray<NWSSEEvent *> *allEvents = [NSMutableArray array];

    // Segment 1: Multiple complete SSE events packed together
    NSString *seg1 = @"data: {\"choices\":[{\"delta\":{\"content\":\"Hello\"}}]}\n\ndata: {\"choices\":[{\"delta\":{\"content\":\" world\"}}]}\n\n";
    [allEvents addObjectsFromArray:[parser parseString:seg1]];

    // Segment 2: Split event
    [allEvents addObjectsFromArray:[parser parseString:@"data: {\"choices\":[{\"delta\":{\"conte"]];

    // Segment 3: Rest of split event
    [allEvents addObjectsFromArray:[parser parseString:@"nt\":\"!\"}}]}\n\n"]];

    // Segment 4: Done marker
    [allEvents addObjectsFromArray:[parser parseString:@"data: [DONE]\n\n"]];

    XCTAssertEqual(allEvents.count, 4u);
    XCTAssertEqualObjects(allEvents[0].data, @"{\"choices\":[{\"delta\":{\"content\":\"Hello\"}}]}");
    XCTAssertEqualObjects(allEvents[1].data, @"{\"choices\":[{\"delta\":{\"content\":\" world\"}}]}");
    XCTAssertEqualObjects(allEvents[2].data, @"{\"choices\":[{\"delta\":{\"content\":\"!\"}}]}");
    XCTAssertEqualObjects(allEvents[3].data, @"[DONE]");
}

#pragma mark - Unknown fields

- (void)testUnknownFieldsIgnored {
    NWSSEParser *parser = [[NWSSEParser alloc] init];
    NSArray *events = [parser parseString:@"foo: bar\ndata: actual\n\n"];
    XCTAssertEqual(events.count, 1u);
    XCTAssertEqualObjects(events[0].data, @"actual");
}

#pragma mark - No colon line

- (void)testFieldWithoutValue {
    NWSSEParser *parser = [[NWSSEParser alloc] init];
    NSArray *events = [parser parseString:@"data\n\n"];
    XCTAssertEqual(events.count, 1u);
    XCTAssertEqualObjects(events[0].data, @"");
}

#pragma mark - Data via NSData

- (void)testParseFromData {
    NWSSEParser *parser = [[NWSSEParser alloc] init];
    NSData *input = [@"data: binary test\n\n" dataUsingEncoding:NSUTF8StringEncoding];
    NSArray *events = [parser parseData:input];
    XCTAssertEqual(events.count, 1u);
    XCTAssertEqualObjects(events[0].data, @"binary test");
}

#pragma mark - Reset

- (void)testReset {
    NWSSEParser *parser = [[NWSSEParser alloc] init];
    [parser parseString:@"data: partial"];
    [parser reset];

    NSArray *events = [parser parseString:@"data: fresh\n\n"];
    XCTAssertEqual(events.count, 1u);
    XCTAssertEqualObjects(events[0].data, @"fresh");
}

#pragma mark - Retry with non-integer

- (void)testRetryWithNonInteger {
    NWSSEParser *parser = [[NWSSEParser alloc] init];
    NSArray *events = [parser parseString:@"retry: abc\ndata: test\n\n"];
    XCTAssertEqual(events.count, 1u);
    XCTAssertEqual(events[0].retry, NSNotFound);
}

#pragma mark - Space after colon

- (void)testSpaceAfterColon {
    NWSSEParser *parser = [[NWSSEParser alloc] init];

    NSArray *events1 = [parser parseString:@"data: with space\n\n"];
    XCTAssertEqualObjects(events1[0].data, @"with space");

    NSArray *events2 = [parser parseString:@"data:without space\n\n"];
    XCTAssertEqualObjects(events2[0].data, @"without space");

    NSArray *events3 = [parser parseString:@"data:  two spaces\n\n"];
    XCTAssertEqualObjects(events3[0].data, @" two spaces");
}

@end
