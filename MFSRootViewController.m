#import "MFSRootViewController.h"
#import "CoreServices.h"

@interface SKUIItemStateCenter : NSObject

+ (id)defaultCenter;
- (id)_newPurchasesWithItems:(id)items;
- (void)_performPurchases:(id)purchases hasBundlePurchase:(_Bool)purchase withClientContext:(id)context completionBlock:(id /* block */)block;
- (void)_performSoftwarePurchases:(id)purchases withClientContext:(id)context completionBlock:(id /* block */)block;

@end

@interface SKUIItem : NSObject
- (id)initWithLookupDictionary:(id)dictionary;
@end

@interface SKUIItemOffer : NSObject
- (id)initWithLookupDictionary:(id)dictionary;
@end

@interface SKUIClientContext : NSObject
+ (id)defaultContext;
@end

@implementation MFSRootViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    self.navigationItem.title = @"MuffinStore";

    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleGrouped];
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    [self.view addSubview:self.tableView];

    [self populateDataSource];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleApplicationWillEnterForeground:) name:UIApplicationWillEnterForegroundNotification object:nil];

    [self.tableView reloadData];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIApplicationWillEnterForegroundNotification object:nil];
}

- (void)handleApplicationWillEnterForeground:(NSNotification *)notification {
    [self populateDataSource];
    [self.tableView reloadData];
}

- (void)populateDataSource {
    NSMutableArray *sections = [NSMutableArray array];

    NSString *aboutText = [self getAboutText];
    NSDictionary *downloadSection = @{
        @"title": @"Download",
        @"footer": aboutText,
        @"rows": @[
            @{ @"title": @"Download App by Link", @"type": @"downloadLink" }
        ]
    };
    [sections addObject:downloadSection];

    NSMutableArray *appRows = [NSMutableArray array];
    [[LSApplicationWorkspace defaultWorkspace] enumerateApplicationsOfType:0 block:^(LSApplicationProxy* appProxy) {
        NSDictionary *appRow = @{
            @"title": appProxy.localizedName ?: @"Unknown App",
            @"type": @"installedApp",
            @"bundleURL": appProxy.bundleURL
        };
        [appRows addObject:appRow];
    }];

    [appRows sortUsingComparator:^NSComparisonResult(NSDictionary* a, NSDictionary* b) {
        return [a[@"title"] compare:b[@"title"]];
    }];

    NSDictionary *installedSection = @{
        @"title": @"Installed Apps",
        @"rows": appRows
    };
    [sections addObject:installedSection];

    self.dataSource = sections;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return self.dataSource.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    NSDictionary *sectionData = self.dataSource[section];
    NSArray *rows = sectionData[@"rows"];
    return rows.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cellIdentifier = @"Cell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellIdentifier];

    if (cell == nil) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:cellIdentifier];
    }

    NSDictionary *sectionData = self.dataSource[indexPath.section];
    NSArray *rows = sectionData[@"rows"];
    NSDictionary *rowData = rows[indexPath.row];

    cell.textLabel.text = rowData[@"title"];

    return cell;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    NSDictionary *sectionData = self.dataSource[section];
    return sectionData[@"title"];
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    NSDictionary *sectionData = self.dataSource[section];
    return sectionData[@"footer"];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    NSDictionary *sectionData = self.dataSource[indexPath.section];
    NSArray *rows = sectionData[@"rows"];
    NSDictionary *rowData = rows[indexPath.row];

    NSString *rowType = rowData[@"type"];

    if ([rowType isEqualToString:@"downloadLink"]) {
        [self downloadApp];
    } else if ([rowType isEqualToString:@"installedApp"]) {
        NSURL *bundleURL = rowData[@"bundleURL"];
        if (bundleURL) {
            [self downloadAppShortcutWithBundleURL:bundleURL];
        } else {
            NSLog(@"Error: Missing bundleURL for installedApp type.");
        }
    }
}

- (void)downloadAppShortcutWithBundleURL:(NSURL*)bundleURL {
	NSDictionary* infoPlist = [NSDictionary dictionaryWithContentsOfFile:[bundleURL.path stringByAppendingPathComponent:@"Info.plist"]];
	NSString* bundleId = infoPlist[@"CFBundleIdentifier"];
	// NSLog(@"Bundle ID: %@", bundleId);
	NSURL* url = [NSURL URLWithString:[NSString stringWithFormat:@"https://itunes.apple.com/lookup?bundleId=%@&limit=1&media=software", bundleId]];
	NSURLRequest* request = [NSURLRequest requestWithURL:url];
	NSURLSessionDataTask* task = [[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData* data, NSURLResponse* response, NSError* error) {
		if (error) {
			[self showAlert:@"Error" message:error.localizedDescription];
			return;
		}
		// NSLog(@"Response: %@", [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]);
		NSError* jsonError = nil;
		NSDictionary* json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
		if (jsonError) {
			[self showAlert:@"JSON Error" message:jsonError.localizedDescription];
			return;
		}
		NSArray* results = json[@"results"];
		if (results.count == 0) {
			[self showAlert:@"Error" message:@"No results"];
			return;
		}
		NSDictionary* app = results[0];
		[self getAllAppVersionIdsAndPrompt:[app[@"trackId"] longLongValue]];
	}];
	[task resume];
}

- (NSString *)getAboutText {
    return @"MuffinStore v1.1.1\nMade by Mineek\nhttps://github.com/mineek/MuffinStore\nCustomized by PaTTeeL";
}

- (void)showAlert:(NSString*)title message:(NSString*)message {
	dispatch_async(dispatch_get_main_queue(), ^{
		UIAlertController* alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
		UIAlertAction* okAction = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil];
		[alert addAction:okAction];
		[self presentViewController:alert animated:YES completion:nil];
	});
}

- (void)getAllAppVersionIdsFromServer:(long long)appId {
	//NSURL* url = [NSURL URLWithString:[NSString stringWithFormat:@"http://192.168.1.180/olderVersions/%lld", appId]];
	NSString* serverURL = @"https://apis.bilin.eu.org/history/";
	NSURL* url = [NSURL URLWithString:[NSString stringWithFormat:@"%@%lld", serverURL, appId]];
	NSURLRequest* request = [NSURLRequest requestWithURL:url];
	NSURLSessionDataTask* task = [[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData* data, NSURLResponse* response, NSError* error) {
		if (error) {
			[self showAlert:@"Error" message:error.localizedDescription];
			return;
		}
		NSError* jsonError = nil;
		NSDictionary* json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
		if (jsonError) {
			[self showAlert:@"JSON Error" message:jsonError.debugDescription];
			return;
		}
		NSArray* versionIds = json[@"data"];
		if (versionIds.count == 0) {
			[self showAlert:@"Error" message:@"No version IDs, internal error maybe?"];
			return;
		}
		dispatch_async(dispatch_get_main_queue(), ^{
			UIAlertController* versionAlert = [UIAlertController alertControllerWithTitle:@"Version ID" message:@"Select the version ID of the app you want to download" preferredStyle:UIAlertControllerStyleActionSheet];
			for(NSDictionary* versionId in versionIds)
			{
				UIAlertAction* versionAction = [UIAlertAction actionWithTitle:[NSString stringWithFormat:@"%@", versionId[@"bundle_version"]] style:UIAlertActionStyleDefault handler:^(UIAlertAction* action) {
					[self downloadAppWithAppId:appId versionId:[versionId[@"external_identifier"] longLongValue]];
				}];
				[versionAlert addAction:versionAction];
			}
			UIAlertAction* cancelAction = [UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil];
			[versionAlert addAction:cancelAction];

			// iPad fix
			if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
				versionAlert.popoverPresentationController.sourceView = self.view;
				versionAlert.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(self.view.bounds), CGRectGetMidY(self.view.bounds), 0, 0);
			}

			[self presentViewController:versionAlert animated:YES completion:nil];
		});
	}];
	[task resume];
}

- (void)promptForVersionId:(long long)appId {
	dispatch_async(dispatch_get_main_queue(), ^{
		UIAlertController* versionAlert = [UIAlertController alertControllerWithTitle:@"Version ID" message:@"Enter the version ID of the app you want to download" preferredStyle:UIAlertControllerStyleAlert];
		[versionAlert addTextFieldWithConfigurationHandler:^(UITextField* textField) {
			textField.placeholder = @"Version ID";
		}];
		UIAlertAction* downloadAction = [UIAlertAction actionWithTitle:@"Download" style:UIAlertActionStyleDefault handler:^(UIAlertAction* action) {
			long long versionId = [versionAlert.textFields.firstObject.text longLongValue];
			[self downloadAppWithAppId:appId versionId:versionId];
		}];
		[versionAlert addAction:downloadAction];
		UIAlertAction* cancelAction = [UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil];
		[versionAlert addAction:cancelAction];
		[self presentViewController:versionAlert animated:YES completion:nil];
	});
}

- (void)getAllAppVersionIdsAndPrompt:(long long)appId {
	dispatch_async(dispatch_get_main_queue(), ^{
		UIAlertController* promptAlert = [UIAlertController alertControllerWithTitle:@"Version ID" message:@"Do you want to enter the version ID manually or request the list of version IDs from the server?" preferredStyle:UIAlertControllerStyleAlert];
		UIAlertAction* manualAction = [UIAlertAction actionWithTitle:@"Manual" style:UIAlertActionStyleDefault handler:^(UIAlertAction* action) {
			[self promptForVersionId:appId];
		}];
		[promptAlert addAction:manualAction];
		UIAlertAction* serverAction = [UIAlertAction actionWithTitle:@"Server" style:UIAlertActionStyleDefault handler:^(UIAlertAction* action) {
			[self getAllAppVersionIdsFromServer:appId];
		}];
		[promptAlert addAction:serverAction];
		UIAlertAction* cancelAction = [UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil];
		[promptAlert addAction:cancelAction];
		[self presentViewController:promptAlert animated:YES completion:nil];
	});
}

- (void)downloadAppWithAppId:(long long)appId versionId:(long long)versionId {
	NSString* adamId = [NSString stringWithFormat:@"%lld", appId];
	NSString* pricingParameters = @"pricingParameter";
	NSString* appExtVrsId = [NSString stringWithFormat:@"%lld", versionId];
	NSString* installed = @"0";
	NSString* offerString = nil;
	if (versionId == 0)
	{
		offerString = [NSString stringWithFormat:@"productType=C&price=0&salableAdamId=%@&pricingParameters=%@&clientBuyId=1&installed=%@&trolled=1", adamId, pricingParameters, installed];
	}
	else
	{
		offerString = [NSString stringWithFormat:@"productType=C&price=0&salableAdamId=%@&pricingParameters=%@&appExtVrsId=%@&clientBuyId=1&installed=%@&trolled=1", adamId, pricingParameters, appExtVrsId, installed];
	}
	NSDictionary* offerDict = @{@"buyParams": offerString};
	NSDictionary* itemDict = @{@"_itemOffer": adamId};
	SKUIItemOffer* offer = [[SKUIItemOffer alloc] initWithLookupDictionary:offerDict];
	SKUIItem* item = [[SKUIItem alloc] initWithLookupDictionary:itemDict];
	[item setValue:offer forKey:@"_itemOffer"];
	[item setValue:@"iosSoftware" forKey:@"_itemKindString"];
	//[item setValue:@(versionId) forKey:@"_versionIdentifier"];
	if(versionId != 0)
	{
		[item setValue:@(versionId) forKey:@"_versionIdentifier"];
	}
	SKUIItemStateCenter* center = [SKUIItemStateCenter defaultCenter];
	NSArray* items = @[item];
	dispatch_async(dispatch_get_main_queue(), ^{
		[center _performPurchases:[center _newPurchasesWithItems:items] hasBundlePurchase:0 withClientContext:[SKUIClientContext defaultContext] completionBlock:^(id arg1){}];
	});
}

- (void)downloadAppWithLink:(NSString*)link {
	NSString* targetAppIdParsed = nil;
	if([link containsString:@"id"])
	{
		NSArray* components = [link componentsSeparatedByString:@"id"];
		if(components.count < 2)
		{
			[self showAlert:@"Error" message:@"Invalid link"];
			return;
		}
		NSArray* idComponents = [components[1] componentsSeparatedByString:@"?"];
		targetAppIdParsed = idComponents[0];
	}
	else
	{
		[self showAlert:@"Error" message:@"Invalid link"];
		return;
	}
	[self getAllAppVersionIdsAndPrompt:[targetAppIdParsed longLongValue]];
}

- (void)downloadApp {
	UIAlertController* linkAlert = [UIAlertController alertControllerWithTitle:@"App Link" message:@"Enter the link to the app you want to download" preferredStyle:UIAlertControllerStyleAlert];
	[linkAlert addTextFieldWithConfigurationHandler:^(UITextField* textField) {
		textField.placeholder = @"App Link";
	}];
	UIAlertAction* downloadAction = [UIAlertAction actionWithTitle:@"Download" style:UIAlertActionStyleDefault handler:^(UIAlertAction* action) {
		[self downloadAppWithLink:linkAlert.textFields.firstObject.text];
	}];
	[linkAlert addAction:downloadAction];
	UIAlertAction* cancelAction = [UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil];
	[linkAlert addAction:cancelAction];
	[self presentViewController:linkAlert animated:YES completion:nil];
}

@end
