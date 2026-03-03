//
//  SocketManager.h
//  iOSDemoObjC
//
//  Encapsulates GCDAsyncSocket operations — equivalent of SocketManager.swift
//  in the Swift demo.
//

#import <Foundation/Foundation.h>
#import "GCDAsyncSocket.h"
#import "GCDAsyncSocketDelegate.h"

NS_ASSUME_NONNULL_BEGIN

/// Notification posted when SocketManager state changes (connection, logs, data).
extern NSNotificationName const SocketManagerDidUpdateNotification;

@interface SocketManager : NSObject

@property (nonatomic, readonly) BOOL isConnected;
@property (nonatomic, readonly, copy) NSArray<NSString *> *logs;
@property (nonatomic, readonly, copy) NSData *receivedData;
@property (nonatomic, readonly, copy) NSString *receivedText;
@property (nonatomic, readonly, copy) NSArray<NWSSEEvent *> *sseEvents;

- (void)connectToHost:(NSString *)host
                 port:(uint16_t)port
               useTLS:(BOOL)useTLS
            enableSSE:(BOOL)enableSSE
      enableStreaming:(BOOL)enableStreaming;

- (void)sendText:(NSString *)text;
- (void)sendData:(NSData *)data;
- (void)readData;
- (void)disconnect;
- (void)clearAll;

@end

NS_ASSUME_NONNULL_END
