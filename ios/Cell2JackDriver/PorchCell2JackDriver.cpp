#include <DriverKit/IOLib.h>
#include <DriverKit/IODispatchQueue.h>
#include <DriverKit/IOBufferMemoryDescriptor.h>
#include <USBDriverKit/IOUSBHostInterface.h>
#include <USBDriverKit/USBDriverKitDefs.h>
#include <USBDriverKit/IOUSBHostPipe.h>
#include <USBDriverKit/AppleUSBDescriptorParsing.h>
#include "PorchCell2JackDriver.h"
#include "PorchCell2JackUserClient.h"

struct PorchCell2JackDriver_IVars {
    IOUSBHostInterface *interface;
    IOUSBHostPipe *input;
    IOUSBHostPipe *output;
    uint16_t packetSize;
    bool opened;
};

bool PorchCell2JackDriver::init() {
    if (!super::init()) return false;
    ivars = IONewZero(PorchCell2JackDriver_IVars, 1);
    return ivars != nullptr;
}
void PorchCell2JackDriver::free() {
    if (ivars) {
        OSSafeReleaseNULL(ivars->input);
        OSSafeReleaseNULL(ivars->output);
        OSSafeReleaseNULL(ivars->interface);
        IOSafeDeleteNULL(ivars, PorchCell2JackDriver_IVars, 1);
    }
    super::free();
}
kern_return_t PorchCell2JackDriver::Start_Impl(IOService *provider) {
    auto status = Start(provider, SUPERDISPATCH);
    if (status != kIOReturnSuccess) return status;
    ivars->interface = OSDynamicCast(IOUSBHostInterface, provider);
    if (!ivars->interface) return kIOReturnUnsupported;
    ivars->interface->retain();
    status = ivars->interface->Open(this, 0, 0);
    if (status != kIOReturnSuccess) return status;
    ivars->opened = true;
    const auto *config = ivars->interface->CopyConfigurationDescriptor();
    if (!config) status = kIOReturnNotFound;
    else {
        const auto *iface = ivars->interface->GetInterfaceDescriptor(config);
        if (!iface) status = kIOReturnNotFound;
        else {
            const IOUSBEndpointDescriptor *ep = nullptr;
            while ((ep = IOUSBGetNextEndpointDescriptor(config, iface, reinterpret_cast<const IOUSBDescriptorHeader *>(ep)))) {
                if ((ep->bmAttributes & 3) != 2) continue; // bulk only
                if (ep->bEndpointAddress & 0x80) {
                    if (!ivars->input) {
                        status = ivars->interface->CopyPipe(ep->bEndpointAddress, &ivars->input);
                        ivars->packetSize = ep->wMaxPacketSize & 0x7ff;
                    }
                } else if (!ivars->output) {
                    status = ivars->interface->CopyPipe(ep->bEndpointAddress, &ivars->output);
                }
                if (status != kIOReturnSuccess) break;
            }
        }
        IOUSBHostFreeDescriptor(config);
    }
    if (status == kIOReturnSuccess && (!ivars->input || !ivars->output ||
        !ivars->packetSize || ivars->packetSize > PorchC2JMaxReply)) status = kIOReturnUnsupported;
    if (status == kIOReturnSuccess) status = SetName("PorchCell2JackDriver");
    if (status == kIOReturnSuccess) status = RegisterService();
    if (status != kIOReturnSuccess && ivars->opened) {
        ivars->interface->Close(this, 0); ivars->opened = false;
    }
    return status;
}
kern_return_t PorchCell2JackDriver::Stop_Impl(IOService *provider) {
    if (ivars->opened) { ivars->interface->Close(this, 0); ivars->opened = false; }
    return Stop(provider, SUPERDISPATCH);
}
kern_return_t PorchCell2JackDriver::NewUserClient_Impl(uint32_t type, IOUserClient **client) {
    if (type != 0) return kIOReturnBadArgument;
    IOService *service = nullptr;
    auto status = Create(this, "UserClientProperties", &service);
    if (status != kIOReturnSuccess) return status;
    *client = OSDynamicCast(PorchCell2JackUserClient, service);
    if (!*client) { service->release(); return kIOReturnError; }
    return kIOReturnSuccess;
}

kern_return_t PorchCell2JackDriver::ReadVersion(PorchC2JReply *reply) {
    bzero(reply, sizeof(*reply)); reply->abi = PorchC2JABI;
    if (!ivars->opened) return kIOReturnNotAttached;
    IOBufferMemoryDescriptor *buffer = nullptr;
    auto status = ivars->interface->CreateIOBuffer(kIOMemoryDirectionOutIn, PorchC2JMaxReply, &buffer);
    if (status != kIOReturnSuccess) return status;
    IOAddressSegment memory = {};
    status = buffer->GetAddressRange(&memory);
    if (status != kIOReturnSuccess) { buffer->release(); return status; }
    auto *bytes = reinterpret_cast<uint8_t *>(memory.address);
    auto control = [&](uint8_t direction, uint8_t request, uint16_t value, uint16_t index, uint16_t length) {
        uint16_t transferred = 0;
        bzero(bytes, PorchC2JMaxReply);
        auto result = buffer->SetLength(length);
        if (result != kIOReturnSuccess) return result;
        result = ivars->interface->DeviceRequest(direction, request, value, index, length,
            length ? buffer : nullptr, &transferred, 500);
        if (result == kIOReturnSuccess && transferred != length) return kIOReturnUnderrun;
        return result;
    };
    // CH34x USB register protocol, separate from the Cell2Jack serial protocol.
    // Only volatile serial configuration is changed; no device firmware writes.
    reply->stage = PorchC2JChipVersion;
    status = control(0xc0, 0x5f, 0, 0, 2);
    if (status == kIOReturnSuccess) {
        reply->chipVersion = bytes[0];
        // Older variants need different line-control sequencing, not implemented.
        if (reply->chipVersion < 0x30) status = kIOReturnUnsupported;
    }
    if (status == kIOReturnSuccess) {
        reply->stage = PorchC2JInitialize; status = control(0x40, 0xa1, 0, 0, 0);
    }
    if (status == kIOReturnSuccess) {
        reply->stage = PorchC2JBaud;
        status = control(0x40, 0x9a, 0x1312, PorchC2JBaudRegister(reply->chipVersion), 0);
    }
    if (status == kIOReturnSuccess) {
        reply->stage = PorchC2JLineControl; status = control(0x40, 0x9a, 0x2518, 0xc3, 0); // 8N1 RX/TX
    }
    if (status == kIOReturnSuccess) {
        // Disable hardware flow control. Keep DTR and RTS inactive, as in test-04.
        reply->stage = PorchC2JModemControl; status = control(0x40, 0x9a, 0x2727, 0, 0);
        if (status == kIOReturnSuccess) status = control(0x40, 0xa4, 0xffff, 0, 0);
    }
    if (status == kIOReturnSuccess) {
        reply->stage = PorchC2JWrite;
        bytes[0] = '/'; bytes[1] = 'v';
        status = buffer->SetLength(2);
        uint32_t transferred = 0;
        if (status == kIOReturnSuccess) status = ivars->output->IO(buffer, 2, &transferred, 500);
        if (status == kIOReturnSuccess && transferred != 2) status = kIOReturnUnderrun;
    }
    if (status == kIOReturnSuccess) {
        reply->stage = PorchC2JRead;
        // Bounded receive window; preserve fragmentation and partial timeout data.
        for (unsigned attempt = 0; attempt < 6 && reply->count < PorchC2JMaxReply; ++attempt) {
            uint32_t transferred = 0;
            status = buffer->SetLength(ivars->packetSize);
            if (status != kIOReturnSuccess) break;
            status = ivars->input->IO(buffer, ivars->packetSize, &transferred, 500);
            if (transferred > ivars->packetSize) { status = kIOReturnOverrun; break; }
            auto available = PorchC2JMaxReply - reply->count;
            auto count = transferred < available ? transferred : available;
            memcpy(reply->bytes + reply->count, bytes, count); reply->count += count;
            bool lineEnded = false;
            for (uint32_t i = 0; i < reply->count; ++i) if (reply->bytes[i] == '\n') lineEnded = true;
            if (lineEnded) { status = kIOReturnSuccess; break; }
            if (status == kIOReturnTimeout || status == kIOReturnUnderrun) continue;
            if (status != kIOReturnSuccess) break;
        }
        if (reply->count && (status == kIOReturnTimeout || status == kIOReturnUnderrun)) status = kIOReturnSuccess;
        if (!reply->count && status == kIOReturnSuccess) status = kIOReturnTimeout;
        if (status == kIOReturnSuccess) reply->stage = PorchC2JComplete;
    }
    reply->usbStatus = status;
    buffer->release();
    return kIOReturnSuccess; // USB result is carried in the fixed-size response.
}
