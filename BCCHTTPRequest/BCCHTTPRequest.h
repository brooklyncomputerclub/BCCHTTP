//
//  BCCHTTPRequest.h
//
//  Created by Buzz Andersen on 3/8/11.
//  Copyright 2013 Brooklyn Computer Club. All rights reserved.
//

#import <Foundation/Foundation.h>

@class BCCHTTPRequest;
@class BCCHTTPRequestQueue;

extern NSString *BCCHTTPRequestErrorDomain;

extern const NSInteger BCCHTTPRequestNoNetworkStatusCode;
extern const NSInteger BCCHTTPRequestNoCachedDataStatusCode;
extern const NSInteger BCCHTTPRequestLoadedCachedDataStatusCode;
extern const NSInteger BCCHTTPRequestSuccessStatusCode;
extern const NSInteger BCCHTTPRequestUnauthorizedStatusCode;
extern const NSInteger BCCHTTPRequestForbiddenStatusCode;
extern const NSInteger BCCHTTPRequestMinClientErrorStatusCode;
extern const NSInteger BCCHTTPRequestMaxClientErrorStatusCode;
extern const NSInteger BCCHTTPRequestMinServerErrorStatusCode;
extern const NSInteger BCCHTTPRequestMaxServerErrorStatusCode;

extern const NSInteger BCCHTTPRequestMethodUnspecified;

extern NSString *BCCHTTPRequestTextHTMLContentType;
extern NSString *BCCHTTPRequestTextPlainContentType;
extern NSString *BCCHTTPRequestJSONContentType;
extern NSString *BCCHTTPRequestJavascriptContentType;
extern NSString *BCCHTTPRequestURLEncodedContentType;
extern NSString *BCCHTTPRequestMultipartContentType;
extern NSString *BCCHTTPRequestOctetStreamContentType;

extern NSString *BCCHTTPRequestContentTypeHeaderKey;
extern NSString *BCCHTTPRequestContentLengthHeaderKey;

typedef enum {
    BCCHTTPRequestMethodGET = 1,
    BCCHTTPRequestMethodPOST,
    BCCHTTPRequestMethodPUT,
    BCCHTTPRequestMethodDELETE,
    BCCHTTPRequestMethodHEAD
} BCCHTTPRequestMethod;

typedef enum {
    BCCHTTPRequestBodyFormatNone,
    BCCHTTPRequestBodyFormatMultipart,
    BCCHTTPRequestBodyFormatJSON,
    BCCHTTPRequestBodyFormatURLEncoded
} BCCHTTPRequestBodyFormat;

typedef enum {
    BCCHTTPRequestStatusIdle,
    BCCHTTPRequestStatusLoading,
    BCCHTTPRequestStatusComplete,
    BCCHTTPRequestStatusFailed
} BCCHTTPRequestStatus;

typedef enum {
    BCCHTTPRequestAuthenticationTypeNone,
    BCCHTTPRequestAuthenticationTypeBasic,
    BCCHTTPRequestAuthenticationTypeAuthToken,
    BCCHTTPRequestAuthenticationTypeOAuth1,
    BCCHTTPRequestAuthenticationTypeOAuth2
} BCCHTTPRequestAuthenticationType;

typedef enum {
    BCCHTTPRequestXAuthModeNone,
    BCCHTTPRequestXAuthModeClientAuth,
    BCCHTTPRequestXAuthModeReverseAuth
} BCCHTTPRequestXAuthMode;

typedef enum {
    BCCHTTPRequestSSLTrustModeValidCertsOnly,
    BCCHTTPRequestSSLTrustModePinnedCertsOnly,
    BCCHTTPRequestSSLTrustModeUnenforced
} BCCHTTPRequestSSLTrustMode;

typedef enum {
    BCCHTTPRequestRetryMethodNone,
    BCCHTTPRequestRetryMethodFixed,
    BCCHTTPRequestRetryMethodExponentialBackoff,
    BCCHTTPRequestRetryMethodRandomizedInterval
} BCCHTTPRequestRetryMethod;

typedef void (^BCCHTTPRequestStatusBlock)(BCCHTTPRequest *request);
typedef NSError *(^BCCHTTPRequestValidationBlock)(BCCHTTPRequest *request);


extern NSString *BCCHTTPRequestFileInfoFilenameKey;
extern NSString *BCCHTTPRequestFileInfoFileDataKey;
extern NSString *BCCHTTPRequestFileInfoFilePathKey;
extern NSString *BCCHTTPRequestFileInfoContentTypeKey;
extern NSString *BCCHTTPRequestFileInfoUUIDKey;


@interface BCCHTTPRequest : NSObject

@property (nonatomic, readonly) NSString *identifier;

@property (nonatomic, readonly) NSURL *URL;
@property (strong, nonatomic) NSString *baseURL;
@property (strong, nonatomic) NSString *APIVersion;
@property (strong, nonatomic) NSString *command;
@property (nonatomic, readonly) NSString *queryString;

@property (assign, nonatomic) BCCHTTPRequestMethod requestMethod;

@property (assign, nonatomic) BCCHTTPRequestBodyFormat bodyFormat;

@property (nonatomic, readonly) NSData *bodyData;

@property (strong, nonatomic) NSData *rawBodyData;
@property (strong, nonatomic) NSString *rawBodyFilePath;
@property (strong, nonatomic) NSInputStream *rawBodyInputStream;

@property (nonatomic, readonly) NSString *bodyStringRepresentation;

@property (nonatomic, readonly) NSDate *time;

@property (strong, nonatomic) NSString *tag;

@property (strong, nonatomic) NSString *userAgent;

#if TARGET_OS_IPHONE
@property (assign, nonatomic) BOOL spinsActivityIndicator;
@property (assign, nonatomic, getter=isBackgroundable) BOOL backgroundable;
#endif

@property (assign, nonatomic, getter=isCacheable) BOOL cacheable;

@property (nonatomic, assign) NSTimeInterval timeoutInterval;

@property (assign, nonatomic) BCCHTTPRequestAuthenticationType authenticationType;
@property (nonatomic, readonly) BOOL requiresOAuth;
@property (nonatomic, readonly) BOOL hasBasicAuthCredentials;

@property (nonatomic, assign) BCCHTTPRequestSSLTrustMode SSLTrustMode;
@property (strong, nonatomic) NSString *publicSSLCertificatePath;

@property (strong, nonatomic) NSString *authToken;

@property (strong, nonatomic) NSString *keychainServiceName;

@property (strong, nonatomic) NSString *basicAuthUsername;
@property (strong, nonatomic) NSString *basicAuthPassword;

@property (strong, nonatomic) NSString *OAuthConsumerKey;
@property (strong, nonatomic) NSString *OAuthSecretKey;
@property (strong, nonatomic) NSString *OAuthToken;
@property (strong, nonatomic) NSString *OAuthTokenSecret;
@property (strong, nonatomic) NSString *OAuthCallbackURL;
@property (assign, nonatomic) BCCHTTPRequestXAuthMode OAuthXAuthMode;

@property (copy) BCCHTTPRequestStatusBlock requestWillStartBlock;
@property (copy) BCCHTTPRequestStatusBlock requestDidStartBlock;
@property (copy) BCCHTTPRequestStatusBlock requestDidLoadFromCacheBlock;
@property (copy) BCCHTTPRequestStatusBlock requestDidFinishBlock;
@property (copy) BCCHTTPRequestStatusBlock requestDidFailBlock;
@property (copy) BCCHTTPRequestStatusBlock requestDidUploadDataBlock;
@property (copy) BCCHTTPRequestStatusBlock requestDidDownloadDataBlock;
@property (copy) BCCHTTPRequestStatusBlock requestDidWriteToCacheBlock;
@property (copy) BCCHTTPRequestStatusBlock requestForbiddenBlock;
@property (copy) BCCHTTPRequestValidationBlock responseValidationBlock;

@property (nonatomic, readonly) NSURLRequest *configuredURLRequest;
@property (strong, nonatomic) NSHTTPURLResponse *response;

@property (nonatomic, readonly) BCCHTTPRequestStatus loadStatus;
@property (nonatomic, readonly) BOOL isLoading;
@property (nonatomic, readonly) NSError *error;

@property (nonatomic, readonly) int64_t uploadPercentComplete;
@property (nonatomic, readonly) int64_t responsePercentComplete;

@property (nonatomic, readonly) NSInteger responseStatusCode;
@property (nonatomic, readonly) BOOL responseStatusCodeIsError;
@property (nonatomic, readonly) BOOL responseStatusCodeIsRetryable;
@property (nonatomic, readonly) NSString *responseMIMEType;

@property (nonatomic, readonly) NSMutableData *responseData;
@property (nonatomic, readonly) id responseJSONObject;
@property (nonatomic, readonly) NSString *responseString;
@property (nonatomic, readonly) NSDictionary *responseURLEncodedDictionary;

@property (nonatomic, readonly) NSMutableDictionary *headers;
@property (nonatomic, readonly) NSMutableDictionary *queryParameters;
@property (nonatomic, readonly) NSMutableDictionary *bodyParameters;

@property (nonatomic, assign) BCCHTTPRequestRetryMethod retryMethod;
@property (nonatomic, readonly) BOOL isRetryable;
@property (nonatomic, readonly) NSInteger retryCount;
@property (nonatomic, assign) NSInteger maximumRetryCount;
@property (nonatomic, assign) NSTimeInterval minimumRetryInterval;
@property (nonatomic, assign) NSTimeInterval maximumRetryInterval;
@property (nonatomic, readonly) NSTimeInterval currentRetryInterval;

// Initialization
- (id)initWithBaseURL:(NSString *)inBaseURL;
- (id)initWithBaseURL:(NSString *)inBaseURL command:(NSString *)inCommand;
- (id)initWithBaseURL:(NSString *)inBaseURL APIVersion:(NSString *)inAPIVersion command:(NSString *)inCommand userInfo:(NSDictionary *)inUserInfo;

- (void)reset;

// Headers
- (void)addHeadersFromDictionary:(NSDictionary *)dictionary;
- (void)setHeaderString:(NSString *)value forKey:(NSString *)key;
- (NSString *)headerStringForKey:(NSString *)key;

// Path Parameters
- (void)addPathParametersFromDictionary:(NSDictionary *)dictionary;
- (void)setPathParameterValue:(id)value forKey:(NSString *)key;

// Query Parameters
- (void)addQueryParametersFromDictionary:(NSDictionary *)dictionary;
- (void)setQueryParametersValue:(id)value forKey:(NSString *)key;
- (id)queryParameterValueForKey:(NSString *)inKey;

// Body Parameters
- (void)addBodyParametersFromDictionary:(NSDictionary *)dictionary;
- (void)setBodyParameterValue:(id)value forKey:(NSString *)key;
- (id)bodyParameterValueForKey:(NSString *)key;

// Files
- (void)setFileData:(NSData *)fileData forParameterName:(NSString *)parameterName filename:(NSString *)filename contentType:(NSString *)contentType;
- (void)setFilePath:(NSString *)filePath forParameterName:(NSString *)parameterName filename:(NSString *)filename contentType:(NSString *)contentType;
- (void)addFileWithFileInfo:(NSDictionary *)dictionary;
- (NSDictionary *)fileInfoForParameterName:(NSString *)key;

// OAuth Parameters
- (void)addOAuthParametersFromDictionary:(NSDictionary *)dictionary;
- (void)setOAuthParameter:(id)value forKey:(NSString *)key;
- (id)OAuthParameterForKey:(NSString *)key;

// User Info
- (void)addUserInfoFromDictionary:(NSDictionary *)dictionary;
- (void)setUserInfoValue:(id)value forKey:(NSString *)key;
- (id)userInfoValueForKey:(NSString *)key;

@end


@interface BCCHTTPRequest (XAuthAdditions)

@property (nonatomic, retain, readonly) NSString *responseOAuthToken;
@property (nonatomic, retain, readonly) NSString *responseOAuthTokenSecret;

+ (BCCHTTPRequest *)xAuthAccessTokenRequestWithEndpoint:(NSString *)inEndpointURL username:(NSString *)inUsername password:(NSString *)inPassword consumerKey:(NSString *)inConsumerKey secretKey:(NSString *)inSecretKey;
+ (BCCHTTPRequest *)xAuthReverseAuthRequestWithEndpoint:(NSString *)inEndpointURL consumerKey:(NSString *)inConsumerKey secretKey:(NSString *)inSecretKey;

- (void)setXAuthUsername:(NSString *)inUsername password:(NSString *)inPassword;

@end


@interface NSMutableURLRequest (BCCHTTPRequest)

@property (strong, nonatomic) NSString *BCCHTTPRequest_identifier;

@end

