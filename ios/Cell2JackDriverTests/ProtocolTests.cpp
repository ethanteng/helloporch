#include "../Cell2JackDriver/Cell2JackProtocol.h"
#include "../Cell2JackDriver/Cell2JackUSBRecovery.h"
#include <assert.h>
#include <stddef.h>
#include <stdio.h>
#include <initializer_list>
int main() {
    static_assert(sizeof(PorchC2JReply) == 276, "User client ABI drift");
    static_assert(offsetof(PorchC2JReply, bytes) == 20, "User client ABI drift");
    assert(PorchC2JBaudRegister(0x31) == 0xfd83);
    assert(PorchC2JBaudRegister(0x27) == 0xfd03);
    const unsigned encoded = PorchC2JBaudRegister(0x31);
    const unsigned divisor = 256 - (encoded >> 8);
    const unsigned prescaler = encoded & 3;
    const unsigned factor = (encoded >> 2) & 1;
    assert(48000000 / ((1 << (12 - 3 * prescaler - factor)) * divisor) == 2000000);
    constexpr int32_t stalled = static_cast<int32_t>(0xe0005000);
    constexpr int32_t failed = -1;
    for (bool reading : {false, true}) {
        uint32_t transferred = 0;
        int calls = 0, clears = 0;
        auto result = PorchC2JTransferRecoveringStall(reading, transferred, stalled,
            [&]() -> int32_t { if (++calls == 1) return stalled; transferred = 2; return 0; },
            [&]() -> int32_t { ++clears; return 0; });
        assert(result == 0 && calls == 2 && clears == 1 && transferred == 2);

        // A second stall is surfaced to the app's reconnect loop, never spun on.
        calls = clears = 0; transferred = 0;
        result = PorchC2JTransferRecoveringStall(reading, transferred, stalled,
            [&]() -> int32_t { ++calls; return stalled; }, [&]() -> int32_t { ++clears; return 0; });
        assert(result == stalled && calls == 2 && clears == 1);

        calls = clears = 0;
        result = PorchC2JTransferRecoveringStall(reading, transferred, stalled,
            [&]() -> int32_t { ++calls; return stalled; }, [&]() -> int32_t { ++clears; return failed; });
        assert(result == failed && calls == 1 && clears == 1);

        // A partially received record is delivered once; a partial write is not replayed.
        calls = clears = 0; transferred = 0;
        result = PorchC2JTransferRecoveringStall(reading, transferred, stalled,
            [&]() -> int32_t { ++calls; transferred = 1; return stalled; }, [&]() -> int32_t { ++clears; return 0; });
        assert(result == (reading ? 0 : stalled) && calls == 1 && clears == 1 && transferred == 1);

        for (int32_t ordinary : {int32_t(0), failed}) {
            calls = clears = 0; transferred = 0;
            result = PorchC2JTransferRecoveringStall(reading, transferred, stalled,
                [&]() -> int32_t { ++calls; return ordinary; }, [&]() -> int32_t { ++clears; return 0; });
            assert(result == ordinary && calls == 1 && clears == 0);
        }
    }
    puts("USB recovery: bounded stall clearing, partial transfers and failures passed");
    puts("USB protocol: fixed response ABI and 2 Mbaud divisor passed");
}
