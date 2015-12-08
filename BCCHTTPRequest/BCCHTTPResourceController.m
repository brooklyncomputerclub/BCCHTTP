//
//  STHTTPResourceController.m
//
//  Created by Buzz Andersen on 9/17/12.
//  Copyright (c) Brooklyn Computer Club. All rights reserved.
//

#import "BCCHTTPResourceController.h"
#import "BCCHTTPRequestQueue.h"
#import "BCCHTTPRequest.h"
#import "BCCPersistentCache.h"
#import <ImageIO/ImageIO.h>

#if TARGET_OS_IPHONE
#import <UIKit/UIKit.h>
#endif

// TO DO: If we have the default version of a cached item,
// we should be able to return that if a request variation
// isn't already cached

NSString *BCCHTTPResourceControllerDataLoadNotification = @"STHTTPResourceControllerLoadedDataNotification";
NSString *BCCHTTPResourceControllerImageLoadNotification = @"STHTTPResourceControllerLoadedImageNotification";
NSString *BCCHTTPResourceControllerNotificationKeyLoadStatus = @"LoadStatus";
NSString *BCCHTTPResourceControllerNotificationKeyImage = @"Image";
NSString *BCCHTTPResourceControllerNotificationKeyData = @"Data";
NSString *BCCHTTPResourceControllerNotificationKeyURL = @"URL";
NSString *BCCHTTPResourceControllerNotificationKeyCacheKey = @"CacheKey";


@interface BCCHTTPResourceController ()

@property (nonatomic, retain) BCCHTTPRequestQueue *requestQueue;
@property (nonatomic, retain) BCCPersistentCache *resourceCache;

- (BCCHTTPRequest *)configuredRequestForURL:(NSString *)inURL;

- (void)sendImageLoadedNotificationForData:(NSData *)inImageData URL:(NSString *)inURL loadStatus:(BCCHTTPResourceControllerLoadStatus)inLoadStatus completionBlock:(BCCHTTPResourceControllerImageLoadBlock)inCompletionBlock;

@end


@implementation BCCHTTPResourceController

@synthesize requestQueue;
@synthesize resourceCache;

#pragma mark - Class Methods

+ (BCCHTTPResourceController *)sharedResourceController
{
    static BCCHTTPResourceController *sharedResourceController;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedResourceController = [[BCCHTTPResourceController alloc] initWithIdentifier:@"com.brooklyncomputerclub.sharedResourceController" cacheDirectory:nil];
        sharedResourceController.resourceCache.usesMemoryCache = NO;
    });
    
    return sharedResourceController;
}

#pragma mark - Initialization

- (id)initWithIdentifier:(NSString *)inIdentifier cacheDirectory:(NSString *)inCacheDirectory;
{
    if (!(self = [super init])) {
        return nil;
    }
    
    self.resourceCache = [[BCCPersistentCache alloc] initWithIdentifier:inIdentifier rootDirectory:inCacheDirectory];
    self.resourceCache.maximumMemoryCacheSize = 5 * 1024 * 1024; // 5 MB
    self.resourceCache.maximumFileCacheSize = 50 * 1024 * 1024; //50MB
    
    self.requestQueue = [[BCCHTTPRequestQueue alloc] initWithQueueName:inIdentifier];
    //self.requestQueue.maxConcurrentOperationCount = 3.0;
    
#if TARGET_OS_IPHONE
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(didReceiveMemoryWarning:) name:UIApplicationDidReceiveMemoryWarningNotification object:nil];
#endif
    
    return self;
}

- (void)dealloc;
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - Image Loading

- (void)requestImageForURL:(NSString *)inURL forceReload:(BOOL)inForceReload;
{
    [self requestImageForURL:inURL forceReload:inForceReload alternateURL:nil completionBlock:NULL];
}

- (void)requestImageForURL:(NSString *)inURL forceReload:(BOOL)inForceReload completionBlock:(BCCHTTPResourceControllerImageLoadBlock)inCompletionBlock;
{
    [self requestImageForURL:inURL forceReload:inForceReload alternateURL:nil completionBlock:inCompletionBlock];
}

- (void)requestImageForURL:(NSString *)inURL forceReload:(BOOL)inForceReload alternateURL:(NSString *)inAlternateURL completionBlock:(BCCHTTPResourceControllerImageLoadBlock)inCompletionBlock
{
    if (!inURL) {
        if (inCompletionBlock) {
            dispatch_async(dispatch_get_main_queue(), ^{
                inCompletionBlock(nil, nil, BCCHTTPResourceControllerLoadStatusLoadFailed, nil);
            });
        }
        
        return;
    }
    
    // If we're not forcing a reload, check the cache
    if (!inForceReload) {
        // If we have a disk cached image, uncompress, cache,
        // and send that off
        NSData *cachedData = [self.resourceCache cacheDataForKey:inURL];
        if (cachedData) {
            [self sendImageLoadedNotificationForData:cachedData URL:inURL loadStatus:BCCHTTPResourceControllerLoadStatusLoadedFromCache completionBlock:inCompletionBlock];
            return;
        }
    }
    
    // If we don't have the image data in the cache or
    // are forcing a reload, do a network request
    
    BCCHTTPRequestStatusBlock imageLoadCompletionBlock = ^(BCCHTTPRequest *inRequest) {
        NSData *imageData = inRequest.responseData;
        if (!imageData) {
            return;
        }
        
        [self.resourceCache setCacheData:imageData forKey:inURL withAttributes:nil inBackground:YES didPersistBlock:NULL];
        [self sendImageLoadedNotificationForData:imageData URL:inURL loadStatus:BCCHTTPResourceControllerLoadStatusLoadedFromNetwork completionBlock:inCompletionBlock];
    };
    
    BCCHTTPRequestStatusBlock imageLoadFailureBlock = ^(BCCHTTPRequest *inRequest) {
        [self sendImageLoadedNotificationForData:nil URL:inURL loadStatus:BCCHTTPResourceControllerLoadStatusLoadFailed completionBlock:inCompletionBlock];
    };
    
    BCCHTTPRequest *imageRequest = [self configuredRequestForURL:inURL];
    
    // If the request is successful, cache the data
    // and call the provided completion block
    // if appropriate
    imageRequest.requestDidFinishBlock = imageLoadCompletionBlock;
    
    // If the request failed, call the failure block
    // if appropriate
    imageRequest.requestDidFailBlock = ^(BCCHTTPRequest *inRequest) {
        if (inAlternateURL) {
            BCCHTTPRequest *alternateImageRequest = [self configuredRequestForURL:inAlternateURL];
            alternateImageRequest.requestDidFinishBlock = imageLoadCompletionBlock;
            [self.requestQueue addRequest:alternateImageRequest];
            
            alternateImageRequest.requestDidFailBlock = imageLoadFailureBlock;
            
            return;
        } else {
            imageLoadFailureBlock(inRequest);
        }
    };
    
    [self.requestQueue addRequest:imageRequest];
}

- (BCCHTTPRequest *)configuredRequestForURL:(NSString *)inURL
{
    BCCHTTPRequest *imageRequest = [self.requestQueue requestWithURL:inURL];
    imageRequest.requestMethod = BCCHTTPRequestMethodGET;
    
    imageRequest.timeoutInterval = 40.0;

#if TARGET_OS_IPHONE
    imageRequest.spinsActivityIndicator = NO;
#endif
    
    return imageRequest;
}

#pragma mark - Cancellation

- (void)cancelLoadForURL:(NSString *)inURL;
{
    [self.requestQueue cancelRequestsForURL:inURL];
}

#pragma mark - Cache Clearance

- (void)clearCache
{
    [self.resourceCache clearCache];
}

#pragma mark - Notifications

- (void)didReceiveMemoryWarning:(NSNotification *)notification
{
    NSLog(@"RESOURCE CONTROLLER MEMORY WARNING");
    [self.resourceCache clearMemoryCache];
}

#pragma mark - Private Methods

- (void)sendImageLoadedNotificationForData:(NSData *)inImageData URL:(NSString *)inURL loadStatus:(BCCHTTPResourceControllerLoadStatus)inLoadStatus completionBlock:(BCCHTTPResourceControllerImageLoadBlock)inCompletionBlock;
{
    if (!inURL || !inImageData) {
        if (inCompletionBlock) {
            inCompletionBlock(nil, nil, BCCHTTPResourceControllerLoadStatusLoadFailed, nil);
        }
        return;
    }
   
    NSMutableDictionary *userInfo = [[NSMutableDictionary alloc] init];
    NSNumber *loadStatusNumber = [NSNumber numberWithInteger:inLoadStatus];

    [userInfo setObject:inURL forKey:BCCHTTPResourceControllerNotificationKeyURL];
    [userInfo setObject:loadStatusNumber forKey:BCCHTTPResourceControllerNotificationKeyLoadStatus];
    
    id image = nil;
    
// TO DO: Make this work on AppKit
#if TARGET_OS_IPHONE
    image = [UIImage imageWithData:inImageData];
#elif TARGET_OS_MAC
    image = [[NSImage alloc] initWithData:inImageData];
#endif

    if (!image) {
        return;
    }
    
    [userInfo setObject:image forKey:BCCHTTPResourceControllerNotificationKeyImage];

    NSNotification *notification = [NSNotification notificationWithName:BCCHTTPResourceControllerImageLoadNotification object:self userInfo:userInfo];
    
    NSPostingStyle postingStyle = NSPostWhenIdle;
    if (inLoadStatus == BCCHTTPResourceControllerLoadStatusLoadedFromCache) {
        postingStyle = NSPostNow;
    }
    
    if (inCompletionBlock) {
        dispatch_async(dispatch_get_main_queue(), ^{
            inCompletionBlock(inImageData, image, inLoadStatus, nil);
        });
    }
    
    [[NSNotificationQueue defaultQueue] enqueueNotification:notification postingStyle:postingStyle coalesceMask:NSNotificationNoCoalescing forModes:nil];
}

@end
