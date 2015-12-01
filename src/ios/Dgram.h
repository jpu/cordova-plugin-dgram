//
//  Dgram.h
//  udpDevelop
//
//  Created by James McCarthy on 11/27/15.
//
//

#import <Cordova/CDV.h>
#import "GCDAsyncUdpSocket.h"


@interface Dgram : CDVPlugin<GCDAsyncUdpSocketDelegate>

@end
