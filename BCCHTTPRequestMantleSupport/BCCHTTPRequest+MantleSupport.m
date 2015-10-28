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

- (id)responseMantleObject
{
    NSString *modelClassName = self.mantleResponseModelClassName;
    if (!modelClassName) {
        return nil;
    }
    
    Class modelClass = NSClassFromString(modelClassName);
    
    id JSONObject = self.responseJSONObject;
    if (!JSONObject) {
        return nil;
    }
    
    NSError *error;
    
    id mantleObject = nil;
    if ([JSONObject isKindOfClass:[NSArray class]]) {
        mantleObject = [MTLJSONAdapter modelsOfClass:modelClass fromJSONArray:JSONObject error:&error];
    } else if ([JSONObject isKindOfClass:[NSDictionary class]]) {
        mantleObject = [MTLJSONAdapter modelOfClass:modelClass fromJSONDictionary:JSONObject error:&error];
    }
    
    return mantleObject;
}

@end
