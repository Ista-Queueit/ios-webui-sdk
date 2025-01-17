#import "QueueITEngine.h"
#import "QueueITApiClient.h"
#import "QueueStatus.h"
#import "IOSUtils.h"
#import "QueueCache.h"
#import "QueueITWaitingRoomView.h"
#import "QueueITWaitingRoomProvider.h"

@interface QueueITEngine()
@property (nonatomic, weak)UIViewController* host;
@property (nonatomic, weak)QueueCache* cache;

@property QueueITWaitingRoomProvider* waitingRoomProvider;
@property QueueITWaitingRoomView* waitingRoomView;
@end

@implementation QueueITEngine

-(instancetype)initWithHost:(UIViewController *)host customerId:(NSString*)customerId eventOrAliasId:(NSString*)eventOrAliasId layoutName:(NSString*)layoutName language:(NSString*)language
{
    self = [super init];
    if(self) {
        self.waitingRoomProvider = [[QueueITWaitingRoomProvider alloc] initWithCustomerId:customerId
                                                                        eventOrAliasId:eventOrAliasId
                                                                        layoutName:layoutName
                                                                        language:language];
        
        self.waitingRoomView = [[QueueITWaitingRoomView alloc] initWithHost: host customerId: customerId eventId: eventOrAliasId];
        self.cache = [QueueCache instance:customerId eventId:eventOrAliasId];
        self.host = host;
        self.customerId = customerId;
        self.eventId = eventOrAliasId;
        self.layoutName = layoutName;
        self.language = language;
        
        self.waitingRoomView.delegate = self;
        self.waitingRoomProvider.delegate = self;
    }
    return self;
}

-(void)setViewDelay:(int)delayInterval {
    [self.waitingRoomView setViewDelay:delayInterval];
}

-(BOOL)isRequestInProgress {
    return [self.waitingRoomProvider IsRequestInProgress];
}

-(BOOL)runWithEnqueueKey:(NSString *)enqueueKey
                   error:(NSError *__autoreleasing *)error
{
    if(![self tryShowQueueFromCache]) {
        return [self.waitingRoomProvider TryPassWithEnqueueKey:enqueueKey error:error];
    }
    return YES;
}

-(BOOL)runWithEnqueueToken:(NSString *)enqueueToken
                     error:(NSError *__autoreleasing *)error
{
    if(![self tryShowQueueFromCache]) {
        return [self.waitingRoomProvider TryPassWithEnqueueToken:enqueueToken error:error];
    }
    return YES;
}

-(BOOL)run:(NSError **)error
{
    if(![self tryShowQueueFromCache]) {
        return [self.waitingRoomProvider TryPass:error];
    }
    return YES;
}

-(BOOL)tryShowQueueFromCache
{
    if (![self.cache isEmpty])
    {
        NSString* urlTtlString = [self.cache getUrlTtl];
        long long cachedTime = [urlTtlString longLongValue];
        long currentTime = (long)(NSTimeInterval)([[NSDate date] timeIntervalSince1970]);
        if (currentTime < cachedTime)
        {
            NSString* targetUrl = [self.cache getTargetUrl];
            NSString* queueUrl = [self.cache getQueueUrl];
            [self showQueue:queueUrl targetUrl:targetUrl];
            return YES;
        }
    }
    return NO;
}

-(void)showQueue:(NSString*)queueUrl targetUrl:(NSString*)targetUrl
{
    [self.waitingRoomView show:queueUrl targetUrl:targetUrl];
}

-(void)updateQueuePageUrl:(NSString *)queuePageUrl
{
    if (![self.cache isEmpty]) {
        NSString* urlTtlString = [self.cache getUrlTtl];
        NSString* targetUrl = [self.cache getTargetUrl];
        [self.cache update:queuePageUrl urlTTL:urlTtlString targetUrl:targetUrl];
    }
}

- (void)waitingRoomView:(nonnull QueueITWaitingRoomView *)view notifyViewPassedQueue:(QueuePassedInfo * _Nullable)queuePassedInfo {
    [self.cache clear];
    [self.queuePassedDelegate notifyYourTurn:queuePassedInfo];
}

- (void)notifyViewQueueWillOpen:(nonnull QueueITWaitingRoomView *)view {
    [self.queueViewWillOpenDelegate notifyQueueViewWillOpen];
}

- (void)waitingRoomProvider:(nonnull QueueITWaitingRoomProvider *)provider notifyProviderFailure:(NSString * _Nullable)errorMessage errorCode:(long)errorCode {
    if(errorCode == 3) {
        [self.queueITUnavailableDelegate notifyQueueITUnavailable:errorMessage];
    }
    
    [self.queueErrorDelegate notifyQueueError:errorMessage errorCode:errorCode];
}

- (void)notifyViewSessionRestart:(nonnull QueueITWaitingRoomView *)view {
    [self.cache clear];
    [self.queueSessionRestartDelegate notifySessionRestart];
}

- (void)notifyViewUserExited:(nonnull QueueITWaitingRoomView *)view {
    [self.queueUserExitedDelegate notifyUserExited];
}

- (void)notifyViewUserClosed:(nonnull QueueITWaitingRoomView *)view {
    [self.queueViewClosedDelegate notifyViewClosed];
}

- (void)waitingRoomView:(nonnull QueueITWaitingRoomView *)view notifyViewUpdatePageUrl:(NSString * _Nullable)urlString {
    [self updateQueuePageUrl:urlString];
    [self.queueUrlChangedDelegate notifyQueueUrlChanged:urlString];
}

-(void)notifyViewQueueDidAppear:(nonnull QueueITWaitingRoomView *)view {
    [self.queueViewDidAppearDelegate notifyQueueViewDidAppear];
}

- (void)waitingRoomProvider:(nonnull QueueITWaitingRoomProvider *)provider notifyProviderSuccess:(QueueTryPassResult * _Nonnull)queuePassResult {
    if([[queuePassResult redirectType]  isEqual: @"safetynet"])
    {
        QueuePassedInfo* queuePassedInfo = [[QueuePassedInfo alloc] initWithQueueitToken:queuePassResult.queueToken];
        [self.queuePassedDelegate notifyYourTurn:queuePassedInfo];
        return;
    }
    else if([[queuePassResult redirectType]  isEqual: @"disabled"])
    {
        QueueDisabledInfo* queueDisabledInfo = [[QueueDisabledInfo alloc]initWithQueueitToken:queuePassResult.queueToken];
        [self.queueDisabledDelegate notifyQueueDisabled:queueDisabledInfo];
        return;
    }
    
    [self showQueue:queuePassResult.queueUrl targetUrl:queuePassResult.targetUrl];
    
    if(queuePassResult.urlTTLInMinutes>0){
        NSString* urlTtlString = [IOSUtils convertTtlMinutesToSecondsString:queuePassResult.urlTTLInMinutes];
        [self.cache update:queuePassResult.queueUrl urlTTL:urlTtlString targetUrl:queuePassResult.targetUrl];
    }
}
@end
