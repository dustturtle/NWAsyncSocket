//
//  NWAsyncSocketObjCDelegate.h
//  NWAsyncSocketObjC
//
//  Delegate protocol modeled after GCDAsyncSocketDelegate.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class NWAsyncSocketObjC;
@class NWSSEEvent;

@protocol NWAsyncSocketObjCDelegate <NSObject>

@required
/// Called when the socket successfully connects to the remote host.
- (void)socket:(NWAsyncSocketObjC *)sock didConnectToHost:(NSString *)host port:(uint16_t)port;

/// Called when data has been read from the socket.
- (void)socket:(NWAsyncSocketObjC *)sock didReadData:(NSData *)data withTag:(long)tag;

/// Called after data has been successfully written.
- (void)socket:(NWAsyncSocketObjC *)sock didWriteDataWithTag:(long)tag;

/// Called when the socket disconnects.
- (void)socketDidDisconnect:(NWAsyncSocketObjC *)sock withError:(nullable NSError *)error;

@optional
/// Called when a complete SSE event has been parsed.
- (void)socket:(NWAsyncSocketObjC *)sock didReceiveSSEEvent:(NWSSEEvent *)event;

/// Called when a UTF-8 safe string chunk is extracted from the stream.
- (void)socket:(NWAsyncSocketObjC *)sock didReceiveString:(NSString *)string;

@end

NS_ASSUME_NONNULL_END
