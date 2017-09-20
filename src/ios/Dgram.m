#import "Dgram.h"
#include <sys/socket.h>
#include <netinet/in.h>

@interface SocketConfig : NSObject

@property (nonatomic,assign) NSInteger socketID;
@property (nonatomic,assign) NSInteger port;
@property (nonatomic,assign) BOOL isMulticast;
@property (nonatomic,assign) BOOL isBroadcast;
@property (nonatomic,strong) GCDAsyncUdpSocket *socketHandle;
@property (nonatomic,assign) BOOL isBound;

+(NSString *)convertIDTokKey:(NSInteger)socketID;

@end

@implementation SocketConfig

+(NSString *)convertIDTokKey:(NSInteger)socketID {
    return [NSString stringWithFormat:@"%ld", socketID];
}

@end

@interface Dgram ()

@property (nonatomic,strong) NSMutableDictionary *sockets;
@property (nonatomic,assign) NSInteger tag;

@end

@implementation Dgram

@synthesize sockets;

- (void)pluginInitialize {
  [super pluginInitialize];
  sockets = [NSMutableDictionary new];
}

-(void)create:(CDVInvokedUrlCommand *)command {
    SocketConfig *sock = [SocketConfig new];
    sock.socketID = [[command argumentAtIndex:0] intValue];
    sock.isMulticast = [[command argumentAtIndex:1] boolValue];
    sock.isBroadcast = [[command argumentAtIndex:2] boolValue];
    sock.port = [[command argumentAtIndex:3] intValue];
    sock.isBound = NO;

    sock.socketHandle = [[GCDAsyncUdpSocket alloc] initWithDelegate:self delegateQueue:dispatch_get_main_queue()];
    CDVPluginResult *result = nil;
    NSError *error = nil;
    if (sock.socketHandle == nil)
        result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Cannot create socket"];
    else {
        [sockets setObject:sock forKey:[SocketConfig convertIDTokKey:sock.socketID]];
        if (![sock.socketHandle enableBroadcast:sock.isBroadcast error:&error])
            result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:error.localizedDescription];
        else
            result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    }

    [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
}

-(void)bind:(CDVInvokedUrlCommand *)command {
    NSInteger socketID = [[command argumentAtIndex:0] intValue];
    SocketConfig *config = [sockets valueForKey:[SocketConfig convertIDTokKey:socketID]];

    CDVPluginResult *result = nil;
    NSError *error;
    if (config == nil || config.socketHandle == nil) {
        result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Socket is not open"];
    }
    else if ([config.socketHandle bindToPort:config.port error:&error]) {
        config.isBound = YES;
        if ((!config.isMulticast && [config.socketHandle beginReceiving:&error]) || config.isMulticast) {
            result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
        }
        else if(!config.isMulticast) {
            result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:[NSString stringWithFormat:@"Cannot listen to socket - %@", error.localizedDescription]];
        }
    }
    else
        result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:[NSString stringWithFormat:@"Cannot bind to socket - %@", error.localizedDescription]];

    [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
}

-(void)close:(CDVInvokedUrlCommand *)command {
    NSInteger socketID = [[command argumentAtIndex:0] intValue];
    SocketConfig *config = [sockets valueForKey:[SocketConfig convertIDTokKey:socketID]];
    CDVPluginResult *result = nil;
    if (config == nil || config.socketHandle == nil) {
        result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Socket is not open"];
    }
    else {
        [config.socketHandle closeAfterSending];
    }

    [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
}

-(void)joinGroup:(CDVInvokedUrlCommand *)command {
    NSInteger socketID = [[command argumentAtIndex:0] intValue];
    NSString *address = [command argumentAtIndex:1];
    SocketConfig *config = [sockets valueForKey:[SocketConfig convertIDTokKey:socketID]];
    CDVPluginResult *result = nil;
    NSError *error;
    if (config == nil || config.socketHandle == nil) {
        result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Socket is not open"];
    }
    else if (!config.isMulticast) {
        result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Cannot join group on non-multicast socket"];
    }
    else if ([config.socketHandle joinMulticastGroup:address error:&error] && [config.socketHandle beginReceiving:&error]) {
        result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    }
    else
        result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:[NSString stringWithFormat:@"Cannot join and listen to multicast group - %@", error.localizedDescription]];

    [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
}

-(void)leaveGroup:(CDVInvokedUrlCommand *)command {
    NSInteger socketID = [[command argumentAtIndex:0] intValue];
    NSString *address = [command argumentAtIndex:1];
    SocketConfig *config = [sockets valueForKey:[SocketConfig convertIDTokKey:socketID]];
    CDVPluginResult *result = nil;
    NSError *error;
    if (config == nil || config.socketHandle == nil) {
        result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Socket is not open"];
    }
    else if ([config.socketHandle leaveMulticastGroup:address error:&error]) {
        result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    }
    else
        result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:[NSString stringWithFormat:@"Cannot leave multicast group - %@", error.localizedDescription]];
}

-(void)send:(CDVInvokedUrlCommand *)command {
    NSInteger socketID = [[command argumentAtIndex:0] intValue];
    NSString *buffer = [command argumentAtIndex:1];
    NSString *remoteAddress = [command argumentAtIndex:2];
    NSInteger remotePort = [[command argumentAtIndex:3] intValue];
    NSString *encoding = [command argumentAtIndex:4];
    SocketConfig *config = [sockets valueForKey:[SocketConfig convertIDTokKey:socketID]];
    CDVPluginResult *result = nil;

    NSData *data = nil;
    if ([encoding isEqualToString:@"utf-8"])
        data = [buffer dataUsingEncoding:NSUTF8StringEncoding];
    else if ([encoding isEqualToString:@"base64"])
        data = [[NSData alloc] initWithBase64EncodedString:buffer options:0];
    else
        data = [NSData data];
    if (config == nil || config.socketHandle == nil) {
        result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Socket is not open"];
    }
    else {
        [config.socketHandle sendData:data toHost:remoteAddress port:remotePort withTimeout:60 tag:self.tag];
        self.tag++;
        result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:buffer];
    }

    [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
}

#pragma mark GCDAsyncUdpSocketDelegate methods

- (void)udpSocket:(GCDAsyncUdpSocket *)sock didSendDataWithTag:(long)tag
{
    // You could add checks here
}

- (void)udpSocket:(GCDAsyncUdpSocket *)sock didNotSendDataWithTag:(long)tag dueToError:(NSError *)error
{
    // You could add checks here
    NSLog(@"Failed to send message due to error: %@", error.localizedDescription);
}

- (void)udpSocket:(GCDAsyncUdpSocket *)sock didReceiveData:(NSData *)data fromAddress:(NSData *)address withFilterContext:(id)filterContext {
    NSString *host = nil;
    uint16_t port = 0;
    [GCDAsyncUdpSocket getHost:&host port:&port fromAddress:address];
    SocketConfig *config = nil;
    for (NSString *key in self.sockets) {
        config = [self.sockets valueForKey:key];
        if ([config.socketHandle isEqual:sock]) {
            break;
        }
        else
            config = nil;
    }

    NSString *msg = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (msg != nil && config != nil) {
        msg = [msg stringByReplacingOccurrencesOfString:@"'" withString:@"\'"];
        msg = [msg stringByReplacingOccurrencesOfString:@"\n" withString:@"\\n"];
        msg = [msg stringByReplacingOccurrencesOfString:@"\r" withString:@"\\r"];
        NSString *command = [NSString stringWithFormat:@"cordova.require('cordova-plugin-dgram.dgram')._onMessage(%d,'%@','%@',%d)", (int)config.socketID, msg, host, port];
        [self.commandDelegate evalJs:command scheduledOnRunLoop:YES];
    }
    else {
        NSLog(@"Failed to get message from host: %@", host);
    }
}

@end
