#import "Cell2JackBridge.h"
#import "../Cell2JackDriver/Cell2JackProtocol.h"
#import <TargetConditionals.h>
#if !TARGET_OS_SIMULATOR
#import <IOKit/IOKitLib.h>
#import <mach/mach.h>
#endif

@implementation Cell2JackBridge
+ (NSString *)usbDiagnostics {
#if TARGET_OS_SIMULATOR
    return @"USB diagnostics require the physical iPad.";
#else
    NSMutableString *report = [NSMutableString stringWithString:@"Read-only USB registry snapshot\n"];
    for (NSString *className in @[@"IOUSBHostDevice", @"IOUSBHostInterface", @"IOUserService"]) {
        CFMutableDictionaryRef matching = IOServiceMatching(className.UTF8String);
        if (!matching) { [report appendFormat:@"%@: cannot create match\n", className]; continue; }
        NSDictionary *properties = [className isEqualToString:@"IOUserService"]
            ? @{@"IOUserClass": @"PorchCell2JackDriver"}
            : @{@"idVendor": @6790, @"idProduct": @29987};
        CFDictionarySetValue(matching, CFSTR("IOPropertyMatch"), (__bridge CFDictionaryRef)properties);
        io_iterator_t iterator = IO_OBJECT_NULL;
        kern_return_t status = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator);
        [report appendFormat:@"%@: search 0x%08x\n", className, status];
        if (status != KERN_SUCCESS) continue;
        unsigned count = 0;
        io_service_t entry;
        while (count < 16 && (entry = IOIteratorNext(iterator)) != IO_OBJECT_NULL) {
            ++count;
            io_name_t name = {};
            IORegistryEntryGetName(entry, name);
            [report appendFormat:@"  %s\n", name];
            CFMutableDictionaryRef allProperties = NULL;
            kern_return_t propertyStatus = IORegistryEntryCreateCFProperties(entry, &allProperties, kCFAllocatorDefault, 0);
            [report appendFormat:@"    property access: 0x%08x\n", propertyStatus];
            for (NSString *key in @[@"idVendor", @"idProduct", @"bDeviceClass", @"bNumConfigurations",
                @"bcdDevice", @"bConfigurationValue", @"bInterfaceNumber", @"bInterfaceClass", @"bNumEndpoints", @"IOUserClass"]) {
                CFTypeRef value = IORegistryEntryCreateCFProperty(entry, (__bridge CFStringRef)key, kCFAllocatorDefault, 0);
                if (value) { [report appendFormat:@"    %@=%@\n", key, (__bridge id)value]; CFRelease(value); }
                else if (allProperties) {
                    id item = ((__bridge NSDictionary *)allProperties)[key];
                    if (item) [report appendFormat:@"    %@=%@\n", key, item];
                }
            }
            if (allProperties) CFRelease(allProperties);
            io_iterator_t children = IO_OBJECT_NULL;
            status = IORegistryEntryGetChildIterator(entry, kIOServicePlane, &children);
            if (status == KERN_SUCCESS) {
                io_registry_entry_t child;
                unsigned childCount = 0;
                while (childCount < 8 && (child = IOIteratorNext(children)) != IO_OBJECT_NULL) {
                    ++childCount;
                    io_name_t childName = {}, childClass = {};
                    IORegistryEntryGetName(child, childName); IOObjectGetClass(child, childClass);
                    [report appendFormat:@"    child=%s (%s)\n", childName, childClass];
                    IOObjectRelease(child);
                }
                IOObjectRelease(children);
            } else { [report appendFormat:@"    children: 0x%08x\n", status]; }
            IOObjectRelease(entry);
        }
        IOObjectRelease(iterator);
        [report appendFormat:@"  Visible matches: %u%@\n", count, count == 16 ? @" (limit reached)" : @""];
    }
    // Cross-check exact USB properties without opening or claiming the device.
    NSArray<NSDictionary *> *checks = @[
        @{@"idVendor": @6790, @"idProduct": @29987, @"bInterfaceNumber": @0,
          @"bConfigurationValue": @1, @"bcdDevice": @0x264},
        @{@"idVendor": @65535, @"idProduct": @65535}
    ];
    for (NSDictionary *properties in checks) {
        CFMutableDictionaryRef matching = IOServiceMatching("IOUSBHostInterface");
        if (!matching) continue;
        CFDictionarySetValue(matching, CFSTR("IOPropertyMatch"), (__bridge CFDictionaryRef)properties);
        io_iterator_t iterator = IO_OBJECT_NULL;
        kern_return_t status = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator);
        unsigned count = 0;
        if (status == KERN_SUCCESS) {
            io_service_t entry;
            while ((entry = IOIteratorNext(iterator)) != IO_OBJECT_NULL) { ++count; IOObjectRelease(entry); }
            IOObjectRelease(iterator);
        }
        [report appendFormat:@"Exact check %@: status=0x%08x count=%u\n", properties, status, count];
    }
    [report appendString:@"Registry visibility may be restricted by iPadOS. Zero visible entries alone do not prove that the cable or device is absent."];
    return report;
#endif
}
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
            @"No running Cell2Jack driver service was found. Turn on its driver switch using Open app settings, then unplug and reconnect Cell2Jack's USB data cable to the iPad and retry. If the switch is already on, this can mean a USB connection, driver matching, or driver startup problem; it does not establish a firmware or baud-rate failure."}];
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
