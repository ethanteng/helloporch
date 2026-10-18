#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
@interface Cell2JackBridge : NSObject
// Runs synchronously on a worker queue. Opens a user client for this one query,
// closes it on every exit, and never accesses the Mac or network.
+ (nullable NSData *)readVersionReplyWithError:(NSError **)error;
// Read-only registry snapshot scoped to the Cell2Jack USB IDs and our service.
+ (NSString *)usbDiagnostics;
@end
@interface Cell2JackLogSession : NSObject
+ (nullable Cell2JackLogSession *)openWithError:(NSError **)error NS_SWIFT_NAME(open());
- (nullable NSData *)beginLogsWithError:(NSError **)error NS_SWIFT_NAME(beginLogs());
- (nullable NSData *)pollLogsWithError:(NSError **)error NS_SWIFT_NAME(pollLogs());
- (nullable NSData *)endLogsWithError:(NSError **)error NS_SWIFT_NAME(endLogs());
- (void)close;
@end
NS_ASSUME_NONNULL_END
