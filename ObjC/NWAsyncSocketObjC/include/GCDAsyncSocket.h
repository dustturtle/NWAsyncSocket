//
//  GCDAsyncSocket.h
//  GCDAsyncSocket (NWAsyncSocket)
//
//  A TCP socket built on top of Network.framework's C API (nw_connection_t)
//  with an API designed as a drop-in replacement for GCDAsyncSocket from
//  CocoaAsyncSocket.  Includes built-in support for:
//
//  - Sticky-packet / split-packet handling via an internal NWStreamBuffer
//  - SSE (Server-Sent Events) parsing for LLM streaming data
//  - UTF-8 boundary detection to prevent character corruption
//  - Read-request queue for ordered, non-blocking reads
//
//  Usage:
//    GCDAsyncSocket *socket = [[GCDAsyncSocket alloc] initWithDelegate:self
//                                                         delegateQueue:dispatch_get_main_queue()];
//    NSError *err = nil;
//    [socket connectToHost:@"example.com" onPort:8080 error:&err];
//    [socket readDataWithTimeout:-1 tag:0];
//

#import <Foundation/Foundation.h>
#import "GCDAsyncSocketDelegate.h"

NS_ASSUME_NONNULL_BEGIN

/// Error domain for GCDAsyncSocket errors.
extern NSString * const GCDAsyncSocketErrorDomain;

typedef NS_ENUM(NSInteger, GCDAsyncSocketError) {
    GCDAsyncSocketErrorNotConnected = 1,
    GCDAsyncSocketErrorAlreadyConnected,
    GCDAsyncSocketErrorConnectionFailed,
    GCDAsyncSocketErrorReadTimeout,
    GCDAsyncSocketErrorWriteTimeout,
    GCDAsyncSocketErrorInvalidParameter,
};

@interface GCDAsyncSocket : NSObject

+ (NSData *)CRLFData;
+ (NSData *)CRData;
+ (NSData *)LFData;
+ (NSData *)ZeroData;

/// The delegate that receives socket events.
@property (atomic, weak, nullable) id<GCDAsyncSocketDelegate> delegate;

/// The dispatch queue on which delegate methods are called.
@property (atomic, strong, readwrite) dispatch_queue_t delegateQueue;

/// Whether to prefer IPv4 over IPv6 during hostname resolution. Default is YES.
@property (atomic, assign) BOOL IPv4PreferredOverIPv6;

/// Whether the socket is currently connected.
@property (atomic, readonly) BOOL isConnected;

/// Whether the socket is currently disconnected.
@property (atomic, readonly) BOOL isDisconnected;

/// Whether the socket is currently listening for incoming connections (server mode).
@property (atomic, readonly) BOOL isListening;

/// Whether the socket is using a secure TLS transport.
@property (atomic, readonly) BOOL isSecure;

/// The remote host the socket is connected to.
@property (atomic, readonly, copy, nullable) NSString *connectedHost;

/// The remote port the socket is connected to.
@property (atomic, readonly) uint16_t connectedPort;

/// The local host/address bound to this socket connection.
@property (atomic, readonly, copy, nullable) NSString *localHost;

/// The local port bound to this socket connection.
@property (atomic, readonly) uint16_t localPort;

/// User-defined data attached to the socket instance.
@property (atomic, strong, nullable) id userData;

// MARK: - Init

/// Create a new socket.
- (instancetype)initWithDelegate:(nullable id<GCDAsyncSocketDelegate>)delegate
                   delegateQueue:(dispatch_queue_t)delegateQueue;

/// Create a new socket with explicit socketQueue (pass NULL to use internal default queue).
- (instancetype)initWithDelegate:(nullable id<GCDAsyncSocketDelegate>)delegate
                   delegateQueue:(nullable dispatch_queue_t)delegateQueue
                     socketQueue:(nullable dispatch_queue_t)socketQueue;

/// Update delegate and callback queue (compatible with CocoaAsyncSocket API).
- (void)setDelegate:(nullable id<GCDAsyncSocketDelegate>)delegate
      delegateQueue:(nullable dispatch_queue_t)delegateQueue;

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

/// Compatibility API for CocoaAsyncSocket server mode.
/// Listen for incoming TCP connections on all interfaces on the given port.
/// Pass port 0 to let the system assign an available port (query via `localPort`).
- (BOOL)acceptOnPort:(uint16_t)port error:(NSError **)errPtr;

/// Listen for incoming TCP connections on a specific interface/address and port.
/// Pass @"localhost" or @"127.0.0.1" to restrict connections to the local machine.
- (BOOL)acceptOnInterface:(nullable NSString *)interface port:(uint16_t)port error:(NSError **)errPtr;

/// Listen for incoming connections on a Unix Domain Socket at the given file URL.
- (BOOL)acceptOnUrl:(NSURL *)url error:(NSError **)errPtr;

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

/// Enqueue a read to delimiter with a maximum length safeguard (0 means unlimited).
- (void)readDataToData:(NSData *)data
           withTimeout:(NSTimeInterval)timeout
             maxLength:(NSUInteger)maxLength
                   tag:(long)tag;

// MARK: - Writing

/// Write data to the socket.
- (void)writeData:(NSData *)data withTimeout:(NSTimeInterval)timeout tag:(long)tag;

@end

NS_ASSUME_NONNULL_END
