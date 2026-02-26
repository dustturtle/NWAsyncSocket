//
//  NWAsyncSocketObjC.h
//  NWAsyncSocketObjC
//
//  Backward-compatibility header. The primary class is now GCDAsyncSocket
//  declared in GCDAsyncSocket.h. NWAsyncSocketObjC is a typedef alias.
//
//  Existing code that imports this header and uses NWAsyncSocketObjC will
//  continue to compile without changes.
//

#import "GCDAsyncSocket.h"
#import "NWAsyncSocketObjCDelegate.h"

// Backward compatibility: class alias.
typedef GCDAsyncSocket NWAsyncSocketObjC;

// Backward compatibility: map old error domain / error code names.
#define NWAsyncSocketObjCErrorDomain GCDAsyncSocketErrorDomain

#define NWAsyncSocketObjCErrorNotConnected    GCDAsyncSocketErrorNotConnected
#define NWAsyncSocketObjCErrorAlreadyConnected GCDAsyncSocketErrorAlreadyConnected
#define NWAsyncSocketObjCErrorConnectionFailed GCDAsyncSocketErrorConnectionFailed
#define NWAsyncSocketObjCErrorReadTimeout     GCDAsyncSocketErrorReadTimeout
#define NWAsyncSocketObjCErrorWriteTimeout    GCDAsyncSocketErrorWriteTimeout
#define NWAsyncSocketObjCErrorInvalidParameter GCDAsyncSocketErrorInvalidParameter
