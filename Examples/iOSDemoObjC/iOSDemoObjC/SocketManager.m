//
//  SocketManager.m
//  iOSDemoObjC
//

#import "SocketManager.h"
#import "NWSSEParser.h"

NSNotificationName const SocketManagerDidUpdateNotification = @"SocketManagerDidUpdate";

@interface SocketManager () <GCDAsyncSocketDelegate>
@property (nonatomic, strong, nullable) GCDAsyncSocket *socket;
@property (nonatomic, assign) long readTag;
@property (nonatomic, strong) NSMutableArray<NSString *> *mutableLogs;
@property (nonatomic, strong) NSMutableData *mutableReceivedData;
@property (nonatomic, strong) NSMutableString *mutableReceivedText;
@property (nonatomic, strong) NSMutableArray<NWSSEEvent *> *mutableSSEEvents;
@property (nonatomic, assign) BOOL pendingManualDisconnect;
@property (nonatomic, copy) NSString *lastConnectHost;
@property (nonatomic, assign) uint16_t lastConnectPort;
@property (nonatomic, assign) BOOL lastUseTLS;
@property (nonatomic, assign) BOOL lastEnableSSE;
@property (nonatomic, assign) BOOL lastEnableStreaming;
@end

@implementation SocketManager

+ (NSData *)JYHeadData2013 {
    int64_t i = 2013;
    NSData *data = [NSData dataWithBytes:&i length:6];
    return data;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _readTag = 0;
        _mutableLogs = [NSMutableArray array];
        _mutableReceivedData = [NSMutableData data];
        _mutableReceivedText = [NSMutableString string];
        _mutableSSEEvents = [NSMutableArray array];
        _pendingManualDisconnect = NO;
        _lastConnectHost = @"";
        _lastConnectPort = 0;
        _lastUseTLS = NO;
        _lastEnableSSE = NO;
        _lastEnableStreaming = NO;
    }
    return self;
}

#pragma mark - Public Accessors

- (NSArray<NSString *> *)logs {
    return [self.mutableLogs copy];
}

- (NSData *)receivedData {
    return [self.mutableReceivedData copy];
}

- (NSString *)receivedText {
    return [self.mutableReceivedText copy];
}

- (NSArray<NWSSEEvent *> *)sseEvents {
    return [self.mutableSSEEvents copy];
}

- (void)runCompatibilityAPIDemoOnSocket:(GCDAsyncSocket *)socket {
    // Compatibility example (disabled by default):
    // [socket setDelegate:nil delegateQueue:nil];
    // [socket readDataToData:[NSData dataWithBytes:"\x48\xF2\x74\xFA" length:4] withTimeout:-1 maxLength:0 tag:0];
    dispatch_queue_t queue = socket.delegateQueue;
    (void)queue;
}

#pragma mark - Connection

- (void)connectToHost:(NSString *)host
                 port:(uint16_t)port
               useTLS:(BOOL)useTLS
            enableSSE:(BOOL)enableSSE
      enableStreaming:(BOOL)enableStreaming {

    self.lastConnectHost = host ?: @"";
    self.lastConnectPort = port;
    self.lastUseTLS = useTLS;
    self.lastEnableSSE = enableSSE;
    self.lastEnableStreaming = enableStreaming;

    if (self.socket) {
        [self appendLog:@"↻ Existing connection found, closing it before reconnecting"];
    }
    [self disconnect];

    GCDAsyncSocket *sock = [[GCDAsyncSocket alloc] initWithDelegate:self
                                                       delegateQueue:dispatch_get_main_queue()
                                                         socketQueue:NULL];
    sock.IPv4PreferredOverIPv6 = YES;
    if (useTLS) {
        [sock enableTLS];
    }
    if (enableSSE) {
        [sock enableSSEParsing];
    }
    if (enableStreaming) {
        [sock enableStreamingText];
    }

    self.socket = sock;
    [self appendLog:[NSString stringWithFormat:@"Connecting to %@:%u...", host, port]];
    [self appendLog:[NSString stringWithFormat:@"Socket queue ready (delegateQueue=%p, IPv4PreferredOverIPv6=%@)",
                     sock.delegateQueue,
                     sock.IPv4PreferredOverIPv6 ? @"YES" : @"NO"]];
    [self appendLog:[NSString stringWithFormat:@"Config: TLS=%@, SSE=%@, Streaming=%@",
                     useTLS ? @"ON" : @"OFF",
                     enableSSE ? @"ON" : @"OFF",
                     enableStreaming ? @"ON" : @"OFF"]];

    NSError *err = nil;
    if (![sock connectToHost:host onPort:port withTimeout:15 error:&err]) {
        [self appendLog:[NSString stringWithFormat:@"❌ Connect start failed: %@ (domain=%@ code=%ld)",
                         err.localizedDescription,
                         err.domain,
                         (long)err.code]];
    }
}

- (void)disconnect {
    if (!self.socket) {
        return;
    }
    self.pendingManualDisconnect = YES;
    [self appendLog:@"⏹ Disconnect requested by client"];
    [self.socket disconnect];
    self.socket = nil;
}

- (void)sendText:(NSString *)text {
    NSData *data = [text dataUsingEncoding:NSUTF8StringEncoding];
    if (!data) {
        [self appendLog:@"❌ Failed to encode text"];
        return;
    }
    [self sendData:data];
}

- (void)sendData:(NSData *)data {
    if (!self.socket) {
        [self appendLog:@"❌ Not connected"];
        return;
    }
    long tag = self.readTag;
    self.readTag++;
    [self.socket writeData:data withTimeout:30 tag:tag];
    [self appendLog:[NSString stringWithFormat:@"📤 Sent %lu bytes (tag: %ld)",
                     (unsigned long)data.length, tag]];
}

- (void)readData {
    if (!self.socket) {
        [self appendLog:@"❌ Not connected"];
        return;
    }
    long tag = self.readTag;
    self.readTag++;
    [self.socket readDataWithTimeout:30 tag:tag];
}

- (void)clearAll {
    [self.mutableLogs removeAllObjects];
    self.mutableReceivedData = [NSMutableData data];
    self.mutableReceivedText = [NSMutableString string];
    [self.mutableSSEEvents removeAllObjects];
    self.readTag = 0;
    [self notify];
}

#pragma mark - Private

- (void)appendLog:(NSString *)message {
    [self.mutableLogs addObject:message];
    [self notify];
}

- (void)notify {
    [[NSNotificationCenter defaultCenter] postNotificationName:SocketManagerDidUpdateNotification
                                                        object:self];
}

#pragma mark - GCDAsyncSocketDelegate

- (void)socket:(GCDAsyncSocket *)sock didConnectToHost:(NSString *)host port:(uint16_t)port {
    _isConnected = YES;
    self.pendingManualDisconnect = NO;

    [self appendLog:[NSString stringWithFormat:@"✅ Connected to %@:%u", host, port]];

    NSData *handshake = [[self class] JYHeadData2013];
    long handshakeTag = self.readTag;
    self.readTag++;
    [sock writeData:handshake withTimeout:30 tag:handshakeTag];
    [self appendLog:[NSString stringWithFormat:@"🤝 Sent handshake (%lu bytes, tag: %ld)",
                     (unsigned long)handshake.length,
                     handshakeTag]];

    [sock readDataWithTimeout:-1 tag:self.readTag];
    self.readTag++;
}

- (void)socket:(GCDAsyncSocket *)sock didReadData:(NSData *)data withTag:(long)tag {
    [self.mutableReceivedData appendData:data];
    [self appendLog:[NSString stringWithFormat:@"📥 Received %lu bytes (tag: %ld)",
                     (unsigned long)data.length, tag]];
    [sock readDataWithTimeout:-1 tag:self.readTag];
    self.readTag++;
}

- (void)socket:(GCDAsyncSocket *)sock didWriteDataWithTag:(long)tag {
    [self appendLog:[NSString stringWithFormat:@"✅ Write complete (tag: %ld)", tag]];
}

- (void)socketDidDisconnect:(GCDAsyncSocket *)sock withError:(NSError *)error {
    _isConnected = NO;

    NSString *target = self.lastConnectHost.length > 0
        ? [NSString stringWithFormat:@"%@:%u", self.lastConnectHost, self.lastConnectPort]
        : @"unknown target";

    if (error) {
        NSString *reason = error.userInfo[@"GCDAsyncSocketDisconnectReason"];
        NSString *nwDomain = error.userInfo[@"GCDAsyncSocketNWErrorDomain"];
        NSNumber *nwCode = error.userInfo[@"GCDAsyncSocketNWErrorCode"];

        NSMutableString *details = [NSMutableString stringWithFormat:@"🔴 Disconnected from %@ with error: %@ (domain=%@ code=%ld)",
                                 target,
                                 error.localizedDescription,
                                 error.domain,
                                 (long)error.code];
        if (reason.length > 0) {
            [details appendFormat:@" | reason=%@", reason];
        }
        if (nwDomain.length > 0 && nwCode != nil) {
            [details appendFormat:@" | nw_error=%@/%ld", nwDomain, (long)nwCode.integerValue];
        }
        [self appendLog:details];
    } else if (self.pendingManualDisconnect) {
        [self appendLog:[NSString stringWithFormat:@"🟠 Disconnected from %@ (client requested)", target]];
    } else {
        [self appendLog:[NSString stringWithFormat:@"🟡 Disconnected from %@ (peer closed connection)", target]];
    }

    self.pendingManualDisconnect = NO;
}

- (void)socket:(GCDAsyncSocket *)sock didReceiveSSEEvent:(NWSSEEvent *)event {
    [self.mutableSSEEvents addObject:event];
    NSString *prefix = event.data.length > 100 ? [event.data substringToIndex:100] : event.data;
    [self appendLog:[NSString stringWithFormat:@"📡 SSE Event: type=%@, data=%@",
                     event.event, prefix]];
}

- (void)socket:(GCDAsyncSocket *)sock didReceiveString:(NSString *)string {
    [self.mutableReceivedText appendString:string];
    NSString *prefix = string.length > 100 ? [string substringToIndex:100] : string;
    [self appendLog:[NSString stringWithFormat:@"📝 Text chunk: %@", prefix]];
}

@end
