//
//  NWSSEParser.m
//  NWAsyncSocketObjC
//

#import "NWSSEParser.h"

#pragma mark - NWSSEEvent

@implementation NWSSEEvent

- (instancetype)initWithEvent:(NSString *)event
                         data:(NSString *)data
                      eventId:(NSString *)eventId
                        retry:(NSInteger)retry {
    self = [super init];
    if (self) {
        _event = [event copy];
        _data = [data copy];
        _eventId = [eventId copy];
        _retry = retry;
    }
    return self;
}

- (BOOL)isEqual:(id)object {
    if (![object isKindOfClass:[NWSSEEvent class]]) return NO;
    NWSSEEvent *other = (NWSSEEvent *)object;
    return [self.event isEqualToString:other.event]
        && [self.data isEqualToString:other.data]
        && (self.eventId == other.eventId || [self.eventId isEqualToString:other.eventId])
        && self.retry == other.retry;
}

- (NSUInteger)hash {
    return self.event.hash ^ self.data.hash ^ self.eventId.hash ^ (NSUInteger)self.retry;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<NWSSEEvent event=%@ data=%@ id=%@ retry=%ld>",
            self.event, self.data, self.eventId, (long)self.retry];
}

@end

#pragma mark - NWSSEParser

@interface NWSSEParser ()
@property (nonatomic, strong) NSMutableString *lineBuffer;
@property (nonatomic, copy) NSString *currentEvent;
@property (nonatomic, strong) NSMutableArray<NSString *> *currentData;
@property (nonatomic, copy, nullable) NSString *currentId;
@property (nonatomic, assign) NSInteger currentRetry;
@end

@implementation NWSSEParser

- (instancetype)init {
    self = [super init];
    if (self) {
        _lineBuffer = [NSMutableString string];
        [self resetCurrentEvent];
    }
    return self;
}

#pragma mark - Feed data

- (NSArray<NWSSEEvent *> *)parseData:(NSData *)data {
    NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (!text) return @[];
    return [self parseString:text];
}

- (NSArray<NWSSEEvent *> *)parseString:(NSString *)string {
    NSMutableArray<NWSSEEvent *> *events = [NSMutableArray array];
    [self.lineBuffer appendString:string];

    NSString *line;
    NSString *remainder;
    while ([self extractLineFrom:self.lineBuffer line:&line remainder:&remainder]) {
        [self.lineBuffer setString:remainder];
        [self processLine:line events:events];
    }

    return events;
}

- (void)reset {
    [self.lineBuffer setString:@""];
    [self resetCurrentEvent];
    _lastEventId = nil;
}

#pragma mark - Private

/// Extract the first complete line from buffer using unicode scalars
/// to correctly handle \r\n (which Swift/ObjC Character type may treat
/// as a single grapheme cluster).
- (BOOL)extractLineFrom:(NSString *)buffer
                    line:(NSString **)outLine
               remainder:(NSString **)outRemainder {
    // Scan through raw UTF-16 code units for \r and \n
    NSUInteger len = buffer.length;
    for (NSUInteger i = 0; i < len; i++) {
        unichar ch = [buffer characterAtIndex:i];
        if (ch == '\r') {
            *outLine = [buffer substringToIndex:i];
            // \r\n counts as single line ending
            if (i + 1 < len && [buffer characterAtIndex:i + 1] == '\n') {
                *outRemainder = [buffer substringFromIndex:i + 2];
            } else {
                *outRemainder = [buffer substringFromIndex:i + 1];
            }
            return YES;
        } else if (ch == '\n') {
            *outLine = [buffer substringToIndex:i];
            *outRemainder = [buffer substringFromIndex:i + 1];
            return YES;
        }
    }
    return NO;
}

- (void)processLine:(NSString *)line events:(NSMutableArray<NWSSEEvent *> *)events {
    // Empty line = dispatch the event
    if (line.length == 0) {
        [self dispatchEventInto:events];
        return;
    }

    // Lines starting with ':' are comments
    if ([line hasPrefix:@":"]) {
        return;
    }

    // Split on first ':'
    NSString *field;
    NSString *value;
    NSRange colonRange = [line rangeOfString:@":"];
    if (colonRange.location != NSNotFound) {
        field = [line substringToIndex:colonRange.location];
        NSUInteger valStart = colonRange.location + 1;
        // Skip a single leading space after the colon (per spec)
        if (valStart < line.length && [line characterAtIndex:valStart] == ' ') {
            valStart++;
        }
        value = [line substringFromIndex:valStart];
    } else {
        field = line;
        value = @"";
    }

    if ([field isEqualToString:@"event"]) {
        self.currentEvent = value;
    } else if ([field isEqualToString:@"data"]) {
        [self.currentData addObject:value];
    } else if ([field isEqualToString:@"id"]) {
        // Per spec, ignore if value contains null
        if ([value rangeOfString:@"\0"].location == NSNotFound) {
            self.currentId = value;
        }
    } else if ([field isEqualToString:@"retry"]) {
        NSScanner *scanner = [NSScanner scannerWithString:value];
        NSInteger retryValue;
        if ([scanner scanInteger:&retryValue] && scanner.isAtEnd) {
            self.currentRetry = retryValue;
        }
    }
    // Unknown fields are ignored per spec
}

- (void)dispatchEventInto:(NSMutableArray<NWSSEEvent *> *)events {
    if (self.currentData.count > 0) {
        NSString *dataStr = [self.currentData componentsJoinedByString:@"\n"];
        NWSSEEvent *event = [[NWSSEEvent alloc] initWithEvent:self.currentEvent
                                                         data:dataStr
                                                      eventId:self.currentId
                                                        retry:self.currentRetry];
        [events addObject:event];
        if (self.currentId) {
            _lastEventId = self.currentId;
        }
    }
    [self resetCurrentEvent];
}

- (void)resetCurrentEvent {
    _currentEvent = @"message";
    _currentData = [NSMutableArray array];
    _currentId = nil;
    _currentRetry = NSNotFound;
}

@end
