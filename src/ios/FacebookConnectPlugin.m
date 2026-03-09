//
//  FacebookConnectPlugin.m
//  GapFacebookConnect
//
//  Created by Jesse MacFadyen on 11-04-22.
//  Updated by Mathijs de Bruin on 11-08-25.
//  Updated by Christine Abernathy on 13-01-22
//  Updated by Jeduan Cornejo on 15-07-04
//  Updated by Eds Keizer on 16-06-13
//  Copyright 2011 Nitobi, Mathijs de Bruin. All rights reserved.
//

#import "FacebookConnectPlugin.h"
#import <objc/runtime.h>
#import <AppTrackingTransparency/AppTrackingTransparency.h>

@interface FacebookConnectPlugin ()

@property (strong, nonatomic) NSString* dialogCallbackId;
@property (strong, nonatomic) FBSDKLoginManager *loginManager;
@property (nonatomic, assign) FBSDKLoginTracking *loginTracking;
@property (strong, nonatomic) NSString* gameRequestDialogCallbackId;
@property (nonatomic, assign) BOOL applicationWasActivated;

- (NSDictionary *)loginResponseObject;
- (NSDictionary *)limitedLoginResponseObject;
- (NSDictionary *)limitedLoginCompatibleResponseObject;
- (NSDictionary *)profileObject;
- (void)enableHybridAppEvents;
- (void)performLimitedLogin:(CDVInvokedUrlCommand *)command permissions:(NSArray *)permissions;
@end

@implementation FacebookConnectPlugin

- (void)pluginInitialize {
    NSLog(@"Starting Facebook Connect plugin");

    // cordova-ios 8.0.0+ uses a scene-based lifecycle where
    // UIApplicationDidFinishLaunchingNotification fires before plugins are initialized.
    // Always initialize the SDK directly — safe to call multiple times.
    [[FBSDKApplicationDelegate sharedInstance] application:[UIApplication sharedApplication]
                             didFinishLaunchingWithOptions:@{}];
    [FBSDKProfile enableUpdatesOnAccessTokenChange:YES];

    // FBSDK 18.x lazily reads appID from the plist but may not have it cached yet
    // when the scene-based lifecycle re-orders initialization. Explicitly set them.
    NSBundle *mainBundle = [NSBundle mainBundle];
    NSString *plistAppID = [mainBundle objectForInfoDictionaryKey:@"FacebookAppID"];
    NSString *plistClientToken = [mainBundle objectForInfoDictionaryKey:@"FacebookClientToken"];
    NSString *plistDisplayName = [mainBundle objectForInfoDictionaryKey:@"FacebookDisplayName"];

    if (!FBSDKSettings.sharedSettings.appID.length && plistAppID.length) {
        [FBSDKSettings.sharedSettings setAppID:plistAppID];
    }
    if (!FBSDKSettings.sharedSettings.clientToken.length && plistClientToken.length) {
        [FBSDKSettings.sharedSettings setClientToken:plistClientToken];
    }
    if (!FBSDKSettings.sharedSettings.displayName.length && plistDisplayName.length) {
        [FBSDKSettings.sharedSettings setDisplayName:plistDisplayName];
    }

    // Fallback for traditional (non-scene) lifecycle
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applicationDidFinishLaunching:)
                                                 name:UIApplicationDidFinishLaunchingNotification object:nil];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applicationDidBecomeActive:)
                                                 name:UIApplicationDidBecomeActiveNotification object:nil];

    // cordova-ios 8.0.0+ URL handling (object=NSURL, userInfo=options)
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleOpenURL:)
                                                 name:CDVPluginHandleOpenURLNotification object:nil];

    // Legacy URL handling for cordova-ios < 8.0.0 (object=NSDictionary with url key)
    [[NSNotificationCenter defaultCenter] addObserver:self
                                         selector:@selector(handleOpenURLWithAppSourceAndAnnotation:)
                                             name:CDVPluginHandleOpenURLWithAppSourceAndAnnotationNotification object:nil];
}

- (void) applicationDidFinishLaunching:(NSNotification *) notification {
    NSDictionary* launchOptions = notification.userInfo;
    if (launchOptions == nil) {
        //launchOptions is nil when not start because of notification or url open
        launchOptions = [NSDictionary dictionary];
    }

    [[FBSDKApplicationDelegate sharedInstance] application:[UIApplication sharedApplication] didFinishLaunchingWithOptions:launchOptions];
    
    [FBSDKProfile enableUpdatesOnAccessTokenChange:YES];
}

- (void) applicationDidBecomeActive:(NSNotification *) notification {
    if (FBSDKSettings.sharedSettings.isAutoLogAppEventsEnabled) {
        [FBSDKAppEvents.shared activateApp];
    }
    if (self.applicationWasActivated == NO) {
        self.applicationWasActivated = YES;
        [self enableHybridAppEvents];
    }
}

// cordova-ios 8.0.0+: notification.object is NSURL, userInfo contains options
- (void) handleOpenURL:(NSNotification *) notification {
    NSURL *url = notification.object;
    NSDictionary *options = notification.userInfo ?: @{};
    [[FBSDKApplicationDelegate sharedInstance] application:[UIApplication sharedApplication] openURL:url options:options];
}

// cordova-ios < 8.0.0: notification.object is NSDictionary with url, sourceApplication, annotation keys
- (void) handleOpenURLWithAppSourceAndAnnotation:(NSNotification *) notification {
    NSMutableDictionary * options = [notification object];
    NSURL* url = options[@"url"];

    [[FBSDKApplicationDelegate sharedInstance] application:[UIApplication sharedApplication] openURL:url options:options];
}

#pragma mark - Cordova commands

- (void)getApplicationId:(CDVInvokedUrlCommand *)command {
    NSString *appID = FBSDKSettings.sharedSettings.appID;
    CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:appID];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void)setApplicationId:(CDVInvokedUrlCommand *)command {
    if ([command.arguments count] == 0) {
        // Not enough arguments
        [self returnInvalidArgsError:command.callbackId];
        return;
    }
    
    NSString *appId = [command argumentAtIndex:0];
    [FBSDKSettings.sharedSettings setAppID:appId];
    [self returnGenericSuccess:command.callbackId];
}

- (void)getClientToken:(CDVInvokedUrlCommand *)command {
    NSString *clientToken = FBSDKSettings.sharedSettings.clientToken;
    CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:clientToken];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void)setClientToken:(CDVInvokedUrlCommand *)command {
    if ([command.arguments count] == 0) {
        // Not enough arguments
        [self returnInvalidArgsError:command.callbackId];
        return;
    }
    
    NSString *clientToken = [command argumentAtIndex:0];
    [FBSDKSettings.sharedSettings setClientToken:clientToken];
    [self returnGenericSuccess:command.callbackId];
}

- (void)getApplicationName:(CDVInvokedUrlCommand *)command {
    NSString *displayName = FBSDKSettings.sharedSettings.displayName;
    CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:displayName];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void)setApplicationName:(CDVInvokedUrlCommand *)command {
    if ([command.arguments count] == 0) {
        // Not enough arguments
        [self returnInvalidArgsError:command.callbackId];
        return;
    }
    
    NSString *displayName = [command argumentAtIndex:0];
    [FBSDKSettings.sharedSettings setDisplayName:displayName];
    [self returnGenericSuccess:command.callbackId];
}

- (void)getLoginStatus:(CDVInvokedUrlCommand *)command {
    // Standard access token takes priority
    if ([FBSDKAccessToken currentAccessToken] && self.loginTracking != FBSDKLoginTrackingLimited) {
        BOOL force = [[command argumentAtIndex:0] boolValue];
        if (force) {
            [FBSDKAccessToken refreshCurrentAccessTokenWithCompletion:^(id<FBSDKGraphRequestConnecting>  _Nullable connection, id  _Nullable result, NSError * _Nullable error) {
                CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK
                                                              messageAsDictionary:[self loginResponseObject]];
                [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
            }];
        } else {
            CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK
                                                          messageAsDictionary:[self loginResponseObject]];
            [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
        }
        return;
    }

    // Fall back to Limited Login JWT if available
    if ([FBSDKAuthenticationToken currentAuthenticationToken]) {
        CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK
                                                      messageAsDictionary:[self limitedLoginCompatibleResponseObject]];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
        return;
    }

    // No active session
    CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK
                                                  messageAsDictionary:@{@"status": @"unknown"}];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void)getAccessToken:(CDVInvokedUrlCommand *)command {
    if (self.loginTracking == FBSDKLoginTrackingLimited) {
        [self returnLimitedLoginMethodError:command.callbackId];
        return;
    }
    
    // Return access token if available
    CDVPluginResult *pluginResult;
    // Check if the session is open or not
    if ([FBSDKAccessToken currentAccessToken]) {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:
                        [FBSDKAccessToken currentAccessToken].tokenString];
    } else {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:
                        @"Session not open."];
    }
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void)setAutoLogAppEventsEnabled:(CDVInvokedUrlCommand *)command {
    BOOL enabled = [[command argumentAtIndex:0] boolValue];
    [FBSDKSettings.sharedSettings setAutoLogAppEventsEnabled:enabled];
    [self returnGenericSuccess:command.callbackId];
}

- (void)setAdvertiserIDCollectionEnabled:(CDVInvokedUrlCommand *)command {
    BOOL enabled = [[command argumentAtIndex:0] boolValue];
    [FBSDKSettings.sharedSettings setAdvertiserIDCollectionEnabled:enabled];
    [self returnGenericSuccess:command.callbackId];
}

- (void)setAdvertiserTrackingEnabled:(CDVInvokedUrlCommand *)command {
    BOOL enabled = [[command argumentAtIndex:0] boolValue];
    [FBSDKSettings.sharedSettings setAdvertiserTrackingEnabled:enabled];
    [self returnGenericSuccess:command.callbackId];
}

- (void)setDataProcessingOptions:(CDVInvokedUrlCommand *)command {
    if ([command.arguments count] == 0) {
        // Not enough arguments
        [self returnInvalidArgsError:command.callbackId];
        return;
    }

    NSArray *options = [command argumentAtIndex:0];
    if ([command.arguments count] == 1) {
        [FBSDKSettings.sharedSettings setDataProcessingOptions:options];
    } else {
        NSString *country = [command.arguments objectAtIndex:1];
        NSString *state = [command.arguments objectAtIndex:2];
        [FBSDKSettings.sharedSettings setDataProcessingOptions:options country:country state:state];
    }
    [self returnGenericSuccess:command.callbackId];
}

- (void)setUserData:(CDVInvokedUrlCommand *)command {
    if ([command.arguments count] == 0) {
        // Not enough arguments
        [self returnInvalidArgsError:command.callbackId];
        return;
    }

    [self.commandDelegate runInBackground:^{
        NSDictionary *params = [command.arguments objectAtIndex:0];

        if (![params isKindOfClass:[NSDictionary class]]) {
            CDVPluginResult *res = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"userData must be an object"];
            [self.commandDelegate sendPluginResult:res callbackId:command.callbackId];
            return;
        } else {
            [FBSDKAppEvents.shared setUserEmail:(NSString *)params[@"em"]
                            firstName:(NSString*)params[@"fn"] 
                            lastName:(NSString *)params[@"ln"] 
                            phone:(NSString *)params[@"ph"] 
                            dateOfBirth:(NSString *)params[@"db"] 
                            gender:(NSString *)params[@"ge"] 
                            city:(NSString *)params[@"ct"] 
                            state:(NSString *)params[@"st"] 
                            zip:(NSString *)params[@"zp"] 
                            country:(NSString *)params[@"cn"]];
        }

        [self returnGenericSuccess:command.callbackId];
    }];
}

- (void)clearUserData:(CDVInvokedUrlCommand *)command {
    [FBSDKAppEvents.shared clearUserData];
    [self returnGenericSuccess:command.callbackId];
}

- (void)logEvent:(CDVInvokedUrlCommand *)command {
    if ([command.arguments count] == 0) {
        // Not enough arguments
        [self returnInvalidArgsError:command.callbackId];
        return;
    }

    [self.commandDelegate runInBackground:^{
        // For more verbose output on logging uncomment the following:
        // [FBSettings setLoggingBehavior:[NSSet setWithObject:FBLoggingBehaviorAppEvents]];
        NSString *eventName = [command.arguments objectAtIndex:0];
        NSDictionary *params;
        double value;

        if ([command.arguments count] == 1) {
            [FBSDKAppEvents.shared logEvent:eventName];

        } else {
            // argument count is not 0 or 1, must be 2 or more
            params = [command.arguments objectAtIndex:1];
            if ([command.arguments count] == 2) {
                // If count is 2 we will just send params
                [FBSDKAppEvents.shared logEvent:eventName parameters:params];
            }

            if ([command.arguments count] >= 3) {
                // If count is 3 we will send params and a value to sum
                value = [[command.arguments objectAtIndex:2] doubleValue];
                [FBSDKAppEvents.shared logEvent:eventName valueToSum:value parameters:params];
            }
        }
        [self returnGenericSuccess:command.callbackId];
    }];
}

- (void)logPurchase:(CDVInvokedUrlCommand *)command {
    if ([command.arguments count] < 2 || [command.arguments count] > 3 ) {
        [self returnInvalidArgsError:command.callbackId];
        return;
    }

    [self.commandDelegate runInBackground:^{
        double value = [[command.arguments objectAtIndex:0] doubleValue];
        NSString *currency = [command.arguments objectAtIndex:1];
        
        if ([command.arguments count] == 2 ) {
            [FBSDKAppEvents.shared logPurchase:value currency:currency];
        } else if ([command.arguments count] >= 3) {
            NSDictionary *params = [command.arguments objectAtIndex:2];
            [FBSDKAppEvents.shared logPurchase:value currency:currency parameters:params];
        }

        [self returnGenericSuccess:command.callbackId];
    }];
}

- (void)login:(CDVInvokedUrlCommand *)command {
    NSLog(@"Starting login");
    CDVPluginResult *pluginResult;
    NSArray *permissions = nil;

    if ([command.arguments count] > 0) {
        permissions = command.arguments;
    }

    // this will prevent from being unable to login after updating plugin or changing permissions
    // without refreshing there will be a cache problem. This simple call should fix the problems
    [FBSDKAccessToken refreshCurrentAccessTokenWithCompletion:nil];

    FBSDKLoginManagerLoginResultBlock loginHandler = ^void(FBSDKLoginManagerLoginResult *result, NSError *error) {
        if (error) {
            // If the SDK has a message for the user, surface it.
            NSString *errorCode = @"-2";
            NSString *errorMessage = error.userInfo[FBSDKErrorLocalizedDescriptionKey];
            [self returnLoginError:command.callbackId:errorCode:errorMessage];
            return;
        } else if (result.isCancelled) {
            NSString *errorCode = @"4201";
            NSString *errorMessage = @"User cancelled.";
            [self returnLoginError:command.callbackId:errorCode:errorMessage];
        } else {
            CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK
                                                          messageAsDictionary:[self loginResponseObject]];
            [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
        }
    };

    // Check if the session is open or not
    if ([FBSDKAccessToken currentAccessToken] == nil) {
        if (permissions == nil) {
            permissions = @[];
        }

        // When ATT is not authorized, FBSDK 17+ returns opaque tokens that the
        // Graph API rejects. Use Limited Login (OIDC JWT) instead.
        if (@available(iOS 14, *)) {
            ATTrackingManagerAuthorizationStatus attStatus = [ATTrackingManager trackingAuthorizationStatus];
            if (attStatus != ATTrackingManagerAuthorizationStatusAuthorized) {
                [self performLimitedLogin:command permissions:permissions];
                return;
            }
        }

        if (self.loginManager == nil || self.loginTracking == FBSDKLoginTrackingLimited) {
            self.loginManager = [[FBSDKLoginManager alloc] init];
        }
        self.loginTracking = FBSDKLoginTrackingEnabled;
        [self.loginManager logInWithPermissions:permissions fromViewController:[self topMostController] handler:loginHandler];
        return;
    }


    if (permissions == nil) {
        // We need permissions
        NSString *permissionsErrorMessage = @"No permissions specified at login";
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                         messageAsString:permissionsErrorMessage];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
        return;
    }

    [self loginWithPermissions:permissions withHandler:loginHandler];

}

- (void)loginWithLimitedTracking:(CDVInvokedUrlCommand *)command {
    if ([command.arguments count] == 1) {
        NSString *nonceErrorMessage = @"No nonce specified";
        CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                         messageAsString:nonceErrorMessage];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
        return;
    }

    NSArray *permissions = [command argumentAtIndex:0];
    NSArray *permissionsArray = @[];
    NSString *nonce = [command argumentAtIndex:1];

    if ([permissions count] > 0) {
        permissionsArray = permissions;
    }

    FBSDKLoginManagerLoginResultBlock loginHandler = ^void(FBSDKLoginManagerLoginResult *result, NSError *error) {
        if (error) {
            // If the SDK has a message for the user, surface it.
            NSString *errorCode = @"-2";
            NSString *errorMessage = error.userInfo[FBSDKErrorLocalizedDescriptionKey];
            [self returnLoginError:command.callbackId:errorCode:errorMessage];
            return;
        } else if (result.isCancelled) {
            NSString *errorCode = @"4201";
            NSString *errorMessage = @"User cancelled.";
            [self returnLoginError:command.callbackId:errorCode:errorMessage];
        } else {
            CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK
                                                          messageAsDictionary:[self limitedLoginResponseObject]];
            [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
        }
    };

    if (self.loginManager == nil || self.loginTracking == FBSDKLoginTrackingEnabled) {
        self.loginManager = [FBSDKLoginManager new];
    }
    self.loginTracking = FBSDKLoginTrackingLimited;
    FBSDKLoginConfiguration *configuration = [[FBSDKLoginConfiguration alloc] initWithPermissions:permissionsArray tracking:FBSDKLoginTrackingLimited nonce:nonce];
    [self.loginManager logInFromViewController:[self topMostController] configuration:configuration completion:loginHandler];
}

// Automatically invoked by login: when ATT is not authorized.
// Uses Limited Login and returns the OIDC JWT in the accessToken field
// so the JS client can consume it without changes.
- (void)performLimitedLogin:(CDVInvokedUrlCommand *)command permissions:(NSArray *)permissions {
    NSString *nonce = [[NSUUID UUID] UUIDString];

    FBSDKLoginManagerLoginResultBlock loginHandler = ^void(FBSDKLoginManagerLoginResult *result, NSError *error) {
        if (error) {
            NSString *errorCode = @"-2";
            NSString *errorMessage = error.userInfo[FBSDKErrorLocalizedDescriptionKey];
            [self returnLoginError:command.callbackId:errorCode:errorMessage];
            return;
        } else if (result.isCancelled) {
            NSString *errorCode = @"4201";
            NSString *errorMessage = @"User cancelled.";
            [self returnLoginError:command.callbackId:errorCode:errorMessage];
        } else {
            CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK
                                                          messageAsDictionary:[self limitedLoginCompatibleResponseObject]];
            [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
        }
    };

    if (self.loginManager == nil || self.loginTracking == FBSDKLoginTrackingEnabled) {
        self.loginManager = [FBSDKLoginManager new];
    }
    self.loginTracking = FBSDKLoginTrackingLimited;
    FBSDKLoginConfiguration *configuration = [[FBSDKLoginConfiguration alloc] initWithPermissions:permissions tracking:FBSDKLoginTrackingLimited nonce:nonce];
    [self.loginManager logInFromViewController:[self topMostController] configuration:configuration completion:loginHandler];
}

- (void) checkHasCorrectPermissions:(CDVInvokedUrlCommand*)command
{
    if (self.loginTracking == FBSDKLoginTrackingLimited) {
        [self returnLimitedLoginMethodError:command.callbackId];
        return;
    }

    NSArray *permissions = nil;

    if ([command.arguments count] > 0) {
        permissions = command.arguments;
    }
    
    NSSet *grantedPermissions = [FBSDKAccessToken currentAccessToken].permissions;

    for (NSString *value in permissions) {
        NSLog(@"Checking permission %@.", value);
        if (![grantedPermissions containsObject:value]) { //checks if permissions does not exists
            CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                                             messageAsString:@"A permission has been denied"];
            [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
            return;
        }
    }
    
    CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK
                                                     messageAsString:@"All permissions have been accepted"];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
    return;
}

- (void) isDataAccessExpired:(CDVInvokedUrlCommand *)command {
    CDVPluginResult *pluginResult;
    if ([FBSDKAccessToken currentAccessToken]) {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:
                        [FBSDKAccessToken currentAccessToken].dataAccessExpired ? @"true" : @"false"];
    } else {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:
                        @"Session not open."];
    }
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void) reauthorizeDataAccess:(CDVInvokedUrlCommand *)command {
    if (self.loginTracking == FBSDKLoginTrackingLimited) {
        [self returnLimitedLoginMethodError:command.callbackId];
        return;
    }
    
    if (self.loginManager == nil) {
        self.loginManager = [[FBSDKLoginManager alloc] init];
    }
    self.loginTracking = FBSDKLoginTrackingEnabled;
    
    FBSDKLoginManagerLoginResultBlock reauthorizeHandler = ^void(FBSDKLoginManagerLoginResult *result, NSError *error) {
        if (error) {
            NSString *errorCode = @"-2";
            NSString *errorMessage = error.userInfo[FBSDKErrorLocalizedDescriptionKey];
            [self returnLoginError:command.callbackId:errorCode:errorMessage];
            return;
        } else if (result.isCancelled) {
            NSString *errorCode = @"4201";
            NSString *errorMessage = @"User cancelled.";
            [self returnLoginError:command.callbackId:errorCode:errorMessage];
        } else {
            CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK
                                                          messageAsDictionary:[self loginResponseObject]];
            [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
        }
    };
    
    [self.loginManager reauthorizeDataAccess:[self topMostController] handler:reauthorizeHandler];
}

- (void) logout:(CDVInvokedUrlCommand*)command
{
    if ([FBSDKAccessToken currentAccessToken] || [FBSDKAuthenticationToken currentAuthenticationToken]) {
        if (self.loginManager == nil) {
            self.loginManager = [[FBSDKLoginManager alloc] init];
        }
        if (self.loginTracking == nil) {
            self.loginTracking = FBSDKLoginTrackingEnabled;
        }

        [self.loginManager logOut];
    }

    // Also clear Limited Login tokens explicitly
    [FBSDKAccessToken setCurrentAccessToken:nil];
    [FBSDKAuthenticationToken setCurrentAuthenticationToken:nil];
    [FBSDKProfile setCurrentProfile:nil];

    [self returnGenericSuccess:command.callbackId];
}

- (void) showDialog:(CDVInvokedUrlCommand*)command
{
    if ([command.arguments count] == 0) {
        CDVPluginResult *pluginResult;
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                         messageAsString:@"No method provided"];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
        return;
    }

    NSMutableDictionary *options = [[command.arguments lastObject] mutableCopy];
    NSString* method = options[@"method"];
    if (!method) {
        CDVPluginResult *pluginResult;
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                         messageAsString:@"No method provided"];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
        return;
    }

    [options removeObjectForKey:@"method"];
    NSDictionary *params = [options copy];

    // Check method
    if ([method isEqualToString:@"send"]) {
        // Send private message dialog
        // Create native params
        FBSDKShareLinkContent *content = [[FBSDKShareLinkContent alloc] init];
        content.contentURL = [NSURL URLWithString:[params objectForKey:@"link"]];

        self.dialogCallbackId = command.callbackId;
        [FBSDKMessageDialog showWithContent:content delegate:self];
        return;

    } else if ([method isEqualToString:@"share"] || [method isEqualToString:@"feed"]) {
        // Create native params
        self.dialogCallbackId = command.callbackId;
        FBSDKShareDialog *dialog = [FBSDKShareDialog alloc];
        dialog.fromViewController = [self topMostController];
        if (params[@"photo_image"]) {
            FBSDKSharePhoto *photo = [FBSDKSharePhoto alloc];
        	NSString *photoImage = params[@"photo_image"];
        	if (![photoImage isKindOfClass:[NSString class]]) {
        		NSLog(@"photo_image must be a string");
        	} else {
        		NSData *photoImageData = [[NSData alloc]initWithBase64EncodedString:photoImage options:NSDataBase64DecodingIgnoreUnknownCharacters];
        		if (!photoImageData) {
        			NSLog(@"photo_image cannot be decoded");
        		} else {
        			photo.image = [UIImage imageWithData:photoImageData];
        			photo.isUserGenerated = YES;
        		}
        	}
        	FBSDKSharePhotoContent *content = [[FBSDKSharePhotoContent alloc] init];
        	content.photos = @[photo];
        	dialog.shareContent = content;
        } else {
        	FBSDKShareLinkContent *content = [[FBSDKShareLinkContent alloc] init];
        	content.contentURL = [NSURL URLWithString:params[@"href"]];
            content.hashtag = [[FBSDKHashtag alloc] initWithString:[params objectForKey:@"hashtag"]];
        	content.quote = params[@"quote"];
        	dialog.shareContent = content;
        }
        dialog.delegate = self;
        // Adopt native share sheets with the following line
        if (params[@"share_sheet"]) {
        	dialog.mode = FBSDKShareDialogModeShareSheet;
        } else if (params[@"share_feedBrowser"]) {
        	dialog.mode = FBSDKShareDialogModeFeedBrowser;
        } else if (params[@"share_native"]) {
        	dialog.mode = FBSDKShareDialogModeNative;
        } else if (params[@"share_feedWeb"]) {
        	dialog.mode = FBSDKShareDialogModeFeedWeb;
        }

        [dialog show];
        return;
    }
    else if ([method isEqualToString:@"apprequests"]) {
        FBSDKGameRequestDialog *dialog = [FBSDKGameRequestDialog alloc];
        dialog.delegate = self;
        if (![dialog canShow]) {
            CDVPluginResult *pluginResult;
            pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                            messageAsString:@"Cannot show dialog"];
            return;
        }

        FBSDKGameRequestContent *content = [FBSDKGameRequestContent alloc];
        NSString *actionType = params[@"actionType"];
        if (!actionType) {
            NSLog(@"Discarding invalid argument actionType");
        } else if ([[actionType lowercaseString] isEqualToString:@"askfor"]) {
            content.actionType = FBSDKGameRequestActionTypeAskFor;
        } else if ([[actionType lowercaseString] isEqualToString:@"send"]) {
            content.actionType = FBSDKGameRequestActionTypeSend;
        } else if ([[actionType lowercaseString] isEqualToString:@"turn"]) {
            content.actionType = FBSDKGameRequestActionTypeTurn;
        } else {
            NSLog(@"Discarding invalid argument actionType");
        }

        NSString *filters = params[@"filters"];
        if (!filters) {
            content.filters = FBSDKGameRequestFilterNone;
        } else if ([filters isEqualToString:@"app_users"]) {
            content.filters = FBSDKGameRequestFilterAppUsers;
        } else if ([filters isEqualToString:@"app_non_users"]) {
            content.filters = FBSDKGameRequestFilterAppNonUsers;
        }

        content.data = params[@"data"];
        content.message = params[@"message"];
        content.objectID = params[@"objectID"];
        content.recipients = params[@"to"];
        content.title = params[@"title"];

        self.gameRequestDialogCallbackId = command.callbackId;
        dialog.content = content;
        [dialog show];
        return;
    }
    CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"method not supported"];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void)getCurrentProfile:(CDVInvokedUrlCommand *)command {
    [FBSDKProfile loadCurrentProfileWithCompletion:^(FBSDKProfile *profile, NSError *error) {
        CDVPluginResult *pluginResult;
        if (![FBSDKProfile currentProfile]) {
            pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                                          messageAsString:@"No current profile."];
            [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
        } else {
            pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK
                                                          messageAsDictionary:[self profileObject]];
            [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
        }
    }];
}

- (void) graphApi:(CDVInvokedUrlCommand *)command
{
    if (self.loginTracking == FBSDKLoginTrackingLimited) {
        [self returnLimitedLoginMethodError:command.callbackId];
        return;
    }
    
    CDVPluginResult *pluginResult;
    if (! [FBSDKAccessToken currentAccessToken]) {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                                          messageAsString:@"You are not logged in."];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
    }

    NSString *graphPath = [command argumentAtIndex:0];
    NSArray *permissionsNeeded = [command argumentAtIndex:1];
    NSString *requestMethod = nil;
    if ([command.arguments count] >= 3) {
        requestMethod = [command argumentAtIndex:2];
    }

    NSSet *currentPermissions = [FBSDKAccessToken currentAccessToken].permissions;

    // We will store here the missing permissions that we will have to request
    NSMutableArray *requestPermissions = [[NSMutableArray alloc] initWithArray:@[]];
    NSArray *permissions;

    // Check if all the permissions we need are present in the user's current permissions
    // If they are not present add them to the permissions to be requested
    for (NSString *permission in permissionsNeeded){
        if (![currentPermissions containsObject:permission]) {
            [requestPermissions addObject:permission];
        }
    }
    permissions = [requestPermissions copy];

    // Defines block that handles the Graph API response
    FBSDKGraphRequestBlock graphHandler = ^(FBSDKGraphRequestConnection *connection, id result, NSError *error) {
        CDVPluginResult* pluginResult;
        if (error) {
            NSString *message = error.userInfo[FBSDKErrorLocalizedDescriptionKey] ?: @"There was an error making the graph call.";
            pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                             messageAsString:message];
        } else {
            NSDictionary *response = (NSDictionary *) result;
            pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:response];
        }
        NSLog(@"Finished GraphAPI request");

        [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
    };

    NSLog(@"Graph Path = %@", graphPath);
    FBSDKGraphRequest *request = [[FBSDKGraphRequest alloc] initWithGraphPath:graphPath parameters:nil HTTPMethod:requestMethod];

    // If we have permissions to request
    if ([permissions count] == 0){
        [request startWithCompletion:^(id<FBSDKGraphRequestConnecting>  _Nullable connection, id  _Nullable result, NSError * _Nullable error) {
            CDVPluginResult* pluginResult;
            if (error) {
                NSString *message = error.userInfo[FBSDKErrorLocalizedDescriptionKey] ?: @"There was an error making the graph call.";
                pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                                 messageAsString:message];
            } else {
                NSDictionary *response = (NSDictionary *) result;
                pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:response];
            }
            NSLog(@"Finished GraphAPI request");

            [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
        }];
        return;
    }

    [self loginWithPermissions:requestPermissions withHandler:^(FBSDKLoginManagerLoginResult *result, NSError *error) {
        if (error) {
            // If the SDK has a message for the user, surface it.
            NSString *errorCode = @"-2";
            NSString *errorMessage = error.userInfo[FBSDKErrorLocalizedDescriptionKey];
            [self returnLoginError:command.callbackId:errorCode:errorMessage];
            return;
        } else if (result.isCancelled) {
            NSString *errorCode = @"4201";
            NSString *errorMessage = @"User cancelled.";
            [self returnLoginError:command.callbackId:errorCode:errorMessage];
            return;
        }

        NSString *deniedPermission = nil;
        for (NSString *permission in permissions) {
            if (![result.grantedPermissions containsObject:permission]) {
                deniedPermission = permission;
                break;
            }
        }

        if (deniedPermission != nil) {
            NSString *errorMessage = [NSString stringWithFormat:@"The user didnt allow necessary permission %@", deniedPermission];
            CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                                              messageAsString:errorMessage];
            [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
            return;
        }

        [request startWithCompletion:^(id<FBSDKGraphRequestConnecting>  _Nullable connection, id  _Nullable result, NSError * _Nullable error) {
            CDVPluginResult* pluginResult;
            if (error) {
                NSString *message = error.userInfo[FBSDKErrorLocalizedDescriptionKey] ?: @"There was an error making the graph call.";
                pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                                 messageAsString:message];
            } else {
                NSDictionary *response = (NSDictionary *) result;
                pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:response];
            }
            NSLog(@"Finished GraphAPI request");

            [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
        }];
    }];
}

- (void) getDeferredApplink:(CDVInvokedUrlCommand *) command
{
    [FBSDKAppLinkUtility fetchDeferredAppLink:^(NSURL *url, NSError *error) {
        if (error) {
            // If the SDK has a message for the user, surface it.
            NSString *errorMessage = error.userInfo[FBSDKErrorLocalizedDescriptionKey] ?: @"Received error while fetching deferred app link.";
            CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                                              messageAsString:errorMessage];
            [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
            return;
        }
        if (url) {
            CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:url.absoluteString];
            [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
        } else {
            [self returnGenericSuccess:command.callbackId];
        }
    }];
}

- (void) activateApp:(CDVInvokedUrlCommand *)command
{
    [FBSDKAppEvents.shared activateApp];
    [self returnGenericSuccess:command.callbackId];
}

#pragma mark - Utility methods

- (void) returnGenericSuccess:(NSString *)callbackId {
    CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:callbackId];
}

- (void) returnInvalidArgsError:(NSString *)callbackId {
    CDVPluginResult *res = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Invalid arguments"];
    [self.commandDelegate sendPluginResult:res callbackId:callbackId];
}

- (void) returnLoginError:(NSString *)callbackId:(NSString *)errorCode:(NSString *)errorMessage {
    NSMutableDictionary *response = [[NSMutableDictionary alloc] init];
    response[@"errorCode"] = errorCode ?: @"-2";
    response[@"errorMessage"] = errorMessage ?: @"There was a problem logging you in.";
    CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                     messageAsString:response];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:callbackId];
}

- (void) returnLimitedLoginMethodError:(NSString *)callbackId {
    NSString *methodErrorMessage = @"Method not available when using Limited Login";
    CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                     messageAsString:methodErrorMessage];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:callbackId];
}

- (void) loginWithPermissions:(NSArray *)permissions withHandler:(FBSDKLoginManagerLoginResultBlock) handler {
    if (self.loginManager == nil) {
        self.loginManager = [[FBSDKLoginManager alloc] init];
    }
    self.loginTracking = FBSDKLoginTrackingEnabled;

    [self.loginManager logInWithPermissions:permissions fromViewController:[self topMostController] handler:handler];
}

- (UIViewController*) topMostController {
    UIViewController *topController = [UIApplication sharedApplication].keyWindow.rootViewController;

    while (topController.presentedViewController) {
        topController = topController.presentedViewController;
    }

    return topController;
}

- (NSDictionary *)loginResponseObject {

    if (![FBSDKAccessToken currentAccessToken]) {
        return @{@"status": @"unknown"};
    }

    NSMutableDictionary *response = [[NSMutableDictionary alloc] init];
    FBSDKAccessToken *token = [FBSDKAccessToken currentAccessToken];

    NSTimeInterval dataAccessExpirationTimeInterval = token.dataAccessExpirationDate.timeIntervalSince1970;
    NSString *dataAccessExpirationTime = @"0";
    if (dataAccessExpirationTimeInterval > 0) {
        dataAccessExpirationTime = [NSString stringWithFormat:@"%0.0f", dataAccessExpirationTimeInterval];
    }

    NSTimeInterval expiresTimeInterval = token.expirationDate.timeIntervalSinceNow;
    NSString *expiresIn = @"0";
    if (expiresTimeInterval > 0) {
        expiresIn = [NSString stringWithFormat:@"%0.0f", expiresTimeInterval];
    }

    response[@"status"] = @"connected";
    response[@"authResponse"] = @{
                                  @"accessToken" : token.tokenString ? token.tokenString : @"",
                                  @"data_access_expiration_time" : dataAccessExpirationTime,
                                  @"expiresIn" : expiresIn,
                                  @"userID" : token.userID ? token.userID : @""
                                  };


    return [response copy];
}

- (NSDictionary *)limitedLoginResponseObject {
    if (![FBSDKAuthenticationToken currentAuthenticationToken]) {
        return @{@"status": @"unknown"};
    }

    NSMutableDictionary *response = [[NSMutableDictionary alloc] init];
    FBSDKAuthenticationToken *token = [FBSDKAuthenticationToken currentAuthenticationToken];

    NSString *userID;
    if ([FBSDKProfile currentProfile]) {
        userID = [FBSDKProfile currentProfile].userID;
    }

    response[@"status"] = @"connected";
    response[@"authResponse"] = @{
                                  @"authenticationToken" : token.tokenString ? token.tokenString : @"",
                                  @"nonce" : token.nonce ? token.nonce : @"",
                                  @"userID" : userID ? userID : @""
                                  };

    return [response copy];
}

// Returns a Limited Login response shaped like a standard login response
// so the JS client can read authResponse.accessToken transparently.
- (NSDictionary *)limitedLoginCompatibleResponseObject {
    if (![FBSDKAuthenticationToken currentAuthenticationToken]) {
        return @{@"status": @"unknown"};
    }

    FBSDKAuthenticationToken *token = [FBSDKAuthenticationToken currentAuthenticationToken];
    NSString *userID = [FBSDKProfile currentProfile] ? [FBSDKProfile currentProfile].userID : @"";

    return @{
        @"status": @"connected",
        @"authResponse": @{
            @"accessToken" : token.tokenString ? token.tokenString : @"",
            @"userID" : userID
        }
    };
}

- (NSDictionary *)profileObject {
    if ([FBSDKProfile currentProfile] == nil) {
        return @{};
    }
    
    NSMutableDictionary *response = [[NSMutableDictionary alloc] init];
    FBSDKProfile *profile = [FBSDKProfile currentProfile];
    NSString *userID = profile.userID;
    
    response[@"userID"] = userID ? userID : @"";
    
    if (self.loginTracking == FBSDKLoginTrackingLimited) {
        NSString *name = profile.name;
        NSString *email = profile.email;
        
        if (name) {
            response[@"name"] = name;
        }
        if (email) {
            response[@"email"] = email;
        }
    } else {
        NSString *firstName = profile.firstName;
        NSString *lastName = profile.lastName;
        
        response[@"firstName"] = firstName ? firstName : @"";
        response[@"lastName"] = lastName ? lastName : @"";
    }
    
    return [response copy];
}

/*
 * Enable the hybrid app events for the webview.
 */
- (void)enableHybridAppEvents {
    if ([self.webView isMemberOfClass:[WKWebView class]]){
        NSString *is_enabled = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"FacebookHybridAppEvents"];
        if([is_enabled isEqualToString:@"true"]){
            [FBSDKAppEvents.shared augmentHybridWebView:(WKWebView*)self.webView];
            NSLog(@"FB Hybrid app events are enabled");
        } else {
            NSLog(@"FB Hybrid app events are not enabled");
        }
    } else {
        NSLog(@"FB Hybrid app events cannot be enabled, this feature requires WKWebView");
    }
}

# pragma mark - FBSDKSharingDelegate

- (void)sharer:(id<FBSDKSharing>)sharer didCompleteWithResults:(NSDictionary *)results {
    if (!self.dialogCallbackId) {
        return;
    }

    CDVPluginResult *pluginResult;
    pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK
                                 messageAsDictionary:results];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:self.dialogCallbackId];
    self.dialogCallbackId = nil;
}

- (void)sharer:(id<FBSDKSharing>)sharer didFailWithError:(NSError *)error {
    if (!self.dialogCallbackId) {
        return;
    }

    CDVPluginResult *pluginResult;
    pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                     messageAsString:[NSString stringWithFormat:@"Error: %@", error.description]];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:self.dialogCallbackId];
    self.dialogCallbackId = nil;
}

- (void)sharerDidCancel:(id<FBSDKSharing>)sharer {
    if (!self.dialogCallbackId) {
        return;
    }

    CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                                      messageAsString:@"User cancelled."];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:self.dialogCallbackId];
    self.dialogCallbackId = nil;
}


#pragma mark - FBSDKGameRequestDialogDelegate

- (void)gameRequestDialog:(FBSDKGameRequestDialog *)gameRequestDialog
   didCompleteWithResults:(NSDictionary *)results
{
    if (!self.gameRequestDialogCallbackId) {
        return;
    }

    NSLog(@"game request dialog did complete");
    NSLog(@"result::%@", results);

    CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:results];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:self.gameRequestDialogCallbackId];
    self.gameRequestDialogCallbackId = nil;
}

- (void)gameRequestDialogDidCancel:(FBSDKGameRequestDialog *)gameRequestDialog
{
    if (!self.gameRequestDialogCallbackId) {
        return;
    }

    NSLog(@"game request dialog did cancel");

    CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"User cancelled dialog"];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:self.gameRequestDialogCallbackId];
    self.gameRequestDialogCallbackId = nil;
}

- (void)gameRequestDialog:(FBSDKGameRequestDialog *)gameRequestDialog
         didFailWithError:(NSError *)error
{
    if (!self.gameRequestDialogCallbackId) {
        return;
    }

    NSLog(@"game request dialog did fail");
    NSLog(@"error::%@", error);

    CDVPluginResult* pluginResult;
    NSString *message = error.userInfo[FBSDKErrorLocalizedDescriptionKey] ?: @"There was an error making the graph call.";
    pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                     messageAsString:message];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:self.gameRequestDialogCallbackId];
    self.gameRequestDialogCallbackId = nil;
}

@end


#pragma mark - AppDelegate Overrides

@implementation AppDelegate (FacebookConnectPlugin)

void FBMethodSwizzle(Class c, SEL originalSelector) {
    NSString *selectorString = NSStringFromSelector(originalSelector);
    SEL newSelector = NSSelectorFromString([@"FacebookConnectPlugin_" stringByAppendingString:selectorString]);
    SEL noopSelector = NSSelectorFromString([@"noop_" stringByAppendingString:selectorString]);
    Method originalMethod, newMethod, noop;
    originalMethod = class_getInstanceMethod(c, originalSelector);
    newMethod = class_getInstanceMethod(c, newSelector);
    noop = class_getInstanceMethod(c, noopSelector);
    if (class_addMethod(c, originalSelector, method_getImplementation(newMethod), method_getTypeEncoding(newMethod))) {
        class_replaceMethod(c, newSelector, method_getImplementation(originalMethod) ?: method_getImplementation(noop), method_getTypeEncoding(originalMethod));
    } else {
        method_exchangeImplementations(originalMethod, newMethod);
    }
}

+ (void)load
{
    FBMethodSwizzle([self class], @selector(application:openURL:options:));
}

- (BOOL)FacebookConnectPlugin_application:(UIApplication *)application openURL:(NSURL *)url options:(NSDictionary<NSString *,id> *)options {
    if (!url) {
        return NO;
    }
    // Required by FBSDKCoreKit for deep linking/to complete login
    [[FBSDKApplicationDelegate sharedInstance] application:application openURL:url sourceApplication:[options valueForKey:@"UIApplicationOpenURLOptionsSourceApplicationKey"] annotation:0x0];
    
    // NOTE: Cordova will run a JavaScript method here named handleOpenURL. This functionality is deprecated
    // but will cause you to see JavaScript errors if you do not have window.handleOpenURL defined:
    // https://github.com/Wizcorp/phonegap-facebook-plugin/issues/703#issuecomment-63748816
    NSLog(@"FB handle url using application:openURL:options: %@", url);

    // Call existing method
    return [self FacebookConnectPlugin_application:application openURL:url options:options];
}

- (BOOL)noop_application:(UIApplication *)application openURL:(NSURL *)url options:(NSDictionary<NSString *,id> *)options
{
    return NO;
}
@end
