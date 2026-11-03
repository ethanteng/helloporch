#include "cell2jack_parser.h"

#include <string.h>

// Hand-written matchers for the regular expressions in Cell2JackDTMFParser.swift.
// Each pattern's character classes don't overlap where they meet, so a single
// left-to-right scan finds the same match the regular expression would.

static bool is_blank(uint8_t c) { return c == ' ' || c == '\t'; }
static bool is_number(uint8_t c) { return c >= '0' && c <= '9'; }
static bool is_symbol(uint8_t c) { return is_number(c) || c == '*' || c == '#' || (c >= 'A' && c <= 'D'); }
static bool is_upper_or_underscore(uint8_t c) { return (c >= 'A' && c <= 'Z') || c == '_'; }

static bool has_at(const uint8_t *s, size_t n, size_t at, const char *word) {
    size_t length = strlen(word);
    return at <= n && n - at >= length && memcmp(s + at, word, length) == 0;
}

static bool contains(const uint8_t *s, size_t n, const char *word) {
    for (size_t at = 0; at < n; at++) if (has_at(s, n, at, word)) return true;
    return false;
}

// (DTMF|RX Double DTMF|Double DTMF) at `at`. At most one can start at a given place.
static bool label_at(const uint8_t *s, size_t n, size_t at, size_t *end, bool *plain) {
    static const char *labels[] = {"DTMF", "RX Double DTMF", "Double DTMF"};
    for (size_t i = 0; i < sizeof labels / sizeof labels[0]; i++) {
        if (has_at(s, n, at, labels[i])) {
            *end = at + strlen(labels[i]);
            *plain = i == 0;
            return true;
        }
    }
    return false;
}

static size_t skip(const uint8_t *s, size_t n, size_t at, bool (*kind)(uint8_t)) {
    while (at < n && kind(s[at])) at++;
    return at;
}

// ^[ \t]*(label)[ \t]+([0-9*#ABCD])(?=[ \t:]|$)
static bool primary_record(const uint8_t *s, size_t n, char *symbol, bool *plain) {
    size_t at = skip(s, n, 0, is_blank), end;
    if (!label_at(s, n, at, &end, plain)) return false;
    at = skip(s, n, end, is_blank);
    if (at == end || at >= n || !is_symbol(s[at])) return false;
    if (at + 1 < n && !is_blank(s[at + 1]) && s[at + 1] != ':') return false;
    *symbol = (char)s[at];
    return true;
}

// From `at`: (label)[ \t]+([0-9*#ABCD])[ \t]*:[0-9]+[ \t]+[0-9]+[ \t]*:[ \t]*[0-9]+[ \t]*$
static bool embedded_record_from(const uint8_t *s, size_t n, size_t at, char *symbol, bool *plain) {
    size_t end, next;
    if (!label_at(s, n, at, &end, plain)) return false;
    at = skip(s, n, end, is_blank);
    if (at == end || at >= n || !is_symbol(s[at])) return false;
    *symbol = (char)s[at];
    at = skip(s, n, at + 1, is_blank);
    if (at >= n || s[at] != ':') return false;
    next = skip(s, n, at + 1, is_number);
    if (next == at + 1) return false;
    at = skip(s, n, next, is_blank);
    if (at == next) return false;
    next = skip(s, n, at, is_number);
    if (next == at) return false;
    at = skip(s, n, next, is_blank);
    if (at >= n || s[at] != ':') return false;
    at = skip(s, n, at + 1, is_blank);
    next = skip(s, n, at, is_number);
    if (next == at) return false;
    return skip(s, n, next, is_blank) == n;
}

// The full keypad capture contains " Cal DTMF 1 :0 20: 2": firmware capture
// joined a status fragment to a genuine event. Recover only the observed
// numeric record shape, not arbitrary mentions of a digit. (?:^|[ \t]) before it.
static bool embedded_record(const uint8_t *s, size_t n, char *symbol, bool *plain) {
    for (size_t at = 0; at < n; at++) {
        if (at == 0 && embedded_record_from(s, n, 0, symbol, plain)) return true;
        if (is_blank(s[at]) && embedded_record_from(s, n, at + 1, symbol, plain)) return true;
    }
    return false;
}

// (?:^|[^A-Z_])ON_HOOK(?:[^A-Z_]|$)
static bool hang_up_line(const uint8_t *s, size_t n) {
    for (size_t at = 0; at < n; at++) {
        if (!has_at(s, n, at, "ON_HOOK")) continue;
        bool starts = at == 0 || !is_upper_or_underscore(s[at - 1]);
        bool ends = at + 7 == n || !is_upper_or_underscore(s[at + 7]);
        if (starts && ends) return true;
    }
    return false;
}

static void parse_line(c2j_parser *parser, const uint8_t *s, size_t n, c2j_event_handler handler, void *context) {
    for (size_t i = 0; i < n; i++) if (s[i] > 0x7f) return; // not ASCII, like String(data:encoding: .ascii)
    if (contains(s, n, "ON_HOOK") || contains(s, n, "OFF_HOOK")) parser->pulse_digit_pending = false;
    if (contains(s, n, "Get PULSE")) parser->pulse_digit_pending = true;
    char symbol = 0;
    bool plain = false, embedded = false;
    bool found = primary_record(s, n, &symbol, &plain);
    if (!found) found = embedded = embedded_record(s, n, &symbol, &plain);
    if (found) {
        c2j_event event = {plain ? C2J_DIGIT : C2J_DOUBLE_REPORT, symbol, embedded};
        if (event.kind == C2J_DIGIT && parser->pulse_digit_pending) {
            event.kind = C2J_PULSE;
            parser->pulse_digit_pending = false;
        }
        handler(&event, context);
        parser->handset_lifted = true;
    }
    // A hang-up joined to a key's line came after the key.
    if (contains(s, n, "OFF_HOOK")) {
        parser->handset_lifted = true;
    } else if (hang_up_line(s, n)) {
        if (parser->handset_lifted) {
            c2j_event event = {C2J_HANG_UP, 0, false};
            handler(&event, context);
        }
        parser->handset_lifted = false;
    }
}

void c2j_parser_init(c2j_parser *parser) { memset(parser, 0, sizeof *parser); }

void c2j_parser_reset_partial_line(c2j_parser *parser) {
    parser->length = 0;
    parser->dropping = false;
}

// Byte-oriented framing preserves fragmented lines and never combines an
// overlong/binary line's suffix with the next line to invent a keypad event.
void c2j_parser_append(c2j_parser *parser, const uint8_t *bytes, size_t count,
                       c2j_event_handler handler, void *context) {
    for (size_t i = 0; i < count; i++) {
        uint8_t byte = bytes[i];
        if (byte == '\n' || byte == '\r') {
            if (!parser->dropping && parser->length) parse_line(parser, parser->line, parser->length, handler, context);
            c2j_parser_reset_partial_line(parser);
        } else if (!parser->dropping) {
            if (parser->length == C2J_MAX_LINE) {
                parser->length = 0;
                parser->dropping = true;
            } else {
                parser->line[parser->length++] = byte;
            }
        }
    }
}
