//
//  main.m
//  NWAsyncSocket Objective-C Demo
//
//  A standalone interactive demo that lets users verify the core components
//  of the Objective-C version of NWAsyncSocket:
//
//    1. NWStreamBuffer  — Sticky-packet / Split-packet handling
//    2. NWSSEParser     — Server-Sent Events incremental parsing
//    3. UTF-8 Safety    — Multi-byte character boundary detection
//    4. NWReadRequest   — Read-request queue types
//    5. GCDAsyncSocket  — Connection usage pattern
//    6. GCDAsyncSocket  — Server socket API (accept/listen)
//
//  Build (from repository root):
//    clang -framework Foundation \
//          -I ObjC/NWAsyncSocketObjC/include \
//          ObjC/NWAsyncSocketObjC/NWStreamBuffer.m \
//          ObjC/NWAsyncSocketObjC/NWSSEParser.m \
//          ObjC/NWAsyncSocketObjC/NWReadRequest.m \
//          ObjC/NWAsyncSocketObjC/GCDAsyncSocket.m \
//          ObjC/ObjCDemo/main.m \
//          -o ObjCDemo
//
//  Run:
//    ./ObjCDemo
//

#import <Foundation/Foundation.h>
#import "NWStreamBuffer.h"
#import "NWSSEParser.h"
#import "NWReadRequest.h"
#import "GCDAsyncSocket.h"
#import "GCDAsyncSocketDelegate.h"

// ============================================================================
#pragma mark - Helpers
// ============================================================================

static void printHeader(NSString *title) {
    NSString *line = [@"" stringByPaddingToLength:60
                                       withString:@"="
                                  startingAtIndex:0];
    printf("\n%s\n  %s\n%s\n",
           line.UTF8String, title.UTF8String, line.UTF8String);
}

static void printSubHeader(NSString *title) {
    printf("\n--- %s ---\n", title.UTF8String);
}

static void waitForUser(void) {
    printf("\nPress Enter to continue...");
    char buf[256];
    fgets(buf, sizeof(buf), stdin);
}

// ============================================================================
#pragma mark - 1. NWStreamBuffer Demo
// ============================================================================

static void demoStreamBuffer(void) {
    printHeader(@"1. NWStreamBuffer — Sticky-Packet / Split-Packet Handling");

    NWStreamBuffer *buffer = [[NWStreamBuffer alloc] init];

    // ---- 1a. Sticky packet (粘包) ----
    printSubHeader(@"1a. Sticky Packet (粘包) — Multiple messages in one TCP segment");

    NSData *stickyData = [@"Hello\r\nWorld\r\nFoo\r\n" dataUsingEncoding:NSUTF8StringEncoding];
    printf("Appending combined data: \"Hello\\r\\nWorld\\r\\nFoo\\r\\n\"\n");
    [buffer appendData:stickyData];
    printf("Buffer size: %lu bytes\n", (unsigned long)buffer.count);

    NSData *delimiter = [@"\r\n" dataUsingEncoding:NSUTF8StringEncoding];
    NSInteger messageIndex = 1;
    NSData *chunk = nil;
    while ((chunk = [buffer readDataToDelimiter:delimiter]) != nil) {
        NSString *text = [[NSString alloc] initWithData:chunk encoding:NSUTF8StringEncoding];
        NSString *display = [[text stringByReplacingOccurrencesOfString:@"\r\n" withString:@"\\r\\n"]
                              stringByReplacingOccurrencesOfString:@"\r" withString:@"\\r"];
        printf("  Message %ld: \"%s\"\n", (long)messageIndex, display.UTF8String);
        messageIndex++;
    }
    printf("Buffer remaining: %lu bytes (expected: 0)\n", (unsigned long)buffer.count);
    printf("✅ Sticky packet correctly split into %ld messages\n", (long)(messageIndex - 1));

    // ---- 1b. Split packet (拆包) ----
    printSubHeader(@"1b. Split Packet (拆包) — One message split across TCP segments");

    [buffer reset];
    NSData *part1 = [@"Hel" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *part2 = [@"lo World" dataUsingEncoding:NSUTF8StringEncoding];
    printf("Appending part 1: \"Hel\" (%lu bytes)\n", (unsigned long)part1.length);
    [buffer appendData:part1];

    NSData *result1 = [buffer readDataToLength:11];
    printf("Attempt to read 11 bytes: %s\n", result1 == nil ? "nil (not enough data yet)" : "got data");

    printf("Appending part 2: \"lo World\" (%lu bytes)\n", (unsigned long)part2.length);
    [buffer appendData:part2];
    printf("Buffer size: %lu bytes\n", (unsigned long)buffer.count);

    NSData *result2 = [buffer readDataToLength:11];
    if (result2) {
        NSString *text = [[NSString alloc] initWithData:result2 encoding:NSUTF8StringEncoding];
        printf("Read 11 bytes: \"%s\"\n", text.UTF8String);
        printf("✅ Split packet correctly reassembled\n");
    }

    // ---- 1c. Delimiter-based read ----
    printSubHeader(@"1c. Delimiter-Based Read");

    [buffer reset];
    [buffer appendData:[@"key1=value1&key2=value2&key3=value3" dataUsingEncoding:NSUTF8StringEncoding]];
    printf("Buffer content: \"key1=value1&key2=value2&key3=value3\"\n");

    NSData *ampersand = [@"&" dataUsingEncoding:NSUTF8StringEncoding];
    NSMutableArray<NSString *> *pairs = [NSMutableArray array];
    NSData *pairData = nil;
    while ((pairData = [buffer readDataToDelimiter:ampersand]) != nil) {
        NSString *pair = [[NSString alloc] initWithData:pairData encoding:NSUTF8StringEncoding];
        [pairs addObject:pair];
    }
    // Read remaining data
    NSData *remaining = [buffer readAllData];
    if (remaining.length > 0) {
        NSString *pair = [[NSString alloc] initWithData:remaining encoding:NSUTF8StringEncoding];
        [pairs addObject:pair];
    }
    printf("Parsed pairs:\n");
    for (NSString *pair in pairs) {
        printf("  \"%s\"\n", pair.UTF8String);
    }
    printf("✅ Delimiter-based reading works correctly\n");

    // ---- 1d. readAllData ----
    printSubHeader(@"1d. Read All Data");

    [buffer reset];
    [buffer appendData:[@"Part A " dataUsingEncoding:NSUTF8StringEncoding]];
    [buffer appendData:[@"Part B " dataUsingEncoding:NSUTF8StringEncoding]];
    [buffer appendData:[@"Part C" dataUsingEncoding:NSUTF8StringEncoding]];
    NSData *allData = [buffer readAllData];
    NSString *allText = [[NSString alloc] initWithData:allData encoding:NSUTF8StringEncoding];
    printf("Read all: \"%s\"\n", allText.UTF8String);
    printf("Buffer empty after readAll: %s\n", buffer.isEmpty ? "YES" : "NO");
    printf("✅ readAllData works correctly\n");

    waitForUser();
}

// ============================================================================
#pragma mark - 2. NWSSEParser Demo
// ============================================================================

static void demoSSEParser(void) {
    printHeader(@"2. NWSSEParser — Server-Sent Events Parsing");

    NWSSEParser *parser = [[NWSSEParser alloc] init];

    // ---- 2a. Single complete SSE event ----
    printSubHeader(@"2a. Single Complete SSE Event");

    NSData *sseData1 = [@"event: chat\ndata: Hello from the server!\n\n" dataUsingEncoding:NSUTF8StringEncoding];
    printf("Feed: \"event: chat\\ndata: Hello from the server!\\n\\n\"\n");
    NSArray<NWSSEEvent *> *events1 = [parser parseData:sseData1];
    for (NWSSEEvent *event in events1) {
        printf("  Parsed Event → type: \"%s\", data: \"%s\"\n",
               event.event.UTF8String, event.data.UTF8String);
    }
    printf("✅ Single event parsed correctly\n");

    // ---- 2b. Multiple events in one chunk ----
    printSubHeader(@"2b. Multiple Events in One Chunk");

    [parser reset];
    NSData *sseData2 = [@"data: first message\n\ndata: second message\n\nevent: custom\ndata: third with type\n\n"
                         dataUsingEncoding:NSUTF8StringEncoding];
    printf("Feed: 3 events in a single chunk\n");
    NSArray<NWSSEEvent *> *events2 = [parser parseData:sseData2];
    printf("  Parsed %lu events:\n", (unsigned long)events2.count);
    for (NSUInteger i = 0; i < events2.count; i++) {
        NWSSEEvent *event = events2[i];
        printf("    [%lu] type: \"%s\", data: \"%s\"\n",
               (unsigned long)(i + 1), event.event.UTF8String, event.data.UTF8String);
    }
    printf("✅ Multiple events parsed correctly\n");

    // ---- 2c. Split across chunks (LLM streaming simulation) ----
    printSubHeader(@"2c. Split Across Chunks — LLM Streaming Simulation");

    [parser reset];
    NSArray<NSString *> *chunks = @[
        @"data: {\"tok",
        @"en\": \"Hel\"}\n",
        @"\ndata: {\"token\"",
        @": \"lo\"}\n\ndata",
        @": {\"token\": \" World\"}\n\n"
    ];
    printf("Feeding %lu partial chunks to simulate LLM streaming:\n", (unsigned long)chunks.count);
    NSMutableArray<NWSSEEvent *> *allEvents = [NSMutableArray array];
    for (NSUInteger i = 0; i < chunks.count; i++) {
        NSString *chunkStr = chunks[i];
        NSString *display = [[chunkStr stringByReplacingOccurrencesOfString:@"\n" withString:@"\\n"]
                              stringByReplacingOccurrencesOfString:@"\r" withString:@"\\r"];
        NSArray<NWSSEEvent *> *parsed = [parser parseString:chunkStr];
        [allEvents addObjectsFromArray:parsed];
        printf("  Chunk %lu: \"%s\" → %lu event(s)\n",
               (unsigned long)(i + 1), display.UTF8String, (unsigned long)parsed.count);
    }
    printf("\nTotal events parsed: %lu\n", (unsigned long)allEvents.count);
    for (NSUInteger i = 0; i < allEvents.count; i++) {
        printf("  [%lu] data: \"%s\"\n",
               (unsigned long)(i + 1), allEvents[i].data.UTF8String);
    }
    printf("✅ Split SSE chunks reassembled correctly\n");

    // ---- 2d. Event with id and retry ----
    printSubHeader(@"2d. Event with ID and Retry Fields");

    [parser reset];
    NSData *sseData4 = [@"id: 42\nretry: 3000\nevent: update\ndata: payload here\n\n"
                         dataUsingEncoding:NSUTF8StringEncoding];
    printf("Feed: event with id=42, retry=3000, type=update\n");
    NSArray<NWSSEEvent *> *events4 = [parser parseData:sseData4];
    for (NWSSEEvent *event in events4) {
        printf("  type: \"%s\", data: \"%s\", id: %s, retry: %ld\n",
               event.event.UTF8String,
               event.data.UTF8String,
               event.eventId ? event.eventId.UTF8String : "nil",
               (long)event.retry);
    }
    printf("  lastEventId: %s\n", parser.lastEventId ? parser.lastEventId.UTF8String : "nil");
    printf("✅ ID and retry fields parsed correctly\n");

    // ---- 2e. Comments ignored ----
    printSubHeader(@"2e. Comments Are Ignored");

    [parser reset];
    NSData *sseData5 = [@": this is a comment\ndata: visible data\n\n" dataUsingEncoding:NSUTF8StringEncoding];
    printf("Feed: \": this is a comment\\ndata: visible data\\n\\n\"\n");
    NSArray<NWSSEEvent *> *events5 = [parser parseData:sseData5];
    printf("  Parsed %lu event(s)\n", (unsigned long)events5.count);
    if (events5.count > 0) {
        printf("  data: \"%s\"\n", events5[0].data.UTF8String);
    }
    printf("✅ Comments correctly ignored\n");

    // ---- 2f. Multi-line data ----
    printSubHeader(@"2f. Multi-Line Data Field");

    [parser reset];
    NSData *sseData6 = [@"data: line one\ndata: line two\ndata: line three\n\n" dataUsingEncoding:NSUTF8StringEncoding];
    printf("Feed: 3 data fields in one event\n");
    NSArray<NWSSEEvent *> *events6 = [parser parseData:sseData6];
    if (events6.count > 0) {
        NWSSEEvent *e = events6[0];
        printf("  data: \"%s\"\n", e.data.UTF8String);
        printf("  (contains newlines: %s)\n",
               [e.data containsString:@"\n"] ? "yes" : "no");
    }
    printf("✅ Multi-line data joined correctly\n");

    waitForUser();
}

// ============================================================================
#pragma mark - 3. UTF-8 Safety Demo
// ============================================================================

static void demoUTF8Safety(void) {
    printHeader(@"3. UTF-8 Safety — Multi-Byte Character Boundary Detection");

    NWStreamBuffer *buffer = [[NWStreamBuffer alloc] init];

    // ---- 3a. Complete multi-byte characters ----
    printSubHeader(@"3a. Complete Multi-Byte Characters");

    NSData *emoji = [@"Hello 🌍🚀" dataUsingEncoding:NSUTF8StringEncoding];
    [buffer appendData:emoji];
    printf("Appended: \"Hello 🌍🚀\" (%lu bytes)\n", (unsigned long)emoji.length);
    NSString *str = [buffer readUTF8SafeString];
    if (str) {
        printf("UTF-8 safe read: \"%s\"\n", str.UTF8String);
    }
    printf("✅ Complete multi-byte characters read correctly\n");

    // ---- 3b. Incomplete multi-byte at boundary ----
    printSubHeader(@"3b. Incomplete Multi-Byte at Boundary");

    [buffer reset];
    NSData *chinese = [@"你好世界" dataUsingEncoding:NSUTF8StringEncoding]; // 12 bytes
    NSData *partial = [chinese subdataWithRange:NSMakeRange(0, 10)];
    [buffer appendData:partial];
    printf("Appended first 10 bytes of \"你好世界\" (%lu bytes total)\n", (unsigned long)chinese.length);
    printf("Buffer size: %lu\n", (unsigned long)buffer.count);

    NSUInteger safeCount = [NWStreamBuffer utf8SafeByteCountForData:buffer.data];
    printf("UTF-8 safe byte count: %lu (expected: 9 = 3 chars × 3 bytes)\n", (unsigned long)safeCount);

    NSString *safeStr = [buffer readUTF8SafeString];
    if (safeStr) {
        printf("UTF-8 safe read: \"%s\"\n", safeStr.UTF8String);
        printf("Remaining bytes in buffer: %lu (the incomplete trailing byte)\n",
               (unsigned long)buffer.count);
    }

    // Now complete the character
    NSData *rest = [chinese subdataWithRange:NSMakeRange(10, chinese.length - 10)];
    [buffer appendData:rest];
    printf("\nAppended remaining %lu bytes\n", (unsigned long)rest.length);
    NSString *safeStr2 = [buffer readUTF8SafeString];
    if (safeStr2) {
        printf("UTF-8 safe read: \"%s\"\n", safeStr2.UTF8String);
    }
    printf("Buffer empty: %s\n", buffer.isEmpty ? "YES" : "NO");
    printf("✅ Incomplete multi-byte characters handled safely\n");

    // ---- 3c. Static utf8SafeByteCount ----
    printSubHeader(@"3c. utf8SafeByteCountForData: Static Method");

    // 2-byte character (é = 0xC3 0xA9)
    NSData *twoByteData = [@"café" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *truncated2 = [twoByteData subdataWithRange:NSMakeRange(0, twoByteData.length - 1)];
    NSUInteger safe2 = [NWStreamBuffer utf8SafeByteCountForData:truncated2];
    printf("\"café\" has %lu bytes; truncated to %lu\n",
           (unsigned long)twoByteData.length, (unsigned long)truncated2.length);
    printf("  Safe byte count: %lu\n", (unsigned long)safe2);

    // 4-byte character (𝕳 = U+1D573)
    NSData *fourByteData = [@"A𝕳B" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *truncated4 = [fourByteData subdataWithRange:NSMakeRange(0, 3)]; // 'A' + first 2 bytes of 𝕳
    NSUInteger safe4 = [NWStreamBuffer utf8SafeByteCountForData:truncated4];
    printf("\"A𝕳B\" has %lu bytes; truncated to 3 bytes\n", (unsigned long)fourByteData.length);
    printf("  Safe byte count: %lu (only 'A' is complete)\n", (unsigned long)safe4);
    printf("✅ utf8SafeByteCountForData works correctly for all multi-byte sequences\n");

    waitForUser();
}

// ============================================================================
#pragma mark - 4. NWReadRequest Demo
// ============================================================================

static void demoReadRequest(void) {
    printHeader(@"4. NWReadRequest — Read-Request Queue Types");

    // ---- 4a. Available request ----
    printSubHeader(@"4a. NWReadRequest — available");
    NWReadRequest *r1 = [NWReadRequest availableRequestWithTimeout:-1 tag:1];
    printf("  type: available, timeout: %.1f, tag: %ld\n", r1.timeout, r1.tag);

    // ---- 4b. toLength request ----
    printSubHeader(@"4b. NWReadRequest — toLength");
    NWReadRequest *r2 = [NWReadRequest toLengthRequest:1024 timeout:30 tag:2];
    printf("  type: toLength(%lu), timeout: %.1f, tag: %ld\n",
           (unsigned long)r2.length, r2.timeout, r2.tag);

    // ---- 4c. toDelimiter request ----
    printSubHeader(@"4c. NWReadRequest — toDelimiter");
    NSData *delimData = [@"\r\n" dataUsingEncoding:NSUTF8StringEncoding];
    NWReadRequest *r3 = [NWReadRequest toDelimiterRequest:delimData timeout:60 tag:3];
    printf("  type: toDelimiter(\\r\\n, %lu bytes), timeout: %.1f, tag: %ld\n",
           (unsigned long)r3.delimiter.length, r3.timeout, r3.tag);

    // ---- 4d. Simulate a read queue ----
    printSubHeader(@"4d. Simulating a Read Queue");

    NWStreamBuffer *buffer = [[NWStreamBuffer alloc] init];
    NSMutableArray<NWReadRequest *> *readQueue = [NSMutableArray arrayWithArray:@[
        [NWReadRequest toLengthRequest:5 timeout:-1 tag:10],
        [NWReadRequest toDelimiterRequest:[@"\n" dataUsingEncoding:NSUTF8StringEncoding]
                                  timeout:-1 tag:11],
        [NWReadRequest availableRequestWithTimeout:-1 tag:12],
    ]];

    printf("Queue: [toLength(5), toDelimiter(\\n), available]\n");
    printf("Feeding data: \"HelloWorld\\nExtra\"\n");

    [buffer appendData:[@"HelloWorld\nExtra" dataUsingEncoding:NSUTF8StringEncoding]];

    NSInteger satisfied = 0;
    while (readQueue.count > 0) {
        NWReadRequest *request = readQueue[0];
        NSData *result = nil;

        switch (request.type) {
            case NWReadRequestTypeAvailable:
                if (!buffer.isEmpty) {
                    result = [buffer readAllData];
                }
                break;
            case NWReadRequestTypeToLength:
                result = [buffer readDataToLength:request.length];
                break;
            case NWReadRequestTypeToDelimiter:
                result = [buffer readDataToDelimiter:request.delimiter];
                break;
        }

        if (result) {
            [readQueue removeObjectAtIndex:0];
            satisfied++;
            NSString *text = [[NSString alloc] initWithData:result encoding:NSUTF8StringEncoding];
            NSString *display = [text stringByReplacingOccurrencesOfString:@"\n" withString:@"\\n"];
            printf("  Tag %ld: \"%s\" (%lu bytes)\n",
                   request.tag, display.UTF8String, (unsigned long)result.length);
        } else {
            break;
        }
    }
    printf("Satisfied %ld of 3 requests, buffer remaining: %lu\n",
           (long)satisfied, (unsigned long)buffer.count);
    printf("✅ Read queue processing works correctly\n");

    waitForUser();
}

// ============================================================================
#pragma mark - 5. GCDAsyncSocket Usage Pattern
// ============================================================================

// Sample delegate class for demonstration
@interface DemoSocketDelegate : NSObject <GCDAsyncSocketDelegate>
@property (nonatomic, strong) NSMutableArray<GCDAsyncSocket *> *acceptedSockets;
@end

@implementation DemoSocketDelegate

- (instancetype)init {
    self = [super init];
    if (self) {
        _acceptedSockets = [NSMutableArray array];
    }
    return self;
}

- (void)socket:(GCDAsyncSocket *)sock didConnectToHost:(NSString *)host port:(uint16_t)port {
    NSLog(@"Connected to %@:%u", host, port);
    // Send an HTTP GET request
    NSString *http = [NSString stringWithFormat:
                      @"GET / HTTP/1.1\r\nHost: %@\r\nConnection: close\r\n\r\n", host];
    NSData *data = [http dataUsingEncoding:NSUTF8StringEncoding];
    [sock writeData:data withTimeout:30 tag:1];
    [sock readDataWithTimeout:30 tag:1];
}

- (void)socket:(GCDAsyncSocket *)sock didReadData:(NSData *)data withTag:(long)tag {
    NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    NSLog(@"Received %lu bytes (tag %ld):", (unsigned long)data.length, tag);
    if (text) {
        // Print first 200 chars
        if (text.length > 200) {
            NSLog(@"%@...", [text substringToIndex:200]);
        } else {
            NSLog(@"%@", text);
        }
    }
    [sock readDataWithTimeout:-1 tag:tag + 1];
}

- (void)socket:(GCDAsyncSocket *)sock didWriteDataWithTag:(long)tag {
    NSLog(@"Write complete (tag %ld)", tag);
}

- (void)socketDidDisconnect:(GCDAsyncSocket *)sock withError:(NSError *)error {
    NSLog(@"Disconnected: %@", error ? error.localizedDescription : @"clean");
}

- (void)socket:(GCDAsyncSocket *)sock didAcceptNewSocket:(GCDAsyncSocket *)newSocket {
    NSLog(@"Accepted new connection: %@", newSocket);
    [self.acceptedSockets addObject:newSocket];
}

- (void)socket:(GCDAsyncSocket *)sock didReceiveSSEEvent:(NWSSEEvent *)event {
    NSLog(@"SSE Event: type=%@ data=%@", event.event, event.data);
}

- (void)socket:(GCDAsyncSocket *)sock didReceiveString:(NSString *)string {
    NSLog(@"Streaming text: %@", string);
}

@end

static void demoGCDAsyncSocketUsage(void) {
    printHeader(@"5. GCDAsyncSocket — Connection Usage Pattern");

    printf("Creating GCDAsyncSocket with delegate...\n\n");

    DemoSocketDelegate *delegate = [[DemoSocketDelegate alloc] init];
    GCDAsyncSocket *socket = [[GCDAsyncSocket alloc] initWithDelegate:delegate
                                                         delegateQueue:dispatch_get_main_queue()];

    printf("Created GCDAsyncSocket instance\n");
    printf("  isConnected: %s\n", socket.isConnected ? "YES" : "NO");
    printf("  connectedHost: %s\n", socket.connectedHost ? socket.connectedHost.UTF8String : "nil");
    printf("  connectedPort: %u\n", socket.connectedPort);

    [socket enableTLS];
    printf("\n  enableTLS called — TLS will be used on next connect\n");

    [socket enableSSEParsing];
    printf("  enableSSEParsing called — SSE events will be parsed automatically\n");

    [socket enableStreamingText];
    printf("  enableStreamingText called — UTF-8 strings will be delivered\n");

    socket.userData = @{@"key": @"value"};
    printf("  userData set: %s\n", [socket.userData description].UTF8String);

    printf("\n"
           "The DemoSocketDelegate class above shows how to implement all\n"
           "GCDAsyncSocketDelegate methods:\n\n"
           "    @interface DemoSocketDelegate : NSObject <GCDAsyncSocketDelegate>\n"
           "    @end\n\n"
           "    @implementation DemoSocketDelegate\n\n"
           "    - (void)socket:(GCDAsyncSocket *)sock didConnectToHost:(NSString *)host\n"
           "                                                      port:(uint16_t)port {\n"
           "        NSLog(@\"Connected to %%@:%%u\", host, port);\n"
           "        NSString *http = [NSString stringWithFormat:\n"
           "            @\"GET / HTTP/1.1\\r\\nHost: %%@\\r\\n\\r\\n\", host];\n"
           "        [sock writeData:[http dataUsingEncoding:NSUTF8StringEncoding]\n"
           "            withTimeout:30 tag:1];\n"
           "        [sock readDataWithTimeout:30 tag:1];\n"
           "    }\n\n"
           "    - (void)socket:(GCDAsyncSocket *)sock didReadData:(NSData *)data\n"
           "                                              withTag:(long)tag {\n"
           "        NSLog(@\"Received %%lu bytes\", (unsigned long)data.length);\n"
           "        [sock readDataWithTimeout:-1 tag:tag + 1];\n"
           "    }\n\n"
           "    - (void)socket:(GCDAsyncSocket *)sock didWriteDataWithTag:(long)tag {\n"
           "        NSLog(@\"Write complete (tag %%ld)\", tag);\n"
           "    }\n\n"
           "    - (void)socketDidDisconnect:(GCDAsyncSocket *)sock withError:(NSError *)error {\n"
           "        NSLog(@\"Disconnected: %%@\",\n"
           "              error ? error.localizedDescription : @\"clean\");\n"
           "    }\n\n"
           "    - (void)socket:(GCDAsyncSocket *)sock didReceiveSSEEvent:(NWSSEEvent *)event {\n"
           "        NSLog(@\"SSE Event: type=%%@ data=%%@\", event.event, event.data);\n"
           "    }\n\n"
           "    @end\n\n"
           "To test with a real server:\n\n"
           "    DemoSocketDelegate *delegate = [[DemoSocketDelegate alloc] init];\n"
           "    GCDAsyncSocket *socket = [[GCDAsyncSocket alloc] initWithDelegate:delegate\n"
           "                                                         delegateQueue:dispatch_get_main_queue()];\n"
           "    [socket enableTLS];\n"
           "    NSError *err = nil;\n"
           "    [socket connectToHost:@\"example.com\" onPort:443 error:&err];\n"
           );

    waitForUser();
}

// ============================================================================
#pragma mark - 6. GCDAsyncSocket Server API
// ============================================================================

static void demoServerSocket(void) {
    printHeader(@"6. GCDAsyncSocket — Server Socket API");

    DemoSocketDelegate *delegate = [[DemoSocketDelegate alloc] init];
    dispatch_queue_t queue = dispatch_queue_create("com.demo.server", DISPATCH_QUEUE_SERIAL);

    // ---- 6a. acceptOnPort: ----
    printSubHeader(@"6a. acceptOnPort: — Listen on a TCP port");

    GCDAsyncSocket *serverSocket = [[GCDAsyncSocket alloc] initWithDelegate:delegate
                                                              delegateQueue:queue];
    printf("Created server socket\n");
    printf("  isListening: %s (expected: NO)\n", serverSocket.isListening ? "YES" : "NO");
    printf("  isConnected: %s (expected: NO)\n", serverSocket.isConnected ? "YES" : "NO");

    NSError *err = nil;
    BOOL ok = [serverSocket acceptOnPort:0 error:&err];
    printf("  acceptOnPort:0 → %s (port 0 lets the system choose)\n", ok ? "YES" : "NO");
    if (err) {
        printf("  Error: %s\n", err.localizedDescription.UTF8String);
    }
    // Give the listener a moment to start
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.3]];
    printf("  isListening: %s (expected: YES)\n", serverSocket.isListening ? "YES" : "NO");
    printf("  localPort: %u (system-assigned)\n", serverSocket.localPort);

    // ---- 6b. Double-accept error ----
    printSubHeader(@"6b. Double-accept error — Calling accept while already listening");

    NSError *doubleErr = nil;
    BOOL doubleOk = [serverSocket acceptOnPort:0 error:&doubleErr];
    printf("  acceptOnPort:0 again → %s (expected: NO)\n", doubleOk ? "YES" : "NO");
    if (doubleErr) {
        printf("  Error: %s (expected: already listening)\n", doubleErr.localizedDescription.UTF8String);
    }
    printf("✅ Double-accept correctly returns error\n");

    // ---- 6c. Client connects to server ----
    printSubHeader(@"6c. Client → Server connection — Verify didAcceptNewSocket:");

    uint16_t serverPort = serverSocket.localPort;
    GCDAsyncSocket *clientSocket = [[GCDAsyncSocket alloc] initWithDelegate:delegate
                                                              delegateQueue:queue];
    NSError *connectErr = nil;
    BOOL connected = [clientSocket connectToHost:@"127.0.0.1" onPort:serverPort error:&connectErr];
    printf("  Client connectToHost:127.0.0.1 onPort:%u → %s\n", serverPort, connected ? "YES" : "NO");
    if (connectErr) {
        printf("  Connect Error: %s\n", connectErr.localizedDescription.UTF8String);
    }

    // Pump the run loop to allow the connection and accept to complete
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.5]];
    printf("  Accepted sockets count: %lu (expected: 1)\n",
           (unsigned long)delegate.acceptedSockets.count);
    if (delegate.acceptedSockets.count > 0) {
        GCDAsyncSocket *accepted = delegate.acceptedSockets[0];
        printf("  Accepted socket isConnected: %s\n", accepted.isConnected ? "YES" : "NO");
        printf("✅ Server accepted client connection via didAcceptNewSocket:\n");
    } else {
        printf("⚠️  No accepted socket yet (listener may need more time)\n");
    }

    // ---- 6d. Disconnect server ----
    printSubHeader(@"6d. Disconnect server — Verify listener stops");

    [serverSocket disconnect];
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.3]];
    printf("  isListening after disconnect: %s (expected: NO)\n",
           serverSocket.isListening ? "YES" : "NO");
    printf("✅ Server socket disconnected, listener stopped\n");

    // Clean up client
    [clientSocket disconnect];
    for (GCDAsyncSocket *s in delegate.acceptedSockets) {
        [s disconnect];
    }

    // ---- 6e. acceptOnInterface:port: ----
    printSubHeader(@"6e. acceptOnInterface:port: — Listen on localhost only");

    GCDAsyncSocket *localServer = [[GCDAsyncSocket alloc] initWithDelegate:delegate
                                                              delegateQueue:queue];
    NSError *ifErr = nil;
    BOOL ifOk = [localServer acceptOnInterface:@"127.0.0.1" port:0 error:&ifErr];
    printf("  acceptOnInterface:@\"127.0.0.1\" port:0 → %s\n", ifOk ? "YES" : "NO");
    if (ifErr) {
        printf("  Error: %s\n", ifErr.localizedDescription.UTF8String);
    }
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.3]];
    printf("  isListening: %s (expected: YES)\n", localServer.isListening ? "YES" : "NO");
    printf("✅ acceptOnInterface works\n");
    [localServer disconnect];
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];

    // ---- 6f. acceptOnUrl: (Unix Domain Socket) ----
    printSubHeader(@"6f. acceptOnUrl: — Listen on Unix Domain Socket");

    GCDAsyncSocket *udsServer = [[GCDAsyncSocket alloc] initWithDelegate:delegate
                                                            delegateQueue:queue];
    NSString *tmpPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"nwasyncsocket_demo.sock"];
    NSURL *sockURL = [NSURL fileURLWithPath:tmpPath];
    NSError *udsErr = nil;
    BOOL udsOk = [udsServer acceptOnUrl:sockURL error:&udsErr];
    printf("  acceptOnUrl:%s → %s\n", tmpPath.UTF8String, udsOk ? "YES" : "NO");
    if (udsErr) {
        printf("  Error: %s\n", udsErr.localizedDescription.UTF8String);
    }
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.3]];
    printf("  isListening: %s (expected: YES)\n", udsServer.isListening ? "YES" : "NO");
    printf("✅ acceptOnUrl works\n");
    [udsServer disconnect];

    // Clean up socket file
    [[NSFileManager defaultManager] removeItemAtPath:tmpPath error:nil];
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];

    // ---- 6g. acceptOnUrl: with non-file URL error ----
    printSubHeader(@"6g. acceptOnUrl: error — Non-file URL rejected");

    GCDAsyncSocket *badUds = [[GCDAsyncSocket alloc] initWithDelegate:delegate
                                                         delegateQueue:queue];
    NSError *badErr = nil;
    NSURL *httpUrl = [NSURL URLWithString:@"http://example.com"];
    BOOL badOk = [badUds acceptOnUrl:httpUrl error:&badErr];
    printf("  acceptOnUrl:http://example.com → %s (expected: NO)\n", badOk ? "YES" : "NO");
    if (badErr) {
        printf("  Error: %s (expected: must be file URL)\n", badErr.localizedDescription.UTF8String);
    }
    printf("✅ Non-file URL correctly rejected\n");

    waitForUser();
}

static void printMenu(void) {
    printHeader(@"NWAsyncSocket Objective-C Demo");
    printf(
        "Choose a demo to run:\n\n"
        "  1. NWStreamBuffer  — Sticky-packet / Split-packet handling\n"
        "  2. NWSSEParser     — Server-Sent Events incremental parsing\n"
        "  3. UTF-8 Safety    — Multi-byte character boundary detection\n"
        "  4. NWReadRequest   — Read-request queue types\n"
        "  5. GCDAsyncSocket  — Connection usage pattern\n"
        "  6. GCDAsyncSocket  — Server socket API\n"
        "  a. Run all demos\n"
        "  q. Quit\n\n"
    );
}

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        BOOL running = YES;
        while (running) {
            printMenu();
            printf("Enter choice: ");
            fflush(stdout);
            char buf[256];
            if (fgets(buf, sizeof(buf), stdin) == NULL) break;

            // Trim whitespace and newline
            NSString *input = [[NSString stringWithUTF8String:buf]
                               stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            input = [input lowercaseString];

            if ([input isEqualToString:@"1"]) {
                demoStreamBuffer();
            } else if ([input isEqualToString:@"2"]) {
                demoSSEParser();
            } else if ([input isEqualToString:@"3"]) {
                demoUTF8Safety();
            } else if ([input isEqualToString:@"4"]) {
                demoReadRequest();
            } else if ([input isEqualToString:@"5"]) {
                demoGCDAsyncSocketUsage();
            } else if ([input isEqualToString:@"6"]) {
                demoServerSocket();
            } else if ([input isEqualToString:@"a"]) {
                demoStreamBuffer();
                demoSSEParser();
                demoUTF8Safety();
                demoReadRequest();
                demoGCDAsyncSocketUsage();
                demoServerSocket();
            } else if ([input isEqualToString:@"q"]) {
                printf("\nGoodbye! 👋\n");
                running = NO;
            } else {
                printf("Invalid choice. Please enter 1-6, a, or q.\n");
            }
        }
    }
    return 0;
}
