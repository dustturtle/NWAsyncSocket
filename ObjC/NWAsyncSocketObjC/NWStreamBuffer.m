//
//  NWStreamBuffer.m
//  NWAsyncSocketObjC
//

#import "NWStreamBuffer.h"

@interface NWStreamBuffer ()
@property (nonatomic, strong) NSMutableData *storage;
@end

@implementation NWStreamBuffer

- (instancetype)init {
    self = [super init];
    if (self) {
        _storage = [NSMutableData data];
    }
    return self;
}

#pragma mark - Properties

- (NSUInteger)count {
    return self.storage.length;
}

- (BOOL)isEmpty {
    return self.storage.length == 0;
}

- (NSData *)data {
    return [self.storage copy];
}

#pragma mark - Append

- (void)appendData:(NSData *)data {
    [self.storage appendData:data];
}

#pragma mark - Read helpers

- (NSData *)readDataToLength:(NSUInteger)length {
    if (self.storage.length < length) {
        return nil;
    }
    NSData *chunk = [self.storage subdataWithRange:NSMakeRange(0, length)];
    [self.storage replaceBytesInRange:NSMakeRange(0, length) withBytes:NULL length:0];
    return chunk;
}

- (NSData *)readDataToDelimiter:(NSData *)delimiter {
    NSRange range = [self.storage rangeOfData:delimiter
                                     options:0
                                       range:NSMakeRange(0, self.storage.length)];
    if (range.location == NSNotFound) {
        return nil;
    }
    NSUInteger end = range.location + range.length;
    NSData *chunk = [self.storage subdataWithRange:NSMakeRange(0, end)];
    [self.storage replaceBytesInRange:NSMakeRange(0, end) withBytes:NULL length:0];
    return chunk;
}

- (NSData *)readAllData {
    NSData *result = [self.storage copy];
    self.storage = [NSMutableData data];
    return result;
}

- (NSData *)peekAllData {
    return [self.storage copy];
}

#pragma mark - UTF-8 safe extraction

- (NSString *)readUTF8SafeString {
    if (self.storage.length == 0) {
        return nil;
    }
    NSUInteger safeCount = [NWStreamBuffer utf8SafeByteCountForData:self.storage];
    if (safeCount == 0) {
        return nil;
    }
    NSData *chunk = [self readDataToLength:safeCount];
    if (!chunk) {
        return nil;
    }
    return [[NSString alloc] initWithData:chunk encoding:NSUTF8StringEncoding];
}

#pragma mark - Reset

- (void)reset {
    self.storage = [NSMutableData data];
}

#pragma mark - UTF-8 helpers

+ (NSUInteger)utf8SafeByteCountForData:(NSData *)data {
    const uint8_t *bytes = (const uint8_t *)data.bytes;
    NSUInteger total = data.length;
    if (total == 0) {
        return 0;
    }

    // Walk backwards from the end to find the start of any trailing
    // incomplete multi-byte sequence.
    NSInteger i = (NSInteger)total - 1;

    // Skip continuation bytes (10xxxxxx)
    while (i >= 0 && (bytes[i] & 0xC0) == 0x80) {
        i--;
    }

    if (i < 0) {
        // All continuation bytes with no leading byte.
        return 0;
    }

    uint8_t leadByte = bytes[i];
    NSUInteger expectedLength;
    if ((leadByte & 0x80) == 0) {
        expectedLength = 1;
    } else if ((leadByte & 0xE0) == 0xC0) {
        expectedLength = 2;
    } else if ((leadByte & 0xF0) == 0xE0) {
        expectedLength = 3;
    } else if ((leadByte & 0xF8) == 0xF0) {
        expectedLength = 4;
    } else {
        // Invalid leading byte
        return total;
    }

    NSUInteger actualLength = total - (NSUInteger)i;
    if (actualLength >= expectedLength) {
        return total;
    } else {
        return (NSUInteger)i;
    }
}

@end
