//
//  SimpleAuthGooglePlusProvider.m
//  SimpleAuth
//
//  Created by Martin Pilch on 16/5/15.
//  Copyright (c) 2015 Martin Pilch, All rights reserved.
//

#import "SimpleAuthGooglePlusProvider.h"
#import "SimpleAuthGooglePlusLoginViewController.h"

#import "UIViewController+SimpleAuthAdditions.h"
#import <ReactiveCocoa/ReactiveCocoa.h>

@implementation SimpleAuthGooglePlusProvider

#pragma mark - SimpleAuthProvider

+ (NSString *)type {
    return @"google-plus";
}

+ (NSDictionary *)defaultOptions {
    
    // Default present block
    SimpleAuthInterfaceHandler presentBlock = ^(UIViewController *controller) {
        UINavigationController *navigationController = [[UINavigationController alloc] initWithRootViewController:controller];
        navigationController.modalPresentationStyle = UIModalPresentationFormSheet;
        UIViewController *presentedViewController = [UIViewController SimpleAuth_presentedViewController];
        [presentedViewController presentViewController:navigationController
                                              animated:YES
                                            completion:nil];
    };
    
    // Default dismiss block
    SimpleAuthInterfaceHandler dismissBlock = ^(id viewController) {
        [viewController dismissViewControllerAnimated:YES
                                           completion:nil];
    };
    
    NSMutableDictionary *options = [NSMutableDictionary dictionaryWithDictionary:[super defaultOptions]];
    options[SimpleAuthPresentInterfaceBlockKey] = presentBlock;
    options[SimpleAuthDismissInterfaceBlockKey] = dismissBlock;
    options[SimpleAuthRedirectURIKey] = @"http://localhost";
    options[@"scope"] = @"email openid profile";
    options[@"access_type"] = @"offline";
    return options;
}

- (void)authorizeWithCompletion:(SimpleAuthRequestHandler)completion {
    dispatch_async(dispatch_get_main_queue(), ^{
        SimpleAuthGooglePlusLoginViewController *loginViewController = [[SimpleAuthGooglePlusLoginViewController alloc] initWithOptions:self.options];
        loginViewController.completion = ^(UIViewController *viewController, NSURL *URL, NSError *error) {
            SimpleAuthInterfaceHandler dismissBlock = self.options[SimpleAuthDismissInterfaceBlockKey];
            dismissBlock(viewController);
            
            NSString *query = [URL query];
            NSDictionary *dictionary = [CMDQueryStringSerialization dictionaryWithQueryString:query];
            NSString *code = dictionary[@"code"];
            if ([code length] > 0) {
                [self userWithCode:code
                               completion:completion];
            } else {
                completion(nil, error);
            }
        };
        SimpleAuthInterfaceHandler block = self.options[SimpleAuthPresentInterfaceBlockKey];
        block(loginViewController);
    });
}

#pragma mark - Private
- (void)userWithCode:(NSString *)code completion:(SimpleAuthRequestHandler)completion
{
    NSDictionary *parameters = @{ @"code" : code,
                                  @"client_id" : self.options[@"client_id"],
                                  @"redirect_uri": self.options[@"redirect_uri"],
                                  @"grant_type": @"authorization_code"};
    
    NSString *data = [CMDQueryStringSerialization queryStringWithDictionary:parameters];
    
    NSString *URLString = [NSString stringWithFormat:@"https://accounts.google.com/o/oauth2/token"];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:URLString]];
    [request setHTTPMethod:@"POST"];
    [request setHTTPBody:[data dataUsingEncoding:NSUTF8StringEncoding]];
    
    [NSURLConnection sendAsynchronousRequest:request
                                       queue:self.operationQueue
                           completionHandler:^(NSURLResponse *response, NSData *data, NSError *connectionError) {
                               NSIndexSet *indexSet = [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(200, 99)];
                               NSInteger statusCode = [(NSHTTPURLResponse *)response statusCode];
                               if ([indexSet containsIndex:statusCode] && data) {
                                   NSError *parseError;
                                   NSDictionary *dictionary = [NSJSONSerialization JSONObjectWithData:data
                                                                                                      options:kNilOptions
                                                                                                        error:&parseError];
                                   NSString *token = dictionary[@"access_token"];
                                   if ([token length] > 0) {
                                       
                                       NSDictionary *credentials = @{
                                                                     @"access_token" : token,
                                                                     @"expires" : [NSDate dateWithTimeIntervalSinceNow:[dictionary[@"expires_in"] doubleValue]],
                                                                     @"token_type" : @"bearer",
                                                                     @"id_token": dictionary[@"id_token"],
                                                                     @"refresh_token": dictionary[@"refresh_token"]
                                                                     };
                                       
                                       [self userWithCredentials:credentials
                                                      completion:completion];
                                   } else {
                                       completion(nil, parseError);
                                   }
                                   
                               } else {
                                   completion(nil, connectionError);
                               }
    }];
}

- (void)userWithCredentials:(NSDictionary *)credentials completion:(SimpleAuthRequestHandler)completion {
    
    NSString *URLString = [NSString stringWithFormat:@"https://www.googleapis.com/plus/v1/people/me"];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:URLString]];
    
    [request setValue:[NSString stringWithFormat:@"Bearer %@", credentials[@"access_token"]] forHTTPHeaderField:@"Authorization"];
    
    [NSURLConnection sendAsynchronousRequest:request
                                       queue:self.operationQueue
                           completionHandler:^(NSURLResponse *response, NSData *data, NSError *connectionError) {
                               
                               NSIndexSet *indexSet = [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(200, 99)];
                               NSInteger statusCode = [(NSHTTPURLResponse *)response statusCode];
                               if ([indexSet containsIndex:statusCode] && data) {
                                   NSError *parseError;
                                   NSDictionary *userInfo = [NSJSONSerialization JSONObjectWithData:data
                                                                                                      options:kNilOptions
                                                                                                        error:&parseError];
                                   if (userInfo) {
                                       completion ([self dictionaryWithAccount:userInfo credentials:credentials], nil);
                                   } else {
                                       completion(nil, parseError);
                                   }
                               } else {
                                   completion(nil, connectionError);
                               }
                           }];
}

- (NSDictionary *)dictionaryWithAccount:(NSDictionary *)account
                            credentials:(NSDictionary *)credentials
{
    NSMutableDictionary *dictionary = [NSMutableDictionary dictionary];
    
    // Provider
    dictionary[@"provider"] = [[self class] type];
    
    // Credentials
    dictionary[@"credentials"] = @{
                                   @"token" : credentials[@"access_token"],
                                   @"expires_at" : credentials[@"expires"],
                                   @"refresh_token" : credentials[@"refresh_token"]
                                   };
    
    // User ID
    dictionary[@"uid"] = account[@"id"];
    
    // Raw response
    dictionary[@"extra"] = @{
                             @"raw_info" : account
                             };
    
    // User info
    NSMutableDictionary *user = [NSMutableDictionary new];
    user[@"name"] = account[@"displayName"] ? account[@"displayName"] : @"";
    user[@"gender"] = account[@"gender"] ? account[@"gender"] : @"";
    
    user[@"image"] = account[@"image"] ? account[@"image"] : @"";
    
    dictionary[@"info"] = user;
    
    return dictionary;
}

@end
