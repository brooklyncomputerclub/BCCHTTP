//
//  BCCHTTPRequest+MantleSupport.h
//  Toilets
//
//  Created by Laurence Andersen on 10/28/15.
//  Copyright © 2015 Brooklyn Computer Club. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "BCCHTTPRequest.h"
#import <Mantle/Mantle.h>

@interface BCCHTTPRequest (MantleSupport)

@property (strong, nonatomic) NSString *mantleResponseModelClassName;
@property (strong, nonatomic) NSString *mantleResponseRootKey;
@property (nonatomic) BOOL interpretMantleDictionaryAsList;
@property (strong, nonatomic, readonly) id responseMantleObject;

@end
