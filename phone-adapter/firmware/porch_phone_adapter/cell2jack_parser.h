#pragma once
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// Reads Cell2Jack's debug log, line by line, with the same rules as Porch's
// Cell2JackDTMFParser.swift (ios/Cell2JackPOC). Keep the two in step: the tests
// in phone-adapter/tests replay the same captures as DTMFParserTests.swift.
typedef enum {
    C2J_DIGIT,         // a key press
    C2J_DOUBLE_REPORT, // a diagnostic repeat of a key press, never an action
    C2J_PULSE,         // a digit counted from hook pulses, such as the phantom 1 on pickup
    C2J_HANG_UP,       // the receiver went back on the cradle
} c2j_kind;

typedef struct {
    c2j_kind kind;
    char symbol; // '0'–'9', '*', '#' or 'A'–'D'; 0 for a hang-up
    bool embedded_in_line;
} c2j_event;

enum { C2J_MAX_LINE = 4096 };

typedef struct {
    uint8_t line[C2J_MAX_LINE];
    size_t length;
    bool dropping;
    // Cell2Jack reports a digit counted from hook pulses as an ordinary DTMF
    // record right after "Get PULSE". A brief line break when the handset is
    // lifted counts as one pulse, so the record that follows is a phantom 1,
    // not a key press. A hook change clears a pulse that never produced one.
    bool pulse_digit_pending;
    // Cell2Jack also reports ON_HOOK as it starts up with the receiver already
    // down. Only a pickup or key press seen in this session makes ON_HOOK a
    // hang-up; keys work only off the cradle.
    bool handset_lifted;
} c2j_parser;

typedef void (*c2j_event_handler)(const c2j_event *event, void *context);

void c2j_parser_init(c2j_parser *parser);
void c2j_parser_reset_partial_line(c2j_parser *parser);
// Bytes may split anywhere, including inside CRLF. Each complete line reports
// at most two events, in order: its key record, then a hang-up.
void c2j_parser_append(c2j_parser *parser, const uint8_t *bytes, size_t count,
                       c2j_event_handler handler, void *context);

#ifdef __cplusplus
}
#endif
