//
//  BCCHTTPRequestQueue.h
//
//  Created by Buzz Andersen on 3/8/11.
//  Copyright 2013 Brooklyn Computer Club. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "BCCHTTPRequest.h"

@protocol BCCHTTPRequestQueueDelegate;


@interface BCCHTTPRequestQueue : NSObject <NSURLSessionDelegate, NSURLSessionTaskDelegate>

@property (nonatomic, readonly) NSString *queueName;
@property (strong, nonatomic) NSString *baseURL;
@property (strong, nonatomic) NSString *APIVersion;
@property (strong, nonatomic) NSString *userAgent;

@property (assign, nonatomic) BOOL processing;

@property (nonatomic) NSUInteger activeRequestLimit;
@property (nonatomic, readonly) NSArray *activeRequests;
@property (nonatomic, readonly) NSArray *idleRequests;
@property (nonatomic, readonly) BCCHTTPRequest *nextIdleRequest;
@property (nonatomic, readonly) NSArray *backgroundableRequests;

@property (readonly) BOOL hasBasicAuthCredentials;
@property (strong, nonatomic, retain) NSString *basicAuthUsername;
@property (strong, nonatomic) NSString *basicAuthPassword;
@property (strong, nonatomic) NSString *keychainServiceName;

@property (nonatomic, assign) BCCHTTPRequestSSLTrustMode SSLTrustMode;
@property (strong, nonatomic) NSString *publicSSLCertificatePath;

@property (readonly) BOOL hasOAuthCredentials;
@property (strong, nonatomic) NSString *OAuthConsumerKey;
@property (strong, nonatomic) NSString *OAuthSecretKey;
@property (strong, nonatomic) NSString *OAuthToken;
@property (strong, nonatomic) NSString *OAuthTokenSecret;

@property (assign, nonatomic) id <BCCHTTPRequestQueueDelegate> delegate;

// Initialization
- (id)initWithQueueName:(NSString *)queueName;

// Life Cycle
- (void)reset;

// Request Creation
- (BCCHTTPRequest *)requestWithURL:(NSString *)inURL;
- (BCCHTTPRequest *)requestWithCommand:(NSString *)inCommand;
- (BCCHTTPRequest *)requestWithCommand:(NSString *)inCommand tag:(NSString *)inTag userInfo:(NSDictionary *)inUserInfo;

// Request Management
- (void)addRequest:(BCCHTTPRequest *)request;

// Request Lookup
- (BOOL)hasRequestForIdentifier:(NSString *)inIdentifier;
- (BOOL)hasRequestsForURL:(NSString *)inURL;
- (BOOL)hasRequestsForCommand:(NSString *)inCommand;
- (BOOL)hasRequestsForTag:(NSString *)inTag;
- (BOOL)hasRequestsForCommand:(NSString *)inCommand tag:(NSString *)inTag;
- (BOOL)hasRequestsForCommand:(NSString *)inCommand method:(BCCHTTPRequestMethod)requestMethod;
- (BOOL)hasRequestsForCommand:(NSString *)inCommand method:(BCCHTTPRequestMethod)requestMethod pathParameterMapping:(NSDictionary *)pathParameterMapping;
- (BOOL)hasRequestsForCommand:(NSString *)inCommand method:(BCCHTTPRequestMethod)requestMethod pathParameterKey:(NSString *)pathParameterKey pathParameterValue:(id)pathParameterValue;
- (BOOL)hasRequestsForCommand:(NSString *)inCommand method:(BCCHTTPRequestMethod)requestMethod pathParameterKeys:(NSArray *)pathParameterKeys pathParameterValues:(NSArray *)pathParameterValues;
- (BOOL)hasBackgroundableRequests;

- (BCCHTTPRequest *)findRequestForIdentifier:(NSString *)identifier;
- (NSArray *)findRequestsForURL:(NSString *)inURL;
- (NSArray *)findRequestsForCommand:(NSString *)command;
- (NSArray *)findRequestsForTag:(NSString *)tag;
- (NSArray *)findRequestsForCommand:(NSString *)command tag:(NSString *)inTag;
- (NSArray *)findRequestsForCommand:(NSString *)inCommand method:(BCCHTTPRequestMethod)requestMethod;
- (NSArray *)findRequestsForCommand:(NSString *)command method:(BCCHTTPRequestMethod)requestMethod pathParameterKeys:(NSArray *)pathParameterKeys pathParameterValues:(NSArray *)pathParameterValues tag:(NSString *)tag;
- (NSArray *)findRequestsWithStatus:(BCCHTTPRequestStatus)status;
- (NSArray *)findRequestsMatchingPredicate:(NSPredicate *)predicate;

- (BOOL)containsRequest:(BCCHTTPRequest *)request;

// Request Cancellation
- (void)cancelRequestForIdentifier:(NSString *)identifier;
- (void)cancelRequestsForCommand:(NSString *)command;
- (void)cancelRequestsForTag:(NSString *)tag;
- (void)cancelRequestsForCommand:(NSString *)command tag:(NSString *)tag;
- (void)cancelRequestsWithStatus:(BCCHTTPRequestStatus)requestStatus;
- (void)cancelRequestsForURL:(NSString *)URL;
- (void)cancelRequest:(BCCHTTPRequest *)request;
- (void)cancelAllRequests;

// Worker Queue
- (void)performBlockOnWorkerQueueAndWait:(void (^)())block;

@end


@interface BCCHTTPRequestQueue (XAuthAdditions)

- (BCCHTTPRequest *)xAuthAccessTokenRequestWithCommand:(NSString *)command username:(NSString *)username password:(NSString *)password consumerKey:(NSString *)consumerKey secretKey:(NSString *)secretKey;
- (BCCHTTPRequest *)xAuthReverseAuthRequestWithCommand:(NSString *)command consumerKey:(NSString *)consumerKey secretKey:(NSString *)secretKey;

@end


@protocol BCCHTTPRequestQueueDelegate <NSObject>

@optional
- (void)requestQueue:(BCCHTTPRequestQueue *)requestQueue requestWillStart:(BCCHTTPRequest *)request;
- (void)requestQueue:(BCCHTTPRequestQueue *)requestQueue requestDidStart:(BCCHTTPRequest *)request;
- (void)requestQueue:(BCCHTTPRequestQueue *)requestQueue requestDidFinish:(BCCHTTPRequest *)request;

- (BOOL)requestQueue:(BCCHTTPRequestQueue *)requestQueue shouldRetryRequest:(BCCHTTPRequest *)request;

- (void)requestQueueDidBecomeIdle:(BCCHTTPRequestQueue *)queue;

@end
