#pragma once
#include <stdint.h>

// Fixed allowlist only: version, start logs, read logs, stop logs. No caller-
// supplied serial/USB bytes, bootloader operations, or flash writes.
enum { PorchC2JABI = 2, PorchC2JReadVersion = 0, PorchC2JBeginLogs = 1,
    PorchC2JPollLogs = 2, PorchC2JEndLogs = 3, PorchC2JMaxReply = 256 };
enum PorchC2JStage { PorchC2JReady = 0, PorchC2JChipVersion, PorchC2JInitialize,
    PorchC2JBaud, PorchC2JLineControl, PorchC2JModemControl, PorchC2JWrite,
    PorchC2JRead, PorchC2JComplete, PorchC2JLogEnable, PorchC2JLogRead, PorchC2JLogStop };
typedef struct {
    uint32_t abi;
    uint32_t stage;
    uint32_t usbStatus;
    uint32_t count;
    uint8_t chipVersion;
    uint8_t reserved[3];
    uint8_t bytes[PorchC2JMaxReply];
} PorchC2JReply;

// Fixed 2 Mbaud: 48 MHz / (2^(12-3*3) * 3) = 2,000,000.
// Registers 0x13/0x12 encode divisor (256-3), fact=0, prescaler=3.
// Chip revisions >0x27 use bit 7 for short-packet delivery.
static inline uint16_t PorchC2JBaudRegister(uint8_t chipVersion) {
    return (uint16_t)(0xfd03 | (chipVersion > 0x27 ? 0x80 : 0));
}
