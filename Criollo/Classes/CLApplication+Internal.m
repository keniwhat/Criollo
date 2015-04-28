//
//  CLApplication+Internal.m
//  Criollo
//
//  Created by Cătălin Stan on 28/04/15.
//
//

#import <Criollo/CLHTTPConnection.h>
#import "CLApplication+Internal.h"

void handleSIGTERM(int signum) {
    [CLApp presentError:[NSError errorWithDomain:CLErrorDomain code:CLErrorSigTERM userInfo:@{ NSLocalizedDescriptionKey: @"Got SIGTERM." }]];
    [CLApp performSelectorOnMainThread:@selector(terminate:) withObject:nil waitUntilDone:YES];
}

@implementation CLApplication (Internal)

BOOL shouldKeepRunning;

#pragma mark - Lifecycle

- (void)quit
{
    [self stopListening];
    [[NSNotificationCenter defaultCenter] postNotificationName:CLApplicationWillTerminateNotification object:self];
    exit(EXIT_SUCCESS);
}

- (void)cancelTermination
{
    [self startRunLoop];
}

- (void)waitingOnTerminateLaterReplyTimerCallback
{
}

- (void)startRunLoop
{
    shouldKeepRunning = YES;
    
    [self startListening];
    [[NSNotificationCenter defaultCenter] postNotificationName:CLApplicationDidFinishLaunchingNotification object:self];
    [[NSRunLoop mainRunLoop] addTimer:[NSTimer timerWithTimeInterval:[[NSDate distantFuture] timeIntervalSinceNow] target:nil selector:@selector(stop) userInfo:nil repeats:YES] forMode:CLApplicationRunLoopMode];
    
    while ( shouldKeepRunning && [[NSRunLoop mainRunLoop] runMode:CLApplicationRunLoopMode beforeDate:[NSDate distantFuture]] );
}

- (void)stopRunLoop
{
    CFRunLoopStop(CFRunLoopGetMain());
}


#pragma mark - Listening

- (void)startListening
{
    self.workerQueue = [[NSOperationQueue alloc] init];
    self.workerQueue.name = [[NSBundle mainBundle].bundleIdentifier stringByAppendingPathExtension:@"WorkerQueue"];
    self.workerQueue.maxConcurrentOperationCount = NSOperationQueueDefaultMaxConcurrentOperationCount;
    self.workerQueue.qualityOfService = NSQualityOfServiceUserInitiated;
    
    self.delegateQueue = [[NSOperationQueue alloc] init];
    self.delegateQueue.name = [[NSBundle mainBundle].bundleIdentifier stringByAppendingPathExtension:@"DelegateQueue"];
    self.delegateQueue.maxConcurrentOperationCount = NSOperationQueueDefaultMaxConcurrentOperationCount;
    self.delegateQueue.qualityOfService = NSQualityOfServiceDefault;
    
    self.httpSocket = [[GCDAsyncSocket alloc] initWithDelegate:self delegateQueue:self.delegateQueue.underlyingQueue];
    
    NSError *error;
    BOOL listening = NO;
    
    listening = [self.httpSocket acceptOnInterface:(self.interface.length == 0 ? nil : self.interface) port:self.portNumber error:&error];
    if ( !listening ) {
        [self presentError:error];
        [self terminate:self];
    } else {
        [self logFormat:@"Listening on %@:%lu", self.interface, self.portNumber];
    }
}

- (void)stopListening
{
    [self.httpSocket setDelegate:nil];
    [self.httpSocket disconnect];
    self.httpSocket = nil;
 
    [self.workerQueue cancelAllOperations];
    [self.delegateQueue cancelAllOperations];
    
    self.workerQueue = nil;
    self.delegateQueue = nil;

    [self.connections removeAllObjects];
}

#pragma mark - GCDAsyncSocketDelegate

- (void)socket:(GCDAsyncSocket *)sock didAcceptNewSocket:(GCDAsyncSocket *)newSocket
{
    NSLog(@"%s", __PRETTY_FUNCTION__);
    CLHTTPConnection* connection = [[CLHTTPConnection alloc] initWithSocket:newSocket];
    
    @synchronized(self.connections) {
        [self.connections addObject:connection];
    }
}

@end
