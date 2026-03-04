//
//  NWReadRequest.m
//  NWAsyncSocketObjC
//

#import "NWReadRequest.h"

@interface NWReadRequest ()
@property (nonatomic, readwrite) NWReadRequestType type;
@property (nonatomic, readwrite) NSUInteger length;
@property (nonatomic, readwrite, copy, nullable) NSData *delimiter;
@property (nonatomic, readwrite) NSUInteger maxLength;
@property (nonatomic, readwrite) NSTimeInterval timeout;
@property (nonatomic, readwrite) long tag;
@end

@implementation NWReadRequest

+ (instancetype)availableRequestWithTimeout:(NSTimeInterval)timeout tag:(long)tag {
    NWReadRequest *req = [[NWReadRequest alloc] init];
    req.type = NWReadRequestTypeAvailable;
    req.timeout = timeout;
    req.tag = tag;
    return req;
}

+ (instancetype)toLengthRequest:(NSUInteger)length timeout:(NSTimeInterval)timeout tag:(long)tag {
    NWReadRequest *req = [[NWReadRequest alloc] init];
    req.type = NWReadRequestTypeToLength;
    req.length = length;
    req.timeout = timeout;
    req.tag = tag;
    return req;
}

+ (instancetype)toDelimiterRequest:(NSData *)delimiter timeout:(NSTimeInterval)timeout tag:(long)tag {
    return [self toDelimiterRequest:delimiter timeout:timeout maxLength:0 tag:tag];
}

+ (instancetype)toDelimiterRequest:(NSData *)delimiter
                           timeout:(NSTimeInterval)timeout
                         maxLength:(NSUInteger)maxLength
                               tag:(long)tag {
    NWReadRequest *req = [[NWReadRequest alloc] init];
    req.type = NWReadRequestTypeToDelimiter;
    req.delimiter = delimiter;
    req.maxLength = maxLength;
    req.timeout = timeout;
    req.tag = tag;
    return req;
}

@end
