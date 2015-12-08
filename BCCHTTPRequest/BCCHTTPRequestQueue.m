//
//  BCCHTTPRequestQueue.m
//
//  Created by Buzz Andersen on 3/8/11.
//  Copyright 2012 Brooklyn Computer Club. All rights reserved.
//

#pragma clang diagnostic ignored "-Warc-performSelector-leaks"

#import "BCCHTTPRequestQueue.h"
#import "BCCHTTPRequest.h"
#import "BCCPersistentCache.h"
#import "NSString+BCCAdditions.h"

#if TARGET_OS_IPHONE
#import <UIKit/UIKit.h>
#elif TARGET_OS_MAC
#import <AppKit/AppKit.h>
#endif

static char *BCCHTTPRequestQueueQueueTypeSpecificKey = "BCCHTTPRequestQueueWorkerQueueSpecificKey";
static char *BCCHTTPRequestQueueWorkerQueueSpecificValue = "BCCHTTPRequestQueueWorkerQueueSpecificValue";
static char *BCCHTTPRequestQueueDelegateQueueSpecificValue = "BCCHTTPRequestQueueDelegateQueueSpecificValue";


@interface BCCHTTPRequestQueue ()

@property (strong, nonatomic) NSString *queueName;

@property (strong, nonatomic) NSMutableArray *requests;

@property (strong, nonatomic) NSURLSession *session;

#if TARGET_OS_IPHONE
@property (nonatomic) UIBackgroundTaskIdentifier backgroundTaskIdentifier;
@property (nonatomic, readonly) BOOL isRunningBackgroundTask;
#endif

@property (strong, nonatomic) dispatch_queue_t workerQueue;
@property (strong, nonatomic) dispatch_queue_t delegateQueue;

@property (strong, nonatomic) BCCPersistentCache *resultsCache;

- (void)configureRequestWithQueueParameters:(BCCHTTPRequest *)request;

- (void)pumpRequestQueue;
- (void)startRequest:(BCCHTTPRequest *)request;
- (void)removeRequest:(BCCHTTPRequest *)request;

- (void)requestWillStart:(BCCHTTPRequest *)request;
- (void)requestDidStart:(BCCHTTPRequest *)request;
- (NSInputStream *)handleRequestNeedsBodyInputStream:(BCCHTTPRequest *)request;
- (NSURLRequest *)request:(BCCHTTPRequest *)request handleHTTPRedirectionWithNewURLRequest:(NSURLRequest *)newRequest;
- (void)request:(BCCHTTPRequest *)request handleBodyDataBytesSent:(int64_t)bytesSent totalBytesSent:(int64_t)totalBytesSent totalBytesExpectedToSend:(int64_t)totalBytesExpectedToSend;
- (NSURLCredential *)request:(BCCHTTPRequest *)request handleAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge;
- (void)request:(BCCHTTPRequest *)request handleResponse:(NSURLResponse *)response;
- (void)request:(BCCHTTPRequest *)request handleResponseData:(NSData *)responseData;
- (void)request:(BCCHTTPRequest *)request handleCompletionWithError:(NSError *)error;

- (void)performBlockOnDelegateQueue:(void (^)())block;
- (void)performBlockOnDelegateQueueAndWait:(void (^)())block;

- (void)performDelegateSelector:(SEL)selector;
- (void)performDelegateSelector:(SEL)selector forRequest:(BCCHTTPRequest *)request;

#if TARGET_OS_IPHONE
- (void)startBackgroundTask;
- (void)endBackgroundTask;
- (void)performBackgroundWorkCleanupIfFinished;
#endif

@end


@interface BCCHTTPURLSessionRequestQueue : BCCHTTPRequestQueue

//@property (strong, nonatomic) NSURLSession *session;
//@property (strong, nonatomic) NSURLSession *backgroundSession;
//@property (copy, nonatomic) void (^backgroundSessionCompletionHandler)();

- (BCCHTTPRequest *)findRequestForTask:(NSURLSessionTask *)task;

@end


@interface BCCHTTPURLConnectionRequestQueue : BCCHTTPRequestQueue

@end


@interface BCCHTTPRequest (Protected)

@property (strong, nonatomic) NSURLConnection *connection;
@property (strong, nonatomic) NSURLSessionTask *task;

- (void)handleRequestStart;
- (void)handleBodyDataBytesSent:(int64_t)bytesSent totalBytesSent:(int64_t)totalBytesSent totalBytesExpectedToSend:(int64_t)totalBytesExpectedToSend;
- (NSURLRequest *)handleHTTPRedirectionWithRequest:(NSURLRequest *)newRequest;
- (NSURLCredential *)handleAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge;
- (void)handleResponse:(NSURLResponse *)response;
- (void)handleResponseData:(NSData *)responseData;
- (void)setResponseData:(NSMutableData *)responseData withMIMEType:(NSString *)mimeType;
- (void)handleRequestCompletionWithError:(NSError *)error;
- (void)handleValidationError:(NSError *)error;

@end

#pragma mark Base Request Queue

@implementation BCCHTTPRequestQueue

#pragma mark - Initialization

- (id)initWithQueueName:(NSString *)queueName
{
    BCCHTTPRequestQueue *subclassInstance = nil;
    
    if ([NSURLSession class]) {
        subclassInstance = [[BCCHTTPURLSessionRequestQueue alloc] init];
    } else {
        subclassInstance = [[BCCHTTPURLConnectionRequestQueue alloc] init];
    }
    
    NSString *workerQueueName = [queueName stringByAppendingString:@" Worker Queue"];
    
    dispatch_queue_t workerQueue = dispatch_queue_create([workerQueueName cStringUsingEncoding:NSUTF8StringEncoding], DISPATCH_QUEUE_SERIAL);
    dispatch_queue_set_specific(workerQueue, BCCHTTPRequestQueueQueueTypeSpecificKey, BCCHTTPRequestQueueWorkerQueueSpecificValue, NULL);
    subclassInstance.workerQueue = workerQueue;

    NSString *delegateQueueName = [queueName stringByAppendingString:@" Delegate Queue"];
    
    dispatch_queue_t delegateQueue = dispatch_queue_create([delegateQueueName cStringUsingEncoding:NSUTF8StringEncoding], DISPATCH_QUEUE_SERIAL);
    dispatch_queue_set_specific(delegateQueue, BCCHTTPRequestQueueQueueTypeSpecificKey, BCCHTTPRequestQueueDelegateQueueSpecificValue, NULL);
    subclassInstance.delegateQueue = delegateQueue;
    
    subclassInstance.processing = YES;
    subclassInstance.activeRequestLimit = 0;
    
    subclassInstance.queueName = queueName;
    subclassInstance.requests = [[NSMutableArray alloc] init];
    
    BCCPersistentCache *cache = [[BCCPersistentCache alloc] initWithIdentifier:queueName rootDirectory:@"com.brooklyncomputerclub.BCCHTTPRequestQueue"];
    cache.maximumMemoryCacheSize = 5 * 1024 * 1024; // 5 MB
    cache.maximumFileCacheSize = 50 * 1024 * 1024; //50MB
    subclassInstance.resultsCache = cache;
    
#if TARGET_OS_IPHONE
    subclassInstance.backgroundTaskIdentifier = UIBackgroundTaskInvalid;
    [[NSNotificationCenter defaultCenter] addObserver:subclassInstance selector:@selector(applicationDidEnterBackground:) name:UIApplicationDidEnterBackgroundNotification object:nil];
#endif
    
    return subclassInstance;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - Request Queue Life Cycle

- (void)reset
{
    [self cancelAllRequests];
    
    if (_workerQueue) {
        [self performBlockOnWorkerQueueAndWait:^{ }];
    }
    
    if (_delegateQueue) {
        [self performBlockOnDelegateQueueAndWait:^{ }];
    }
}

#pragma mark - Request Queue Configuration

- (BOOL)hasOAuthCredentials;
{
    return (self.OAuthConsumerKey != nil && self.OAuthSecretKey != nil && self.OAuthToken != nil && self.OAuthTokenSecret != nil);
}

- (BOOL)hasBasicAuthCredentials;
{
    return (self.basicAuthUsername != nil && (self.keychainServiceName != nil || self.basicAuthPassword != nil));
}

#pragma mark - Request Queue Management

- (void)setProcessing:(BOOL)processing
{
    _processing = processing;
    dispatch_async(self.workerQueue, ^{
        [self pumpRequestQueue];
    });
}

- (void)addRequest:(BCCHTTPRequest *)request
{
    dispatch_async(self.workerQueue, ^{
        // Don't run duplicate requests
        if ([self hasRequestForIdentifier:request.identifier]) {
            return;
        }
        
        [self.requests addObject:request];
        [self pumpRequestQueue];
    });
}

- (void)pumpRequestQueue
{
    if (!self.processing || (self.activeRequestLimit > 0 && self.activeRequests.count == self.activeRequestLimit)) {
        return;
    }
    
    //NSLog(@"Pumping request queue with active request count %lu : %lu", (unsigned long)self.activeRequests.count, (unsigned long)self.activeRequestLimit);
    
    __block BOOL hasBarrierRequest = NO;
    [self.activeRequests enumerateObjectsUsingBlock:^(BCCHTTPRequest *  _Nonnull currentRequest, NSUInteger idx, BOOL * _Nonnull stop) {
        if (currentRequest.isBarrier) {
            hasBarrierRequest = YES;
            *stop = YES;
        }
    }];
    
    if (hasBarrierRequest) {
        return;
    }
    
    while (self.activeRequestLimit == 0 || (self.activeRequests.count < self.activeRequestLimit)) {
        BCCHTTPRequest *nextRequest = self.nextIdleRequest;
        if (!nextRequest) {
            break;
        }
        
        [self startRequest:nextRequest];
    }
    
    if (self.activeRequests.count == 0) {
        [self performDelegateSelector:@selector(requestQueueDidBecomeIdle:)];
    }

#if TARGET_OS_IPHONE
    [self performBackgroundWorkCleanupIfFinished];
#endif
}

- (void)startRequest:(BCCHTTPRequest *)request
{
    if (!request) {
        return;
    }
    
    if (request.cacheable && request.requestDidLoadFromCacheBlock) {
        NSString *requestURL = [request.URL absoluteString];
        
        NSDictionary *cachedResponseAttributes = [self.resultsCache attributesForKey:requestURL];
        NSString *mimeType = [cachedResponseAttributes objectForKey:BCCHTTPRequestContentTypeHeaderKey];
        
        NSData *cacheData = [self.resultsCache cacheDataForKey:requestURL];
        
        if (cacheData) {
            [request setResponseData:[cacheData mutableCopy] withMIMEType:mimeType];
            [self performBlockOnDelegateQueueAndWait:^{
                request.requestDidLoadFromCacheBlock(request);
            }];
        }
    }
    
    [request handleRequestStart];
}

- (void)removeRequest:(BCCHTTPRequest *)request
{
    if (!request) {
        return;
    }
    
    [self performBlockOnWorkerQueueAndWait:^{
        [self.requests removeObject:request];
        [self pumpRequestQueue];
    }];
}

#pragma mark - Request Creation

- (BCCHTTPRequest *)requestWithURL:(NSString *)baseURL;
{
    if (!baseURL.length) {
        return nil;
    }
    
    BCCHTTPRequest *request = [[BCCHTTPRequest alloc] initWithBaseURL:baseURL];
    [self configureRequestWithQueueParameters:request];
    
    return request;
}

- (BCCHTTPRequest *)requestWithCommand:(NSString *)inCommand;
{
    return [self requestWithCommand:inCommand tag:nil userInfo:nil];
}

- (BCCHTTPRequest *)requestWithCommand:(NSString *)inCommand tag:(NSString *)inTag userInfo:(NSDictionary *)inUserInfo
{
    if (!self.baseURL || !inCommand.length) {
        return nil;
    }
    
    BCCHTTPRequest *request = [[BCCHTTPRequest alloc] initWithBaseURL:self.baseURL APIVersion:self.APIVersion command:inCommand userInfo:inUserInfo];
    request.tag = inTag;
    
    [self configureRequestWithQueueParameters:request];
    
    return request;
}

- (void)configureRequestWithQueueParameters:(BCCHTTPRequest *)request
{
    if (!request.basicAuthUsername) {
        request.basicAuthUsername = self.basicAuthUsername;
    }
    
    if (!request.basicAuthPassword && !request.keychainServiceName) {
        if (self.keychainServiceName) {
            request.keychainServiceName = self.keychainServiceName;
        } else if (self.basicAuthPassword) {
            request.basicAuthPassword = self.basicAuthPassword;
        }
    }
    
    request.SSLTrustMode = self.SSLTrustMode;
    request.publicSSLCertificatePath = self.publicSSLCertificatePath;
    
    request.OAuthConsumerKey = self.OAuthConsumerKey;
    request.OAuthSecretKey = self.OAuthSecretKey;
    request.OAuthToken = self.OAuthToken;
    request.OAuthTokenSecret = self.OAuthTokenSecret;
    
    request.userAgent = self.userAgent;
}

#pragma mark - Request Lifecycle

- (void)requestWillStart:(BCCHTTPRequest *)request
{
    [self performDelegateSelector:@selector(requestQueue:requestWillStart:) forRequest:request];
    
    if (request.requestWillStartBlock) {
        [self performBlockOnDelegateQueueAndWait:^{
            request.requestWillStartBlock(request);
        }];
    }
}

- (void)requestDidStart:(BCCHTTPRequest *)request
{
    [self performDelegateSelector:@selector(requestQueue:requestDidStart:) forRequest:request];
    
    if (request.requestDidStartBlock) {
        [self performBlockOnDelegateQueueAndWait:^{
            request.requestDidStartBlock(request);
        }];
    }
}

- (NSInputStream *)handleRequestNeedsBodyInputStream:(BCCHTTPRequest *)request
{
    return request.rawBodyInputStream;
}

- (NSURLRequest *)request:(BCCHTTPRequest *)request handleHTTPRedirectionWithNewURLRequest:(NSURLRequest *)newRequest
{
    return [request handleHTTPRedirectionWithRequest:newRequest];
}

- (void)request:(BCCHTTPRequest *)request handleBodyDataBytesSent:(int64_t)bytesSent totalBytesSent:(int64_t)totalBytesSent totalBytesExpectedToSend:(int64_t)totalBytesExpectedToSend
{
    [request handleBodyDataBytesSent:bytesSent totalBytesSent:totalBytesSent totalBytesExpectedToSend:totalBytesExpectedToSend];

    if (request.requestDidUploadDataBlock) {
        [self performBlockOnDelegateQueueAndWait:^{
            request.requestDidUploadDataBlock(request);
        }];
    }
}

- (NSURLCredential *)request:(BCCHTTPRequest *)request handleAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge
{
    return [request handleAuthenticationChallenge:challenge];
}

- (void)request:(BCCHTTPRequest *)request handleResponse:(NSURLResponse *)response
{
    [request handleResponse:response];
}

- (void)request:(BCCHTTPRequest *)request handleResponseData:(NSData *)responseData
{
    [request handleResponseData:responseData];

    if (request.requestDidDownloadDataBlock) {
        [self performBlockOnDelegateQueueAndWait:^{
            request.requestDidDownloadDataBlock(request);
        }];
    }
}

- (void)request:(BCCHTTPRequest *)request handleCompletionWithError:(NSError *)error
{
    [request handleRequestCompletionWithError:error];

    if (request.responseValidationBlock) {
        __block NSError *validationError = nil;
        [self performBlockOnDelegateQueueAndWait:^{
            validationError = request.responseValidationBlock(request);
        }];
        
        [request handleValidationError:validationError];
    }
        
    BOOL shouldRetry = NO;
    
    if (request.loadStatus == BCCHTTPRequestStatusFailed) {
        if (request.requestDidFailBlock) {
            [self performBlockOnDelegateQueueAndWait:^{
                request.requestDidFailBlock(request);
            }];
        }
        
        __block BOOL shouldRetry = request.isRetryable;
        if (self.delegate && [self.delegate respondsToSelector:@selector(requestQueue:shouldRetryRequest:)]) {
            [self performBlockOnDelegateQueueAndWait:^{
                shouldRetry = [self.delegate requestQueue:self shouldRetryRequest:request];
            }];
        }
        
        if (shouldRetry) {
            dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, request.currentRetryInterval * NSEC_PER_SEC);
            dispatch_after(popTime, self.workerQueue, ^(void){
                [self startRequest:request];
            });
        
            return;
        }
    } else if (request.requestDidFinishBlock) {
        [self performBlockOnDelegateQueueAndWait:^{
            request.requestDidFinishBlock(request);
        }];
        
        [self performDelegateSelector:@selector(requestQueue:requestDidFinish:) forRequest:request];
        
        NSData *responseData = request.responseData;
        NSString *mimeType = request.responseMIMEType;
        
        if (responseData && request.isCacheable) {
            NSMutableDictionary *requestAttributes = [[NSMutableDictionary alloc] initWithObjectsAndKeys:@(responseData.length), BCCHTTPRequestContentLengthHeaderKey, nil];
            
            if (request.responseMIMEType) {
                [requestAttributes setObject:mimeType forKey:BCCHTTPRequestContentTypeHeaderKey];
            }
            
            [self.resultsCache setCacheData:request.responseData forKey:[request.URL absoluteString] withAttributes:requestAttributes inBackground:YES didPersistBlock:^{
                    if (request.requestDidWriteToCacheBlock) {
                        request.requestDidWriteToCacheBlock(request);
                    }
            }];
        }
    }
    
    if (!shouldRetry) {
        [self removeRequest:request];
    }
}

#pragma mark - Request Lookup

- (NSArray *)activeRequests
{
    if (!self.requests) {
        return [NSArray array];
    }
    
    return [self findRequestsMatchingPredicate:[NSPredicate predicateWithFormat:@"%K != %d", @"loadStatus", BCCHTTPRequestStatusIdle]];
}

- (NSArray *)idleRequests {
    if (!self.requests) {
        return [NSArray array];
    }
    
    return [self findRequestsWithStatus:BCCHTTPRequestStatusIdle];
}

- (BCCHTTPRequest *)nextIdleRequest
{
    NSMutableString *predicateFormat = [[NSMutableString alloc] initWithFormat:@"loadStatus == %d", BCCHTTPRequestStatusIdle];
    
    // If we're running in the background, only process backgroundable
    // requests

#if TARGET_OS_IPHONE
    if (self.isRunningBackgroundTask) {
        [predicateFormat BCC_appendPredicateConditionWithOperator:@"AND" format:@"backgroundable == %@", [NSNumber numberWithBool:NO]];
    }
#endif
    
    NSArray *idleRequests = [self findRequestsMatchingPredicate:[NSPredicate predicateWithFormat:predicateFormat]];
    if (idleRequests.count < 1) {
        return nil;
    }
    
    return [idleRequests objectAtIndex:0];
}

- (NSArray *)backgroundableRequests
{
    if (!self.requests) {
        return [NSArray array];
    }
    
    return [self findRequestsMatchingPredicate:[NSPredicate predicateWithFormat:@"%K == %@", @"backgroundable", [NSNumber numberWithBool:YES]]];
}

- (BOOL)hasRequestForIdentifier:(NSString *)inIdentifier
{
    return ([self findRequestForIdentifier:inIdentifier] != nil);
}

- (BOOL)hasRequestsForURL:(NSString *)inURL
{
    NSArray *foundRequests = [self findRequestsForURL:inURL];
    return (foundRequests.count > 0);
}

- (BOOL)hasRequestsForCommand:(NSString *)inCommand
{
    NSArray *foundRequests = [self findRequestsForCommand:inCommand];
    return (foundRequests.count > 0);
}

- (BOOL)hasRequestsForTag:(NSString *)inTag
{
    NSArray *foundRequests = [self findRequestsForTag:inTag];
    return (foundRequests.count > 0);
}

- (BOOL)hasRequestsForCommand:(NSString *)inCommand tag:(NSString *)inTag{
    NSArray *foundRequests = [self findRequestsForCommand:inCommand tag:inTag];
    return (foundRequests.count > 0);
}

- (BOOL)hasRequestsForCommand:(NSString *)inCommand method:(BCCHTTPRequestMethod)requestMethod
{
    return [self hasRequestsForCommand:inCommand method:requestMethod pathParameterKeys:nil pathParameterValues:nil];
}

- (BOOL)hasRequestsForCommand:(NSString *)inCommand method:(BCCHTTPRequestMethod)requestMethod pathParameterMapping:(NSDictionary *)pathParameterMapping
{
    if (!pathParameterMapping) {
        return NO;
    }
    
    return [self hasRequestsForCommand:inCommand method:requestMethod pathParameterKeys:[pathParameterMapping allKeys] pathParameterValues:[pathParameterMapping allValues]];
}

- (BOOL)hasRequestsForCommand:(NSString *)inCommand method:(BCCHTTPRequestMethod)requestMethod pathParameterKey:(NSString *)pathParameterKey pathParameterValue:(id)pathParameterValue
{
    if (!pathParameterKey || !pathParameterValue) {
        return NO;
    }
    
    return [self hasRequestsForCommand:inCommand method:requestMethod pathParameterKeys:@[pathParameterKey] pathParameterValues:@[pathParameterValue]];
}

- (BOOL)hasRequestsForCommand:(NSString *)inCommand method:(BCCHTTPRequestMethod)requestMethod pathParameterKeys:(NSArray *)pathParameterKeys pathParameterValues:(NSArray *)pathParameterValues
{
    NSArray *foundRequests = [self findRequestsForCommand:inCommand method:requestMethod pathParameterKeys:pathParameterKeys pathParameterValues:pathParameterValues tag:nil];
    return (foundRequests.count > 0);
}

- (BOOL)hasBackgroundableRequests
{
    NSArray *foundRequests = self.backgroundableRequests;
    return (foundRequests.count > 0);
}

- (BCCHTTPRequest *)findRequestForIdentifier:(NSString *)identifier
{
    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"identifier == %@", identifier];
    NSArray *results = [self findRequestsMatchingPredicate:predicate];
    if (!results) {
        return nil;
    }
    
    return [results firstObject];
}

- (NSArray *)findRequestsForURL:(NSString *)requestURL
{
    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"URL.absoluteString == %@", requestURL];
    return [self findRequestsMatchingPredicate:predicate];
}

- (NSArray *)findRequestsForCommand:(NSString *)command
{
    if (!command) {
        return nil;
    }
    
    return [self findRequestsForCommand:command method:0 pathParameterKeys:nil pathParameterValues:nil tag:nil];
}

- (NSArray *)findRequestsForTag:(NSString *)tag
{
    if (!tag) {
        return nil;
    }
    
    return [self findRequestsForCommand:nil method:0 pathParameterKeys:nil pathParameterValues:nil tag:tag];
}

- (NSArray *)findRequestsForCommand:(NSString *)command tag:(NSString *)tag
{
    if (!command && !tag) {
        return nil;
    }
    
    return [self findRequestsForCommand:command method:0 pathParameterKeys:nil pathParameterValues:nil tag:tag];
}

- (NSArray *)findRequestsForCommand:(NSString *)command method:(BCCHTTPRequestMethod)requestMethod
{
    if (!command || requestMethod == 0) {
        return nil;
    }
    
    return [self findRequestsForCommand:command method:requestMethod pathParameterKeys:nil pathParameterValues:nil tag:nil];
}

- (NSArray *)findRequestsForCommand:(NSString *)command method:(BCCHTTPRequestMethod)requestMethod pathParameterKey:(NSString *)pathParameterKey pathParameterValue:(id)pathParameterValue
{
    return [self findRequestsForCommand:command method:requestMethod pathParameterKeys:@[pathParameterKey] pathParameterValues:@[pathParameterValue] tag:nil];
}

- (NSArray *)findRequestsForCommand:(NSString *)command method:(BCCHTTPRequestMethod)requestMethod pathParameterKeys:(NSArray *)pathParameterKeys pathParameterValues:(NSArray *)pathParameterValues tag:(NSString *)tag
{
    if (!command || !tag || !pathParameterKeys || !pathParameterValues) {
        return nil;
    }
    
    NSMutableString *predicateFormatString = [[NSMutableString alloc] init];
    NSMutableArray *argumentArray = [[NSMutableArray alloc] init];
    
    if (command) {
        [predicateFormatString BCC_appendPredicateCondition:@"%K == %@"];
        [argumentArray addObject:@"command"];
        [argumentArray addObject:command];
    }
    
    if (tag) {
        [predicateFormatString BCC_appendPredicateCondition:@"%K == %@"];
        [argumentArray addObject:@"tag"];
        [argumentArray addObject:tag];
    }
    
    if (pathParameterKeys.count > 0 && pathParameterValues.count > 0) {
        [pathParameterKeys enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
            NSString *currentPathParameterKey = (NSString *)obj;
            id currentPathParameterValue = [pathParameterValues objectAtIndex:idx];
            
            [predicateFormatString BCC_appendPredicateCondition:@"%K.%@ == %@"];
            [argumentArray addObject:@"pathParameters"];
            [argumentArray addObject:currentPathParameterKey];
            [argumentArray addObject:currentPathParameterValue];
        }];
    }
    
    if (requestMethod != 0) {
        [predicateFormatString BCC_appendPredicateCondition:@"%K == %@"];
        [argumentArray addObject:@"requestMethod"];
        [argumentArray addObject:@(requestMethod)];
    }
    
    NSPredicate *predicate = [NSPredicate predicateWithFormat:predicateFormatString argumentArray:argumentArray];
    return [self findRequestsMatchingPredicate:predicate];
}

- (NSArray *)findRequestsWithStatus:(BCCHTTPRequestStatus)status
{
    return [self findRequestsMatchingPredicate:[NSPredicate predicateWithFormat:@"%K == %d", @"loadStatus", status]];
}

- (BOOL)containsRequest:(BCCHTTPRequest *)request
{
    BCCHTTPRequest *foundRequest = [self findRequestForIdentifier:request.identifier];
    return (foundRequest != nil);
}

- (NSArray *)findRequestsMatchingPredicate:(NSPredicate *)predicate
{
    if (!predicate || self.requests.count < 1) {
        return nil;
    }
    
    /*__block NSArray *returnValue = nil;
    [self performBlockOnWorkerQueueAndWait:^{
        returnValue = [self.requests filteredArrayUsingPredicate:predicate];
    }];
    
    return returnValue;*/
    
    NSArray *foundRequests = [self.requests filteredArrayUsingPredicate:predicate];
    
    return foundRequests;
}

#pragma mark - Request Cancellation

- (void)cancelRequestForIdentifier:(NSString *)identifier
{
    if (!identifier) {
        return;
    }
    
    BCCHTTPRequest *request = [self findRequestForIdentifier:identifier];
    [self cancelRequest:request];
}

- (void)cancelRequestsForCommand:(NSString *)command
{
    if (!command) {
        return;
    }
    
    NSArray *requests = [self findRequestsForCommand:command];
    [self cancelRequests:requests];
}

- (void)cancelRequestsForTag:(NSString *)tag
{
    if (!tag) {
        return;
    }
    
    NSArray *requests = [self findRequestsForTag:tag];
    [self cancelRequests:requests];
}

- (void)cancelRequestsForCommand:(NSString *)command tag:(NSString *)tag
{
    if (!command || !tag) {
        return;
    }
    
    NSArray *requests = [self findRequestsForCommand:command tag:tag];
    [self cancelRequests:requests];
}

- (void)cancelRequestsWithStatus:(BCCHTTPRequestStatus)requestStatus
{
    NSArray *requests = [self findRequestsWithStatus:requestStatus];
    [self cancelRequests:requests];
}

- (void)cancelRequestsForURL:(NSString *)URL
{
    if (!URL) {
        return;
    }
    
    NSArray *requests = [self findRequestsForURL:URL];
    [self cancelRequests:requests];
}

- (void)cancelRequests:(NSArray *)requests
{
    if (requests.count < 1) {
        return;
    }
 
    [self performBlockOnWorkerQueueAndWait:^{
        [requests enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
            BCCHTTPRequest *request = (BCCHTTPRequest *)obj;
            [self cancelRequest:request];
        }];
    }];
}

- (void)cancelRequest:(BCCHTTPRequest *)request
{
    [self performBlockOnWorkerQueueAndWait:^{
        [self removeRequest:request];
    }];
}

- (void)cancelAllRequests
{
    [self cancelRequests:self.requests];
}

#pragma mark - Worker Queue

- (void)performBlockOnWorkerQueueAndWait:(void (^)())block
{
    char *specificValue = (char *)dispatch_get_specific(BCCHTTPRequestQueueQueueTypeSpecificKey);
    BOOL isOnWorkerQueue = (specificValue == BCCHTTPRequestQueueWorkerQueueSpecificValue);
    
    isOnWorkerQueue ? block() : dispatch_sync(self.workerQueue, block);
}

#pragma mark - Delegate Queue

- (void)performDelegateSelector:(SEL)selector
{
    [self performDelegateSelector:selector forRequest:nil];
}

- (void)performDelegateSelector:(SEL)selector forRequest:(BCCHTTPRequest *)request
{
    if (!self.delegate || !selector || ![self.delegate respondsToSelector:selector]) {
        return;
    }
    
    [self performBlockOnDelegateQueueAndWait:^{
        request ? [self.delegate performSelector:selector withObject:self withObject:request] : [self.delegate performSelector:selector withObject:self];
    }];
}

- (void)performBlockOnDelegateQueue:(void (^)())block
{
    dispatch_async(self.delegateQueue, block);
}

- (void)performBlockOnDelegateQueueAndWait:(void (^)())block
{
    char *specificValue = (char *)dispatch_get_specific(BCCHTTPRequestQueueQueueTypeSpecificKey);
    BOOL isOnDelegateQueue = (specificValue == BCCHTTPRequestQueueDelegateQueueSpecificValue);
    
    isOnDelegateQueue ? block() : dispatch_sync(self.delegateQueue, block);
}

#pragma mark - Background Requests

#if TARGET_OS_IPHONE

- (void)performBackgroundWorkCleanupIfFinished
{
    if (self.hasBackgroundableRequests) {
        return;
    }
    
    [self endBackgroundTask];
}

- (void)startBackgroundTask
{
    if (self.backgroundTaskIdentifier != UIBackgroundTaskInvalid) {
        return;
    }
    
    self.backgroundTaskIdentifier = [[UIApplication sharedApplication] beginBackgroundTaskWithName:self.queueName expirationHandler:^{
        [self endBackgroundTask];
    }];
}

- (void)endBackgroundTask
{
    [[UIApplication sharedApplication] endBackgroundTask:self.backgroundTaskIdentifier];
    self.backgroundTaskIdentifier = UIBackgroundTaskInvalid;
}


- (BOOL)isRunningBackgroundTask
{
    return (self.backgroundTaskIdentifier != UIBackgroundTaskInvalid);
}

- (void)applicationDidEnterBackground:(NSNotification *)notification
{
    if (!self.hasBackgroundableRequests) {
        return;
    }
    
    [self startBackgroundTask];

}
#endif

@end


#pragma mark URL Session Subclass Implementation

@implementation BCCHTTPURLSessionRequestQueue

#pragma mark - Initialization

- (id)init
{
    NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    self.session = [NSURLSession sessionWithConfiguration:configuration delegate:self delegateQueue:nil];
    
    /*NSString *sessionName = [NSString stringWithFormat:@"%@ Background Session", self.queueName];
    NSURLSessionConfiguration *backgroundConfiguration = [NSURLSessionConfiguration backgroundSessionConfiguration:sessionName];
    self.backgroundSession = [NSURLSession sessionWithConfiguration:backgroundConfiguration delegate:self delegateQueue:nil];*
    
    self.backgroundSessionCompletionHandler = NULL;*/
    
    return self;
}

/*#pragma mark - Request Queue Life Cycle

- (void)reset
{
    [self.session invalidateAndCancel];
    [super reset];
}*/

#pragma mark - Request Management

- (void)startRequest:(BCCHTTPRequest *)request
{
    [super startRequest:request];
    
    NSURLRequest *URLRequest = request.configuredURLRequest;
    if (!URLRequest) {
        return;
    }
    
    //NSURLSession *session = request.backgroundable ? self.backgroundSession : self.session;
    
    NSURLSession *session = self.session;
    NSURLSessionTask *task = nil;
    
    if (request.bodyData) {
        task = [session uploadTaskWithRequest:URLRequest fromData:request.bodyData];
    } else if (request.rawBodyFilePath) {
        task = [session uploadTaskWithRequest:URLRequest fromFile:[NSURL fileURLWithPath:request.rawBodyFilePath]];
    } else if (request.rawBodyInputStream) {
        task = [session uploadTaskWithStreamedRequest:URLRequest];
    } else {
        task = [self.session dataTaskWithRequest:URLRequest];
    }
    
    [self requestWillStart:request];
    
    [task resume];

    [self requestDidStart:request];
}

#pragma mark - Request Cancellation

- (void)cancelRequest:(BCCHTTPRequest *)request
{
    [request.task cancel];
    
    [super cancelRequest:request];
}

#pragma mark - Request Search

- (BCCHTTPRequest *)findRequestForTask:(NSURLSessionTask *)task
{
    NSString *requestIdentifier = ((NSMutableURLRequest *)(task.originalRequest)).BCCHTTPRequest_identifier;
    return [self findRequestForIdentifier:requestIdentifier];
}

#pragma mark - URL Session Delegate

- (void)URLSession:(NSURLSession *)session didBecomeInvalidWithError:(NSError *)error
{
    if (!self.session) {
        return;
    }
    
    NSLog(@"URL session \"%@\" became invalid with error: %@", self.queueName, error);
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task needNewBodyStream:(void (^)(NSInputStream *bodyStream))completionHandler
{
    if (!self.session) {
        return;
    }
    
    BCCHTTPRequest *request = [self findRequestForTask:task];
    if (!request) {
        return;
    }
    
    NSInputStream *bodyStream = [self handleRequestNeedsBodyInputStream:request];
    
    completionHandler(bodyStream);
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didSendBodyData:(int64_t)bytesSent totalBytesSent:(int64_t)totalBytesSent totalBytesExpectedToSend:(int64_t)totalBytesExpectedToSend
{
    if (session != self.session) {
        return;
    }
    
    BCCHTTPRequest *request = [self findRequestForTask:task];
    if (!request) {
        return;
    }
    
    [self request:request handleBodyDataBytesSent:bytesSent totalBytesSent:totalBytesSent totalBytesExpectedToSend:totalBytesExpectedToSend];
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task willPerformHTTPRedirection:(NSHTTPURLResponse *)response newRequest:(NSURLRequest *)newRequest completionHandler:(void (^)(NSURLRequest *))completionHandler
{
    if (session != self.session) {
        return;
    }
    
    BCCHTTPRequest *request = [self findRequestForTask:task];
    if (!request) {
        return;
    }
    
    NSURLRequest *redirectedRequest = [self request:request handleHTTPRedirectionWithNewURLRequest:newRequest];
    if (redirectedRequest) {
        completionHandler(redirectedRequest);
    } else {
        completionHandler(NULL);
    }
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition disposition, NSURLCredential *credential))completionHandler
{
    if (session != self.session) {
        return;
    }
    
    BCCHTTPRequest *request = [self findRequestForTask:task];
    if (!request) {
        return;
    }
    
    NSURLCredential *credential = [self request:request handleAuthenticationChallenge:challenge];
    if (credential) {
        completionHandler(NSURLSessionAuthChallengeUseCredential, credential);
    } else {
        completionHandler(NSURLSessionAuthChallengeCancelAuthenticationChallenge, NULL);
    }
}

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)task didReceiveResponse:(NSURLResponse *)response completionHandler:(void (^)(NSURLSessionResponseDisposition disposition))completionHandler
{
    if (session != self.session) {
        return;
    }
    
    BCCHTTPRequest *request = [self findRequestForTask:task];
    if (!request) {
        return;
    }
    
    [self request:request handleResponse:response];

    completionHandler(NSURLSessionResponseAllow);
}

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)task didReceiveData:(NSData *)data
{
    if (session != self.session) {
        return;
    }
    
    BCCHTTPRequest *request = [self findRequestForTask:task];
    if (!request) {
        return;
    }
    
    [self request:request handleResponseData:data];
}

/*- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)downloadTask didWriteData:(int64_t)bytesWritten totalBytesWritten:(int64_t)totalBytesWritten totalBytesExpectedToWrite:(int64_t)totalBytesExpectedToWrite
{

}

- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)downloadTask didFinishDownloadingToURL:(NSURL *)location
{
    
}*/

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error
{
    if (session != self.session) {
        return;
    }
    
    BCCHTTPRequest *request = [self findRequestForTask:task];
    if (!request) {
        return;
    }
    
    [self request:request handleCompletionWithError:error];
}

//#pragma mark Background Requests

/*- (void)performBackgroundWorkCleanupIfFinished
{
    [super performBackgroundWorkCleanupIfFinished];
    
    [self.backgroundSession getTasksWithCompletionHandler:^(NSArray *dataTasks, NSArray *uploadTasks, NSArray *downloadTasks) {
        NSUInteger totalCount = uploadTasks.count + downloadTasks.count;
        if (totalCount != 0) {
            return;
        }
        
        if (self.backgroundSessionCompletionHandler) {
            self.backgroundSessionCompletionHandler();
        }
    }];
}*/

@end


@implementation BCCHTTPRequestQueue (XAuthAdditions)

- (BCCHTTPRequest *)xAuthAccessTokenRequestWithCommand:(NSString *)command username:(NSString *)username password:(NSString *)password consumerKey:(NSString *)consumerKey secretKey:(NSString *)secretKey
{
    BCCHTTPRequest *request = [BCCHTTPRequest xAuthAccessTokenRequestWithEndpoint:self.baseURL username:username password:password consumerKey:consumerKey secretKey:secretKey];
    request.command = command;
    
    return request;
}

- (BCCHTTPRequest *)xAuthReverseAuthRequestWithCommand:(NSString *)command consumerKey:(NSString *)consumerKey secretKey:(NSString *)secretKey
{
    BCCHTTPRequest *request = [BCCHTTPRequest xAuthReverseAuthRequestWithEndpoint:self.baseURL consumerKey:consumerKey secretKey:secretKey];
    request.command = command;
    
    return request;
}

@end


#pragma mark URL Connection Subclass Implementation

@implementation BCCHTTPURLConnectionRequestQueue

#pragma mark - Request Management

- (void)startRequest:(BCCHTTPRequest *)request
{
    [super startRequest:request];
    
    // We do this here in the URL connection case because
    // we don't want to read the data in from the file until
    // the request is actually run. In the URL session case,
    // this is all handled by simply providing a path to the
    // task.
    
    // Maybe it'd be good to make this internal to the request
    // somehow?
    
    if (request.rawBodyFilePath) {
        request.rawBodyData = [NSData dataWithContentsOfFile:request.rawBodyFilePath options:NSDataReadingMappedIfSafe error:NULL];
    }
    
    NSURLRequest *URLRequest = request.configuredURLRequest;
    if (!URLRequest) {
        return;
    }
    
    NSURLConnection *connection = [[NSURLConnection alloc] initWithRequest:URLRequest delegate:self startImmediately:NO];
    [connection scheduleInRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    
    request.connection = connection;
    
    [self requestWillStart:request];
    
    [connection start];
    
    [self requestDidStart:request];
}

#pragma mark - Request Cancellation

- (void)cancelRequest:(BCCHTTPRequest *)request
{
    [request.connection cancel];
    
    [super cancelRequest:request];
}

#pragma mark - Request Search

- (BCCHTTPRequest *)findRequestForURLRequest:(NSURLRequest *)URLRequest
{
    NSString *requestIdentifier = ((NSMutableURLRequest *)URLRequest).BCCHTTPRequest_identifier;
    return [self findRequestForIdentifier:requestIdentifier];
}

#pragma mark - URL Connection Delegate

- (NSURLRequest *)connection:(NSURLConnection *)connection willSendRequest:(NSURLRequest *)URLRequest redirectResponse:(NSURLResponse *)redirectResponse
{
    BCCHTTPRequest *originalRequest = [self findRequestForURLRequest:connection.originalRequest];
    if (!originalRequest) {
        return nil;
    }
    
    return [self request:originalRequest handleHTTPRedirectionWithNewURLRequest:URLRequest];
}

- (NSInputStream *)connection:(NSURLConnection *)connection needNewBodyStream:(NSURLRequest *)request
{
    BCCHTTPRequest *originalRequest = [self findRequestForURLRequest:connection.originalRequest];
    if (!originalRequest) {
        return nil;
    }
    
    return [self handleRequestNeedsBodyInputStream:originalRequest];
}

- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response
{
    BCCHTTPRequest *request = [self findRequestForURLRequest:connection.originalRequest];
    if (!request) {
        return;
    }

    [self request:request handleResponse:response];
}

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data
{
    BCCHTTPRequest *request = [self findRequestForURLRequest:connection.originalRequest];
    if (!request) {
        return;
    }
    
    [self request:request handleResponseData:data];
}

- (BOOL)connection:(NSURLConnection *)connection canAuthenticateAgainstProtectionSpace:(NSURLProtectionSpace *)protectionSpace {
    BCCHTTPRequest *request = [self findRequestForURLRequest:connection.originalRequest];
    if (!request) {
        return NO;
    }
    
    if ([protectionSpace.authenticationMethod isEqualToString:NSURLAuthenticationMethodServerTrust]) {
        return (request.publicSSLCertificatePath != nil);
    }
    
    return YES;
}

- (void)connection:(NSURLConnection *)connection didReceiveAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge
{
    BCCHTTPRequest *request = [self findRequestForURLRequest:connection.originalRequest];
    if (!request) {
        return;
    }
    
    [self request:request handleAuthenticationChallenge:challenge];
}

- (void)connection:(NSURLConnection *)connection didSendBodyData:(NSInteger)bytesWritten totalBytesWritten:(NSInteger)totalBytesWritten totalBytesExpectedToWrite:(NSInteger)totalBytesExpectedToWrite
{
    BCCHTTPRequest *request = [self findRequestForURLRequest:connection.originalRequest];
    if (!request) {
        return;
    }
    
    [self request:request handleBodyDataBytesSent:bytesWritten totalBytesSent:totalBytesWritten totalBytesExpectedToSend:totalBytesExpectedToWrite];
}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error
{
    BCCHTTPRequest *request = [self findRequestForURLRequest:connection.originalRequest];
    if (!request) {
        return;
    }
    
    [self request:request handleCompletionWithError:error];
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection
{
    BCCHTTPRequest *request = [self findRequestForURLRequest:connection.originalRequest];
    if (!request) {
        return;
    }
    
    [self request:request handleCompletionWithError:nil];
}

@end

