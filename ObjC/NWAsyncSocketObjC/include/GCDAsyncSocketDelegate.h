//
//  GCDAsyncSocketDelegate.h
//  GCDAsyncSocket (NWAsyncSocket)
//
//  Delegate protocol modeled after GCDAsyncSocketDelegate from CocoaAsyncSocket.
//  Drop-in replacement: use GCDAsyncSocket / GCDAsyncSocketDelegate as class
//  and protocol names so existing code that depends on GCDAsyncSocket can
//  migrate transparently to the Network.framework-backed implementation.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class GCDAsyncSocket;
@class NWSSEEvent;

@protocol GCDAsyncSocketDelegate <NSObject>

@required
/// Called when the socket successfully connects to the remote host.
- (void)socket:(GCDAsyncSocket *)sock didConnectToHost:(NSString *)host port:(uint16_t)port;

/// Called when data has been read from the socket.
- (void)socket:(GCDAsyncSocket *)sock didReadData:(NSData *)data withTag:(long)tag;

/// Called after data has been successfully written.
- (void)socket:(GCDAsyncSocket *)sock didWriteDataWithTag:(long)tag;

/// Called when the socket disconnects.
- (void)socketDidDisconnect:(GCDAsyncSocket *)sock withError:(nullable NSError *)error;

@optional
/// Called when a complete SSE event has been parsed.
- (void)socket:(GCDAsyncSocket *)sock didReceiveSSEEvent:(NWSSEEvent *)event;

/// Called when a UTF-8 safe string chunk is extracted from the stream.
- (void)socket:(GCDAsyncSocket *)sock didReceiveString:(NSString *)string;

@end

NS_ASSUME_NONNULL_END
