// Host tests for the adapter's parser, keys and session. The parser cases mirror
// ios/Cell2JackDriverTests/DTMFParserTests.swift, so both parsers answer alike.
// Run with phone-adapter/test.sh; pass a raw capture to replay it as well.
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "cell2jack_parser.h"
#include "cell2jack_session.h"
#include "porch_keys.h"

#define CHECK(condition)                                                          \
    do {                                                                          \
        if (!(condition)) {                                                       \
            fprintf(stderr, "%s:%d: check failed: %s\n", __FILE__, __LINE__, #condition); \
            exit(1);                                                              \
        }                                                                         \
    } while (0)

typedef struct {
    c2j_event events[64];
    size_t count;
} collected;

static void collect(const c2j_event *event, void *context) {
    collected *into = context;
    CHECK(into->count < 64);
    into->events[into->count++] = *event;
}

static collected feed(c2j_parser *parser, const char *text, size_t length) {
    collected result = {0};
    c2j_parser_append(parser, (const uint8_t *)text, length, collect, &result);
    return result;
}

static collected feed_text(c2j_parser *parser, const char *text) { return feed(parser, text, strlen(text)); }

// Every way of splitting `text` into two reads gives the same events.
static collected feed_split(const char *text, size_t split) {
    c2j_parser parser;
    c2j_parser_init(&parser);
    collected first = feed(&parser, text, split), second = feed(&parser, text + split, strlen(text) - split);
    for (size_t i = 0; i < second.count; i++) first.events[first.count++] = second.events[i];
    return first;
}

static void symbols(const collected *events, char *out) {
    for (size_t i = 0; i < events->count; i++) out[i] = events->events[i].symbol;
    out[events->count] = 0;
}

static bool symbols_are(const collected *events, const char *expected) {
    char actual[65];
    symbols(events, actual);
    return strcmp(actual, expected) == 0;
}

static bool kinds_are(const collected *events, const c2j_kind *expected, size_t count) {
    if (events->count != count) return false;
    for (size_t i = 0; i < count; i++) if (events->events[i].kind != expected[i]) return false;
    return true;
}

static void test_parser(void) {
    const char *observed = " DTMF 1 :0 20: 2\r\n DTMF 2 :1 20: 2\r\n DTMF 3 :2 20: 2\r\n DTMF 0 :3 20: 2\r\n DTMF * :4 20: 2\r\n DTMF # :0 20: 2\r\n";
    for (size_t split = 0; split <= strlen(observed); split++) {
        collected events = feed_split(observed, split);
        CHECK(symbols_are(&events, "1230*#"));
        for (size_t i = 0; i < events.count; i++) CHECK(events.events[i].kind == C2J_DIGIT);
    }
    c2j_parser bytewise;
    c2j_parser_init(&bytewise);
    collected digits = {0};
    for (size_t i = 0; i < strlen(observed); i++) c2j_parser_append(&bytewise, (const uint8_t *)observed + i, 1, collect, &digits);
    CHECK(symbols_are(&digits, "1230*#"));

    c2j_parser parser;
    c2j_parser_init(&parser);
    collected repeats = feed_text(&parser, "DTMF 5 :0\nDTMF 5 :1\nDouble DTMF 5\rRX Double DTMF 5\n");
    CHECK(symbols_are(&repeats, "5555"));
    c2j_kind repeat_kinds[] = {C2J_DIGIT, C2J_DIGIT, C2J_DOUBLE_REPORT, C2J_DOUBLE_REPORT};
    CHECK(kinds_are(&repeats, repeat_kinds, 4));
    const char *config = "DTMF=1, DTMFO=2\nUnknown DTMF key 1\nDTMFIS=0\nCJ Version = a06\nDTMF 12\nDTMF X\nnot DTMF 1\n";
    CHECK(feed_text(&parser, config).count == 0);
    const char *keys = "0123456789*#ABCD";
    char every_key[128] = "";
    for (const char *key = keys; *key; key++) {
        size_t at = strlen(every_key);
        snprintf(every_key + at, sizeof every_key - at, "DTMF %c\r", *key);
    }
    collected all = feed_text(&parser, every_key);
    CHECK(symbols_are(&all, keys));
    CHECK(feed_text(&parser, "DTMF 9").count == 0);
    c2j_parser_reset_partial_line(&parser);
    CHECK(feed_text(&parser, " :0\n").count == 0);

    static char oversized[4097 + 32];
    memset(oversized, ' ', 4097);
    strcpy(oversized + 4097, "DTMF 8\nDTMF 7\r\n");
    collected after_overflow = feed_text(&parser, oversized);
    CHECK(symbols_are(&after_overflow, "7"));
    const char binary[] = "\xff" "DTMF 1\n";
    CHECK(feed(&parser, binary, sizeof binary - 1).count == 0);
    collected four = feed_text(&parser, "DTMF 4\r");
    CHECK(symbols_are(&four, "4"));
    CHECK(feed_text(&parser, "\n").count == 0);

    const char *joined = " Cal DTMF 1 :0 20: 2\r\n";
    for (size_t split = 0; split <= strlen(joined); split++) {
        collected recovered = feed_split(joined, split);
        CHECK(symbols_are(&recovered, "1"));
        CHECK(recovered.events[0].embedded_in_line);
    }
    collected diagnostic = feed_text(&parser, " Cal RX Double DTMF 1 :0 20: 2\n");
    CHECK(diagnostic.count == 1 && diagnostic.events[0].kind == C2J_DOUBLE_REPORT);
    CHECK(feed_text(&parser, "status mentions DTMF 1\nUnknown DTMF key 1\nstatus DTMF 12 :0 20: 2\n").count == 0);

    // Captured from the bedside's picture phone: the first pickup after reconnecting
    // Cell2Jack broke the line once, which it counted as a pulse-dialed 1. The next
    // pickup's 0 is a real key press.
    const char *pickups = "L1L2 OFF_HOOK \r\n Set OFF-hook 230\r\n Play tone\r\nH1H2L1L2 FLASH \r\n Set OFF-hook 230\r\n.. Get PULSE 1 1\r\n Stop Playing Dialtone\r\n DTMF 1 :0 20: 2\r\nH1H2.Loop 1: Null Addr\r\n ON_HOOK \r\nL1L2 OFF_HOOK \r\n Play tone\r\n Stop Playing Audio\r\n DTMF 0 :0 20: 2\r\nH1H2 ON_HOOK \r\n";
    c2j_kind pickup_kinds[] = {C2J_PULSE, C2J_HANG_UP, C2J_DIGIT, C2J_HANG_UP};
    for (size_t split = 0; split <= strlen(pickups); split++) {
        collected events = feed_split(pickups, split);
        CHECK(kinds_are(&events, pickup_kinds, 4));
        CHECK(events.events[0].symbol == '1' && events.events[2].symbol == '0');
    }
    c2j_parser stale;
    c2j_parser_init(&stale);
    collected after_stale = feed_text(&stale, ".. Get PULSE 1 1\r\n ON_HOOK \r\nL1L2 OFF_HOOK \r\n DTMF 3 :0 20: 2\r\n");
    c2j_kind digit_kind[] = {C2J_DIGIT};
    CHECK(kinds_are(&after_stale, digit_kind, 1));

    // Captured when Cell2Jack was plugged back in: it reports ON_HOOK as it starts, with no
    // pickup before it. Only putting the receiver back after a pickup is a hang-up.
    c2j_parser hooks;
    c2j_parser_init(&hooks);
    CHECK(feed_text(&hooks, " ON_HOOK \r\n Set ON-hook 121\r\n Set Ring = 0\r\n Set ON-hook 121\r\n--Cell2Jack CopyRight00\r\n").count == 0);
    collected lifted = feed_text(&hooks, "L1L2 OFF_HOOK \r\nH1H2L1L2 FLASH \r\n Set OFF-hook 230\r\nH1H2 ON_HOOK \r\n Set ON-hook 121\r\n ON_HOOK \r\n");
    c2j_kind hang_up_kind[] = {C2J_HANG_UP};
    CHECK(kinds_are(&lifted, hang_up_kind, 1) && lifted.events[0].symbol == 0);
    collected joined_hang_up = feed_text(&hooks, "L1L2 OFF_HOOK \r\nNON_HOOKED\r\n DTMF 0 :0 20: 2 H1H2 ON_HOOK \r\n");
    c2j_kind digit_then_hang_up[] = {C2J_DIGIT, C2J_HANG_UP};
    CHECK(kinds_are(&joined_hang_up, digit_then_hang_up, 2));
    // Logs that start with the receiver already up: a key press shows it was off the cradle.
    c2j_parser started_lifted;
    c2j_parser_init(&started_lifted);
    collected early = feed_text(&started_lifted, " DTMF 5 :0 20: 2\r\nH1H2 ON_HOOK \r\n ON_HOOK \r\n");
    CHECK(kinds_are(&early, digit_then_hang_up, 2));
    puts("Parser: same results as DTMFParserTests.swift");
}

static void test_keys(void) {
    const char *symbols_in = "1234567890*#";
    const uint8_t expected[] = {0x59, 0x5a, 0x5b, 0x5c, 0x5d, 0x5e, 0x5f, 0x60, 0x61, 0x62, 0x55, 0xcc};
    for (size_t i = 0; i < 12; i++) {
        c2j_event event = {C2J_DIGIT, symbols_in[i], false};
        CHECK(porch_key_for_event(&event) == expected[i]);
    }
    c2j_event hang_up = {C2J_HANG_UP, 0, false};
    CHECK(porch_key_for_event(&hang_up) == 0x73);
    c2j_event ignored[] = {{C2J_PULSE, '1', false}, {C2J_DOUBLE_REPORT, '5', false}, {C2J_DIGIT, 'A', false}, {C2J_DIGIT, 'D', false}};
    for (size_t i = 0; i < 4; i++) CHECK(porch_key_for_event(&ignored[i]) == 0);
    puts("Keys: keypad digits, * and #, F24 for hang-up, nothing for pulses, repeats or A–D");
}

static void receive(c2j_session *session, uint32_t now, const char *text) {
    c2j_session_received(session, now, (const uint8_t *)text, strlen(text));
}

static void test_session(void) {
    c2j_session session;
    c2j_session_init(&session);
    CHECK(c2j_session_poll(&session, 0) == C2J_DO_NOTHING);
    receive(&session, 0, "stray"); // nothing attached yet
    CHECK(session.state == C2J_SESSION_DETACHED);

    // The proven sequence: configure, /v, its reply, 500 ms, /d, log bytes.
    c2j_session_attached(&session, 100);
    CHECK(c2j_session_poll(&session, 100) == C2J_DO_CONFIGURE);
    CHECK(c2j_session_poll(&session, 101) == C2J_DO_NOTHING);
    c2j_session_configured(&session, 120, true);
    CHECK(c2j_session_poll(&session, 120) == C2J_DO_SEND_VERSION);
    receive(&session, 130, " >>>>>>>>>>>>>> CJ Version = a06");
    CHECK(c2j_session_poll(&session, 140) == C2J_DO_NOTHING && session.state == C2J_SESSION_VERSION);
    receive(&session, 150, "\r\n");
    CHECK(c2j_session_poll(&session, 150) == C2J_DO_NOTHING && session.state == C2J_SESSION_SETTLING);
    CHECK(c2j_session_poll(&session, 649) == C2J_DO_NOTHING);
    CHECK(c2j_session_poll(&session, 650) == C2J_DO_SEND_LOGS_ON);
    receive(&session, 900, "L1L2 OFF_HOOK \r\n");
    CHECK(session.state == C2J_SESSION_LOGGING);
    CHECK(c2j_session_poll(&session, 100000) == C2J_DO_NOTHING && session.state == C2J_SESSION_LOGGING);

    // Silence after /d: /q, then /v again, three attempts in all, then back off 1, 2, 4, 8, 15, 15 s.
    c2j_session_attached(&session, 0);
    uint32_t now = 0;
    const uint32_t waits[] = {1000, 2000, 4000, 8000, 15000, 15000};
    for (size_t round = 0; round < 6; round++) {
        CHECK(c2j_session_poll(&session, now) == C2J_DO_CONFIGURE);
        c2j_session_configured(&session, now, true);
        for (int attempt = 1; attempt <= 3; attempt++) {
            CHECK(c2j_session_poll(&session, now) == C2J_DO_SEND_VERSION);
            receive(&session, now, "CJ Version = a06\r\n");
            CHECK(c2j_session_poll(&session, now) == C2J_DO_NOTHING);
            now += 500;
            CHECK(c2j_session_poll(&session, now) == C2J_DO_SEND_LOGS_ON);
            CHECK(c2j_session_poll(&session, now + 1999) == C2J_DO_NOTHING);
            now += 2000;
            CHECK(c2j_session_poll(&session, now) == C2J_DO_SEND_LOGS_OFF);
            now += 250;
        }
        CHECK(c2j_session_poll(&session, now) == C2J_DO_NOTHING && session.state == C2J_SESSION_WAITING);
        CHECK(session.wait == waits[round]);
        CHECK(c2j_session_poll(&session, now + waits[round] - 1) == C2J_DO_NOTHING);
        now += waits[round];
    }

    // Thirty seconds of a working log resets the wait.
    CHECK(c2j_session_poll(&session, now) == C2J_DO_CONFIGURE);
    c2j_session_configured(&session, now, true);
    CHECK(c2j_session_poll(&session, now) == C2J_DO_SEND_VERSION);
    receive(&session, now, "\n");
    c2j_session_poll(&session, now);
    CHECK(c2j_session_poll(&session, now + 500) == C2J_DO_SEND_LOGS_ON);
    receive(&session, now + 600, "x");
    CHECK(c2j_session_poll(&session, now + 30600) == C2J_DO_NOTHING);
    c2j_session_failed(&session, now + 30600);
    CHECK(session.wait == 1000);

    // No reply to /v at all, a failed configuration, a configuration that never finishes.
    c2j_session_attached(&session, 0);
    c2j_session_poll(&session, 0);
    c2j_session_configured(&session, 0, true);
    CHECK(c2j_session_poll(&session, 0) == C2J_DO_SEND_VERSION);
    CHECK(c2j_session_poll(&session, 2999) == C2J_DO_NOTHING && session.state == C2J_SESSION_VERSION);
    CHECK(c2j_session_poll(&session, 3000) == C2J_DO_NOTHING && session.state == C2J_SESSION_WAITING);
    // A partial reply that never ends its line still counts, as in the driver.
    c2j_session_attached(&session, 0);
    c2j_session_poll(&session, 0);
    c2j_session_configured(&session, 0, true);
    c2j_session_poll(&session, 0);
    receive(&session, 10, "CJ Vers");
    CHECK(c2j_session_poll(&session, 3000) == C2J_DO_NOTHING && session.state == C2J_SESSION_SETTLING);
    c2j_session_attached(&session, 0);
    c2j_session_poll(&session, 0);
    c2j_session_configured(&session, 5, false);
    CHECK(session.state == C2J_SESSION_WAITING && session.wait == 1000);
    c2j_session_attached(&session, 0);
    CHECK(c2j_session_poll(&session, 0) == C2J_DO_CONFIGURE);
    CHECK(c2j_session_poll(&session, 1999) == C2J_DO_NOTHING && session.state == C2J_SESSION_CONFIGURING);
    CHECK(c2j_session_poll(&session, 2000) == C2J_DO_NOTHING && session.state == C2J_SESSION_WAITING);
    c2j_session_configured(&session, 2001, true); // too late: ignored
    CHECK(session.state == C2J_SESSION_WAITING);

    // Unplugging stops everything; the clock wrapping doesn't confuse the timeouts.
    c2j_session_detached(&session);
    CHECK(c2j_session_poll(&session, 50000) == C2J_DO_NOTHING && session.state == C2J_SESSION_DETACHED);
    c2j_session_failed(&session, 50000);
    CHECK(session.state == C2J_SESSION_DETACHED);
    uint32_t late = UINT32_MAX - 100;
    c2j_session_attached(&session, late);
    c2j_session_poll(&session, late);
    c2j_session_configured(&session, late, true);
    c2j_session_poll(&session, late);
    receive(&session, late, "\n");
    c2j_session_poll(&session, late);
    CHECK(c2j_session_poll(&session, late + 499) == C2J_DO_NOTHING);
    CHECK(c2j_session_poll(&session, late + 500) == C2J_DO_SEND_LOGS_ON);
    puts("Session: proven enable sequence, retries, backoff and reset, timeouts, unplugging, clock wrap");
}

// A saved raw Cell2Jack capture, such as Documents/cell2jack-usb-tail.bin from the
// bedside or keypad-<UUID>/received.bin from the test app. Prints what the adapter would type.
static void replay(const char *path) {
    FILE *file = fopen(path, "rb");
    CHECK(file);
    c2j_parser parser;
    c2j_parser_init(&parser);
    uint8_t buffer[4096];
    size_t read;
    collected events = {0};
    char typed[4096] = "";
    while ((read = fread(buffer, 1, sizeof buffer, file)) > 0) {
        events.count = 0;
        c2j_parser_append(&parser, buffer, read, collect, &events);
        for (size_t i = 0; i < events.count; i++) {
            const c2j_event *event = &events.events[i];
            size_t at = strlen(typed);
            if (at > sizeof typed - 16) break;
            if (event->kind == C2J_HANG_UP) strcat(typed, "[hang up]");
            else if (porch_key_for_event(event)) typed[at] = event->symbol, typed[at + 1] = 0;
        }
    }
    fclose(file);
    printf("%s would type: %s\n", path, typed);
}

int main(int argc, char **argv) {
    test_parser();
    test_keys();
    test_session();
    for (int i = 1; i < argc; i++) replay(argv[i]);
    return 0;
}
