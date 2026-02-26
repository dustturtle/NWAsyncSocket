//
//  NWSSEParser.h
//  NWAsyncSocketObjC
//
//  Incremental SSE (Server-Sent Events) parser that accumulates raw bytes
//  and emits complete NWSSEEvent objects. Handles partial lines split across
//  multiple TCP segments.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Represents a single Server-Sent Events event.
@interface NWSSEEvent : NSObject

/// The event type (from `event:` field). Defaults to @"message".
@property (nonatomic, readonly, copy) NSString *event;

/// The data payload (from `data:` fields, joined by newlines).
@property (nonatomic, readonly, copy) NSString *data;

/// The optional `id:` field.
@property (nonatomic, readonly, copy, nullable) NSString *eventId;

/// The optional `retry:` field (milliseconds). NSNotFound if not set.
@property (nonatomic, readonly) NSInteger retry;

- (instancetype)initWithEvent:(NSString *)event
                         data:(NSString *)data
                      eventId:(nullable NSString *)eventId
                        retry:(NSInteger)retry;

@end

/// Incremental SSE parser.
@interface NWSSEParser : NSObject

/// Last seen event id (for reconnection).
@property (nonatomic, readonly, copy, nullable) NSString *lastEventId;

/// Feed raw bytes into the parser. Returns an array of fully parsed NWSSEEvent objects.
- (NSArray<NWSSEEvent *> *)parseData:(NSData *)data;

/// Feed a string chunk into the parser.
- (NSArray<NWSSEEvent *> *)parseString:(NSString *)string;

/// Reset all internal state.
- (void)reset;

@end

NS_ASSUME_NONNULL_END
