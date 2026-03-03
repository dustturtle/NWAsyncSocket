//
//  AppDelegate.m
//  iOSDemoObjC
//

#import "AppDelegate.h"
#import "MainViewController.h"

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application
    didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {

    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];

    MainViewController *mainVC = [[MainViewController alloc] initWithStyle:UITableViewStyleInsetGrouped];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:mainVC];

    self.window.rootViewController = nav;
    [self.window makeKeyAndVisible];

    return YES;
}

@end
