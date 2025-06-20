#import <UIKit/UIKit.h>
//#import <Preferences/PSListController.h>
//#import <Preferences/PSSpecifier.h>

//@interface MFSRootViewController : PSListController

// 将父类改为 UIViewController，添加 UITableViewDataSource 和 UITableViewDelegate 协议
@interface MFSRootViewController : UIViewController <UITableViewDataSource, UITableViewDelegate>

// 添加 UITableView 属性
@property (nonatomic, strong) UITableView *tableView;
// 添加用于存储应用数据的属性
@property (nonatomic, strong) NSMutableArray *dataSource;

@end
