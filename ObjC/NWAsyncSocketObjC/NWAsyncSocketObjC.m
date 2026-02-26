//
//  NWAsyncSocketObjC.m
//  NWAsyncSocketObjC
//
//  TCP socket using Network.framework's C API (nw_connection_t).
//  Only compiles on Apple platforms (iOS 13+, macOS 10.15+).
//

#import "NWAsyncSocketObjC.h"

#if __has_include(<Network/Network.h>)
#define NW_FRAMEWORK_AVAILABLE 1
#import <Network/Network.h>
#else
#define NW_FRAMEWORK_AVAILABLE 0
#endif

NSString * const NWAsyncSocketObjCErrorDomain = @"NWAsyncSocketObjCErrorDomain";

@interface NWAsyncSocketObjC ()
@property (nonatomic, readwrite, copy, nullable) NSString *connectedHost;
@property (nonatomic, readwrite) uint16_t connectedPort;
@property (nonatomic, readwrite) BOOL isConnected;

#if NW_FRAMEWORK_AVAILABLE
@property (nonatomic, assign) nw_connection_t connection;
#endif

@property (nonatomic, strong) dispatch_queue_t socketQueue;
@property (nonatomic, strong) NWStreamBuffer *buffer;
@property (nonatomic, strong) NSMutableArray<NWReadRequest *> *readQueue;
@property (nonatomic, assign) BOOL isReadingContinuously;

// SSE / streaming text mode
@property (nonatomic, strong, nullable) NWSSEParser *sseParser;
@property (nonatomic, assign) BOOL streamingTextEnabled;

// TLS
@property (nonatomic, assign) BOOL tlsEnabled;
@end

@implementation NWAsyncSocketObjC

#pragma mark - Init

- (instancetype)initWithDelegate:(id<NWAsyncSocketObjCDelegate>)delegate
                   delegateQueue:(dispatch_queue_t)delegateQueue {
    self = [super init];
    if (self) {
        _delegate = delegate;
        _delegateQueue = delegateQueue;
        _socketQueue = dispatch_queue_create("com.nwasyncsocket.objc.socketQueue",
                                             DISPATCH_QUEUE_SERIAL);
        _buffer = [[NWStreamBuffer alloc] init];
        _readQueue = [NSMutableArray array];
        _isReadingContinuously = NO;
        _tlsEnabled = NO;
        _streamingTextEnabled = NO;
    }
    return self;
}

- (void)dealloc {
#if NW_FRAMEWORK_AVAILABLE
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

- (BOOL)connectToHost:(NSString *)host
               onPort:(uint16_t)port
          withTimeout:(NSTimeInterval)timeout
                error:(NSError **)errPtr {

    if (self.isConnected) {
        if (errPtr) {
            *errPtr = [NSError errorWithDomain:NWAsyncSocketObjCErrorDomain
                                          code:NWAsyncSocketObjCErrorAlreadyConnected
                                      userInfo:@{NSLocalizedDescriptionKey: @"Socket is already connected."}];
        }
        return NO;
    }

#if NW_FRAMEWORK_AVAILABLE
    // Create endpoint
    NSString *portStr = [NSString stringWithFormat:@"%u", port];
    nw_endpoint_t endpoint = nw_endpoint_create_host(host.UTF8String, portStr.UTF8String);

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
    self.connectedHost = host;
    self.connectedPort = port;

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
                NSError *timeoutError = [NSError errorWithDomain:NWAsyncSocketObjCErrorDomain
                                                           code:NWAsyncSocketObjCErrorConnectionFailed
                                                       userInfo:@{NSLocalizedDescriptionKey: @"Connection timed out."}];
                [strongSelf disconnectWithError:timeoutError];
            }
        });
    }

    return YES;
#else
    if (errPtr) {
        *errPtr = [NSError errorWithDomain:NWAsyncSocketObjCErrorDomain
                                      code:NWAsyncSocketObjCErrorConnectionFailed
                                  userInfo:@{NSLocalizedDescriptionKey: @"Network.framework is not available on this platform."}];
    }
    return NO;
#endif
}

#pragma mark - Disconnect

- (void)disconnect {
    __weak typeof(self) weakSelf = self;
    dispatch_async(self.socketQueue, ^{
        [weakSelf disconnectInternalWithError:nil];
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
    __weak typeof(self) weakSelf = self;
    dispatch_async(self.socketQueue, ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        NWReadRequest *req = [NWReadRequest toDelimiterRequest:data timeout:timeout tag:tag];
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
                NSError *err = [NSError errorWithDomain:NWAsyncSocketObjCErrorDomain
                                                   code:NWAsyncSocketObjCErrorNotConnected
                                               userInfo:@{NSLocalizedDescriptionKey: @"Socket is not connected."}];
                [strongSelf.delegate socketDidDisconnect:strongSelf withError:err];
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
                    NSError *err = [NSError errorWithDomain:NWAsyncSocketObjCErrorDomain
                                                       code:NWAsyncSocketObjCErrorWriteTimeout
                                                   userInfo:@{NSLocalizedDescriptionKey: @"Write timed out."}];
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
                NSError *nsError = [NSError errorWithDomain:NWAsyncSocketObjCErrorDomain
                                                       code:NWAsyncSocketObjCErrorConnectionFailed
                                                   userInfo:@{NSLocalizedDescriptionKey: @"Write failed."}];
                [sself disconnectWithError:nsError];
            } else {
                dispatch_async(sself.delegateQueue, ^{
                    [sself.delegate socket:sself didWriteDataWithTag:tag];
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
            NSString *host = self.connectedHost ?: @"";
            uint16_t port = self.connectedPort;
            __weak typeof(self) weakSelf = self;
            dispatch_async(self.delegateQueue, ^{
                [weakSelf.delegate socket:weakSelf didConnectToHost:host port:port];
            });
            [self startContinuousRead];
            break;
        }
        case nw_connection_state_failed: {
            NSError *nsError = nil;
            if (error) {
                nsError = [NSError errorWithDomain:NWAsyncSocketObjCErrorDomain
                                              code:NWAsyncSocketObjCErrorConnectionFailed
                                          userInfo:@{NSLocalizedDescriptionKey: @"Connection failed."}];
            }
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
            dispatch_data_t contiguous = dispatch_data_create_map(content, &buffer, &size);
            NSData *data = [NSData dataWithBytes:buffer length:size];
            (void)contiguous; // Keep reference alive

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

            // Streaming text mode
            if (strongSelf.streamingTextEnabled) {
                NSString *str = [strongSelf.buffer readUTF8SafeString];
                if (str) {
                    dispatch_async(strongSelf.delegateQueue, ^{
                        if ([strongSelf.delegate respondsToSelector:@selector(socket:didReceiveString:)]) {
                            [strongSelf.delegate socket:strongSelf didReceiveString:str];
                        }
                    });
                }
            }

            // Process read queue
            [strongSelf processReadQueue];
        }

        if (is_complete) {
            [strongSelf disconnectInternalWithError:nil];
            return;
        }

        if (error) {
            NSError *nsError = [NSError errorWithDomain:NWAsyncSocketObjCErrorDomain
                                                   code:NWAsyncSocketObjCErrorConnectionFailed
                                               userInfo:@{NSLocalizedDescriptionKey: @"Read error."}];
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
                        [weakSelf.delegate socket:weakSelf didReadData:data withTag:tag];
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
                        [weakSelf.delegate socket:weakSelf didReadData:data withTag:tag];
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
                        [weakSelf.delegate socket:weakSelf didReadData:data withTag:tag];
                    });
                } else {
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
    if (!self.isConnected
#if NW_FRAMEWORK_AVAILABLE
        && !self.connection
#endif
    ) {
        return;
    }

    self.isConnected = NO;
    self.isReadingContinuously = NO;

#if NW_FRAMEWORK_AVAILABLE
    if (self.connection) {
        nw_connection_cancel(self.connection);
        self.connection = nil;
    }
#endif

    self.connectedHost = nil;
    self.connectedPort = 0;
    [self.readQueue removeAllObjects];
    [self.buffer reset];
    [self.sseParser reset];

    __weak typeof(self) weakSelf = self;
    dispatch_async(self.delegateQueue, ^{
        [weakSelf.delegate socketDidDisconnect:weakSelf withError:error];
    });
}

@end
