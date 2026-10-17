#import "NSExceptionCatcher.h"
NSException *TopitCatchException(void (^operation)(void)) {
    @try { operation(); return nil; }
    @catch (NSException *exception) { return exception; }
}
