//
//  NWReadRequestTests.m
//  NWAsyncSocketObjCTests
//
//  Tests for NWReadRequest.
//

#import <XCTest/XCTest.h>
#import "NWReadRequest.h"

@interface NWReadRequestTests : XCTestCase
@end

@implementation NWReadRequestTests

- (void)testAvailableRequest {
    NWReadRequest *req = [NWReadRequest availableRequestWithTimeout:-1 tag:0];
    XCTAssertEqual(req.type, NWReadRequestTypeAvailable);
    XCTAssertEqual(req.tag, 0);
    XCTAssertEqual(req.timeout, -1);
}

- (void)testToLengthRequest {
    NWReadRequest *req = [NWReadRequest toLengthRequest:1024 timeout:30 tag:42];
    XCTAssertEqual(req.type, NWReadRequestTypeToLength);
    XCTAssertEqual(req.length, 1024u);
    XCTAssertEqual(req.tag, 42);
    XCTAssertEqual(req.timeout, 30);
}

- (void)testToDelimiterRequest {
    NSData *delimiter = [@"\n\n" dataUsingEncoding:NSUTF8StringEncoding];
    NWReadRequest *req = [NWReadRequest toDelimiterRequest:delimiter timeout:10 tag:7];
    XCTAssertEqual(req.type, NWReadRequestTypeToDelimiter);
    XCTAssertEqualObjects(req.delimiter, delimiter);
    XCTAssertEqual(req.tag, 7);
    XCTAssertEqual(req.timeout, 10);
}

@end
