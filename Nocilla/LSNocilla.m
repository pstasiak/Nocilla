#import "LSNocilla.h"
#import "LSNSURLHook.h"
#import "LSStubRequest.h"
#import "LSStubRequestDSL.h"
#import "LSStubResponseDSL.h"
#import "LSHTTPRequestDSLRepresentation.h"
#import "LSASIHTTPRequestHook.h"
#import "LSNSURLSessionHook.h"
#import "LSASIHTTPRequestHook.h"
#import "LSHTTPStubURLProtocol.h"

NSString * const LSUnexpectedRequest = @"Unexpected Request";

@interface LSNocilla ()
@property (nonatomic, strong) NSMutableArray *mutableRequests;
@property (nonatomic, strong) NSMutableArray *hooks;
@property (nonatomic, assign, getter = isStarted) BOOL started;

- (void)loadHooks;
- (void)unloadHooks;
@end

static LSNocilla *sharedInstace = nil;

@implementation LSNocilla

+ (LSNocilla *)sharedInstance {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstace = [[self alloc] init];
    });
    return sharedInstace;
}

- (id)init {
    self = [super init];
    if (self) {
        _mutableRequests = [NSMutableArray array];
        _hooks = [NSMutableArray array];

        Class stubUrlProtocolClass = [LSHTTPStubURLProtocol randomSubclass];
        [stubUrlProtocolClass registerNocilla:self];
        
        LSNSURLHook *urlHook = [[LSNSURLHook alloc] init];
        urlHook.urlProtocolClass = stubUrlProtocolClass;
        
        [self registerHook:urlHook];
        if (NSClassFromString(@"NSURLSession") != nil) {
            LSNSURLSessionHook *sessionHook = [[LSNSURLSessionHook alloc] init];
            sessionHook.urlProtocolClass = stubUrlProtocolClass;
            [self registerHook:sessionHook];
        }
        [self registerHook:[[LSASIHTTPRequestHook alloc] init]];
    }
    return self;
}

- (NSArray *)stubbedRequests {
    return [NSArray arrayWithArray:self.mutableRequests];
}

- (void)start {
    if (!self.isStarted){
        [self loadHooks];
        self.started = YES;
    }
}

- (void)stop {
    [self unloadHooks];
    [self clearStubs];
    self.started = NO;
}

- (void)addStubbedRequest:(LSStubRequest *)request {
    [self.mutableRequests addObject:request];
}

- (void)clearStubs {
    [self.mutableRequests removeAllObjects];
}

- (LSStubResponse *)responseForRequest:(id<LSHTTPRequest>)actualRequest {
    NSArray* requests = self.stubbedRequests;

    for(LSStubRequest *someStubbedRequest in requests) {
        if ([someStubbedRequest matchesRequest:actualRequest]) {
            return someStubbedRequest.response;
        }
    }
    [NSException raise:@"NocillaUnexpectedRequest" format:@"An unexpected HTTP request was fired.\n\nUse this snippet to stub the request:\n%@\n", [[[LSHTTPRequestDSLRepresentation alloc] initWithRequest:actualRequest] description]];

    return nil;
}

- (void)registerHook:(LSHTTPClientHook *)hook {
    if (![self hookWasRegistered:hook]) {
        [[self hooks] addObject:hook];
    }
}

- (BOOL)hookWasRegistered:(LSHTTPClientHook *)aHook {
    for (LSHTTPClientHook *hook in self.hooks) {
        if ([hook isMemberOfClass: [aHook class]]) {
            return YES;
        }
    }
    return NO;
}

- ( LSStubRequestDSL *(^)(NSString *method, id<LSMatcheable> url))stubRequest
{
    return ^(NSString *method, id<LSMatcheable> url){
        LSStubRequest *request = [[LSStubRequest alloc] initWithMethod:method urlMatcher:url.matcher];
        LSStubRequestDSL *dsl = [[LSStubRequestDSL alloc] initWithRequest:request];
        [self addStubbedRequest:request];
        return dsl;
    };
}

#pragma mark - Private
- (void)loadHooks {
    for (LSHTTPClientHook *hook in self.hooks) {
        [hook load];
    }
}

- (void)unloadHooks {
    for (LSHTTPClientHook *hook in self.hooks) {
        [hook unload];
    }
}

@end
