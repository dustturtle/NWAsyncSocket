//
//  NWStreamBufferTests.m
//  NWAsyncSocketObjCTests
//
//  Comprehensive tests for NWStreamBuffer.
//

#import <XCTest/XCTest.h>
#import "NWStreamBuffer.h"

@interface NWStreamBufferTests : XCTestCase
@end

@implementation NWStreamBufferTests

#pragma mark - Basic operations

- (void)testEmptyBuffer {
    NWStreamBuffer *buf = [[NWStreamBuffer alloc] init];
    XCTAssertTrue(buf.isEmpty);
    XCTAssertEqual(buf.count, 0u);
}

- (void)testAppendAndCount {
    NWStreamBuffer *buf = [[NWStreamBuffer alloc] init];
    uint8_t bytes[] = {1, 2, 3};
    [buf appendData:[NSData dataWithBytes:bytes length:3]];
    XCTAssertFalse(buf.isEmpty);
    XCTAssertEqual(buf.count, 3u);
}

- (void)testReadAllData {
    NWStreamBuffer *buf = [[NWStreamBuffer alloc] init];
    uint8_t bytes[] = {0xAA, 0xBB, 0xCC};
    NSData *input = [NSData dataWithBytes:bytes length:3];
    [buf appendData:input];
    NSData *result = [buf readAllData];
    XCTAssertEqualObjects(result, input);
    XCTAssertTrue(buf.isEmpty);
}

- (void)testPeekDoesNotConsume {
    NWStreamBuffer *buf = [[NWStreamBuffer alloc] init];
    uint8_t bytes[] = {1, 2, 3};
    [buf appendData:[NSData dataWithBytes:bytes length:3]];
    NSData *peek = [buf peekAllData];
    XCTAssertEqualObjects(peek, [NSData dataWithBytes:bytes length:3]);
    XCTAssertEqual(buf.count, 3u);
}

- (void)testReset {
    NWStreamBuffer *buf = [[NWStreamBuffer alloc] init];
    uint8_t bytes[] = {1, 2, 3, 4, 5};
    [buf appendData:[NSData dataWithBytes:bytes length:5]];
    [buf reset];
    XCTAssertTrue(buf.isEmpty);
}

#pragma mark - readDataToLength

- (void)testReadToLengthExact {
    NWStreamBuffer *buf = [[NWStreamBuffer alloc] init];
    uint8_t bytes[] = {10, 20, 30, 40, 50};
    [buf appendData:[NSData dataWithBytes:bytes length:5]];
    NSData *result = [buf readDataToLength:3];
    uint8_t expected[] = {10, 20, 30};
    XCTAssertEqualObjects(result, [NSData dataWithBytes:expected length:3]);
    XCTAssertEqual(buf.count, 2u);
}

- (void)testReadToLengthInsufficient {
    NWStreamBuffer *buf = [[NWStreamBuffer alloc] init];
    uint8_t bytes[] = {10, 20};
    [buf appendData:[NSData dataWithBytes:bytes length:2]];
    NSData *result = [buf readDataToLength:5];
    XCTAssertNil(result);
    XCTAssertEqual(buf.count, 2u);
}

- (void)testReadToLengthMultipleCalls {
    NWStreamBuffer *buf = [[NWStreamBuffer alloc] init];
    uint8_t bytes[] = {1, 2, 3, 4, 5, 6};
    [buf appendData:[NSData dataWithBytes:bytes length:6]];
    NSData *first = [buf readDataToLength:2];
    NSData *second = [buf readDataToLength:2];
    NSData *third = [buf readDataToLength:2];
    uint8_t e1[] = {1, 2}, e2[] = {3, 4}, e3[] = {5, 6};
    XCTAssertEqualObjects(first, [NSData dataWithBytes:e1 length:2]);
    XCTAssertEqualObjects(second, [NSData dataWithBytes:e2 length:2]);
    XCTAssertEqualObjects(third, [NSData dataWithBytes:e3 length:2]);
    XCTAssertTrue(buf.isEmpty);
}

#pragma mark - readDataToDelimiter

- (void)testReadToDelimiterFound {
    NWStreamBuffer *buf = [[NWStreamBuffer alloc] init];
    [buf appendData:[@"hello\nworld" dataUsingEncoding:NSUTF8StringEncoding]];
    NSData *delimiter = [@"\n" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *result = [buf readDataToDelimiter:delimiter];
    NSString *str = [[NSString alloc] initWithData:result encoding:NSUTF8StringEncoding];
    XCTAssertEqualObjects(str, @"hello\n");
    NSData *remaining = [buf readAllData];
    NSString *remStr = [[NSString alloc] initWithData:remaining encoding:NSUTF8StringEncoding];
    XCTAssertEqualObjects(remStr, @"world");
}

- (void)testReadToDelimiterNotFound {
    NWStreamBuffer *buf = [[NWStreamBuffer alloc] init];
    [buf appendData:[@"no newline here" dataUsingEncoding:NSUTF8StringEncoding]];
    NSData *delimiter = [@"\n" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *result = [buf readDataToDelimiter:delimiter];
    XCTAssertNil(result);
    XCTAssertEqual(buf.count, 15u);
}

- (void)testReadToMultiByteDelimiter {
    NWStreamBuffer *buf = [[NWStreamBuffer alloc] init];
    [buf appendData:[@"data\r\nmore" dataUsingEncoding:NSUTF8StringEncoding]];
    NSData *delimiter = [@"\r\n" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *result = [buf readDataToDelimiter:delimiter];
    NSString *str = [[NSString alloc] initWithData:result encoding:NSUTF8StringEncoding];
    XCTAssertEqualObjects(str, @"data\r\n");
}

#pragma mark - Sticky packet simulation (粘包)

- (void)testStickyPacketReassembly {
    NWStreamBuffer *buf = [[NWStreamBuffer alloc] init];
    NSString *combined = @"data: {\"text\":\"hello\"}\n\ndata: {\"text\":\"world\"}\n\n";
    [buf appendData:[combined dataUsingEncoding:NSUTF8StringEncoding]];

    NSData *delimiter = [@"\n\n" dataUsingEncoding:NSUTF8StringEncoding];

    NSData *msg1 = [buf readDataToDelimiter:delimiter];
    XCTAssertNotNil(msg1);
    NSString *str1 = [[NSString alloc] initWithData:msg1 encoding:NSUTF8StringEncoding];
    XCTAssertEqualObjects(str1, @"data: {\"text\":\"hello\"}\n\n");

    NSData *msg2 = [buf readDataToDelimiter:delimiter];
    XCTAssertNotNil(msg2);
    NSString *str2 = [[NSString alloc] initWithData:msg2 encoding:NSUTF8StringEncoding];
    XCTAssertEqualObjects(str2, @"data: {\"text\":\"world\"}\n\n");

    XCTAssertTrue(buf.isEmpty);
}

#pragma mark - Split packet simulation (拆包)

- (void)testSplitPacketReassembly {
    NWStreamBuffer *buf = [[NWStreamBuffer alloc] init];
    NSData *delimiter = [@"\n\n" dataUsingEncoding:NSUTF8StringEncoding];

    // First TCP segment: partial message
    [buf appendData:[@"data: {\"text\":\"he" dataUsingEncoding:NSUTF8StringEncoding]];
    NSData *result1 = [buf readDataToDelimiter:delimiter];
    XCTAssertNil(result1);

    // Second TCP segment: rest of message
    [buf appendData:[@"llo\"}\n\n" dataUsingEncoding:NSUTF8StringEncoding]];
    NSData *result2 = [buf readDataToDelimiter:delimiter];
    XCTAssertNotNil(result2);
    NSString *str = [[NSString alloc] initWithData:result2 encoding:NSUTF8StringEncoding];
    XCTAssertEqualObjects(str, @"data: {\"text\":\"hello\"}\n\n");
}

#pragma mark - UTF-8 safety

- (void)testUTF8SafeCountWithASCII {
    NSData *data = [@"Hello" dataUsingEncoding:NSUTF8StringEncoding];
    XCTAssertEqual([NWStreamBuffer utf8SafeByteCountForData:data], 5u);
}

- (void)testUTF8SafeCountWithCompleteMultibyte {
    // "你好" = 6 bytes in UTF-8
    NSData *data = [@"你好" dataUsingEncoding:NSUTF8StringEncoding];
    XCTAssertEqual(data.length, 6u);
    XCTAssertEqual([NWStreamBuffer utf8SafeByteCountForData:data], 6u);
}

- (void)testUTF8SafeCountWithIncompleteMultibyte {
    // "你" = E4 BD A0 in UTF-8 — only first 2 bytes
    uint8_t bytes[] = {0xE4, 0xBD};
    NSData *data = [NSData dataWithBytes:bytes length:2];
    XCTAssertEqual([NWStreamBuffer utf8SafeByteCountForData:data], 0u);
}

- (void)testUTF8SafeCountMixedASCIIAndIncomplete {
    // "Hi" + first byte of a 3-byte char
    uint8_t bytes[] = {0x48, 0x69, 0xE4};
    NSData *data = [NSData dataWithBytes:bytes length:3];
    XCTAssertEqual([NWStreamBuffer utf8SafeByteCountForData:data], 2u);
}

- (void)testUTF8SafeCountWith4ByteCharIncomplete {
    // "Hi" + partial emoji (3 of 4 bytes)
    uint8_t bytes[] = {0x48, 0x69, 0xF0, 0x9F, 0x98};
    NSData *data = [NSData dataWithBytes:bytes length:5];
    XCTAssertEqual([NWStreamBuffer utf8SafeByteCountForData:data], 2u);
}

- (void)testUTF8SafeCountWith4ByteCharComplete {
    // "Hi" + complete emoji 😀 = F0 9F 98 80
    uint8_t bytes[] = {0x48, 0x69, 0xF0, 0x9F, 0x98, 0x80};
    NSData *data = [NSData dataWithBytes:bytes length:6];
    XCTAssertEqual([NWStreamBuffer utf8SafeByteCountForData:data], 6u);
}

- (void)testReadUTF8SafeString {
    NWStreamBuffer *buf = [[NWStreamBuffer alloc] init];
    // "Hello" + first 2 bytes of "你"
    uint8_t bytes[] = {0x48, 0x65, 0x6C, 0x6C, 0x6F, 0xE4, 0xBD};
    [buf appendData:[NSData dataWithBytes:bytes length:7]];
    NSString *str = [buf readUTF8SafeString];
    XCTAssertEqualObjects(str, @"Hello");
    XCTAssertEqual(buf.count, 2u);
}

- (void)testReadUTF8SafeStringCompleteCharLater {
    NWStreamBuffer *buf = [[NWStreamBuffer alloc] init];
    // "Hi" + partial 你
    uint8_t bytes1[] = {0x48, 0x69, 0xE4, 0xBD};
    [buf appendData:[NSData dataWithBytes:bytes1 length:4]];
    NSString *str1 = [buf readUTF8SafeString];
    XCTAssertEqualObjects(str1, @"Hi");

    // Remaining byte of 你
    uint8_t bytes2[] = {0xA0};
    [buf appendData:[NSData dataWithBytes:bytes2 length:1]];
    NSString *str2 = [buf readUTF8SafeString];
    XCTAssertEqualObjects(str2, @"你");
    XCTAssertTrue(buf.isEmpty);
}

- (void)testEmptyData {
    XCTAssertEqual([NWStreamBuffer utf8SafeByteCountForData:[NSData data]], 0u);
}

@end
