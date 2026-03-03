//
//  UTF8SafetyDemoViewController.m
//  iOSDemoObjC
//

#import "UTF8SafetyDemoViewController.h"
#import "NWStreamBuffer.h"

@interface UTF8SafetyDemoResult : NSObject
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *detail;
@property (nonatomic, assign) BOOL success;
@end

@implementation UTF8SafetyDemoResult
@end

@interface UTF8SafetyDemoViewController ()
@property (nonatomic, strong) NSMutableArray<UTF8SafetyDemoResult *> *results;
@end

@implementation UTF8SafetyDemoViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"UTF-8 Safety";
    self.results = [NSMutableArray array];
    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithTitle:@"Run All"
                                         style:UIBarButtonItemStylePlain
                                        target:self
                                        action:@selector(runAllDemos)];
}

- (void)runAllDemos {
    [self.results removeAllObjects];
    [self demoCompleteMultiByte];
    [self demoIncompleteBoundary];
    [self demoSafeByteCount];
    [self.tableView reloadData];
}

#pragma mark - Demos

- (void)demoCompleteMultiByte {
    NWStreamBuffer *buffer = [[NWStreamBuffer alloc] init];
    NSData *emoji = [@"Hello 🌍🚀" dataUsingEncoding:NSUTF8StringEncoding];
    [buffer appendData:emoji];
    NSString *str = [buffer readUTF8SafeString];

    UTF8SafetyDemoResult *r = [[UTF8SafetyDemoResult alloc] init];
    r.title = @"Complete Multi-Byte Characters";
    r.success = [str isEqualToString:@"Hello 🌍🚀"];
    r.detail = [NSString stringWithFormat:
                @"Input: \"Hello 🌍🚀\" (%lu bytes)\n"
                @"UTF-8 safe read: \"%@\"",
                (unsigned long)emoji.length, str ?: @"nil"];
    [self.results addObject:r];
}

- (void)demoIncompleteBoundary {
    NWStreamBuffer *buffer = [[NWStreamBuffer alloc] init];
    NSData *chinese = [@"你好世界" dataUsingEncoding:NSUTF8StringEncoding]; // 12 bytes
    NSData *partial = [chinese subdataWithRange:NSMakeRange(0, 10)];
    [buffer appendData:partial];

    NSUInteger safeCount = [NWStreamBuffer utf8SafeByteCountForData:buffer.data];
    NSString *str1 = [buffer readUTF8SafeString];
    NSUInteger remaining1 = buffer.count;

    // Complete the character
    [buffer appendData:[chinese subdataWithRange:NSMakeRange(10, chinese.length - 10)]];
    NSString *str2 = [buffer readUTF8SafeString];

    UTF8SafetyDemoResult *r = [[UTF8SafetyDemoResult alloc] init];
    r.title = @"Incomplete Boundary Detection";
    r.success = safeCount == 9 &&
                [str1 isEqualToString:@"你好世"] &&
                [str2 isEqualToString:@"界"] &&
                buffer.isEmpty;
    r.detail = [NSString stringWithFormat:
                @"\"你好世界\" = %lu bytes (3 bytes/char)\n"
                @"Truncated to 10 bytes:\n"
                @"  Safe byte count: %lu (3 chars × 3 bytes)\n"
                @"  First read: \"%@\"\n"
                @"  Remaining: %lu byte(s)\n"
                @"After appending final %lu bytes:\n"
                @"  Second read: \"%@\"\n"
                @"  Buffer empty: %@",
                (unsigned long)chinese.length,
                (unsigned long)safeCount,
                str1 ?: @"nil",
                (unsigned long)remaining1,
                (unsigned long)(chinese.length - 10),
                str2 ?: @"nil",
                buffer.isEmpty ? @"YES" : @"NO"];
    [self.results addObject:r];
}

- (void)demoSafeByteCount {
    // 2-byte character (é = 0xC3 0xA9)
    NSData *cafe = [@"café" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *truncated2 = [cafe subdataWithRange:NSMakeRange(0, cafe.length - 1)];
    NSUInteger safe2 = [NWStreamBuffer utf8SafeByteCountForData:truncated2];

    // 4-byte character (𝕳 = U+1D573)
    NSData *fourByte = [@"A𝕳B" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *truncated4 = [fourByte subdataWithRange:NSMakeRange(0, 3)];
    NSUInteger safe4 = [NWStreamBuffer utf8SafeByteCountForData:truncated4];

    UTF8SafetyDemoResult *r = [[UTF8SafetyDemoResult alloc] init];
    r.title = @"utf8SafeByteCount";
    r.success = safe2 == cafe.length - 2 && safe4 == 1;
    r.detail = [NSString stringWithFormat:
                @"\"café\" → %lu bytes, truncated to %lu:\n"
                @"  Safe count: %lu (excludes incomplete é)\n\n"
                @"\"A𝕳B\" → %lu bytes, truncated to 3:\n"
                @"  Safe count: %lu (only 'A' is complete)",
                (unsigned long)cafe.length, (unsigned long)truncated2.length,
                (unsigned long)safe2,
                (unsigned long)fourByte.length,
                (unsigned long)safe4];
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
        cell.textLabel.text = @"Tap \"Run All\" to demonstrate UTF-8 boundary safety.";
        cell.textLabel.textColor = UIColor.secondaryLabelColor;
        cell.textLabel.numberOfLines = 0;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        return cell;
    }

    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    UTF8SafetyDemoResult *r = self.results[indexPath.section];
    cell.textLabel.text = r.success ? @"✅ Passed" : @"❌ Failed";
    cell.textLabel.textColor = r.success ? UIColor.systemGreenColor : UIColor.systemRedColor;
    cell.detailTextLabel.text = r.detail;
    cell.detailTextLabel.numberOfLines = 0;
    cell.detailTextLabel.font = [UIFont monospacedSystemFontOfSize:13 weight:UIFontWeightRegular];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    return cell;
}

@end
