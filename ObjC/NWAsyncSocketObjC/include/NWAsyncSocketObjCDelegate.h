//
//  NWAsyncSocketObjCDelegate.h
//  NWAsyncSocketObjC
//
//  Backward-compatibility header. The primary protocol is now
//  GCDAsyncSocketDelegate declared in GCDAsyncSocketDelegate.h.
//  NWAsyncSocketObjCDelegate is a preprocessor alias.
//

#import "GCDAsyncSocketDelegate.h"

// Backward compatibility: existing code using NWAsyncSocketObjCDelegate
// will continue to compile.
#define NWAsyncSocketObjCDelegate GCDAsyncSocketDelegate
