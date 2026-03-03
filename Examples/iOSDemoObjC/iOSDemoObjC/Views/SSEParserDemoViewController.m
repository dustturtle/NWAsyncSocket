//
//  SSEParserDemoViewController.m
//  iOSDemoObjC
//

#import "SSEParserDemoViewController.h"
#import "NWSSEParser.h"

@interface SSEParserDemoResult : NSObject
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *detail;
@property (nonatomic, assign) BOOL success;
@end

@implementation SSEParserDemoResult
@end

@interface SSEParserDemoViewController ()
@property (nonatomic, strong) NSMutableArray<SSEParserDemoResult *> *results;
@end

@implementation SSEParserDemoViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"SSE Parser";
    self.results = [NSMutableArray array];
    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithTitle:@"Run All"
                                         style:UIBarButtonItemStylePlain
                                        target:self
                                        action:@selector(runAllDemos)];
}

- (void)runAllDemos {
    [self.results removeAllObjects];
    [self demoSingleEvent];
    [self demoMultipleEvents];
    [self demoLLMStreaming];
    [self demoIdRetry];
    [self demoMultiLineData];
    [self.tableView reloadData];
}

#pragma mark - Demos

- (void)demoSingleEvent {
    NWSSEParser *parser = [[NWSSEParser alloc] init];
    NSData *data = [@"event: chat\ndata: Hello from the server!\n\n" dataUsingEncoding:NSUTF8StringEncoding];
    NSArray<NWSSEEvent *> *events = [parser parseData:data];

    SSEParserDemoResult *r = [[SSEParserDemoResult alloc] init];
    r.title = @"Single SSE Event";
    r.success = events.count == 1 && [events.firstObject.event isEqualToString:@"chat"];

    NSMutableString *detail = [NSMutableString string];
    [detail appendString:@"Input: \"event: chat\\ndata: Hello from the server!\\n\\n\"\n"];
    [detail appendFormat:@"Parsed %lu event(s):\n", (unsigned long)events.count];
    for (NWSSEEvent *e in events) {
        [detail appendFormat:@"  type: %@, data: %@\n", e.event, e.data];
    }
    r.detail = detail;
    [self.results addObject:r];
}

- (void)demoMultipleEvents {
    NWSSEParser *parser = [[NWSSEParser alloc] init];
    NSData *data = [@"data: first\n\ndata: second\n\nevent: custom\ndata: third\n\n"
                    dataUsingEncoding:NSUTF8StringEncoding];
    NSArray<NWSSEEvent *> *events = [parser parseData:data];

    SSEParserDemoResult *r = [[SSEParserDemoResult alloc] init];
    r.title = @"Multiple Events in One Chunk";
    r.success = events.count == 3;

    NSMutableString *detail = [NSMutableString string];
    [detail appendFormat:@"Parsed %lu events from one chunk:\n", (unsigned long)events.count];
    for (NSUInteger i = 0; i < events.count; i++) {
        NWSSEEvent *e = events[i];
        [detail appendFormat:@"  [%lu] type: %@, data: %@\n", (unsigned long)(i + 1), e.event, e.data];
    }
    r.detail = detail;
    [self.results addObject:r];
}

- (void)demoLLMStreaming {
    NWSSEParser *parser = [[NWSSEParser alloc] init];
    NSArray<NSString *> *chunks = @[
        @"data: {\"tok",
        @"en\": \"Hel\"}\n",
        @"\ndata: {\"token\"",
        @": \"lo\"}\n\ndata",
        @": {\"token\": \" World\"}\n\n"
    ];

    NSMutableArray<NWSSEEvent *> *allEvents = [NSMutableArray array];
    NSMutableString *chunkDetails = [NSMutableString string];
    for (NSUInteger i = 0; i < chunks.count; i++) {
        NSArray<NWSSEEvent *> *parsed = [parser parseString:chunks[i]];
        [allEvents addObjectsFromArray:parsed];
        NSString *display = [chunks[i] stringByReplacingOccurrencesOfString:@"\n" withString:@"\\n"];
        [chunkDetails appendFormat:@"  Chunk %lu: \"%@\" → %lu event(s)\n",
         (unsigned long)(i + 1), display, (unsigned long)parsed.count];
    }

    SSEParserDemoResult *r = [[SSEParserDemoResult alloc] init];
    r.title = @"LLM Streaming Simulation";
    r.success = allEvents.count == 3;

    NSMutableString *detail = [NSMutableString string];
    [detail appendFormat:@"Fed %lu partial chunks:\n%@", (unsigned long)chunks.count, chunkDetails];
    [detail appendFormat:@"Total events: %lu\n", (unsigned long)allEvents.count];
    for (NSUInteger i = 0; i < allEvents.count; i++) {
        [detail appendFormat:@"  [%lu] %@\n", (unsigned long)(i + 1), allEvents[i].data];
    }
    r.detail = detail;
    [self.results addObject:r];
}

- (void)demoIdRetry {
    NWSSEParser *parser = [[NWSSEParser alloc] init];
    NSData *data = [@"id: 42\nretry: 3000\nevent: update\ndata: payload\n\n"
                    dataUsingEncoding:NSUTF8StringEncoding];
    NSArray<NWSSEEvent *> *events = [parser parseData:data];
    NWSSEEvent *event = events.firstObject;

    SSEParserDemoResult *r = [[SSEParserDemoResult alloc] init];
    r.title = @"ID and Retry Fields";
    r.success = [event.eventId isEqualToString:@"42"] &&
                event.retry == 3000 &&
                [event.event isEqualToString:@"update"];

    r.detail = [NSString stringWithFormat:
                @"Input: \"id: 42\\nretry: 3000\\nevent: update\\ndata: payload\\n\\n\"\n"
                @"type: %@\ndata: %@\nid: %@\nretry: %ld\nlastEventId: %@",
                event.event, event.data,
                event.eventId ?: @"nil",
                (long)event.retry,
                parser.lastEventId ?: @"nil"];
    [self.results addObject:r];
}

- (void)demoMultiLineData {
    NWSSEParser *parser = [[NWSSEParser alloc] init];
    NSData *data = [@"data: line one\ndata: line two\ndata: line three\n\n"
                    dataUsingEncoding:NSUTF8StringEncoding];
    NSArray<NWSSEEvent *> *events = [parser parseData:data];
    NWSSEEvent *event = events.firstObject;

    SSEParserDemoResult *r = [[SSEParserDemoResult alloc] init];
    r.title = @"Multi-Line Data";
    r.success = [event.data isEqualToString:@"line one\nline two\nline three"];

    r.detail = [NSString stringWithFormat:
                @"Input: 3 data fields in one event\n"
                @"data: \"%@\"\n"
                @"Contains newlines: %@",
                event.data,
                [event.data containsString:@"\n"] ? @"yes" : @"no"];
    [self.results addObject:r];
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    if (self.results.count == 0) return 1;
    return (NSInteger)self.results.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return 1;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (self.results.count == 0) return nil;
    return self.results[section].title;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (self.results.count == 0) {
        UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
        cell.textLabel.text = @"Tap \"Run All\" to demonstrate SSE parsing capabilities.";
        cell.textLabel.textColor = UIColor.secondaryLabelColor;
        cell.textLabel.numberOfLines = 0;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        return cell;
    }

    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    SSEParserDemoResult *r = self.results[indexPath.section];
    cell.textLabel.text = r.success ? @"✅ Passed" : @"❌ Failed";
    cell.textLabel.textColor = r.success ? UIColor.systemGreenColor : UIColor.systemRedColor;
    cell.detailTextLabel.text = r.detail;
    cell.detailTextLabel.numberOfLines = 0;
    cell.detailTextLabel.font = [UIFont monospacedSystemFontOfSize:13 weight:UIFontWeightRegular];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    return cell;
}

@end
