/*
 Copyright 2009-2017 Urban Airship Inc. All rights reserved.

 Redistribution and use in source and binary forms, with or without
 modification, are permitted provided that the following conditions are met:

 1. Redistributions of source code must retain the above copyright notice, this
 list of conditions and the following disclaimer.

 2. Redistributions in binary form must reproduce the above copyright notice,
 this list of conditions and the following disclaimer in the documentation
 and/or other materials provided with the distribution.

 THIS SOFTWARE IS PROVIDED BY THE URBAN AIRSHIP INC ``AS IS'' AND ANY EXPRESS OR
 IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF
 MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO
 EVENT SHALL URBAN AIRSHIP INC OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT,
 INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,
 BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
 DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
 LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE
 OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
 ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */


#import "UARequestSession+Internal.h"
#import "UAURLRequestOperation+Internal.h"
#import "UADelayOperation+Internal.h"
#import "UAConfig.h"
#import "UAirship.h"

@interface UARequestSession()
@property(nonatomic, strong) NSURLSession *session;
@property(nonatomic, strong) NSOperationQueue *queue;
@property(nonatomic, strong) NSMutableDictionary *headers;
@end

const NSTimeInterval InitialDelay = 30;
const NSTimeInterval MaxBackOff = 3000;

@implementation UARequestSession

- (instancetype)initWithConfig:(UAConfig *)config session:(NSURLSession *)session queue:(NSOperationQueue *)queue {
    self = [super init];

    if (self) {
        self.headers = [NSMutableDictionary dictionary];
        self.session = session;
        self.queue = queue;

        [self setValue:@"gzip;q=1.0, compress;q=0.5" forHeader:@"Accept-Encoding"];
        [self setValue:[UARequestSession userAgentWithAppKey:config.appKey] forHeader:@"User-Agent"];
    }

    return self;
}

+ (instancetype)sessionWithConfig:(UAConfig *)config {
    NSOperationQueue *queue = [[NSOperationQueue alloc] init];
    queue.maxConcurrentOperationCount = 1;

    NSURLSessionConfiguration *sessionConfig = [NSURLSessionConfiguration defaultSessionConfiguration];
    NSURLSession *session = [NSURLSession sessionWithConfiguration:sessionConfig delegate:nil delegateQueue:nil];

    return [[UARequestSession alloc] initWithConfig:config session:session queue:queue];
}

+ (instancetype)sessionWithConfig:(UAConfig *)config NSURLSession:(NSURLSession *)session {
    NSOperationQueue *queue = [[NSOperationQueue alloc] init];
    queue.maxConcurrentOperationCount = 1;

    return [[UARequestSession alloc] initWithConfig:config session:session queue:queue];
}

+ (instancetype)sessionWithConfig:(UAConfig *)config NSURLSession:(NSURLSession *)session queue:(NSOperationQueue *)queue {
    return [[UARequestSession alloc] initWithConfig:config session:session queue:queue];
}

- (void)setValue:(id)value forHeader:(NSString *)field {
    [self.headers setValue:value forKey:field];
}

- (void)dataTaskWithRequest:(UARequest *)request
          completionHandler:(UARequestCompletionHandler)completionHandler {

    [self dataTaskWithRequest:request retryWhere:nil completionHandler:completionHandler];
}

- (void)dataTaskWithRequest:(UARequest *)request
                 retryWhere:(UARequestRetryBlock)retryBlock
          completionHandler:(UARequestCompletionHandler)completionHandler {

    // Create the URLRequest
    NSMutableURLRequest *urlRequest = [NSMutableURLRequest requestWithURL:request.URL];
    [urlRequest setHTTPShouldHandleCookies:NO];
    [urlRequest setHTTPMethod:request.method];
    [urlRequest setHTTPBody:request.body];

    // Session Headers
    for (NSString *key in self.headers) {
        [urlRequest setValue:self.headers[key] forHTTPHeaderField:key];
    }

    // Request Headers
    for (NSString *key in request.headers) {
        [urlRequest setValue:request.headers[key] forHTTPHeaderField:key];
    }

    NSOperation *operation = [self operationWithRequest:urlRequest
                                             retryDelay:InitialDelay
                                             retryWhere:retryBlock
                                      completionHandler:completionHandler];

    [self.queue addOperation:operation];
}

- (void)cancelAllRequests {
    [self.queue cancelAllOperations];
}

- (NSOperation *)operationWithRequest:(NSURLRequest *)request
                           retryDelay:(NSTimeInterval)retryDelay
                           retryWhere:(BOOL (^)(NSData *data, NSURLResponse *response))retryBlock
                    completionHandler:(void (^)(NSData *data, NSURLResponse *response, NSError *error))completionHandler {


    UAURLRequestOperation *operation = [UAURLRequestOperation operationWithRequest:request
                                                                           session:self.session
                                                                 completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {

        if (!error && retryBlock && retryBlock(data, response)) {
            UADelayOperation *delayOperation = [UADelayOperation operationWithDelayInSeconds:retryDelay];
            NSOperation *retryOperation = [self operationWithRequest:request
                                                          retryDelay:MIN(retryDelay * 2, MaxBackOff)
                                                          retryWhere:retryBlock
                                                   completionHandler:completionHandler];

            [retryOperation addDependency:delayOperation];

            [self.queue addOperation:delayOperation];
            [self.queue addOperation:retryOperation];

            return;
        } else {
            completionHandler(data, response, error);
        }

    }];
    
    return operation;
}


+ (NSString *)userAgentWithAppKey:(NSString *)appKey {
    /*
     * [LIB-101] User agent string should be:
     * App 1.0 (iPad; iPhone OS 5.0.1; UALib 1.1.2; <app key>; en_US)
     */

    UIDevice *device = [UIDevice currentDevice];

    NSBundle *bundle = [NSBundle mainBundle];
    NSDictionary *info = [bundle infoDictionary];

    NSString *appName = [info objectForKey:(NSString*)kCFBundleNameKey];
    NSString *appVersion = [info objectForKey:@"CFBundleShortVersionString"];

    NSString *deviceModel = [device model];
    NSString *osName = [device systemName];
    NSString *osVersion = [device systemVersion];

    NSString *libVersion = [UAirshipVersion get];
    NSString *locale = [[NSLocale autoupdatingCurrentLocale] localeIdentifier];

    return [NSString stringWithFormat:@"%@ %@ (%@; %@ %@; UALib %@; %@; %@)",
            appName, appVersion, deviceModel, osName, osVersion, libVersion, appKey, locale];
}

@end
