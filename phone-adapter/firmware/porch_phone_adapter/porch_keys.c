#include "porch_keys.h"

uint8_t porch_key_for_event(const c2j_event *event) {
    if (event->kind == C2J_HANG_UP) return PORCH_KEY_RECEIVER_HANG_UP;
    if (event->kind != C2J_DIGIT) return 0;
    char symbol = event->symbol;
    if (symbol >= '1' && symbol <= '9') return (uint8_t)(PORCH_KEY_KEYPAD_1 + (symbol - '1'));
    if (symbol == '0') return PORCH_KEY_KEYPAD_0;
    if (symbol == '*') return PORCH_KEY_KEYPAD_STAR;
    if (symbol == '#') return PORCH_KEY_KEYPAD_HASH;
    return 0;
}
