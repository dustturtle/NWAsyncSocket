//
//  SocketManager.m
//  iOSDemoObjC
//

#import "SocketManager.h"

NSNotificationName const SocketManagerDidUpdateNotification = @"SocketManagerDidUpdate";

@interface SocketManager () <GCDAsyncSocketDelegate>
@property (nonatomic, strong, nullable) GCDAsyncSocket *socket;
@property (nonatomic, assign) long readTag;
@property (nonatomic, strong) NSMutableArray<NSString *> *mutableLogs;
@property (nonatomic, strong) NSMutableData *mutableReceivedData;
@property (nonatomic, strong) NSMutableString *mutableReceivedText;
@property (nonatomic, strong) NSMutableArray<NWSSEEvent *> *mutableSSEEvents;
@end

@implementation SocketManager

- (instancetype)init {
    self = [super init];
    if (self) {
        _readTag = 0;
        _mutableLogs = [NSMutableArray array];
        _mutableReceivedData = [NSMutableData data];
        _mutableReceivedText = [NSMutableString string];
        _mutableSSEEvents = [NSMutableArray array];
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

#pragma mark - Connection

- (void)connectToHost:(NSString *)host
                 port:(uint16_t)port
               useTLS:(BOOL)useTLS
            enableSSE:(BOOL)enableSSE
      enableStreaming:(BOOL)enableStreaming {

    [self disconnect];

    GCDAsyncSocket *sock = [[GCDAsyncSocket alloc] initWithDelegate:self
                                                       delegateQueue:dispatch_get_main_queue()];
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

    NSError *err = nil;
    if (![sock connectToHost:host onPort:port withTimeout:15 error:&err]) {
        [self appendLog:[NSString stringWithFormat:@"❌ Connect error: %@", err.localizedDescription]];
    }
}

- (void)disconnect {
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
    [self appendLog:[NSString stringWithFormat:@"✅ Connected to %@:%u", host, port]];
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
    if (error) {
        [self appendLog:[NSString stringWithFormat:@"🔴 Disconnected: %@", error.localizedDescription]];
    } else {
        [self appendLog:@"🔴 Disconnected"];
    }
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
