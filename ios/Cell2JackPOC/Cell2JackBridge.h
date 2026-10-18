#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
@interface Cell2JackBridge : NSObject
// Runs synchronously on a worker queue. Opens a user client for this one query,
// closes it on every exit, and never accesses the Mac or network.
+ (nullable NSData *)readVersionReplyWithError:(NSError **)error;
// Read-only registry snapshot scoped to the Cell2Jack USB IDs and our service.
+ (NSString *)usbDiagnostics;
@end
NS_ASSUME_NONNULL_END
