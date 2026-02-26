//
//  NWReadRequest.h
//  NWAsyncSocketObjC
//
//  Represents a pending read operation in the read-request queue.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, NWReadRequestType) {
    /// Read any available data.
    NWReadRequestTypeAvailable = 0,
    /// Read exactly N bytes.
    NWReadRequestTypeToLength,
    /// Read until delimiter is found.
    NWReadRequestTypeToDelimiter,
};

@interface NWReadRequest : NSObject

/// The type of read to perform.
@property (nonatomic, readonly) NWReadRequestType type;

/// The number of bytes to read (for NWReadRequestTypeToLength).
@property (nonatomic, readonly) NSUInteger length;

/// The delimiter to search for (for NWReadRequestTypeToDelimiter).
@property (nonatomic, readonly, copy, nullable) NSData *delimiter;

/// Timeout in seconds. Negative means no timeout.
@property (nonatomic, readonly) NSTimeInterval timeout;

/// An application-defined tag for correlating delegate callbacks.
@property (nonatomic, readonly) long tag;

+ (instancetype)availableRequestWithTimeout:(NSTimeInterval)timeout tag:(long)tag;
+ (instancetype)toLengthRequest:(NSUInteger)length timeout:(NSTimeInterval)timeout tag:(long)tag;
+ (instancetype)toDelimiterRequest:(NSData *)delimiter timeout:(NSTimeInterval)timeout tag:(long)tag;

@end

NS_ASSUME_NONNULL_END
