#pragma once
#include <stdint.h>

// At most one CLEAR_FEATURE(ENDPOINT_HALT) and one retry per transfer.
// Preserve partial reads; never replay a partially written serial command.
template <typename Transfer, typename ClearStall>
int32_t PorchC2JTransferRecoveringStall(bool reading, uint32_t &transferred,
    int32_t stalled, Transfer transfer, ClearStall clearStall) {
    auto status = transfer();
    if (status != stalled) return status;
    auto cleared = clearStall();
    if (cleared != 0) return cleared;
    if (transferred != 0) return reading ? 0 : status;
    return transfer();
}
