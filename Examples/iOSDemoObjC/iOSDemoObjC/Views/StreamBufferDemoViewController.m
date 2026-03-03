//
//  StreamBufferDemoViewController.m
//  iOSDemoObjC
//

#import "StreamBufferDemoViewController.h"
#import "NWStreamBuffer.h"

@interface StreamBufferDemoResult : NSObject
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *detail;
@property (nonatomic, assign) BOOL success;
@end

@implementation StreamBufferDemoResult
@end

@interface StreamBufferDemoViewController ()
@property (nonatomic, strong) NSMutableArray<StreamBufferDemoResult *> *results;
@end

@implementation StreamBufferDemoViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"StreamBuffer";
    self.results = [NSMutableArray array];
    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithTitle:@"Run All"
                                         style:UIBarButtonItemStylePlain
                                        target:self
                                        action:@selector(runAllDemos)];
}

- (void)runAllDemos {
    [self.results removeAllObjects];
    [self demoStickyPacket];
    [self demoSplitPacket];
    [self demoDelimiterRead];
    [self demoReadAll];
    [self.tableView reloadData];
}

#pragma mark - Demos

- (void)demoStickyPacket {
    NWStreamBuffer *buffer = [[NWStreamBuffer alloc] init];
    NSData *data = [@"Hello\r\nWorld\r\nFoo\r\n" dataUsingEncoding:NSUTF8StringEncoding];
    [buffer appendData:data];

    NSData *delimiter = [@"\r\n" dataUsingEncoding:NSUTF8StringEncoding];
    NSMutableArray<NSString *> *messages = [NSMutableArray array];
    NSData *chunk = nil;
    while ((chunk = [buffer readDataToDelimiter:delimiter]) != nil) {
        NSString *text = [[NSString alloc] initWithData:chunk encoding:NSUTF8StringEncoding];
        if (text) [messages addObject:text];
    }

    StreamBufferDemoResult *r = [[StreamBufferDemoResult alloc] init];
    r.title = @"Sticky Packet (粘包)";
    r.success = messages.count == 3;

    NSMutableString *detail = [NSMutableString string];
    [detail appendString:@"Input: \"Hello\\r\\nWorld\\r\\nFoo\\r\\n\"\n"];
    [detail appendFormat:@"Parsed %lu messages:\n", (unsigned long)messages.count];
    for (NSUInteger i = 0; i < messages.count; i++) {
        NSString *display = [messages[i] stringByReplacingOccurrencesOfString:@"\r\n" withString:@"\\r\\n"];
        [detail appendFormat:@"  [%lu] %@\n", (unsigned long)(i + 1), display];
    }
    [detail appendFormat:@"Remaining: %lu bytes", (unsigned long)buffer.count];
    r.detail = detail;

    [self.results addObject:r];
}

- (void)demoSplitPacket {
    NWStreamBuffer *buffer = [[NWStreamBuffer alloc] init];
    [buffer appendData:[@"Hel" dataUsingEncoding:NSUTF8StringEncoding]];
    NSData *first = [buffer readDataToLength:11];

    [buffer appendData:[@"lo World" dataUsingEncoding:NSUTF8StringEncoding]];
    NSData *second = [buffer readDataToLength:11];

    NSString *text = second ? [[NSString alloc] initWithData:second encoding:NSUTF8StringEncoding] : nil;

    StreamBufferDemoResult *r = [[StreamBufferDemoResult alloc] init];
    r.title = @"Split Packet (拆包)";
    r.success = first == nil && [text isEqualToString:@"Hello World"];
    r.detail = [NSString stringWithFormat:
                @"Part 1: \"Hel\" → read 11 bytes: %@\n"
                @"Part 2: \"lo World\" → read 11 bytes: \"%@\"",
                first == nil ? @"nil (waiting)" : @"got data",
                text ?: @"nil"];
    [self.results addObject:r];
}

- (void)demoDelimiterRead {
    NWStreamBuffer *buffer = [[NWStreamBuffer alloc] init];
    [buffer appendData:[@"key1=value1&key2=value2&key3=value3" dataUsingEncoding:NSUTF8StringEncoding]];

    NSData *amp = [@"&" dataUsingEncoding:NSUTF8StringEncoding];
    NSMutableArray<NSString *> *pairs = [NSMutableArray array];
    NSData *pairData = nil;
    while ((pairData = [buffer readDataToDelimiter:amp]) != nil) {
        NSString *text = [[NSString alloc] initWithData:pairData encoding:NSUTF8StringEncoding];
        if (text) [pairs addObject:text];
    }
    NSData *remaining = [buffer readAllData];
    if (remaining.length > 0) {
        NSString *text = [[NSString alloc] initWithData:remaining encoding:NSUTF8StringEncoding];
        if (text) [pairs addObject:text];
    }

    StreamBufferDemoResult *r = [[StreamBufferDemoResult alloc] init];
    r.title = @"Delimiter-Based Read";
    r.success = pairs.count == 3;

    NSMutableString *detail = [NSMutableString string];
    [detail appendString:@"Input: \"key1=value1&key2=value2&key3=value3\"\n"];
    [detail appendFormat:@"Parsed %lu pairs:\n", (unsigned long)pairs.count];
    for (NSString *pair in pairs) {
        [detail appendFormat:@"  %@\n", pair];
    }
    r.detail = detail;

    [self.results addObject:r];
}

- (void)demoReadAll {
    NWStreamBuffer *buffer = [[NWStreamBuffer alloc] init];
    [buffer appendData:[@"Part A " dataUsingEncoding:NSUTF8StringEncoding]];
    [buffer appendData:[@"Part B " dataUsingEncoding:NSUTF8StringEncoding]];
    [buffer appendData:[@"Part C" dataUsingEncoding:NSUTF8StringEncoding]];
    NSData *all = [buffer readAllData];
    NSString *text = [[NSString alloc] initWithData:all encoding:NSUTF8StringEncoding];

    StreamBufferDemoResult *r = [[StreamBufferDemoResult alloc] init];
    r.title = @"Read All Data";
    r.success = [text isEqualToString:@"Part A Part B Part C"] && buffer.isEmpty;
    r.detail = [NSString stringWithFormat:
                @"Appended: \"Part A \" + \"Part B \" + \"Part C\"\n"
                @"readAllData: \"%@\"\n"
                @"Buffer empty: %@",
                text, buffer.isEmpty ? @"YES" : @"NO"];
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
        cell.textLabel.text = @"Tap \"Run All\" to demonstrate StreamBuffer capabilities.";
        cell.textLabel.textColor = UIColor.secondaryLabelColor;
        cell.textLabel.numberOfLines = 0;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        return cell;
    }

    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    StreamBufferDemoResult *r = self.results[indexPath.section];
    cell.textLabel.text = r.success ? @"✅ Passed" : @"❌ Failed";
    cell.textLabel.textColor = r.success ? UIColor.systemGreenColor : UIColor.systemRedColor;
    cell.detailTextLabel.text = r.detail;
    cell.detailTextLabel.numberOfLines = 0;
    cell.detailTextLabel.font = [UIFont monospacedSystemFontOfSize:13 weight:UIFontWeightRegular];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    return cell;
}

@end
