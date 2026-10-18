#import "Cell2JackBridge.h"
#import "../Cell2JackDriver/Cell2JackProtocol.h"
#import <TargetConditionals.h>
#if !TARGET_OS_SIMULATOR
#import <IOKit/IOKitLib.h>
#import <mach/mach.h>
#endif

@implementation Cell2JackBridge
+ (NSData *)readVersionReplyWithError:(NSError **)error {
#if TARGET_OS_SIMULATOR
    if (error) *error = [NSError errorWithDomain:@"PorchCell2Jack" code:1 userInfo:@{NSLocalizedDescriptionKey:
        @"USB drivers cannot run in Simulator. Install the signed USB Test build on the M3 iPad."}];
    return nil;
#else
    io_iterator_t iterator = IO_OBJECT_NULL;
    kern_return_t status = IOServiceGetMatchingServices(kIOMainPortDefault,
        IOServiceNameMatching("PorchCell2JackDriver"), &iterator);
    if (status != KERN_SUCCESS) {
        if (error) *error = [self errorForStatus:status action:@"Looking for the USB driver"];
        return nil;
    }
    io_service_t service = IOIteratorNext(iterator);
    if (service == IO_OBJECT_NULL) {
        IOObjectRelease(iterator);
        if (error) *error = [NSError errorWithDomain:@"PorchCell2Jack" code:2 userInfo:@{NSLocalizedDescriptionKey:
            @"Cell2Jack driver not found. Enable it in Settings → General → Drivers, connect Cell2Jack with a USB data cable, then retry. If Drivers is absent, this build may not contain an approved, signed driver."}];
        return nil;
    }
    io_service_t extra = IOIteratorNext(iterator);
    IOObjectRelease(iterator);
    if (extra != IO_OBJECT_NULL) {
        IOObjectRelease(extra); IOObjectRelease(service);
        if (error) *error = [NSError errorWithDomain:@"PorchCell2Jack" code:3 userInfo:@{NSLocalizedDescriptionKey:
            @"More than one matching USB serial adapter is connected. Leave only Cell2Jack connected and retry."}];
        return nil;
    }
    io_connect_t connection = IO_OBJECT_NULL;
    status = IOServiceOpen(service, mach_task_self(), 0, &connection);
    IOObjectRelease(service);
    if (status != KERN_SUCCESS) {
        if (error) *error = [self errorForStatus:status action:@"Opening the USB driver"];
        return nil;
    }
    PorchC2JReply reply = {};
    size_t length = sizeof(reply);
    status = IOConnectCallStructMethod(connection, PorchC2JReadVersion, NULL, 0, &reply, &length);
    IOServiceClose(connection);
    if (status != KERN_SUCCESS) {
        if (error) *error = [self errorForStatus:status action:@"Requesting the version"];
        return nil;
    }
    if (length != sizeof(reply) || reply.abi != PorchC2JABI || reply.count > PorchC2JMaxReply) {
        if (error) *error = [NSError errorWithDomain:@"PorchCell2Jack" code:4 userInfo:@{NSLocalizedDescriptionKey:
            @"The driver returned an incompatible response. Reinstall matching app and driver builds."}];
        return nil;
    }
    return [NSData dataWithBytes:&reply length:length];
#endif
}
#if !TARGET_OS_SIMULATOR
+ (NSError *)errorForStatus:(kern_return_t)status action:(NSString *)action {
    return [NSError errorWithDomain:@"PorchCell2Jack" code:status userInfo:@{NSLocalizedDescriptionKey:
        [NSString stringWithFormat:@"%@: 0x%08x. Check driver signing, permission in Settings, and the USB connection.", action, status]}];
}
#endif
@end
