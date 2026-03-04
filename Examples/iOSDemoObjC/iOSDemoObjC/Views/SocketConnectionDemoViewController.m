//
//  SocketConnectionDemoViewController.m
//  iOSDemoObjC
//

#import "SocketConnectionDemoViewController.h"
#import "SocketManager.h"

typedef NS_ENUM(NSInteger, SocketSection) {
    SocketSectionSettings = 0,
    SocketSectionActions,
    SocketSectionSend,
    SocketSectionReceivedText,
    SocketSectionSSEEvents,
    SocketSectionLogs,
    SocketSectionCount
};

@interface SocketConnectionDemoViewController () <UITextFieldDelegate>
@property (nonatomic, strong) SocketManager *manager;
@property (nonatomic, copy) NSString *host;
@property (nonatomic, copy) NSString *port;
@property (nonatomic, assign) BOOL useTLS;
@property (nonatomic, assign) BOOL enableSSE;
@property (nonatomic, assign) BOOL enableStreaming;
@property (nonatomic, copy) NSString *messageToSend;
@end

@implementation SocketConnectionDemoViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Socket Connection";
    self.manager = [[SocketManager alloc] init];
    self.host = @"example.com";
    self.port = @"exampleport";
    self.useTLS = NO;
    self.enableSSE = NO;
    self.enableStreaming = YES;
    self.messageToSend = @"GET / HTTP/1.1\r\nHost: example.com\r\nConnection: close\r\n\r\n";

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(managerDidUpdate)
                                                 name:SocketManagerDidUpdateNotification
                                               object:self.manager];

    UIView *statusView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 12, 12)];
    statusView.backgroundColor = UIColor.systemRedColor;
    statusView.layer.cornerRadius = 6;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:statusView];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)managerDidUpdate {
    UIView *dot = self.navigationItem.rightBarButtonItem.customView;
    dot.backgroundColor = self.manager.isConnected ? UIColor.systemGreenColor : UIColor.systemRedColor;
    [self.tableView reloadData];
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return SocketSectionCount;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    switch (section) {
        case SocketSectionSettings:      return @"Connection Settings";
        case SocketSectionActions:       return @"Actions";
        case SocketSectionSend:          return self.manager.isConnected ? @"Send Data" : nil;
        case SocketSectionReceivedText:  return self.manager.receivedText.length > 0 ? @"Received Text" : nil;
        case SocketSectionSSEEvents:     return self.manager.sseEvents.count > 0 ?
            [NSString stringWithFormat:@"SSE Events (%lu)", (unsigned long)self.manager.sseEvents.count] : nil;
        case SocketSectionLogs:          return [NSString stringWithFormat:@"Logs (%lu)",
                                                  (unsigned long)self.manager.logs.count];
        default: return nil;
    }
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch (section) {
        case SocketSectionSettings:      return 6;
        case SocketSectionActions:       return 1;
        case SocketSectionSend:          return self.manager.isConnected ? 2 : 0;
        case SocketSectionReceivedText:  return self.manager.receivedText.length > 0 ? 1 : 0;
        case SocketSectionSSEEvents:     return (NSInteger)self.manager.sseEvents.count;
        case SocketSectionLogs: {
            NSInteger count = (NSInteger)self.manager.logs.count;
            return count == 0 ? 1 : count + 1; // +1 for "Clear" button
        }
        default: return 0;
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    switch (indexPath.section) {
        case SocketSectionSettings:
            return [self settingsCellForRow:indexPath.row tableView:tableView];
        case SocketSectionActions:
            return [self actionsCellForTableView:tableView];
        case SocketSectionSend:
            return [self sendCellForRow:indexPath.row tableView:tableView];
        case SocketSectionReceivedText:
            return [self receivedTextCellForTableView:tableView];
        case SocketSectionSSEEvents:
            return [self sseCellForRow:indexPath.row tableView:tableView];
        case SocketSectionLogs:
            return [self logsCellForRow:indexPath.row tableView:tableView];
        default:
            return [[UITableViewCell alloc] init];
    }
}

#pragma mark - Cell Builders

- (UITableViewCell *)settingsCellForRow:(NSInteger)row tableView:(UITableView *)tableView {
    if (row < 2) {
        UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;

        UITextField *field = [[UITextField alloc] init];
        field.textAlignment = NSTextAlignmentRight;
        field.delegate = self;
        field.tag = row;
        field.autocapitalizationType = UITextAutocapitalizationTypeNone;
        field.autocorrectionType = UITextAutocorrectionTypeNo;
        field.returnKeyType = UIReturnKeyDone;

        if (row == 0) {
            cell.textLabel.text = @"Host";
            field.text = self.host;
            field.placeholder = @"Host";
        } else {
            cell.textLabel.text = @"Port";
            field.text = self.port;
            field.placeholder = @"Port";
            field.keyboardType = UIKeyboardTypeNumberPad;
        }

        field.translatesAutoresizingMaskIntoConstraints = NO;
        [cell.contentView addSubview:field];
        [NSLayoutConstraint activateConstraints:@[
            [field.trailingAnchor constraintEqualToAnchor:cell.contentView.layoutMarginsGuide.trailingAnchor],
            [field.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor],
            [field.widthAnchor constraintEqualToConstant:200]
        ]];
        return cell;
    }

    if (row == 5) {
        UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.textLabel.text = @"Link Status";
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ (%@:%@)",
                                     self.manager.isConnected ? @"Connected" : @"Disconnected",
                                     self.host,
                                     self.port];
        cell.detailTextLabel.textColor = self.manager.isConnected ? UIColor.systemGreenColor : UIColor.systemRedColor;
        return cell;
    }

    // Toggle rows
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;

    UISwitch *toggle = [[UISwitch alloc] init];
    toggle.tag = row;
    [toggle addTarget:self action:@selector(toggleChanged:) forControlEvents:UIControlEventValueChanged];

    switch (row) {
        case 2:
            cell.textLabel.text = @"TLS";
            toggle.on = self.useTLS;
            break;
        case 3:
            cell.textLabel.text = @"SSE Parsing";
            toggle.on = self.enableSSE;
            break;
        case 4:
            cell.textLabel.text = @"Streaming Text";
            toggle.on = self.enableStreaming;
            break;
    }

    cell.accessoryView = toggle;
    return cell;
}

- (UITableViewCell *)actionsCellForTableView:(UITableView *)tableView {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];

    if (self.manager.isConnected) {
        cell.textLabel.text = @"🔴 Disconnect";
        cell.textLabel.textColor = UIColor.systemRedColor;
    } else {
        cell.textLabel.text = @"▶️ Connect";
        cell.textLabel.textColor = UIColor.systemBlueColor;
    }
    return cell;
}

- (UITableViewCell *)sendCellForRow:(NSInteger)row tableView:(UITableView *)tableView {
    if (row == 0) {
        UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;

        UITextView *textView = [[UITextView alloc] init];
        textView.text = self.messageToSend;
        textView.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];
        textView.tag = 100;
        textView.layer.borderColor = UIColor.separatorColor.CGColor;
        textView.layer.borderWidth = 0.5;
        textView.layer.cornerRadius = 6;

        textView.translatesAutoresizingMaskIntoConstraints = NO;
        [cell.contentView addSubview:textView];
        [NSLayoutConstraint activateConstraints:@[
            [textView.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:8],
            [textView.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-8],
            [textView.leadingAnchor constraintEqualToAnchor:cell.contentView.layoutMarginsGuide.leadingAnchor],
            [textView.trailingAnchor constraintEqualToAnchor:cell.contentView.layoutMarginsGuide.trailingAnchor],
            [textView.heightAnchor constraintGreaterThanOrEqualToConstant:80]
        ]];
        return cell;
    }

    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    cell.textLabel.text = @"📤 Send";
    cell.textLabel.textColor = UIColor.systemBlueColor;
    return cell;
}

- (UITableViewCell *)receivedTextCellForTableView:(UITableView *)tableView {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    NSString *text = self.manager.receivedText;
    if (text.length > 2000) text = [text substringToIndex:2000];
    cell.textLabel.text = text;
    cell.textLabel.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];
    cell.textLabel.numberOfLines = 0;
    return cell;
}

- (UITableViewCell *)sseCellForRow:(NSInteger)row tableView:(UITableView *)tableView {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    NWSSEEvent *event = self.manager.sseEvents[row];
    cell.textLabel.text = [NSString stringWithFormat:@"[%ld] type: %@", (long)(row + 1), event.event];
    cell.textLabel.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];
    NSString *dataPrefix = event.data.length > 200 ? [event.data substringToIndex:200] : event.data;
    cell.detailTextLabel.text = [NSString stringWithFormat:@"data: %@", dataPrefix];
    cell.detailTextLabel.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];
    cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
    return cell;
}

- (UITableViewCell *)logsCellForRow:(NSInteger)row tableView:(UITableView *)tableView {
    if (self.manager.logs.count == 0) {
        UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
        cell.textLabel.text = @"No activity yet";
        cell.textLabel.textColor = UIColor.secondaryLabelColor;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        return cell;
    }

    if (row == 0) {
        UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
        cell.textLabel.text = @"Clear";
        cell.textLabel.textColor = UIColor.systemBlueColor;
        return cell;
    }

    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    NSArray<NSString *> *logs = self.manager.logs;
    // Show logs in reverse order
    NSInteger logIndex = (NSInteger)logs.count - row;
    if (logIndex >= 0 && logIndex < (NSInteger)logs.count) {
        cell.textLabel.text = logs[logIndex];
    }
    cell.textLabel.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];
    cell.textLabel.numberOfLines = 0;
    return cell;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    if (indexPath.section == SocketSectionActions) {
        if (self.manager.isConnected) {
            [self.manager disconnect];
        } else {
            uint16_t portNum = (uint16_t)[self.port integerValue];
            if (portNum == 0) portNum = 6100;
            [self.manager connectToHost:self.host
                                   port:portNum
                                 useTLS:self.useTLS
                              enableSSE:self.enableSSE
                        enableStreaming:self.enableStreaming];
        }
    } else if (indexPath.section == SocketSectionSend && indexPath.row == 1) {
        // Find the text view to get current text
        NSIndexPath *textViewPath = [NSIndexPath indexPathForRow:0 inSection:SocketSectionSend];
        UITableViewCell *textCell = [tableView cellForRowAtIndexPath:textViewPath];
        UITextView *tv = [textCell.contentView viewWithTag:100];
        if (tv) {
            self.messageToSend = tv.text;
        }
        [self.manager sendText:self.messageToSend];
    } else if (indexPath.section == SocketSectionLogs && indexPath.row == 0 && self.manager.logs.count > 0) {
        [self.manager clearAll];
    }
}

#pragma mark - Toggle

- (void)toggleChanged:(UISwitch *)sender {
    switch (sender.tag) {
        case 2: self.useTLS = sender.isOn; break;
        case 3: self.enableSSE = sender.isOn; break;
        case 4: self.enableStreaming = sender.isOn; break;
    }
}

#pragma mark - UITextFieldDelegate

- (void)textFieldDidEndEditing:(UITextField *)textField {
    if (textField.tag == 0) {
        self.host = textField.text;
    } else if (textField.tag == 1) {
        self.port = textField.text;
    }
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    return YES;
}

@end
