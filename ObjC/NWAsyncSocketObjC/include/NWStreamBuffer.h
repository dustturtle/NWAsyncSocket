//
//  NWStreamBuffer.h
//  NWAsyncSocketObjC
//
//  A byte buffer that accumulates incoming TCP data and supports extracting
//  complete messages from the stream. Handles sticky-packet (粘包) reassembly,
//  split-packet reconstruction, and UTF-8 boundary detection.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface NWStreamBuffer : NSObject

/// Number of bytes currently in the buffer.
@property (nonatomic, readonly) NSUInteger count;

/// Whether the buffer is empty.
@property (nonatomic, readonly) BOOL isEmpty;

/// A copy of the buffered data (for inspection / testing).
@property (nonatomic, readonly, copy) NSData *data;

/// Append raw bytes received from the network.
- (void)appendData:(NSData *)data;

/// Read and remove exactly `length` bytes from the front of the buffer.
/// Returns nil if fewer bytes are available.
- (nullable NSData *)readDataToLength:(NSUInteger)length;

/// Read and remove all bytes up to and including the first occurrence of `delimiter`.
/// Returns nil if the delimiter is not found.
- (nullable NSData *)readDataToDelimiter:(NSData *)delimiter;

/// Drain and return all available bytes.
- (NSData *)readAllData;

/// Peek at all data without consuming.
- (NSData *)peekAllData;

/// Return the longest prefix that forms valid UTF-8, leaving any trailing
/// incomplete multi-byte sequence in the buffer.
- (nullable NSString *)readUTF8SafeString;

/// Discard all buffered data.
- (void)reset;

/// Returns the number of leading bytes that form complete UTF-8 code points.
+ (NSUInteger)utf8SafeByteCountForData:(NSData *)data;

@end

NS_ASSUME_NONNULL_END
