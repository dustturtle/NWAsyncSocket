//
//  GCDAsyncSocket.m
//  GCDAsyncSocket (NWAsyncSocket)
//
//  TCP socket using Network.framework's C API (nw_connection_t).
//  Drop-in replacement for GCDAsyncSocket from CocoaAsyncSocket.
//  Only compiles on Apple platforms (iOS 13+, macOS 10.15+).
//

#import "GCDAsyncSocket.h"
#import "NWStreamBuffer.h"
#import "NWSSEParser.h"
#import "NWReadRequest.h"

#if __has_include(<Network/Network.h>)
#define NW_FRAMEWORK_AVAILABLE 1
#import <Network/Network.h>
#include <arpa/inet.h>
#include <netdb.h>
#else
#define NW_FRAMEWORK_AVAILABLE 0
#endif

NSString * const GCDAsyncSocketErrorDomain = @"GCDAsyncSocketErrorDomain";

static const void *kGCDAsyncSocketQueueKey = &kGCDAsyncSocketQueueKey;

static NSString * const GCDAsyncSocketDisconnectReasonKey = @"GCDAsyncSocketDisconnectReason";
static NSString * const GCDAsyncSocketNWErrorDomainKey = @"GCDAsyncSocketNWErrorDomain";
static NSString * const GCDAsyncSocketNWErrorCodeKey = @"GCDAsyncSocketNWErrorCode";

@interface GCDAsyncSocket ()
@property (atomic, readwrite, copy, nullable) NSString *connectedHost;
@property (atomic, readwrite) uint16_t connectedPort;
@property (atomic, readwrite, copy, nullable) NSString *localHost;
@property (atomic, readwrite) uint16_t localPort;
@property (atomic, readwrite) BOOL isConnected;

#if NW_FRAMEWORK_AVAILABLE
@property (nonatomic, assign) nw_connection_t connection;
@property (nonatomic, assign, nullable) nw_listener_t listener;
#endif

@property (nonatomic, strong) dispatch_queue_t socketQueue;
@property (nonatomic, strong) NWStreamBuffer *buffer;
@property (nonatomic, strong) NSMutableArray<NWReadRequest *> *readQueue;
@property (nonatomic, assign) BOOL isReadingContinuously;
@property (nonatomic, assign) BOOL isListening;

// SSE / streaming text mode
@property (nonatomic, strong, nullable) NWSSEParser *sseParser;
@property (nonatomic, assign) BOOL streamingTextEnabled;

// TLS
@property (nonatomic, assign) BOOL tlsEnabled;

@end

@implementation GCDAsyncSocket

#pragma mark - Error Helpers

#if NW_FRAMEWORK_AVAILABLE
- (NSString *)nwErrorDomainString:(nw_error_domain_t)domain {
    switch (domain) {
        case nw_error_domain_posix:
            return @"posix";
        case nw_error_domain_dns:
            return @"dns";
        case nw_error_domain_tls:
            return @"tls";
        default:
            return @"unknown";
    }
}

- (NSError *)socketErrorWithCode:(GCDAsyncSocketError)code
                      description:(NSString *)description
                          reason:(NSString *)reason
                         nwError:(nw_error_t _Nullable)nwError {
    NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
    if (description.length > 0) {
        userInfo[NSLocalizedDescriptionKey] = description;
    }
    if (reason.length > 0) {
        userInfo[GCDAsyncSocketDisconnectReasonKey] = reason;
    }
    if (nwError) {
        nw_error_domain_t domain = nw_error_get_error_domain(nwError);
        int errorCode = nw_error_get_error_code(nwError);
        userInfo[GCDAsyncSocketNWErrorDomainKey] = [self nwErrorDomainString:domain];
        userInfo[GCDAsyncSocketNWErrorCodeKey] = @(errorCode);
    }
    return [NSError errorWithDomain:GCDAsyncSocketErrorDomain code:code userInfo:userInfo];
}

- (NSString *)preferredHostForHost:(NSString *)host {
    struct addrinfo hints;
    memset(&hints, 0, sizeof(hints));
    hints.ai_family = AF_UNSPEC;
    hints.ai_socktype = SOCK_STREAM;

    struct addrinfo *result = NULL;
    int ga = getaddrinfo(host.UTF8String, NULL, &hints, &result);
    if (ga != 0 || !result) {
        return host;
    }

    NSString *firstIPv4 = nil;
    NSString *firstIPv6 = nil;
    char addressBuffer[INET6_ADDRSTRLEN] = {0};

    for (struct addrinfo *p = result; p != NULL; p = p->ai_next) {
        if (p->ai_family == AF_INET && !firstIPv4) {
            struct sockaddr_in *addr = (struct sockaddr_in *)p->ai_addr;
            if (inet_ntop(AF_INET, &(addr->sin_addr), addressBuffer, sizeof(addressBuffer))) {
                firstIPv4 = [NSString stringWithUTF8String:addressBuffer];
            }
        } else if (p->ai_family == AF_INET6 && !firstIPv6) {
            struct sockaddr_in6 *addr6 = (struct sockaddr_in6 *)p->ai_addr;
            if (inet_ntop(AF_INET6, &(addr6->sin6_addr), addressBuffer, sizeof(addressBuffer))) {
                firstIPv6 = [NSString stringWithUTF8String:addressBuffer];
            }
        }

        if (firstIPv4 && firstIPv6) {
            break;
        }
    }

    freeaddrinfo(result);

    if (self.IPv4PreferredOverIPv6) {
        return firstIPv4 ?: firstIPv6 ?: host;
    }
    return firstIPv6 ?: firstIPv4 ?: host;
}
#endif

#pragma mark - Init

- (instancetype)initWithDelegate:(id<GCDAsyncSocketDelegate>)delegate
                   delegateQueue:(dispatch_queue_t)delegateQueue {
    return [self initWithDelegate:delegate delegateQueue:delegateQueue socketQueue:NULL];
}

- (instancetype)initWithDelegate:(id<GCDAsyncSocketDelegate>)delegate
                   delegateQueue:(dispatch_queue_t)delegateQueue
                     socketQueue:(dispatch_queue_t)socketQueue {
    self = [super init];
    if (self) {
        _delegate = delegate;
        _delegateQueue = delegateQueue ?: dispatch_get_main_queue();
        _socketQueue = socketQueue ?: dispatch_queue_create("com.gcdasyncsocket.nw.socketQueue",
                                                            DISPATCH_QUEUE_SERIAL);
        dispatch_queue_set_specific(_socketQueue, kGCDAsyncSocketQueueKey, (void *)kGCDAsyncSocketQueueKey, NULL);
        _buffer = [[NWStreamBuffer alloc] init];
        _readQueue = [NSMutableArray array];
        _isReadingContinuously = NO;
        _tlsEnabled = NO;
        _streamingTextEnabled = NO;
        _IPv4PreferredOverIPv6 = YES;
    }
    return self;
}

- (void)setDelegate:(id<GCDAsyncSocketDelegate>)delegate delegateQueue:(dispatch_queue_t)delegateQueue {
    __weak typeof(self) weakSelf = self;
    dispatch_async(self.socketQueue, ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        strongSelf.delegate = delegate;
        strongSelf.delegateQueue = delegateQueue ?: dispatch_get_main_queue();
    });
}

- (void)performSyncOnSocketQueue:(dispatch_block_t)block {
    if (!block) {
        return;
    }
    if (dispatch_get_specific(kGCDAsyncSocketQueueKey)) {
        block();
    } else {
        dispatch_sync(self.socketQueue, block);
    }
}

- (BOOL)isConnected {
    __block BOOL connected = NO;
    [self performSyncOnSocketQueue:^{
        connected = _isConnected;
    }];
    return connected;
}

- (BOOL)isDisconnected {
    return !self.isConnected;
}

- (BOOL)isSecure {
    __block BOOL secure = NO;
    [self performSyncOnSocketQueue:^{
        secure = _isConnected && _tlsEnabled;
    }];
    return secure;
}

- (NSString *)connectedHost {
    __block NSString *host = nil;
    [self performSyncOnSocketQueue:^{
        host = _isConnected ? [_connectedHost copy] : nil;
    }];
    return host;
}

- (uint16_t)connectedPort {
    __block uint16_t port = 0;
    [self performSyncOnSocketQueue:^{
        port = _isConnected ? _connectedPort : 0;
    }];
    return port;
}

- (uint16_t)localPort {
    __block uint16_t port = 0;
    [self performSyncOnSocketQueue:^{
        if (_isListening) {
            port = _localPort;
        } else {
            port = _isConnected ? _localPort : 0;
        }
    }];
    return port;
}

- (NSString *)localHost {
    __block NSString *host = nil;
    [self performSyncOnSocketQueue:^{
        host = _isConnected ? [_localHost copy] : nil;
    }];
    return host;
}

- (void)dealloc {
#if NW_FRAMEWORK_AVAILABLE
    if (_listener) {
        nw_listener_cancel(_listener);
    }
    if (_connection) {
        nw_connection_cancel(_connection);
    }
#endif
}

#pragma mark - Configuration

- (void)enableTLS {
    _tlsEnabled = YES;
}

- (void)enableSSEParsing {
    __weak typeof(self) weakSelf = self;
    dispatch_async(self.socketQueue, ^{
        weakSelf.sseParser = [[NWSSEParser alloc] init];
    });
}

- (void)enableStreamingText {
    __weak typeof(self) weakSelf = self;
    dispatch_async(self.socketQueue, ^{
        weakSelf.streamingTextEnabled = YES;
    });
}

#pragma mark - Connect

- (BOOL)connectToHost:(NSString *)host onPort:(uint16_t)port error:(NSError **)errPtr {
    return [self connectToHost:host onPort:port withTimeout:-1 error:errPtr];
}

- (BOOL)acceptOnPort:(uint16_t)port error:(NSError **)errPtr {
    return [self acceptOnInterface:nil port:port error:errPtr];
}

- (BOOL)acceptOnInterface:(NSString *)interface port:(uint16_t)port error:(NSError **)errPtr {
#if NW_FRAMEWORK_AVAILABLE
    if (self.isListening) {
        if (errPtr) {
            *errPtr = [NSError errorWithDomain:GCDAsyncSocketErrorDomain
                                          code:GCDAsyncSocketErrorAlreadyConnected
                                      userInfo:@{NSLocalizedDescriptionKey: @"Socket is already listening."}];
        }
        return NO;
    }

    nw_parameters_t parameters = nw_parameters_create_secure_tcp(
        NW_PARAMETERS_DISABLE_PROTOCOL,
        NW_PARAMETERS_DEFAULT_CONFIGURATION
    );

    if (interface.length > 0) {
        // Bind to a specific interface/address
        NSString *portStr = [NSString stringWithFormat:@"%u", port];
        nw_endpoint_t localEndpoint = nw_endpoint_create_host(interface.UTF8String, portStr.UTF8String);
        nw_parameters_set_local_endpoint(parameters, localEndpoint);
    }

    nw_listener_t listener = nw_listener_create_with_port([NSString stringWithFormat:@"%u", port].UTF8String, parameters);
    if (!listener) {
        if (errPtr) {
            *errPtr = [NSError errorWithDomain:GCDAsyncSocketErrorDomain
                                          code:GCDAsyncSocketErrorConnectionFailed
                                      userInfo:@{NSLocalizedDescriptionKey: @"Failed to create listener."}];
        }
        return NO;
    }

    self.listener = listener;

    __weak typeof(self) weakSelf = self;

    nw_listener_set_state_changed_handler(listener, ^(nw_listener_state_t state, nw_error_t _Nullable error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;

        switch (state) {
            case nw_listener_state_ready: {
                strongSelf.isListening = YES;
                uint16_t assignedPort = nw_listener_get_port(listener);
                strongSelf.localPort = assignedPort;
                break;
            }
            case nw_listener_state_failed: {
                strongSelf.isListening = NO;
                NSError *nsError = [strongSelf socketErrorWithCode:GCDAsyncSocketErrorConnectionFailed
                                                       description:@"Listener failed."
                                                           reason:@"NW listener entered failed state"
                                                          nwError:error];
                [strongSelf disconnectInternalWithError:nsError];
                break;
            }
            case nw_listener_state_cancelled: {
                strongSelf.isListening = NO;
                break;
            }
            default:
                break;
        }
    });

    nw_listener_set_new_connection_handler(listener, ^(nw_connection_t newConnection) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;

        // Create a new GCDAsyncSocket for the accepted connection
        GCDAsyncSocket *newSocket = [[GCDAsyncSocket alloc] initWithDelegate:strongSelf.delegate
                                                               delegateQueue:strongSelf.delegateQueue
                                                                 socketQueue:nil];
        newSocket.connection = newConnection;

        // State change handler for the accepted connection
        nw_connection_set_state_changed_handler(newConnection, ^(nw_connection_state_t state, nw_error_t _Nullable error) {
            [newSocket handleStateChange:state error:error];
        });

        nw_connection_set_queue(newConnection, newSocket.socketQueue);
        nw_connection_start(newConnection);

        dispatch_async(strongSelf.delegateQueue, ^{
            id delegate = strongSelf.delegate;
            if ([delegate respondsToSelector:@selector(socket:didAcceptNewSocket:)]) {
                [delegate socket:strongSelf didAcceptNewSocket:newSocket];
            }
        });
    });

    nw_listener_set_queue(listener, self.socketQueue);
    nw_listener_start(listener);

    return YES;
#else
    if (errPtr) {
        *errPtr = [NSError errorWithDomain:GCDAsyncSocketErrorDomain
                                      code:GCDAsyncSocketErrorConnectionFailed
                                  userInfo:@{NSLocalizedDescriptionKey: @"Network.framework is not available on this platform."}];
    }
    return NO;
#endif
}

- (BOOL)acceptOnUrl:(NSURL *)url error:(NSError **)errPtr {
#if NW_FRAMEWORK_AVAILABLE
    if (self.isListening) {
        if (errPtr) {
            *errPtr = [NSError errorWithDomain:GCDAsyncSocketErrorDomain
                                          code:GCDAsyncSocketErrorAlreadyConnected
                                      userInfo:@{NSLocalizedDescriptionKey: @"Socket is already listening."}];
        }
        return NO;
    }

    if (!url.isFileURL) {
        if (errPtr) {
            *errPtr = [NSError errorWithDomain:GCDAsyncSocketErrorDomain
                                          code:GCDAsyncSocketErrorInvalidParameter
                                      userInfo:@{NSLocalizedDescriptionKey: @"URL must be a file URL for Unix Domain Socket."}];
        }
        return NO;
    }

    nw_parameters_t parameters = nw_parameters_create_secure_tcp(
        NW_PARAMETERS_DISABLE_PROTOCOL,
        NW_PARAMETERS_DEFAULT_CONFIGURATION
    );

    // Remove existing socket file if present
    NSString *path = url.path;
    [[NSFileManager defaultManager] removeItemAtPath:path error:nil];

    nw_endpoint_t localEndpoint = nw_endpoint_create_url(url.absoluteString.UTF8String);
    nw_parameters_set_local_endpoint(parameters, localEndpoint);

    nw_listener_t listener = nw_listener_create(parameters);
    if (!listener) {
        if (errPtr) {
            *errPtr = [NSError errorWithDomain:GCDAsyncSocketErrorDomain
                                          code:GCDAsyncSocketErrorConnectionFailed
                                      userInfo:@{NSLocalizedDescriptionKey: @"Failed to create Unix Domain Socket listener."}];
        }
        return NO;
    }

    self.listener = listener;

    __weak typeof(self) weakSelf = self;

    nw_listener_set_state_changed_handler(listener, ^(nw_listener_state_t state, nw_error_t _Nullable error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;

        switch (state) {
            case nw_listener_state_ready: {
                strongSelf.isListening = YES;
                break;
            }
            case nw_listener_state_failed: {
                strongSelf.isListening = NO;
                NSError *nsError = [strongSelf socketErrorWithCode:GCDAsyncSocketErrorConnectionFailed
                                                       description:@"Unix Domain Socket listener failed."
                                                           reason:@"NW listener entered failed state"
                                                          nwError:error];
                [strongSelf disconnectInternalWithError:nsError];
                break;
            }
            case nw_listener_state_cancelled: {
                strongSelf.isListening = NO;
                break;
            }
            default:
                break;
        }
    });

    nw_listener_set_new_connection_handler(listener, ^(nw_connection_t newConnection) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;

        GCDAsyncSocket *newSocket = [[GCDAsyncSocket alloc] initWithDelegate:strongSelf.delegate
                                                               delegateQueue:strongSelf.delegateQueue
                                                                 socketQueue:nil];
        newSocket.connection = newConnection;

        nw_connection_set_state_changed_handler(newConnection, ^(nw_connection_state_t state, nw_error_t _Nullable error) {
            [newSocket handleStateChange:state error:error];
        });

        nw_connection_set_queue(newConnection, newSocket.socketQueue);
        nw_connection_start(newConnection);

        dispatch_async(strongSelf.delegateQueue, ^{
            id delegate = strongSelf.delegate;
            if ([delegate respondsToSelector:@selector(socket:didAcceptNewSocket:)]) {
                [delegate socket:strongSelf didAcceptNewSocket:newSocket];
            }
        });
    });

    nw_listener_set_queue(listener, self.socketQueue);
    nw_listener_start(listener);

    return YES;
#else
    if (errPtr) {
        *errPtr = [NSError errorWithDomain:GCDAsyncSocketErrorDomain
                                      code:GCDAsyncSocketErrorConnectionFailed
                                  userInfo:@{NSLocalizedDescriptionKey: @"Network.framework is not available on this platform."}];
    }
    return NO;
#endif
}

- (BOOL)connectToHost:(NSString *)host
               onPort:(uint16_t)port
          withTimeout:(NSTimeInterval)timeout
                error:(NSError **)errPtr {

    if (self.isConnected) {
        if (errPtr) {
            *errPtr = [NSError errorWithDomain:GCDAsyncSocketErrorDomain
                                          code:GCDAsyncSocketErrorAlreadyConnected
                                      userInfo:@{NSLocalizedDescriptionKey: @"Socket is already connected."}];
        }
        return NO;
    }

#if NW_FRAMEWORK_AVAILABLE
    // Create endpoint (resolve with configurable IPv4/IPv6 preference)
    NSString *portStr = [NSString stringWithFormat:@"%u", port];
    NSString *targetHost = [self preferredHostForHost:host];
    nw_endpoint_t endpoint = nw_endpoint_create_host(targetHost.UTF8String, portStr.UTF8String);

    // Create parameters
    nw_parameters_t parameters;
    if (self.tlsEnabled) {
        parameters = nw_parameters_create_secure_tcp(
            NW_PARAMETERS_DEFAULT_CONFIGURATION,
            NW_PARAMETERS_DEFAULT_CONFIGURATION
        );
    } else {
        parameters = nw_parameters_create_secure_tcp(
            NW_PARAMETERS_DISABLE_PROTOCOL,
            NW_PARAMETERS_DEFAULT_CONFIGURATION
        );
    }

    // Create connection
    nw_connection_t conn = nw_connection_create(endpoint, parameters);
    self.connection = conn;
    self.connectedHost = targetHost;
    self.connectedPort = port;
    self.localHost = nil;
    self.localPort = 0;

    // State change handler
    __weak typeof(self) weakSelf = self;
    nw_connection_set_state_changed_handler(conn, ^(nw_connection_state_t state, nw_error_t _Nullable error) {
        [weakSelf handleStateChange:state error:error];
    });

    // Start connection
    nw_connection_set_queue(conn, self.socketQueue);
    nw_connection_start(conn);

    // Connection timeout
    if (timeout > 0) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(timeout * NSEC_PER_SEC)),
                       self.socketQueue, ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (strongSelf && !strongSelf.isConnected) {
                NSError *timeoutError = [strongSelf socketErrorWithCode:GCDAsyncSocketErrorConnectionFailed
                                                              description:@"Connection timed out."
                                                                  reason:@"Connect timeout"
                                                                 nwError:nil];
                [strongSelf disconnectWithError:timeoutError];
            }
        });
    }

    return YES;
#else
    if (errPtr) {
        *errPtr = [NSError errorWithDomain:GCDAsyncSocketErrorDomain
                                      code:GCDAsyncSocketErrorConnectionFailed
                                  userInfo:@{NSLocalizedDescriptionKey: @"Network.framework is not available on this platform."}];
    }
    return NO;
#endif
}

#pragma mark - Disconnect

- (void)disconnect {
    __weak typeof(self) weakSelf = self;
    dispatch_async(self.socketQueue, ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
#if NW_FRAMEWORK_AVAILABLE
        // Stop listener if in server mode
        if (strongSelf.listener) {
            nw_listener_cancel(strongSelf.listener);
            strongSelf.listener = nil;
            strongSelf.isListening = NO;
            strongSelf.localPort = 0;
        }
#endif
        [strongSelf disconnectInternalWithError:nil];
    });
}

- (void)disconnectAfterWriting {
    [self disconnect];
}

- (void)disconnectAfterReading {
    [self disconnect];
}

#pragma mark - Reading

- (void)readDataWithTimeout:(NSTimeInterval)timeout tag:(long)tag {
    __weak typeof(self) weakSelf = self;
    dispatch_async(self.socketQueue, ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        NWReadRequest *req = [NWReadRequest availableRequestWithTimeout:timeout tag:tag];
        [strongSelf.readQueue addObject:req];
        [strongSelf dequeueNextRead];
    });
}

- (void)readDataToLength:(NSUInteger)length withTimeout:(NSTimeInterval)timeout tag:(long)tag {
    __weak typeof(self) weakSelf = self;
    dispatch_async(self.socketQueue, ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        NWReadRequest *req = [NWReadRequest toLengthRequest:length timeout:timeout tag:tag];
        [strongSelf.readQueue addObject:req];
        [strongSelf dequeueNextRead];
    });
}

- (void)readDataToData:(NSData *)data withTimeout:(NSTimeInterval)timeout tag:(long)tag {
    [self readDataToData:data withTimeout:timeout maxLength:0 tag:tag];
}

- (void)readDataToData:(NSData *)data
           withTimeout:(NSTimeInterval)timeout
             maxLength:(NSUInteger)maxLength
                   tag:(long)tag {
    __weak typeof(self) weakSelf = self;
    dispatch_async(self.socketQueue, ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        NWReadRequest *req = [NWReadRequest toDelimiterRequest:data
                                                       timeout:timeout
                                                     maxLength:maxLength
                                                           tag:tag];
        [strongSelf.readQueue addObject:req];
        [strongSelf dequeueNextRead];
    });
}

#pragma mark - Writing

- (void)writeData:(NSData *)data withTimeout:(NSTimeInterval)timeout tag:(long)tag {
#if NW_FRAMEWORK_AVAILABLE
    __weak typeof(self) weakSelf = self;
    dispatch_async(self.socketQueue, ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;

        if (!strongSelf.connection || !strongSelf.isConnected) {
            dispatch_async(strongSelf.delegateQueue, ^{
                NSError *err = [strongSelf socketErrorWithCode:GCDAsyncSocketErrorNotConnected
                                                     description:@"Socket is not connected."
                                                         reason:@"Write requested while socket not connected"
                                                        nwError:nil];
                id delegate = strongSelf.delegate;
                if ([delegate respondsToSelector:@selector(socketDidDisconnect:withError:)]) {
                    [delegate socketDidDisconnect:strongSelf withError:err];
                }
            });
            return;
        }

        // Convert NSData to dispatch_data_t
        dispatch_data_t dispatchData = dispatch_data_create(data.bytes, data.length,
                                                            strongSelf.socketQueue,
                                                            DISPATCH_DATA_DESTRUCTOR_DEFAULT);

        __block BOOL timedOut = NO;
        __block BOOL writeCompleted = NO;
        __block dispatch_block_t timeoutBlock = nil;

        if (timeout > 0) {
            timeoutBlock = dispatch_block_create(0, ^{
                if (!writeCompleted) {
                    timedOut = YES;
                    NSError *err = [strongSelf socketErrorWithCode:GCDAsyncSocketErrorWriteTimeout
                                                         description:@"Write timed out."
                                                             reason:@"Write timeout"
                                                            nwError:nil];
                    [strongSelf disconnectWithError:err];
                }
            });
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(timeout * NSEC_PER_SEC)),
                           strongSelf.socketQueue, timeoutBlock);
        }

        nw_connection_send(strongSelf.connection, dispatchData,
                           NW_CONNECTION_DEFAULT_MESSAGE_CONTEXT,
                           true, ^(nw_error_t _Nullable error) {
            writeCompleted = YES;
            if (timeoutBlock) {
                dispatch_block_cancel(timeoutBlock);
            }
            if (timedOut) return;

            __strong typeof(weakSelf) sself = weakSelf;
            if (!sself) return;

            if (error) {
                NSError *nsError = [sself socketErrorWithCode:GCDAsyncSocketErrorConnectionFailed
                                                  description:@"Write failed."
                                                      reason:@"nw_connection_send failed"
                                                     nwError:error];
                [sself disconnectWithError:nsError];
            } else {
                dispatch_async(sself.delegateQueue, ^{
                    id delegate = sself.delegate;
                    if ([delegate respondsToSelector:@selector(socket:didWriteDataWithTag:)]) {
                        [delegate socket:sself didWriteDataWithTag:tag];
                    }
                });
            }
        });
    });
#endif
}

#pragma mark - Private: State handling

#if NW_FRAMEWORK_AVAILABLE
- (void)handleStateChange:(nw_connection_state_t)state error:(nw_error_t _Nullable)error {
    switch (state) {
        case nw_connection_state_ready: {
            self.isConnected = YES;
#if NW_FRAMEWORK_AVAILABLE
            nw_path_t path = nw_connection_copy_current_path(self.connection);
            if (path) {
                nw_endpoint_t localEndpoint = nw_path_copy_effective_local_endpoint(path);
                if (localEndpoint) {
                    const char *localHostStr = nw_endpoint_get_hostname(localEndpoint);
                    if (localHostStr) {
                        self.localHost = [NSString stringWithUTF8String:localHostStr];
                    }
                    const char *localPortStr = nw_endpoint_get_port(localEndpoint);
                    if (localPortStr) {
                        self.localPort = (uint16_t)strtoul(localPortStr, NULL, 10);
                    }
                }
            }
#endif
            NSString *host = self.connectedHost ?: @"";
            uint16_t port = self.connectedPort;
            __weak typeof(self) weakSelf = self;
            dispatch_async(self.delegateQueue, ^{
                id delegate = weakSelf.delegate;
                if ([delegate respondsToSelector:@selector(socket:didConnectToHost:port:)]) {
                    [delegate socket:weakSelf didConnectToHost:host port:port];
                }
            });
            [self startContinuousRead];
            break;
        }
        case nw_connection_state_failed: {
            NSError *nsError = [self socketErrorWithCode:GCDAsyncSocketErrorConnectionFailed
                                             description:@"Connection failed."
                                                 reason:@"NW connection entered failed state"
                                                nwError:error];
            [self disconnectInternalWithError:nsError];
            break;
        }
        case nw_connection_state_cancelled: {
            [self disconnectInternalWithError:nil];
            break;
        }
        default:
            break;
    }
}
#endif

#pragma mark - Private: Continuous read loop

- (void)startContinuousRead {
    if (self.isReadingContinuously) return;
    self.isReadingContinuously = YES;
    [self readNextChunk];
}

- (void)readNextChunk {
#if NW_FRAMEWORK_AVAILABLE
    if (!self.connection || !self.isConnected) return;

    __weak typeof(self) weakSelf = self;
    nw_connection_receive(self.connection, 1, 65536,
                          ^(dispatch_data_t _Nullable content,
                            nw_content_context_t _Nullable context,
                            bool is_complete,
                            nw_error_t _Nullable error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;

        if (content) {
            // Convert dispatch_data_t to NSData
            const void *buffer;
            size_t size;
            __unused dispatch_data_t contiguous = dispatch_data_create_map(content, &buffer, &size);
            NSData *data = [NSData dataWithBytes:buffer length:size];

            [strongSelf.buffer appendData:data];

            // SSE parsing mode
            if (strongSelf.sseParser) {
                NSArray<NWSSEEvent *> *events = [strongSelf.sseParser parseData:data];
                for (NWSSEEvent *event in events) {
                    dispatch_async(strongSelf.delegateQueue, ^{
                        if ([strongSelf.delegate respondsToSelector:@selector(socket:didReceiveSSEEvent:)]) {
                            [strongSelf.delegate socket:strongSelf didReceiveSSEEvent:event];
                        }
                    });
                }
            }

            // Streaming text mode: extract UTF-8 safe string from the
            // newly received data without consuming the buffer.
            if (strongSelf.streamingTextEnabled) {
                NSUInteger safeCount = [NWStreamBuffer utf8SafeByteCountForData:data];
                if (safeCount > 0) {
                    NSData *safeData = [data subdataWithRange:NSMakeRange(0, safeCount)];
                    NSString *str = [[NSString alloc] initWithData:safeData encoding:NSUTF8StringEncoding];
                    if (str) {
                        dispatch_async(strongSelf.delegateQueue, ^{
                            if ([strongSelf.delegate respondsToSelector:@selector(socket:didReceiveString:)]) {
                                [strongSelf.delegate socket:strongSelf didReceiveString:str];
                            }
                        });
                    }
                }
            }

            // Process read queue
            [strongSelf processReadQueue];
        }

        if (is_complete) {
            NSError *eofError = [strongSelf socketErrorWithCode:GCDAsyncSocketErrorConnectionFailed
                                                    description:@"Connection closed by peer."
                                                        reason:@"EOF received (nw_connection_receive is_complete=1)"
                                                       nwError:nil];
            [strongSelf disconnectInternalWithError:eofError];
            return;
        }

        if (error) {
            NSError *nsError = [strongSelf socketErrorWithCode:GCDAsyncSocketErrorConnectionFailed
                                                   description:@"Read error."
                                                       reason:@"nw_connection_receive returned error"
                                                      nwError:error];
            [strongSelf disconnectInternalWithError:nsError];
            return;
        }

        // Continue reading
        [strongSelf readNextChunk];
    });
#endif
}

#pragma mark - Private: Read queue processing

- (void)dequeueNextRead {
    [self processReadQueue];
}

- (void)processReadQueue {
    while (self.readQueue.count > 0) {
        NWReadRequest *request = self.readQueue[0];

        switch (request.type) {
            case NWReadRequestTypeAvailable: {
                if (!self.buffer.isEmpty) {
                    NSData *data = [self.buffer readAllData];
                    [self.readQueue removeObjectAtIndex:0];
                    long tag = request.tag;
                    __weak typeof(self) weakSelf = self;
                    dispatch_async(self.delegateQueue, ^{
                        id delegate = weakSelf.delegate;
                        if ([delegate respondsToSelector:@selector(socket:didReadData:withTag:)]) {
                            [delegate socket:weakSelf didReadData:data withTag:tag];
                        }
                    });
                } else {
                    return;
                }
                break;
            }
            case NWReadRequestTypeToLength: {
                NSData *data = [self.buffer readDataToLength:request.length];
                if (data) {
                    [self.readQueue removeObjectAtIndex:0];
                    long tag = request.tag;
                    __weak typeof(self) weakSelf = self;
                    dispatch_async(self.delegateQueue, ^{
                        id delegate = weakSelf.delegate;
                        if ([delegate respondsToSelector:@selector(socket:didReadData:withTag:)]) {
                            [delegate socket:weakSelf didReadData:data withTag:tag];
                        }
                    });
                } else {
                    return;
                }
                break;
            }
            case NWReadRequestTypeToDelimiter: {
                NSData *data = [self.buffer readDataToDelimiter:request.delimiter];
                if (data) {
                    [self.readQueue removeObjectAtIndex:0];
                    long tag = request.tag;
                    __weak typeof(self) weakSelf = self;
                    dispatch_async(self.delegateQueue, ^{
                        id delegate = weakSelf.delegate;
                        if ([delegate respondsToSelector:@selector(socket:didReadData:withTag:)]) {
                            [delegate socket:weakSelf didReadData:data withTag:tag];
                        }
                    });
                } else {
                    if (request.maxLength > 0 && self.buffer.count > request.maxLength) {
                        NSError *maxError = [self socketErrorWithCode:GCDAsyncSocketErrorInvalidParameter
                                                          description:@"Read exceeded maxLength before delimiter was found."
                                                              reason:@"Read to delimiter maxLength overflow"
                                                             nwError:nil];
                        [self disconnectInternalWithError:maxError];
                    }
                    return;
                }
                break;
            }
        }
    }
}

#pragma mark - Private: Disconnect

- (void)disconnectWithError:(NSError *)error {
    __weak typeof(self) weakSelf = self;
    dispatch_async(self.socketQueue, ^{
        [weakSelf disconnectInternalWithError:error];
    });
}

- (void)disconnectInternalWithError:(NSError *)error {
    if (!self.isConnected && !self.isListening
#if NW_FRAMEWORK_AVAILABLE
        && !self.connection && !self.listener
#endif
    ) {
        return;
    }

    self.isConnected = NO;
    self.isReadingContinuously = NO;

#if NW_FRAMEWORK_AVAILABLE
    if (self.listener) {
        nw_listener_cancel(self.listener);
        self.listener = nil;
        self.isListening = NO;
    }
    if (self.connection) {
        nw_connection_cancel(self.connection);
        self.connection = nil;
    }
#endif

    self.connectedHost = nil;
    self.connectedPort = 0;
    self.localHost = nil;
    self.localPort = 0;
    [self.readQueue removeAllObjects];
    [self.buffer reset];
    [self.sseParser reset];

    __weak typeof(self) weakSelf = self;
    dispatch_async(self.delegateQueue, ^{
        id delegate = weakSelf.delegate;
        if ([delegate respondsToSelector:@selector(socketDidDisconnect:withError:)]) {
            [delegate socketDidDisconnect:weakSelf withError:error];
        }
    });
}

@end
