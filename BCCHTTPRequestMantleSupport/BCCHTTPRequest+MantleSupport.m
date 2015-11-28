//
//  BCCHTTPRequest+MantleSupport.m
//  Toilets
//
//  Created by Laurence Andersen on 10/28/15.
//  Copyright © 2015 Brooklyn Computer Club. All rights reserved.
//

#import "BCCHTTPRequest+MantleSupport.h"
#import <objc/runtime.h>

@implementation BCCHTTPRequest (MantleSupport)

- (NSString *)mantleResponseModelClassName
{
    return objc_getAssociatedObject(self, @"mantleResponseModelClassName");
}

- (void)setMantleResponseModelClassName:(NSString *)className
{
    objc_setAssociatedObject(self, @"mantleResponseModelClassName", className, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (NSString *)mantleResponseRootKey
{
    return objc_getAssociatedObject(self, @"mantleResponseRootKey");
}

- (void)setMantleResponseRootKey:(NSString *)className
{
    objc_setAssociatedObject(self, @"mantleResponseRootKey", className, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (BOOL)interpretMantleDictionaryAsList
{
    NSNumber *interpretValue = objc_getAssociatedObject(self, @"interpretMantleDictionaryAsList");
    return [interpretValue boolValue];
}

- (void)setInterpretMantleDictionaryAsList:(BOOL)interpret
{
    objc_setAssociatedObject(self, @"interpretMantleDictionaryAsList", @(interpret), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (id)responseMantleObject
{
    NSString *modelClassName = self.mantleResponseModelClassName;
    if (!modelClassName) {
        return nil;
    }
    
    NSString *rootKey = self.mantleResponseRootKey;
    
    id JSONObject = self.responseJSONObject;
    if (!JSONObject) {
        return nil;
    }
    
    if (rootKey) {
        JSONObject = [JSONObject objectForKey:rootKey];
    }

    Class modelClass = NSClassFromString(modelClassName);
    
    NSError *error;
    
    id mantleObject = nil;
    if ([JSONObject isKindOfClass:[NSArray class]]) {
        mantleObject = [MTLJSONAdapter modelsOfClass:modelClass fromJSONArray:JSONObject error:&error];
    } else if ([JSONObject isKindOfClass:[NSDictionary class]]) {
        if (self.interpretMantleDictionaryAsList) {
            mantleObject = [MTLJSONAdapter modelsOfClass:modelClass fromJSONArray:[JSONObject allValues] error:&error];
        } else {
            mantleObject = [MTLJSONAdapter modelOfClass:modelClass fromJSONDictionary:JSONObject error:&error];
        }

    }
    
    return mantleObject;
}

@end
