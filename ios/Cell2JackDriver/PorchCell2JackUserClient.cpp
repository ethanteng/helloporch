#include <DriverKit/IOLib.h>
#include <DriverKit/OSData.h>
#include <DriverKit/IODispatchQueue.h>
#include "PorchCell2JackDriver.h"
#include "PorchCell2JackUserClient.h"

struct PorchCell2JackUserClient_IVars { PorchCell2JackDriver *driver; };
bool PorchCell2JackUserClient::init() {
    if (!super::init()) return false;
    ivars = IONewZero(PorchCell2JackUserClient_IVars, 1);
    return ivars != nullptr;
}
void PorchCell2JackUserClient::free() {
    if (ivars) { OSSafeReleaseNULL(ivars->driver); IOSafeDeleteNULL(ivars, PorchCell2JackUserClient_IVars, 1); }
    super::free();
}
kern_return_t PorchCell2JackUserClient::Start_Impl(IOService *provider) {
    auto status = Start(provider, SUPERDISPATCH);
    if (status != kIOReturnSuccess) return status;
    ivars->driver = OSDynamicCast(PorchCell2JackDriver, provider);
    if (!ivars->driver) return kIOReturnBadArgument;
    ivars->driver->retain();
    // Share the provider's serial queue so query and detach cannot race USB state.
    IODispatchQueue *queue = nullptr;
    status = provider->CopyDispatchQueue("Default", &queue);
    if (status == kIOReturnSuccess) { status = SetDispatchQueue("Default", queue); queue->release(); }
    return status;
}
kern_return_t PorchCell2JackUserClient::Stop_Impl(IOService *provider) {
    if (ivars->driver) {
        PorchC2JReply reply = {};
        ivars->driver->EndLogs(this, &reply); // best effort on close/crash
    }
    return Stop(provider, SUPERDISPATCH);
}
kern_return_t PorchCell2JackUserClient::ExternalMethod(uint64_t selector,
    IOUserClientMethodArguments *arguments, const IOUserClientMethodDispatch *, OSObject *, void *) {
    // This endpoint deliberately accepts no input and no asynchronous callback.
    if (!arguments || selector > PorchC2JEndLogs || arguments->completion ||
        arguments->scalarInputCount || arguments->scalarOutputCount || arguments->structureInput ||
        arguments->structureInputDescriptor || arguments->structureOutputDescriptor ||
        arguments->structureOutputMaximumSize != sizeof(PorchC2JReply)) return kIOReturnBadArgument;
    if (!ivars->driver) return kIOReturnNotAttached;
    PorchC2JReply reply = {};
    kern_return_t status = kIOReturnBadArgument;
    switch (selector) {
        case PorchC2JReadVersion: status = ivars->driver->ReadVersion(&reply); break;
        case PorchC2JBeginLogs: status = ivars->driver->BeginLogs(this, &reply); break;
        case PorchC2JPollLogs: status = ivars->driver->PollLogs(this, &reply); break;
        case PorchC2JEndLogs: status = ivars->driver->EndLogs(this, &reply); break;
    }
    if (status != kIOReturnSuccess) return status;
    arguments->structureOutput = OSData::withBytes(&reply, sizeof(reply));
    return arguments->structureOutput ? kIOReturnSuccess : kIOReturnNoMemory;
}
