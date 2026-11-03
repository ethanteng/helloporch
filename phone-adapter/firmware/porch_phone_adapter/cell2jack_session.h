#pragma once
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// When to configure the Cell2Jack and turn its debug log on, following the
// sequence the iPad driver proved on hardware (ios/CELL2JACK-CALLS.md): /v,
// read its reply, wait 500 ms, then /d. If /d brings no bytes within two
// seconds, send /q and try again, three times in all, then wait 1, 2, 4, 8,
// then 15 seconds before the next round. Thirty seconds of a working log reset
// the wait. Times are milliseconds from any free-running clock; they may wrap.
typedef enum {
    C2J_SESSION_DETACHED,
    C2J_SESSION_CONFIGURING, // setting 2,000,000 baud with DTR and RTS off
    C2J_SESSION_VERSION,     // sent /v, waiting for its reply
    C2J_SESSION_SETTLING,    // the 500 ms before /d
    C2J_SESSION_ENABLING,    // sent /d, waiting for log bytes
    C2J_SESSION_STOPPING,    // sent /q after silence, pausing before /v again
    C2J_SESSION_LOGGING,     // working: keys arrive in the log
    C2J_SESSION_WAITING,     // backing off after a failed round
} c2j_session_state;

typedef enum {
    C2J_DO_NOTHING,
    C2J_DO_CONFIGURE,
    C2J_DO_SEND_VERSION, // write "/v"
    C2J_DO_SEND_LOGS_ON, // write "/d"
    C2J_DO_SEND_LOGS_OFF, // write "/q"
} c2j_session_action;

typedef struct {
    c2j_session_state state;
    c2j_session_action due;
    uint32_t since;
    uint32_t wait;
    uint32_t next_wait;
    uint8_t attempts;
    bool received;
    bool line_ended;
} c2j_session;

void c2j_session_init(c2j_session *session);
void c2j_session_attached(c2j_session *session, uint32_t now);
void c2j_session_detached(c2j_session *session);
// The configuration started by C2J_DO_CONFIGURE finished.
void c2j_session_configured(c2j_session *session, uint32_t now, bool succeeded);
// A write or other USB request failed: start over after the backoff.
void c2j_session_failed(c2j_session *session, uint32_t now);
void c2j_session_received(c2j_session *session, uint32_t now, const uint8_t *bytes, size_t count);
// Call often. Returns each action once, when it's due.
c2j_session_action c2j_session_poll(c2j_session *session, uint32_t now);

#ifdef __cplusplus
}
#endif
