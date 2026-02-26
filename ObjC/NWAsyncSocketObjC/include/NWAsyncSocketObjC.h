//
//  NWAsyncSocketObjC.h
//  NWAsyncSocketObjC
//
//  A TCP socket built on top of Network.framework's C API (nw_connection_t)
//  with an API modeled after GCDAsyncSocket. Includes built-in support for:
//
//  - Sticky-packet / split-packet handling via an internal NWStreamBuffer
//  - SSE (Server-Sent Events) parsing for LLM streaming data
//  - UTF-8 boundary detection to prevent character corruption
//  - Read-request queue for ordered, non-blocking reads
//
//  Usage:
//    NWAsyncSocketObjC *socket = [[NWAsyncSocketObjC alloc] initWithDelegate:self
//                                                             delegateQueue:dispatch_get_main_queue()];
//    NSError *err = nil;
//    [socket connectToHost:@"example.com" onPort:8080 error:&err];
//    [socket readDataWithTimeout:-1 tag:0];
//

#import <Foundation/Foundation.h>
#import "NWAsyncSocketObjCDelegate.h"
#import "NWStreamBuffer.h"
#import "NWSSEParser.h"
#import "NWReadRequest.h"

NS_ASSUME_NONNULL_BEGIN

/// Error domain for NWAsyncSocketObjC errors.
extern NSString * const NWAsyncSocketObjCErrorDomain;

typedef NS_ENUM(NSInteger, NWAsyncSocketObjCErrorCode) {
    NWAsyncSocketObjCErrorNotConnected = 1,
    NWAsyncSocketObjCErrorAlreadyConnected,
    NWAsyncSocketObjCErrorConnectionFailed,
    NWAsyncSocketObjCErrorReadTimeout,
    NWAsyncSocketObjCErrorWriteTimeout,
    NWAsyncSocketObjCErrorInvalidParameter,
};

@interface NWAsyncSocketObjC : NSObject

/// The delegate that receives socket events.
@property (nonatomic, weak, nullable) id<NWAsyncSocketObjCDelegate> delegate;

/// The dispatch queue on which delegate methods are called.
@property (nonatomic, strong, readonly) dispatch_queue_t delegateQueue;

/// Whether the socket is currently connected.
@property (nonatomic, readonly) BOOL isConnected;

/// The remote host the socket is connected to.
@property (nonatomic, readonly, copy, nullable) NSString *connectedHost;

/// The remote port the socket is connected to.
@property (nonatomic, readonly) uint16_t connectedPort;

/// User-defined data attached to the socket instance.
@property (nonatomic, strong, nullable) id userData;

// MARK: - Init

/// Create a new socket.
- (instancetype)initWithDelegate:(nullable id<NWAsyncSocketObjCDelegate>)delegate
                   delegateQueue:(dispatch_queue_t)delegateQueue;

// MARK: - Configuration

/// Enable TLS. Must be called before connect.
- (void)enableTLS;

/// Enable SSE parsing mode.
- (void)enableSSEParsing;

/// Enable streaming text mode.
- (void)enableStreamingText;

// MARK: - Connect

/// Connect to the specified host and port.
- (BOOL)connectToHost:(NSString *)host onPort:(uint16_t)port error:(NSError **)errPtr;

/// Connect to the specified host and port with a timeout.
- (BOOL)connectToHost:(NSString *)host
               onPort:(uint16_t)port
          withTimeout:(NSTimeInterval)timeout
                error:(NSError **)errPtr;

// MARK: - Disconnect

/// Disconnect the socket gracefully.
- (void)disconnect;

/// Disconnect after all pending writes have completed.
- (void)disconnectAfterWriting;

/// Disconnect after all pending reads have completed.
- (void)disconnectAfterReading;

// MARK: - Reading

/// Enqueue a read for any available data.
- (void)readDataWithTimeout:(NSTimeInterval)timeout tag:(long)tag;

/// Enqueue a read for exactly `length` bytes.
- (void)readDataToLength:(NSUInteger)length withTimeout:(NSTimeInterval)timeout tag:(long)tag;

/// Enqueue a read that completes when the specified delimiter is found.
- (void)readDataToData:(NSData *)data withTimeout:(NSTimeInterval)timeout tag:(long)tag;

// MARK: - Writing

/// Write data to the socket.
- (void)writeData:(NSData *)data withTimeout:(NSTimeInterval)timeout tag:(long)tag;

@end

NS_ASSUME_NONNULL_END
