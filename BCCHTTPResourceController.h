//
//  BCCHTTPResourceController.h
//
//  Created by Buzz Andersen on 9/17/12.
//  Copyright (c) 2012 Brooklyn Computer Club. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "BCCHTTPRequest.h"

@class BCCPersistentCache;
@class BCCHTTPRequestQueue;

typedef enum {
    BCCHTTPResourceControllerLoadStatusLoadFailed,
    BCCHTTPResourceControllerLoadStatusLoadedFromNetwork,
    BCCHTTPResourceControllerLoadStatusLoadedFromCache,
} BCCHTTPResourceControllerLoadStatus;

extern NSString *BCCHTTPResourceControllerDataLoadNotification;
extern NSString *BCCHTTPResourceControllerImageLoadNotification;
extern NSString *BCCHTTPResourceControllerNotificationKeyLoadStatus;
extern NSString *BCCHTTPResourceControllerNotificationKeyImage;
extern NSString *BCCHTTPResourceControllerNotificationKeyData;
extern NSString *BCCHTTPResourceControllerNotificationKeyURL;
extern NSString *BCCHTTPResourceControllerNotificationKeyCacheKey;

typedef void (^BCCHTTPResourceControllerImageLoadBlock)(NSData *imageData, UIImage *image, BCCHTTPResourceControllerLoadStatus status, NSError *error);


@interface BCCHTTPResourceController : NSObject <NSCacheDelegate>

@property (nonatomic, retain, readonly) BCCPersistentCache *resourceCache;
@property (nonatomic, retain, readonly) BCCHTTPRequestQueue *requestQueue;

// Class Methods
+ (BCCHTTPResourceController *)sharedResourceController;

// Initialization
- (id)initWithIdentifier:(NSString *)inIdentifier cacheDirectory:(NSString *)inCacheDirectory;

// Image Loading
- (void)requestImageForURL:(NSString *)inURL forceReload:(BOOL)inForceReload;
- (void)requestImageForURL:(NSString *)inURL forceReload:(BOOL)inForceReload completionBlock:(BCCHTTPResourceControllerImageLoadBlock)inCompletionBlock;
- (void)requestImageForURL:(NSString *)inURL forceReload:(BOOL)inForceReload alternateURL:(NSString *)alternateURL completionBlock:(BCCHTTPResourceControllerImageLoadBlock)inCompletionBlock;

// Cancellation
- (void)cancelLoadForURL:(NSString *)inURL;

// Cache Clearance
- (void)clearCache;

@end
