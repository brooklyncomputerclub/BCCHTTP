//
//  BCCHTTPRequest.m
//
//  Created by Buzz Andersen on 3/8/11.
//  Copyright 2013 Brooklyn Computer Club. All rights reserved.
//

#import "BCCHTTPRequest.h"

#import "BCCKeychain.h"

#import "BCCNetworkActivityIndicator.h"
#import "BCCRandomization.h"

#import "NSData+BCCAdditions.h"
#import "NSDate+BCCAdditions.h"
#import "NSDictionary+BCCAdditions.h"
#import "NSFileHandle+BCCAdditions.h"
#import "NSFileManager+BCCAdditions.h"
#import "NSString+BCCAdditions.h"
#import "NSURL+BCCAdditions.h"

// Constants
NSString *BCCHTTPRequestErrorDomain = @"BCCHTTPRequestErrorDomain";

NSString *BCCHTTPRequestMultipartBoundaryString = @"0xKhTmLbOuNdArY";

NSString *BCCHTTPRequestCacheSubdirectory = @"BCCHTTPRequest";
NSString *BCCHTTPRequestBodyCacheDirectory = @"BodyCache";

NSString *BCCHTTPRequestDefaultUserAgent = @"BCCHTTPRequest/2.0 (http://bcc.nyc)";

const NSInteger BCCHTTPRequestDefaultBodyFormat = BCCHTTPRequestBodyFormatURLEncoded;

const NSTimeInterval BCCHTTPRequestDefaultTimeoutInterval = 20.0;
const NSInteger BCCHTTPRequestDefaultMaximumRetryCount = 5;
const NSTimeInterval BCCHTTPRequestDefaultMinimumRetryInterval = 1.0;
const NSTimeInterval BCCHTTPRequestDefaultMaximumRetryInterval = 60.0;

const NSInteger BCCHTTPRequestNoNetworkStatusCode = 0;
const NSInteger BCCHTTPRequestNoCachedDataStatusCode = 1;
const NSInteger BCCHTTPRequestLoadedCachedDataStatusCode = 2;
const NSInteger BCCHTTPRequestSuccessStatusCode = 200;
const NSInteger BCCHTTPRequestUnauthorizedStatusCode = 401;
const NSInteger BCCHTTPRequestForbiddenStatusCode = 403;
const NSInteger BCCHTTPRequestMinClientErrorStatusCode = 400;
const NSInteger BCCHTTPRequestMaxClientErrorStatusCode = 499;
const NSInteger BCCHTTPRequestMinServerErrorStatusCode = 500;
const NSInteger BCCHTTPRequestMaxServerErrorStatusCode = 599;

const NSInteger BCCHTTPRequestMethodUnspecified = 0;

NSString *BCCHTTPRequestURLParametersKeyAPIVersion = @"BCCHTTPRequestAPIVersion";

NSString *BCCHTTPRequestFileInfoParameterNameKey = @"BCCHTTPRequestFileInfoParameterNameKey";
NSString *BCCHTTPRequestFileInfoFilenameKey = @"BCCHTTPRequestFileInfoFilenameKey";
NSString *BCCHTTPRequestFileInfoFileDataKey = @"BCCHTTPRequestFileInfoFileDataKey";
NSString *BCCHTTPRequestFileInfoFilePathKey = @"BCCHTTPRequestFileInfoFilePathKey";
NSString *BCCHTTPRequestFileInfoContentTypeKey = @"BCCHTTPRequestFileInfoContentTypeKey";
NSString *BCCHTTPRequestFileInfoUUIDKey = @"BCCHTTPRequestFileInfoUUIDKey";

NSString *BCCHTTPRequestTextHTMLContentType = @"text/html";
NSString *BCCHTTPRequestTextPlainContentType = @"text/plain";
NSString *BCCHTTPRequestJSONContentType = @"application/json";
NSString *BCCHTTPRequestJavascriptContentType = @"text/javascript";
NSString *BCCHTTPRequestURLEncodedContentType = @"application/x-www-form-urlencoded";
NSString *BCCHTTPRequestMultipartContentType = @"multipart/form-data; boundary=\"%@\"";
NSString *BCCHTTPRequestOctetStreamContentType = @"application/octet-stream";

NSString *BCCHTTPRequestUserAgentHeaderKey = @"User-Agent";
NSString *BCCHTTPRequestTimeZoneHeaderKey = @"Time-Zone";
NSString *BCCHTTPRequestGeoPositionHeaderKey = @"Geo-Position";
NSString *BCCHTTPRequestContentTypeHeaderKey = @"Content-Type";
NSString *BCCHTTPRequestContentLengthHeaderKey = @"Content-Length";
NSString *BCCHTTPRequestAuthorizationHeaderKey = @"Authorization";

NSString *BCCHTTPRequestOAuthConsumerKeyKey = @"oauth_consumer_key";
NSString *BCCHTTPRequestOAuthVersionKey = @"oauth_version";
NSString *BCCHTTPRequestOAuthTimestampKey = @"oauth_timestamp";
NSString *BCCHTTPRequestOauthNonceKey = @"oauth_nonce";
NSString *BCCHTTPRequestOAuthSignatureMethodKey = @"oauth_signature_method";
NSString *BCCHTTPRequestOAuthSignatureKey = @"oauth_signature";
NSString *BCCHTTPRequestOAuthCallbackURLKey = @"oauth_callback";
NSString *BCCHTTPRequestXAuthUsernameParameterKey = @"x_auth_username";
NSString *BCCHTTPRequestXAuthPasswordParameterKey = @"x_auth_password";
NSString *BCCHTTPRequestXAuthAuthModeKey = @"x_auth_mode";
NSString *BCCHTTPRequestOAuthTokenKey = @"oauth_token";
NSString *BCCHTTPRequestOAuthTokenSecretKey = @"oauth_token_secret";


@interface BCCHTTPRequest ()

@property (strong, nonatomic) NSString *identifier;

@property (strong, nonatomic) NSURL *URL;

@property (strong, nonatomic) NSDate *time;

@property (nonatomic, readonly) NSString *basicAuthAuthorizationHeaderString;
@property (nonatomic, readonly) NSString *OAuthAuthorizationHeaderString;
@property (nonatomic, readonly) NSString *OAuth2AuthorizationHeaderString;

@property (strong, nonatomic) NSString *responseMIMEType;

@property (strong, nonatomic) NSMutableData *responseData;

@property (strong, nonatomic) id responseJSONObject;
@property (strong, nonatomic) NSString *responseString;
@property (strong, nonatomic) NSDictionary *responseURLEncodedDictionary;

@property (assign, nonatomic) BCCHTTPRequestStatus loadStatus;
@property (strong, nonatomic) NSError *error;

@property (nonatomic) int64_t uploadPercentComplete;
@property (nonatomic) int64_t responsePercentComplete;

@property (strong, nonatomic) NSMutableDictionary *headers;
@property (strong, nonatomic) NSMutableDictionary *pathParameters;
@property (strong, nonatomic) NSMutableDictionary *queryParameters;
@property (strong, nonatomic) NSMutableDictionary *bodyParameters;
@property (strong, nonatomic) NSMutableData *formattedBodyData;
@property (strong, nonatomic) NSMutableDictionary *bodyFiles;
@property (strong, nonatomic) NSMutableDictionary *additionalOAuthParameters;
@property (strong, nonatomic) NSMutableDictionary *userInfo;

@property (nonatomic, assign) NSInteger retryCount;
@property (nonatomic, readonly) NSTimeInterval exponentialBackoffRetryInterval;

@property (strong, nonatomic) NSURLConnection *connection;
@property (strong, nonatomic) NSURLSessionTask *task;

// Initialization
- (void)resetFormattedBody;

// Files
- (void)addFileWithPath:(NSString *)inPath data:(NSData *)inData forParameterName:(NSString *)inParameterName filename:(NSString *)inFilename contentType:(NSString *)inContentType fileUUID:(NSString *)inFileUUID;

// URL
- (void)updateURL;

// NSURL Loading System Configuration
- (NSURLRequest *)configuredURLRequestForURL:(NSURL *)requestURL;
- (NSURLCredential *)credentialForAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge;

// Auth
- (NSString *)stringForXAuthAuthMode:(BCCHTTPRequestXAuthMode)authMode;

// SSL
- (BOOL)shouldTrustProtectionSpace:(NSURLProtectionSpace *)protectionSpace forSSLTrustMode:(BCCHTTPRequestSSLTrustMode)trustMode;

// Body Construction
- (NSInteger)buildRequestBody;
- (NSInteger)buildMultipartBody;
- (NSInteger)buildJSONBody;
- (NSInteger)buildURLEncodedBody;

- (NSInteger)appendBodyUTF8StringWithFormat:(NSString *)inString, ...;
- (NSInteger)appendBodyUTF8String:(NSString *)inString;
- (NSInteger)appendBodyData:(NSData *)inData;
- (NSInteger)appendBodyFileDataAtPath:(NSString *)inPath;

- (NSString *)cachePathForFilename:(NSString *)inFilename;
- (NSString *)stringValueForParameterObject:(NSString *)inObject;

- (NSString *)contentTypeStringForBodyFormat:(BCCHTTPRequestBodyFormat)bodyFormat;

// Retries
- (void)incrementRetryCount;

// Protected Interface
- (void)handleRequestStart;
- (NSURLRequest *)handleHTTPRedirectionWithRequest:(NSURLRequest *)newRequest;
- (NSURLCredential *)handleAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge;
- (void)handleBodyDataBytesSent:(int64_t)bytesSent totalBytesSent:(int64_t)totalBytesSent totalBytesExpectedToSend:(int64_t)totalBytesExpectedToSend;
- (void)handleResponse:(NSURLResponse *)response;
- (void)handleResponseData:(NSData *)responseData;
- (void)setResponseData:(NSMutableData *)responseData withMIMEType:(NSString *)mimeType;
- (void)handleRequestCompletionWithError:(NSError *)error;
- (void)handleValidationError:(NSError *)error;

@end


@implementation BCCHTTPRequest

#pragma mark Initialization

- (id)initWithBaseURL:(NSString *)baseURL
{
    return [self initWithBaseURL:baseURL APIVersion:nil command:nil userInfo:nil];
}

- (id)initWithBaseURL:(NSString *)baseURL command:(NSString *)inCommand
{
    return [self initWithBaseURL:baseURL APIVersion:nil command:inCommand userInfo:nil];
}

- (id)initWithBaseURL:(NSString *)baseURL APIVersion:(NSString *)APIVersion command:(NSString *)command userInfo:(NSDictionary *)userInfo
{
    if (!(self = [super init])) {
        return nil;
    }
    
    self.identifier = [[NSUUID UUID] UUIDString];
    
    self.baseURL = baseURL;
    self.APIVersion = APIVersion;
    self.command = command;
    self.userInfo = [userInfo mutableCopy];
    
    self.requestMethod = BCCHTTPRequestMethodGET;
    self.userAgent = BCCHTTPRequestDefaultUserAgent;
    self.timeoutInterval = BCCHTTPRequestDefaultTimeoutInterval;
    
    self.authenticationType = BCCHTTPRequestAuthenticationTypeNone;
    self.OAuthXAuthMode = BCCHTTPRequestXAuthModeNone;
    
    self.SSLTrustMode = BCCHTTPRequestSSLTrustModeValidCertsOnly;
    
    self.cacheable = NO;
    
#if TARGET_OS_IPHONE
    self.spinsActivityIndicator = YES;
#endif
    
    self.retryCount = 0;
    self.minimumRetryInterval = BCCHTTPRequestDefaultMinimumRetryInterval;
    self.maximumRetryInterval = BCCHTTPRequestDefaultMaximumRetryInterval;
    self.maximumRetryCount = BCCHTTPRequestDefaultMaximumRetryCount;
    
    self.queryParameters = [[NSMutableDictionary alloc] init];
    self.pathParameters = [[NSMutableDictionary alloc] init];
    self.additionalOAuthParameters = [[NSMutableDictionary alloc] init];
    self.headers = [[NSMutableDictionary alloc] init];
    self.userInfo = [[NSMutableDictionary alloc] init];
    
    [self reset];
    [self resetFormattedBody];
    
    return self;
}

- (void)reset
{
    self.loadStatus = BCCHTTPRequestStatusIdle;
    self.responseData = [[NSMutableData alloc] init];
    self.response = nil;
    self.responseJSONObject = nil;
    self.responseURLEncodedDictionary = nil;
    self.responseString = nil;
    self.error = nil;
    self.time = nil;
    self.uploadPercentComplete = 0;
    self.responsePercentComplete = 0;
    self.formattedBodyData = nil;
}

- (void)resetFormattedBody
{
    self.bodyFormat = BCCHTTPRequestDefaultBodyFormat;
    self.bodyParameters = [[NSMutableDictionary alloc] init];
    self.bodyFiles = [[NSMutableDictionary alloc] init];
    self.formattedBodyData = nil;
}

- (NSString *)description
{
    NSString *stringForBodyFormat = nil;
    if (self.bodyFormat == BCCHTTPRequestBodyFormatJSON) {
        stringForBodyFormat = @"JSON";
    } else if (self.bodyFormat == BCCHTTPRequestBodyFormatMultipart) {
        stringForBodyFormat = @"Multipart";
    } else if (self.bodyFormat == BCCHTTPRequestBodyFormatURLEncoded) {
        stringForBodyFormat = @"URL encoded";
    } else {
        stringForBodyFormat = @"None";
    }
    
    NSString *bodyContentType = [self contentTypeStringForBodyFormat:self.bodyFormat];
    
    return [NSString stringWithFormat:@"<%@: %p (method: %@; base URL: %@; version: %@; command: %@; tag: %@; identifier: %@)>\nFull URL: %@\nPath Parameters: %@\nQuery Parameters: %@\nBody Parameters: %@\nHeaders: %@\nUser Info: %@\nBody (format: %@): %@\nBody Content Type: %@\nError: %@", NSStringFromClass([self class]), self, [self requestMethodStringForRequestMethod:self.requestMethod], self.baseURL, self.APIVersion, self.command, self.tag, self.identifier, self.URL, self.pathParameters, self.queryParameters, self.bodyParameters, self.headers, self.userInfo, stringForBodyFormat, self.bodyStringRepresentation, bodyContentType, self.error];
}

#pragma mark URL

- (void)setBaseURL:(NSString *)baseURL;
{
    if (self.isLoading) {
        return;
    }
    
    _baseURL = baseURL;
    
    [self updateURL];
}

- (void)setAPIVersion:(NSString *)APIVersion;
{
    if (self.isLoading) {
        return;
    }
    
    _APIVersion = APIVersion;
    
    [self updateURL];
}

- (void)setCommand:(NSString *)command;
{
    if (self.isLoading) {
        return;
    }
    
    _command = command;
    
    [self updateURL];
}

- (void)setRequestMethod:(BCCHTTPRequestMethod)requestMethod;
{
    if (self.isLoading) {
        return;
    }
    
    _requestMethod = requestMethod;
    
    [self updateURL];
}

- (NSString *)queryString
{
    return [self.queryParameters BCC_URLEncodedStringValue];
}

- (void)updateURL
{
    if (!self.baseURL) {
        self.URL = nil;
        return;
    }
    
    NSMutableString *URLString = [[NSMutableString alloc] init];
    
    [URLString appendString:self.baseURL];
    
    if (self.command) {
        NSString *parsedPath = self.command;
        
        NSMutableDictionary *pathParameters = _pathParameters ? [_pathParameters mutableCopy] : [[NSMutableDictionary alloc] init];
        
        if (self.APIVersion && ([pathParameters valueForKey:BCCHTTPRequestURLParametersKeyAPIVersion] == nil)) {
            [pathParameters setObject:self.APIVersion forKey:BCCHTTPRequestURLParametersKeyAPIVersion];
        }
        
        if (pathParameters.count > 0) {
            parsedPath = [self.command BCC_stringByParsingTagsWithStartDelimeter:@"{" endDelimeter:@"}" usingObject:pathParameters];
        }
        
        [URLString BCC_appendURLPathComponent:parsedPath];
    }
    
    NSString *queryString = self.queryString;
    if (queryString.length > 0) {
        [URLString appendFormat:@"?%@", queryString];
    }
    
    self.URL = [NSURL URLWithString:URLString];
}

#pragma mark Status

- (BOOL)isLoading
{
    return (self.loadStatus == BCCHTTPRequestStatusLoading);
}

#pragma mark Headers

- (void)addHeadersFromDictionary:(NSDictionary *)dictionary
{
    if (self.isLoading || dictionary.count < 1) {
        return;
    }
    
    [self.headers addEntriesFromDictionary:dictionary];
}

- (void)setHeaderString:(NSString *)value forKey:(NSString *)key
{
    if (self.isLoading || !value || !key) {
        return;
    }
    
    [self.headers setObject:value forKey:key];
}

- (NSString *)headerStringForKey:(NSString *)key
{
    if (!key) {
        return nil;
    }
    
    return [self.headers BCC_stringForKey:key];
}

#pragma mark Path Parameters

- (void)addPathParametersFromDictionary:(NSDictionary *)dictionary
{
    if (self.isLoading || dictionary.count < 1) {
        return;
    }
    
    [self.pathParameters addEntriesFromDictionary:dictionary];
    [self updateURL];
}

- (void)setPathParameterValue:(id)value forKey:(NSString *)key
{
    if (self.isLoading || !value || !key) {
        return;
    }

    [self.pathParameters setObject:value forKey:key];
    [self updateURL];
}

#pragma mark Query Parameters

- (void)addQueryParametersFromDictionary:(NSDictionary *)dictionary
{
    if (self.isLoading || dictionary.count < 1) {
        return;
    }
    
    [self.queryParameters addEntriesFromDictionary:dictionary];
    [self updateURL];
}

- (void)setQueryParametersValue:(id)value forKey:(NSString *)key
{
    if (self.isLoading || !value || !key) {
        return;
    }
    
    [self.queryParameters setObject:value forKey:key];
    [self updateURL];
}

- (id)queryParameterValueForKey:(NSString *)inKey;
{
    return [self.queryParameters objectForKey:inKey];
}

#pragma mark Body Parameters

- (NSData *)bodyData
{
    return self.rawBodyData ? self.rawBodyData : self.formattedBodyData;
}

- (void)setRawBodyInputStream:(NSInputStream *)rawBodyInputStream
{
    if (self.isLoading) {
        return;
    }
    
    _rawBodyInputStream = rawBodyInputStream;
    
    if (_rawBodyInputStream) {
        [self resetFormattedBody];
        _bodyFormat = BCCHTTPRequestBodyFormatNone;
    }
}

- (void)setRawBodyData:(NSData *)rawBodyData
{
    if (self.isLoading) {
        return;
    }
    
    _rawBodyData = rawBodyData;
    
    if (_rawBodyData) {
        [self resetFormattedBody];
        _bodyFormat = BCCHTTPRequestBodyFormatNone;
    }
}

- (void)setRawBodyFilePath:(NSString *)rawBodyFilePath
{
    if (self.isLoading) {
        return;
    }
    
    _rawBodyFilePath = rawBodyFilePath;
    
    if (_rawBodyFilePath) {
        [self resetFormattedBody];
        _bodyFormat = BCCHTTPRequestBodyFormatNone;
    }
}

- (void)addBodyParametersFromDictionary:(NSDictionary *)dictionary
{
    if (self.isLoading || dictionary.count < 1) {
        return;
    }
    
    [self.bodyParameters addEntriesFromDictionary:dictionary];
}

- (void)setBodyParameterValue:(id)value forKey:(NSString *)key
{
    if (self.isLoading || !value || !key) {
        return;
    }
    
    [self.bodyParameters setObject:value forKey:key];
}

- (id)bodyParameterValueForKey:(NSString *)key
{
    return [self.bodyParameters objectForKey:key];
}

- (NSString *)bodyStringRepresentation
{
    if (!self.bodyData) {
        [self buildRequestBody];
    }
    
    return [self.bodyData BCC_UTF8String];
}

#pragma mark Files

- (void)setFileData:(NSData *)fileData forParameterName:(NSString *)parameterName filename:(NSString *)filename contentType:(NSString *)contentType
{
    [self addFileWithPath:nil data:fileData forParameterName:parameterName filename:filename contentType:contentType fileUUID:nil];
}

- (void)setFilePath:(NSString *)filePath forParameterName:(NSString *)parameterName filename:(NSString *)filename contentType:(NSString *)contentType
{
    [self addFileWithPath:filePath data:nil forParameterName:parameterName filename:filename contentType:contentType fileUUID:nil];
}

- (void)addFileWithFileInfo:(NSDictionary *)dictionary
{
    if (self.isLoading || dictionary.count < 1) {
        return;
    }
    
    NSString *parameterName = [dictionary objectForKey:BCCHTTPRequestFileInfoParameterNameKey];
    NSString *mimeType = [dictionary objectForKey:BCCHTTPRequestFileInfoContentTypeKey];
    NSData *fileData = [dictionary objectForKey:BCCHTTPRequestFileInfoFileDataKey];
    NSString *filePath = [dictionary objectForKey:BCCHTTPRequestFileInfoFilePathKey];
    
    // Make sure the dictionary contains the required attributes
    // before adding it to the file info
    if ((!filePath || fileData.length > 0) || !mimeType || !parameterName) {
        return;
    }
    
    [self.bodyFiles setObject:dictionary forKey:parameterName];
}

- (void)addFileWithPath:(NSString *)filePath data:(NSData *)fileData forParameterName:(NSString *)parameterName filename:(NSString *)filename contentType:(NSString *)contentType fileUUID:(NSString *)fileUUID
{
    if (self.isLoading || (!filePath || fileData.length > 0) || !contentType || !parameterName) {
        return;
    }
    
    // If a file UUID is provided, use that, otherwise create one
    NSString *UUID = fileUUID ? fileUUID : [[NSUUID UUID] UUIDString];
    
    if (!filename) {
        if (filePath) {
            filename = [filePath lastPathComponent];
        } else {
            filename = parameterName;
        }
    }
    
    NSMutableDictionary *fileInfoDictionary = [[NSMutableDictionary alloc] init];
    [fileInfoDictionary setObject:filename forKey:BCCHTTPRequestFileInfoFilenameKey];
    [fileInfoDictionary setObject:contentType forKey:BCCHTTPRequestFileInfoContentTypeKey];
    [fileInfoDictionary setObject:UUID forKey:BCCHTTPRequestFileInfoUUIDKey];
    [fileInfoDictionary setObject:parameterName forKey:BCCHTTPRequestFileInfoParameterNameKey];
    
    if (fileData.length) {
        [fileInfoDictionary setObject:fileData forKey:BCCHTTPRequestFileInfoFileDataKey];
    } else {
        [fileInfoDictionary setObject:filePath forKey:BCCHTTPRequestFileInfoFilePathKey];
    }
    
    [self.bodyFiles setObject:fileInfoDictionary forKey:parameterName];
}

- (NSDictionary *)fileInfoForParameterName:(NSString *)key
{
    return [self.bodyFiles objectForKey:key];
}

#pragma mark Auth

- (BOOL)hasBasicAuthCredentials
{
    if (self.basicAuthUsername && self.basicAuthPassword) {
        return YES;
    }
    
    return NO;
}

- (BOOL)requiresOAuth;
{
    return (self.authenticationType == BCCHTTPRequestAuthenticationTypeOAuth1 || self.authenticationType == BCCHTTPRequestAuthenticationTypeOAuth2);
}

- (NSString *)basicAuthPassword;
{
    if (_basicAuthPassword.length) {
        return _basicAuthPassword;
    }
    
    if (!self.basicAuthUsername.length || !self.keychainServiceName.length) {
        return nil;
    }
    
    NSString *keychainPassword = nil;
    
    NSError *keychainError;
    keychainPassword = [BCCKeychain getPasswordStringForUsername:self.basicAuthUsername andServiceName:self.keychainServiceName error:&keychainError];
    
    if (keychainError) {
        return nil;
    }
    
    return keychainPassword;
}

#pragma mark - Certificates

- (BOOL)shouldTrustProtectionSpace:(NSURLProtectionSpace *)protectionSpace forSSLTrustMode:(BCCHTTPRequestSSLTrustMode)trustMode
{
    if (trustMode == BCCHTTPRequestSSLTrustModeUnenforced) {
        return YES;
    }
    
    SecTrustRef serverTrust = protectionSpace.serverTrust;
    if (!serverTrust) {
        return NO;
    }
    
    SecTrustResultType trustResult;
    
    if (trustMode == BCCHTTPRequestSSLTrustModeValidCertsOnly) {
        SecTrustEvaluate(serverTrust, &trustResult);
    } else if (trustMode == BCCHTTPRequestSSLTrustModePinnedCertsOnly) {
        NSString *certPath = self.publicSSLCertificatePath;
        if (!certPath) {
            return NO;
        }
        
        // Load the specified server public SSL cert
        NSData *certData = [[NSData alloc] initWithContentsOfFile:certPath];
        CFDataRef certDataRef = (__bridge_retained CFDataRef)certData;
        SecCertificateRef cert = SecCertificateCreateWithData(NULL, certDataRef);
        
        // Establish a chain of trust anchored on the specified public cert
        CFArrayRef certArrayRef = CFArrayCreate(NULL, (void *)&cert, 1, NULL);
        SecTrustSetAnchorCertificates(serverTrust, certArrayRef);
        
        // Verify the trust
        SecTrustEvaluate(serverTrust, &trustResult);
        
        CFRelease(certArrayRef);
        CFRelease(cert);
        CFRelease(certDataRef);
    }
    
    return (trustResult == kSecTrustResultUnspecified || trustResult == kSecTrustResultProceed);
}

#pragma mark OAuth

- (void)addOAuthParametersFromDictionary:(NSDictionary *)dictionary
{
    if (self.isLoading || dictionary.count < 1) {
        return;
    }
    
    [self.additionalOAuthParameters addEntriesFromDictionary:dictionary];
}

- (void)setOAuthParameter:(id)value forKey:(NSString *)key
{
    if (!value || !key || self.isLoading) {
        return;
    }
    
    [self.additionalOAuthParameters setObject:value forKey:key];
}

- (id)OAuthParameterForKey:(NSString *)key
{
    return [self.additionalOAuthParameters objectForKey:key];
}

- (NSString *)stringForXAuthAuthMode:(BCCHTTPRequestXAuthMode)authMode
{
    switch (authMode) {
        case BCCHTTPRequestXAuthModeClientAuth:
            return @"client_auth";
        case BCCHTTPRequestXAuthModeReverseAuth:
            return @"reverse_auth";
        default:
            break;
    }
    
    return nil;
}

#pragma mark User Info

- (void)addUserInfoFromDictionary:(NSDictionary *)dictionary
{
    [self.userInfo addEntriesFromDictionary:dictionary];
}

- (void)setUserInfoValue:(id)value forKey:(NSString *)key
{
    [self.userInfo setObject:value forKey:key];
}

- (id)userInfoValueForKey:(NSString *)key
{
    return [self.userInfo objectForKey:key];
}

#pragma mark Response

- (NSInteger)responseStatusCode
{
    if (!self.response) {
        return 0;
    }
    
    return self.response.statusCode;
}

- (BOOL)responseStatusCodeIsError
{
    if (!self.response) {
        return NO;
    }
    
    NSInteger statusCode = self.responseStatusCode;
    if (statusCode == BCCHTTPRequestNoNetworkStatusCode || (statusCode >= BCCHTTPRequestMinClientErrorStatusCode && statusCode <= BCCHTTPRequestMaxClientErrorStatusCode) || (statusCode >= BCCHTTPRequestMinServerErrorStatusCode && statusCode <= BCCHTTPRequestMaxServerErrorStatusCode)) {
        return YES;
    }
    
    return NO;
}

- (BOOL)responseStatusCodeIsRetryable
{
    if (!self.response) {
        return NO;
    }
    
    NSInteger statusCode = self.responseStatusCode;
    if (statusCode == BCCHTTPRequestNoNetworkStatusCode || statusCode == BCCHTTPRequestUnauthorizedStatusCode || (statusCode < BCCHTTPRequestMinServerErrorStatusCode && statusCode > BCCHTTPRequestMaxServerErrorStatusCode)) {
        return YES;
    }
    
    return NO;
}

#pragma mark NSURL Loading System Configuration

- (NSURLRequest *)configuredURLRequest
{
    return [self configuredURLRequestForURL:self.URL];
}

- (NSURLRequest *)configuredURLRequestForURL:(NSURL *)requestURL
{
    if (!requestURL) {
        return nil;
    }

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:requestURL cachePolicy:NSURLRequestReloadIgnoringLocalAndRemoteCacheData timeoutInterval:self.timeoutInterval];
    
    request.BCCHTTPRequest_identifier = self.identifier;

    request.HTTPMethod = [self requestMethodStringForRequestMethod:self.requestMethod];

    // Process the user-specified headers
    NSArray *headerKeys = [self.headers allKeys];
    for (NSString *currentKey in headerKeys) {
        NSString *currentValue = [self.headers BCC_stringForKey:currentKey];
        [request addValue:currentValue forHTTPHeaderField:currentKey];
    }

    // Set the user agent header
    if (self.userAgent) {
        [request setValue:self.userAgent forHTTPHeaderField:BCCHTTPRequestUserAgentHeaderKey];
    }

    // Set the time zone header
    if (self.time) {
        [request setValue:[self.time BCC_HTTPTimeZoneHeaderString] forHTTPHeaderField:BCCHTTPRequestTimeZoneHeaderKey];
    }

    // Set the content type and body if it's
    // a POST/PUT/DELETE request
    if ((self.requestMethod == BCCHTTPRequestMethodPOST || self.requestMethod == BCCHTTPRequestMethodPUT || self.requestMethod == BCCHTTPRequestMethodDELETE) && (self.bodyParameters.count > 0 || self.bodyFiles.count > 0 || self.rawBodyInputStream)) {
        NSString *contentType = [self contentTypeStringForBodyFormat:self.bodyFormat];
        
        NSUInteger contentLength = 0;
        
        if (self.rawBodyInputStream) {
            request.HTTPBodyStream = self.rawBodyInputStream;
        } else if (self.bodyData) {
            contentLength = self.bodyData.length;
            request.HTTPBody = self.bodyData;
        } else if (self.bodyFormat != BCCHTTPRequestBodyFormatNone) {
            contentLength = [self buildRequestBody];
            request.HTTPBody = self.bodyData ? self.bodyData : self.formattedBodyData;
        }
        
        if (contentLength > 0) {
            [request setValue:[NSString stringWithFormat:@"%lu", (unsigned long)contentLength] forHTTPHeaderField:BCCHTTPRequestContentLengthHeaderKey];
        }
        
        [request setValue:contentType forHTTPHeaderField:BCCHTTPRequestContentTypeHeaderKey];
    }

    if (self.requiresOAuth) {
        NSString *OAuthSignature;
        switch(self.authenticationType) {
            case BCCHTTPRequestAuthenticationTypeOAuth2:
                OAuthSignature = self.OAuth2AuthorizationHeaderString;
                break;
            default:
                OAuthSignature = self.OAuthAuthorizationHeaderString;
                break;
        }
        
        if (OAuthSignature.length > 0) {
            [request setValue:OAuthSignature forHTTPHeaderField:BCCHTTPRequestAuthorizationHeaderKey];
        }
    } else if (self.authenticationType == BCCHTTPRequestAuthenticationTypeAuthToken && self.authToken) {
        [request setValue:self.authToken forHTTPHeaderField:BCCHTTPRequestAuthorizationHeaderKey];
    } else if (self.authenticationType == BCCHTTPRequestAuthenticationTypeBasic) {
        NSString *headerString = self.basicAuthAuthorizationHeaderString;
        [request setValue:headerString forHTTPHeaderField:BCCHTTPRequestAuthorizationHeaderKey];
    }
    
    request.HTTPShouldHandleCookies = NO;

    return request;
}

- (NSString *)requestMethodStringForRequestMethod:(BCCHTTPRequestMethod)inRequestMethod
{
    //Set the request method
    NSString *requestMethodString = @"GET";
    
    switch (inRequestMethod) {
        case BCCHTTPRequestMethodPOST:
            requestMethodString = @"POST";
            break;
        case BCCHTTPRequestMethodPUT:
            requestMethodString = @"PUT";
            break;
        case BCCHTTPRequestMethodDELETE:
            requestMethodString = @"DELETE";
            break;
        case BCCHTTPRequestMethodHEAD:
            requestMethodString = @"HEAD";
            break;
        default:
            break;
    }
    
    return requestMethodString;
}

- (NSString *)contentTypeStringForBodyFormat:(BCCHTTPRequestBodyFormat)bodyFormat
{
    NSString *contentType = BCCHTTPRequestOctetStreamContentType;
    
    switch (bodyFormat) {
        case BCCHTTPRequestBodyFormatMultipart:
            contentType = [NSString stringWithFormat:BCCHTTPRequestMultipartContentType, BCCHTTPRequestMultipartBoundaryString];
            break;
        case BCCHTTPRequestBodyFormatJSON:
            contentType = BCCHTTPRequestJSONContentType;
            break;
        case BCCHTTPRequestBodyFormatURLEncoded:
            contentType = BCCHTTPRequestURLEncodedContentType;
            break;
        default:
            break;
    }
    
    return contentType;
}

- (NSURLCredential *)credentialForAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge
{
    if ([challenge.protectionSpace.authenticationMethod isEqualToString:NSURLAuthenticationMethodServerTrust]) {
        if ([self shouldTrustProtectionSpace:challenge.protectionSpace forSSLTrustMode:self.SSLTrustMode]) {
            return [NSURLCredential credentialForTrust:challenge.protectionSpace.serverTrust];
        }
    } else if (([challenge.protectionSpace.authenticationMethod isEqualToString:NSURLAuthenticationMethodDefault] || [challenge.protectionSpace.authenticationMethod isEqualToString:NSURLAuthenticationMethodHTTPBasic] || [challenge.protectionSpace.authenticationMethod isEqualToString:NSURLAuthenticationMethodHTTPDigest])) {
        if (self.hasBasicAuthCredentials) {
            return [NSURLCredential credentialWithUser:self.basicAuthUsername password:self.basicAuthPassword persistence:NSURLCredentialPersistenceNone];
        }
    }
    
    return nil;
}

#pragma mark Header Construction

- (NSString *)basicAuthAuthorizationHeaderString
{
    if (!self.hasBasicAuthCredentials) {
        return nil;
    }
    
    NSString *combinedUsernamePassword = [[NSString alloc] initWithFormat:@"%@:%@", self.basicAuthUsername, self.basicAuthPassword];
    NSString *base64String = [combinedUsernamePassword BCC_base64String];
    
    return [NSString stringWithFormat:@"Basic %@", base64String];
}

- (NSString *)OAuthAuthorizationHeaderString
{
    if (!self.OAuthConsumerKey || !self.OAuthSecretKey) {
        return nil;
    }
    
    NSMutableDictionary *signatureParameterDictionary = [[NSMutableDictionary alloc] init];
    NSMutableDictionary *headerParameterDictionary = [[NSMutableDictionary alloc] init];
    
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    
    // Add the standard boilerplate parameters common to all OAuth requests to the header parameters
    [headerParameterDictionary setObject:[NSString stringWithFormat:@"%d", (int)now] forKey:BCCHTTPRequestOAuthTimestampKey];
    [headerParameterDictionary setObject:self.identifier forKey:BCCHTTPRequestOauthNonceKey];
    [headerParameterDictionary setObject:@"1.0" forKey:BCCHTTPRequestOAuthVersionKey];
    [headerParameterDictionary setObject:@"HMAC-SHA1" forKey:BCCHTTPRequestOAuthSignatureMethodKey];
    [headerParameterDictionary setObject:self.OAuthConsumerKey forKey:BCCHTTPRequestOAuthConsumerKeyKey];
    if (self.OAuthToken) {
        [headerParameterDictionary setObject:self.OAuthToken forKey:BCCHTTPRequestOAuthTokenKey];
    }
    
    if (self.OAuthXAuthMode != BCCHTTPRequestXAuthModeNone) {
        [headerParameterDictionary setObject:[self stringForXAuthAuthMode:self.OAuthXAuthMode] forKey:BCCHTTPRequestXAuthAuthModeKey];
    }
    
    if (self.OAuthCallbackURL) {
        // This is supposed to be double-encoded in the signature strong, which is kind of
        // confusing. It gets URL encoded once here, and then again down below.
        [headerParameterDictionary setObject:self.OAuthCallbackURL forKey:BCCHTTPRequestOAuthCallbackURLKey];
    }
    
    // Add in any additionally specified OAuth parameters to the header parameters
    if (self.additionalOAuthParameters.count) {
        [headerParameterDictionary addEntriesFromDictionary:self.additionalOAuthParameters];
    }
    
    // Mix the header parameters into the signature parameter dictionary
    [signatureParameterDictionary addEntriesFromDictionary:headerParameterDictionary];
    
    if (self.queryParameters.count) {
        [signatureParameterDictionary addEntriesFromDictionary:self.queryParameters];
    }
    
    // Add any POST body parameters to the signature dictionary, but only as long as the
    // post body format is URL encoded.
    if (self.bodyParameters.count && self.bodyFormat == BCCHTTPRequestBodyFormatURLEncoded) {
        // The post parameter values need to be double percent encodeded
        for (NSString *currentBodyKey in [self.bodyParameters allKeys]) {
            NSString *currentBodyValue = [self.bodyParameters objectForKey:currentBodyKey];
            [signatureParameterDictionary setObject:[currentBodyValue BCC_stringByEscapingQueryParameters] forKey:currentBodyKey];
        }
    }
    
    // Start the raw signature string
    NSMutableString *rawSignatureString = [[NSMutableString alloc] init];
    
    [rawSignatureString appendFormat:@"%@&%@&", [self requestMethodStringForRequestMethod:self.requestMethod], [[self.URL BCC_absoluteStringMinusQueryString] BCC_stringByEscapingQueryParameters]];
    
    NSArray *parameterKeys = [[signatureParameterDictionary allKeys] sortedArrayUsingSelector:@selector(caseInsensitiveCompare:)];
    id lastElement = [parameterKeys lastObject];
    for (NSString *currentKey in parameterKeys) {
        id currentValue = [signatureParameterDictionary objectForKey:currentKey];
        NSMutableString *parameterString = [[NSMutableString alloc] init];
        [parameterString appendFormat:@"%@=%@", currentKey, [currentValue BCC_stringByEscapingQueryParameters]];
        
        if (currentKey != lastElement) {
            [parameterString appendString:@"&"];
        }
        
        [rawSignatureString appendString:[parameterString BCC_stringByEscapingQueryParameters]];
    }
    
    // Hash the raw signature string into an encrypted signature
    NSString *keyString = [NSString stringWithFormat:@"%@&", self.OAuthSecretKey];
    if (self.OAuthTokenSecret) {
        keyString = [keyString stringByAppendingString:self.OAuthTokenSecret];
    }
    NSString *encryptedSignatureString = [[[rawSignatureString dataUsingEncoding:NSUTF8StringEncoding] BCC_hmacSHA1DataValueWithKey:[keyString dataUsingEncoding:NSUTF8StringEncoding]] BCC_base64EncodedString];
    
    // Add the encrypted signature to the header parameter dictionary
    [headerParameterDictionary setObject:encryptedSignatureString forKey:BCCHTTPRequestOAuthSignatureKey];
    
    // Turn the header parameter dictionary into a string
    NSString *authorizationHeaderString = [NSString stringWithFormat:@"OAuth %@", [headerParameterDictionary BCC_URLEncodedQuotedKeyValueListValue]];
    
    return authorizationHeaderString;
}

- (NSString *)OAuth2AuthorizationHeaderString
{
    if (!self.OAuthSecretKey.length || !self.OAuthConsumerKey.length) {
        return nil;
    }
    
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    NSString *OAuthNonce = self.identifier;
    NSString *OAuthTimeStamp = [NSString stringWithFormat:@"%d", (int)now];
    
    NSMutableString *rawSignatureString = [[NSMutableString alloc] init];
    
    [rawSignatureString appendFormat:@"%@\n", self.OAuthToken];
    [rawSignatureString appendFormat:@"%@\n", OAuthTimeStamp];
    [rawSignatureString appendFormat:@"%@\n", OAuthNonce];
    [rawSignatureString appendFormat:@"%@\n", [self requestMethodStringForRequestMethod:self.requestMethod]];
    [rawSignatureString appendFormat:@"%@\n", [[self URL] host]];
    [rawSignatureString appendFormat:@"%d\n", 80];
    [rawSignatureString appendFormat:@"%@\n", [[self URL] path]];
    
    NSString *encryptedSignatureString = [[[rawSignatureString dataUsingEncoding:NSUTF8StringEncoding] BCC_hmacSHA1DataValueWithKey:[self.OAuthTokenSecret dataUsingEncoding:NSUTF8StringEncoding]] BCC_base64EncodedString];
    
    NSString *authorizationString = [NSString stringWithFormat:@"MAC token=\"%@\", timestamp=\"%@\", nonce=\"%@\", signature=\"%@\"", self.OAuthToken, OAuthTimeStamp, OAuthNonce, encryptedSignatureString];
    
    return authorizationString;
}

#pragma mark Body Construction

- (NSInteger)buildRequestBody
{
    NSInteger bytesWritten = 0;
    
    self.formattedBodyData = [[NSMutableData alloc] init];
    
    switch (self.bodyFormat) {
        case BCCHTTPRequestBodyFormatJSON:
            bytesWritten = [self buildJSONBody];
            break;
        case BCCHTTPRequestBodyFormatMultipart:
            bytesWritten = [self buildMultipartBody];
            break;
        case BCCHTTPRequestBodyFormatURLEncoded:
            bytesWritten = [self buildURLEncodedBody];
            break;
        default:
            break;
    }
    
    return bytesWritten;
}

- (NSInteger)buildMultipartBody
{
    BOOL hasBodyParametersOrFiles = (self.bodyParameters.count < 1 && self.bodyFiles.count < 1);
    if (hasBodyParametersOrFiles) {
        return 0;
    }
    
    NSUInteger bytesWritten = 0;
    
    NSString *startItemBoundary = [NSString stringWithFormat:@"\r\n--%@\r\n", BCCHTTPRequestMultipartBoundaryString];
    
    // Handle all the basic POST form parameters
    NSUInteger parameterIndex = 0;
    NSArray *postKeys = [self.bodyParameters allKeys];
    for (id currentKey in postKeys) {
        id currentObject = [self.bodyParameters objectForKey:currentKey];
        NSString *parameterValue = [self stringValueForParameterObject:currentObject];
        
        if (!parameterValue.length) {
            continue;
        }
        
        // Append the start item boundary
        bytesWritten += [self appendBodyUTF8String:startItemBoundary];
        
        // Append the content disposition
        bytesWritten += [self appendBodyUTF8StringWithFormat:@"Content-Disposition: form-data; name=\"%@\"\r\n\r\n", currentKey];
        
        // Append the parameter string
        bytesWritten += [self appendBodyUTF8String:parameterValue];
        
        // Append the end item boundary, but only if this
        // isn't the last item.
        parameterIndex++;
        if (parameterIndex > self.bodyParameters.count || self.bodyFiles.count) {
            bytesWritten += [self appendBodyUTF8String:startItemBoundary];
        }
    }
    
    // Handle all the file parameters
    NSUInteger fileIndex = 0;
    for (NSString *currentFileKey in self.bodyFiles) {
        NSDictionary *currentFileInfo = [self fileInfoForParameterName:currentFileKey];
        NSString *filename = [currentFileInfo objectForKey:BCCHTTPRequestFileInfoFilenameKey];
        NSData *fileData = [currentFileInfo objectForKey:BCCHTTPRequestFileInfoFileDataKey];
        NSString *filePath = [currentFileInfo objectForKey:BCCHTTPRequestFileInfoFilePathKey];
        NSString *contentType = [currentFileInfo objectForKey:BCCHTTPRequestFileInfoContentTypeKey];
        
        if (!fileData.length && !(filePath.length && [[NSFileManager defaultManager] fileExistsAtPath:filePath])) {
            continue;
        }
        
        bytesWritten += [self appendBodyUTF8StringWithFormat:@"Content-Disposition: form-data; name=\"%@\"; filename=\"%@\"\r\n", currentFileKey, filename];
        bytesWritten += [self appendBodyUTF8StringWithFormat:@"Content-Type: %@\r\n\r\n", contentType];
        
        // Write the file data
        if (fileData.length) {
            bytesWritten +=  [self appendBodyData:fileData];
        } else {
            bytesWritten += [self appendBodyFileDataAtPath:filePath];
        }
        
        // Append the end item boundary, but only if this
        // isn't the last item.
        fileIndex++;
        if (fileIndex < self.bodyFiles.count) {
            bytesWritten += [self appendBodyUTF8String:startItemBoundary];
        }
    }
    
    // Append the end boundary
    bytesWritten += [self appendBodyUTF8StringWithFormat:@"\r\n--%@--\r\n", BCCHTTPRequestMultipartBoundaryString];
    
    return bytesWritten;
}

- (NSInteger)buildJSONBody
{
    // TO DO: What about files?
    if (self.bodyParameters.count == 0) {
        return 0;
    }
    
    NSData *JSONData = [NSJSONSerialization dataWithJSONObject:self.bodyParameters options:kNilOptions error:NULL];
    [self appendBodyData:JSONData];
    
    return JSONData.length;
}

- (NSInteger)buildURLEncodedBody
{
    // TO DO: What about files?
    if (self.bodyParameters.count == 0) {
        return 0;
    }
    
    NSData *URLEncodedData = [[self.bodyParameters BCC_URLEncodedStringValue] dataUsingEncoding:NSUTF8StringEncoding];
    [self appendBodyData:URLEncodedData];
    return URLEncodedData.length;
}

- (NSInteger)appendBodyUTF8StringWithFormat:(NSString *)inString, ...
{
    NSInteger bytesWritten = 0;
    
    va_list args;
    va_start(args, inString);
    
    bytesWritten = [inString lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
    [self.formattedBodyData BCC_appendUTF8StringWithFormat:inString arguments:args];
    
    va_end(args);
    
    return bytesWritten;
}

- (NSInteger)appendBodyUTF8String:(NSString *)inString
{
    NSInteger bytesWritten = [inString lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
    [self.formattedBodyData BCC_appendUTF8String:inString];
    
    return bytesWritten;
}

- (NSInteger)appendBodyData:(NSData *)inData
{
    NSInteger bytesWritten = [inData length];
    [self.formattedBodyData appendData:inData];
    
    return bytesWritten;
}

- (NSInteger)appendBodyFileDataAtPath:(NSString *)filePath
{
    if (!filePath.length || ![[NSFileManager defaultManager] fileExistsAtPath:filePath]) {
        return 0;
    }
    
    NSData *fileData = [NSData dataWithContentsOfFile:filePath options:NSDataReadingMappedIfSafe error:NULL];
    NSInteger bytesWritten = fileData.length;
    [self.formattedBodyData appendData:fileData];
    
    return bytesWritten;
}

- (NSString *)cachePathForFilename:(NSString *)inFilename
{
    if (!inFilename.length) {
        return nil;
    }
    
    NSMutableArray *pathComponents = [[NSMutableArray alloc] init];
    
    // If we're on a Mac, include the app name in the
    // application support path.
#if !TARGET_OS_IPHONE
    [pathComponents addObject:[[NSFileManager defaultManager] BCC_cachePathIncludingAppName]];
#else
    [pathComponents addObject:[[NSFileManager defaultManager] BCC_cachePath]];
#endif
    
    [pathComponents addObject:BCCHTTPRequestCacheSubdirectory];
    [pathComponents addObject:inFilename];
    
    NSString *fullPath = [NSString pathWithComponents:pathComponents];
    
    return fullPath;
}

- (NSString *)stringValueForParameterObject:(NSString *)inObject
{
    NSString *stringValue = nil;
    
	if ([inObject isKindOfClass:[NSString class]]) {
		stringValue = (NSString *)inObject;
	} else if ([inObject isKindOfClass:[NSNumber class]]) {
		stringValue = [(NSNumber *)inObject stringValue];
	} else if ([self isKindOfClass:[NSDate class]]) {
		stringValue = [(NSDate *)inObject BCC_HTTPTimeZoneHeaderString];
	} else if ([self isKindOfClass:[NSData class]]) {
        stringValue = [(NSData *)inObject BCC_base64EncodedString];
    }
	
	return stringValue;
}

#pragma mark Response Data

- (void)setResponseData:(NSMutableData *)responseData withMIMEType:(NSString *)mimeType
{
    self.responseMIMEType = mimeType;
    self.responseData = responseData;
    
    [self processResponseData];
}

- (void)processResponseData
{
    if (!self.responseMIMEType || !self.responseData.length) {
        return;
    }
    
    // Uncomment to see raw body
    // NSLog(@"Response body string for %@: %@", self.command, [NSString stringWithUTF8String:[[self.responseData UTF8String] UTF8String]]);
    
    if ([self.responseMIMEType isEqualToString:BCCHTTPRequestJSONContentType] || [self.responseMIMEType isEqualToString:BCCHTTPRequestJavascriptContentType]) {
        id responseObject = [NSJSONSerialization JSONObjectWithData:self.responseData options:kNilOptions error:NULL];
        if (responseObject) {
            self.responseJSONObject = responseObject;
        } else {
            self.responseString = [self.responseData BCC_UTF8String];
        }
    } else if ([self.responseMIMEType isEqualToString:BCCHTTPRequestTextHTMLContentType] || [self.responseMIMEType isEqualToString:BCCHTTPRequestTextPlainContentType]) {
        self.responseString = [self.responseData BCC_UTF8String];
    } else if ([self.responseMIMEType isEqualToString:BCCHTTPRequestURLEncodedContentType]) {
        self.responseURLEncodedDictionary = [NSDictionary BCC_dictionaryWithURLEncodedString:[self.responseData BCC_UTF8String]];
    }
}

#pragma mark Retries

- (BOOL)isRetryable;
{
    return (self.retryMethod != BCCHTTPRequestRetryMethodNone) && (self.retryCount < self.maximumRetryCount) && (self.responseStatusCode == BCCHTTPRequestNoNetworkStatusCode || self.responseStatusCode == BCCHTTPRequestUnauthorizedStatusCode || (self.responseStatusCode < BCCHTTPRequestMinServerErrorStatusCode && self.responseStatusCode > BCCHTTPRequestMaxServerErrorStatusCode));
}

- (NSTimeInterval)currentRetryInterval
{
    switch (self.retryMethod) {
        case BCCHTTPRequestRetryMethodExponentialBackoff:
            return self.exponentialBackoffRetryInterval;
            break;
        case BCCHTTPRequestRetryMethodRandomizedInterval:
            return (NSTimeInterval)BCCRandomIntegerWithMax(self.maximumRetryInterval);
            break;
        default:
            break;
    }
    
    return self.minimumRetryInterval;
}

- (NSTimeInterval)exponentialBackoffRetryInterval
{
    NSTimeInterval calculatedInterval = pow(self.retryCount, 2.0) + BCCRandomIntegerWithMax(2);
    if (calculatedInterval < self.minimumRetryInterval) {
        return self.minimumRetryInterval;
    } else if (calculatedInterval > self.maximumRetryInterval) {
        return self.maximumRetryInterval;
    }
    
    return calculatedInterval;
}

- (void)incrementRetryCount
{
    self.retryCount++;
}

#pragma mark Lifecycle

- (void)handleRequestStart
{
    [self reset];
    
    [self incrementRetryCount];
    
    self.loadStatus = BCCHTTPRequestStatusLoading;
    self.time = [NSDate date];
    
#if TARGET_OS_IPHONE
    if (self.spinsActivityIndicator) {
        [[BCCNetworkActivityIndicator sharedIndicator] increment];
    }
#endif
}

- (void)handleBodyDataBytesSent:(int64_t)bytesSent totalBytesSent:(int64_t)totalBytesSent totalBytesExpectedToSend:(int64_t)totalBytesExpectedToSend
{
    self.uploadPercentComplete = (int64_t) totalBytesSent / totalBytesExpectedToSend;
}

- (NSURLCredential *)handleAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge
{
    if (challenge.previousFailureCount > 0) {
        [challenge.sender cancelAuthenticationChallenge:challenge];
        return nil;
    }
    
    NSURLCredential *credential = [self credentialForAuthenticationChallenge:challenge];
    if (!credential) {
        [challenge.sender cancelAuthenticationChallenge:challenge];
        return nil;
    }
    
    return credential;
}

- (NSURLRequest *)handleHTTPRedirectionWithRequest:(NSURLRequest *)newRequest
{
    if (!newRequest) {
        return nil;
    }
    
    NSURLRequest *originalRequest = self.configuredURLRequest;
    NSMutableURLRequest *redirectedRequest = [originalRequest mutableCopy]; // original request
    redirectedRequest.URL = newRequest.URL;
    return redirectedRequest;
}

- (void)handleResponse:(NSURLResponse *)response
{
    self.response = (NSHTTPURLResponse *)response;
    self.responseMIMEType = response.MIMEType;
}

- (void)handleResponseData:(NSData *)newResponseData
{
    if (!self.response) {
        return;
    }
    
    [self.responseData appendData:newResponseData];
    
    self.responsePercentComplete = (int64_t) newResponseData.length / [self.response expectedContentLength];
}

- (void)handleRequestCompletionWithError:(NSError *)error
{
    [self processResponseData];

#if TARGET_OS_IPHONE
    if (self.spinsActivityIndicator) {
        [[BCCNetworkActivityIndicator sharedIndicator] decrement];
    }
#endif
 
    self.error = error;
    
    if (!error && self.responseStatusCodeIsError) {
        self.error = [NSError errorWithDomain:BCCHTTPRequestErrorDomain code:self.responseStatusCode userInfo:[NSDictionary dictionaryWithObject:[NSHTTPURLResponse localizedStringForStatusCode:self.responseStatusCode] forKey:NSLocalizedDescriptionKey]];
    }
    
    if (self.error) {
        self.loadStatus = BCCHTTPRequestStatusFailed;
    } else {
        self.loadStatus = BCCHTTPRequestStatusComplete;
    }
}

- (void)handleValidationError:(NSError *)error
{
    if (!error) {
        return;
    }
    
    self.error = error;
    self.loadStatus = BCCHTTPRequestStatusFailed;
}

@end


@implementation BCCHTTPRequest (XAuthAdditions)

+ (BCCHTTPRequest *)xAuthAccessTokenRequestWithEndpoint:(NSString *)inEndpointURL username:(NSString *)inUsername password:(NSString *)inPassword consumerKey:(NSString *)inConsumerKey secretKey:(NSString *)inSecretKey
{
    if (!inEndpointURL.length || !inUsername.length || !inPassword.length || !inConsumerKey.length || !inSecretKey.length) {
        return nil;
    }
    
    BCCHTTPRequest *xAuthRequest = [[BCCHTTPRequest alloc] initWithBaseURL:inEndpointURL];
    xAuthRequest.requestMethod = BCCHTTPRequestMethodPOST;
    xAuthRequest.bodyFormat = BCCHTTPRequestBodyFormatURLEncoded;
    xAuthRequest.OAuthConsumerKey = inConsumerKey;
    xAuthRequest.OAuthSecretKey = inSecretKey;
    xAuthRequest.OAuthXAuthMode = BCCHTTPRequestXAuthModeClientAuth;
    xAuthRequest.authenticationType = BCCHTTPRequestAuthenticationTypeOAuth1;
    [xAuthRequest setXAuthUsername:inUsername password:inPassword];
    
    return xAuthRequest;
}

+ (BCCHTTPRequest *)xAuthReverseAuthRequestWithEndpoint:(NSString *)inEndpointURL consumerKey:(NSString *)inConsumerKey secretKey:(NSString *)inSecretKey
{
    if (!inEndpointURL.length || !inConsumerKey.length || !inSecretKey.length) {
        return nil;
    }
    
    BCCHTTPRequest *xAuthRequest = [[BCCHTTPRequest alloc] initWithBaseURL:inEndpointURL];
    xAuthRequest.requestMethod = BCCHTTPRequestMethodPOST;
    xAuthRequest.bodyFormat = BCCHTTPRequestBodyFormatURLEncoded;
    xAuthRequest.OAuthConsumerKey = inConsumerKey;
    xAuthRequest.OAuthSecretKey = inSecretKey;
    xAuthRequest.OAuthXAuthMode = BCCHTTPRequestXAuthModeReverseAuth;
    xAuthRequest.authenticationType = BCCHTTPRequestAuthenticationTypeOAuth1;
    [xAuthRequest setBodyParameterValue:[xAuthRequest stringForXAuthAuthMode:BCCHTTPRequestXAuthModeReverseAuth] forKey:BCCHTTPRequestXAuthAuthModeKey];
    
    return xAuthRequest;
}

- (void)setXAuthUsername:(NSString *)inUsername password:(NSString *)inPassword;
{
    if (!inUsername.length || !inPassword.length) {
        return;
    }
    
    [self setBodyParameterValue:inUsername forKey:BCCHTTPRequestXAuthUsernameParameterKey];
    [self setBodyParameterValue:inPassword forKey:BCCHTTPRequestXAuthPasswordParameterKey];
    [self setBodyParameterValue:[self stringForXAuthAuthMode:BCCHTTPRequestXAuthModeClientAuth] forKey:BCCHTTPRequestXAuthAuthModeKey];
}

- (NSString *)responseOAuthToken;
{
    if (!self.responseURLEncodedDictionary.count) {
        return nil;
    }
    
    return [self.responseURLEncodedDictionary objectForKey:BCCHTTPRequestOAuthTokenKey];
}

- (NSString *)responseOAuthTokenSecret;
{
    if (!self.responseURLEncodedDictionary.count) {
        return nil;
    }
    
    return [self.responseURLEncodedDictionary objectForKey:BCCHTTPRequestOAuthTokenSecretKey];
    
}

@end


@implementation NSMutableURLRequest (BCCHTTPRequest)

- (NSString *)BCCHTTPRequest_identifier
{
    return [NSURLProtocol propertyForKey:@"BCCHTTPRequest_identifier" inRequest:self];
}

- (void)setBCCHTTPRequest_identifier:(NSString *)identifier
{
    [NSURLProtocol setProperty:identifier forKey:@"BCCHTTPRequest_identifier" inRequest:self];
}

@end
