//
//  MainViewController.m
//  iOSDemoObjC
//

#import "MainViewController.h"
#import "StreamBufferDemoViewController.h"
#import "SSEParserDemoViewController.h"
#import "UTF8SafetyDemoViewController.h"
#import "SocketConnectionDemoViewController.h"

typedef NS_ENUM(NSInteger, DemoSection) {
    DemoSectionCore = 0,
    DemoSectionSocket,
    DemoSectionCount
};

@implementation MainViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"NWAsyncSocket ObjC Demo";
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return DemoSectionCount;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    switch (section) {
        case DemoSectionCore:   return @"Core Components";
        case DemoSectionSocket: return @"Socket";
        default: return nil;
    }
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch (section) {
        case DemoSectionCore:   return 3;
        case DemoSectionSocket: return 1;
        default: return 0;
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"Cell"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"Cell"];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }

    UIListContentConfiguration *config = [UIListContentConfiguration cellConfiguration];

    if (indexPath.section == DemoSectionCore) {
        switch (indexPath.row) {
            case 0:
                config.text = @"StreamBuffer";
                config.image = [UIImage systemImageNamed:@"arrow.left.arrow.right"];
                break;
            case 1:
                config.text = @"SSE Parser";
                config.image = [UIImage systemImageNamed:@"antenna.radiowaves.left.and.right"];
                break;
            case 2:
                config.text = @"UTF-8 Safety";
                config.image = [UIImage systemImageNamed:@"textformat"];
                break;
        }
    } else {
        config.text = @"Socket Connection";
        config.image = [UIImage systemImageNamed:@"network"];
    }

    cell.contentConfiguration = config;
    return cell;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    UIViewController *vc = nil;
    if (indexPath.section == DemoSectionCore) {
        switch (indexPath.row) {
            case 0:
                vc = [[StreamBufferDemoViewController alloc] initWithStyle:UITableViewStyleGrouped];
                break;
            case 1:
                vc = [[SSEParserDemoViewController alloc] initWithStyle:UITableViewStyleGrouped];
                break;
            case 2:
                vc = [[UTF8SafetyDemoViewController alloc] initWithStyle:UITableViewStyleGrouped];
                break;
        }
    } else {
        vc = [[SocketConnectionDemoViewController alloc] initWithStyle:UITableViewStyleGrouped];
    }

    if (vc) {
        [self.navigationController pushViewController:vc animated:YES];
    }
}

@end
