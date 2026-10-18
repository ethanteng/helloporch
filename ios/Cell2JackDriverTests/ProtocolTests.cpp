#include "../Cell2JackDriver/Cell2JackProtocol.h"
#include <assert.h>
#include <stddef.h>
#include <stdio.h>
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
    puts("USB protocol: fixed response ABI and 2 Mbaud divisor passed");
}
