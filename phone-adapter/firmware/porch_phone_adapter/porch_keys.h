#pragma once
#include <stdint.h>

#include "cell2jack_parser.h"

#ifdef __cplusplus
extern "C" {
#endif

// HID keyboard usages the adapter types into the iPad. Porch reads the keypad
// keys like any USB number pad (CallTrigger.slot in PorchCore), and reads F24 as
// the receiver going back on the cradle (CallTrigger.receiverHangUpKey).
enum {
    PORCH_KEY_KEYPAD_1 = 0x59, // keypad 1–9 follow in order
    PORCH_KEY_KEYPAD_0 = 0x62,
    PORCH_KEY_KEYPAD_STAR = 0x55,
    PORCH_KEY_KEYPAD_HASH = 0xCC,
    PORCH_KEY_RECEIVER_HANG_UP = 0x73, // F24
};

// The key for a parsed event, or 0 for events Porch never acts on: pulse digits,
// diagnostic repeats, and A–D, which the phone has no keys for.
uint8_t porch_key_for_event(const c2j_event *event);

#ifdef __cplusplus
}
#endif
