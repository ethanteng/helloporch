#include "cell2jack_session.h"

#include <string.h>

enum {
    CONFIGURE_TIMEOUT = 2000,
    VERSION_TIMEOUT = 3000, // the driver reads for up to six 500 ms windows
    SETTLE = 500,
    ENABLE_SILENCE = 2000,
    STOP_PAUSE = 250,
    ENABLE_ATTEMPTS = 3,
    FIRST_WAIT = 1000,
    LONGEST_WAIT = 15000,
    RESPONSIVE = 30000,
};

static void enter(c2j_session *session, c2j_session_state state, uint32_t now, c2j_session_action due) {
    session->state = state;
    session->since = now;
    session->due = due;
    session->received = false;
    session->line_ended = false;
}

void c2j_session_init(c2j_session *session) {
    memset(session, 0, sizeof *session);
    session->next_wait = FIRST_WAIT;
}

void c2j_session_attached(c2j_session *session, uint32_t now) {
    c2j_session_init(session);
    enter(session, C2J_SESSION_CONFIGURING, now, C2J_DO_CONFIGURE);
}

void c2j_session_detached(c2j_session *session) { c2j_session_init(session); }

void c2j_session_failed(c2j_session *session, uint32_t now) {
    if (session->state == C2J_SESSION_DETACHED) return;
    session->wait = session->next_wait;
    session->next_wait = session->next_wait * 2 > LONGEST_WAIT ? LONGEST_WAIT : session->next_wait * 2;
    enter(session, C2J_SESSION_WAITING, now, C2J_DO_NOTHING);
}

void c2j_session_configured(c2j_session *session, uint32_t now, bool succeeded) {
    if (session->state != C2J_SESSION_CONFIGURING) return;
    if (!succeeded) {
        c2j_session_failed(session, now);
        return;
    }
    session->attempts = 0;
    enter(session, C2J_SESSION_VERSION, now, C2J_DO_SEND_VERSION);
}

void c2j_session_received(c2j_session *session, uint32_t now, const uint8_t *bytes, size_t count) {
    if (!count || session->state == C2J_SESSION_DETACHED) return;
    session->received = true;
    if (session->state == C2J_SESSION_VERSION && memchr(bytes, '\n', count)) session->line_ended = true;
    // Any byte counts as the log starting, as in the app; /d has no acknowledgement.
    if (session->state == C2J_SESSION_ENABLING) enter(session, C2J_SESSION_LOGGING, now, C2J_DO_NOTHING);
}

c2j_session_action c2j_session_poll(c2j_session *session, uint32_t now) {
    uint32_t elapsed = now - session->since;
    switch (session->state) {
        case C2J_SESSION_CONFIGURING:
            if (session->due == C2J_DO_NOTHING && elapsed >= CONFIGURE_TIMEOUT) c2j_session_failed(session, now);
            break;
        case C2J_SESSION_VERSION:
            // A partial reply still shows the Cell2Jack is answering, as in the driver.
            if (session->line_ended || (elapsed >= VERSION_TIMEOUT && session->received)) {
                enter(session, C2J_SESSION_SETTLING, now, C2J_DO_NOTHING);
            } else if (elapsed >= VERSION_TIMEOUT) {
                c2j_session_failed(session, now);
            }
            break;
        case C2J_SESSION_SETTLING:
            if (elapsed >= SETTLE) enter(session, C2J_SESSION_ENABLING, now, C2J_DO_SEND_LOGS_ON);
            break;
        case C2J_SESSION_ENABLING:
            if (session->due == C2J_DO_NOTHING && elapsed >= ENABLE_SILENCE) {
                session->attempts++;
                enter(session, C2J_SESSION_STOPPING, now, C2J_DO_SEND_LOGS_OFF);
            }
            break;
        case C2J_SESSION_STOPPING:
            if (session->due == C2J_DO_NOTHING && elapsed >= STOP_PAUSE) {
                if (session->attempts < ENABLE_ATTEMPTS) enter(session, C2J_SESSION_VERSION, now, C2J_DO_SEND_VERSION);
                else c2j_session_failed(session, now);
            }
            break;
        case C2J_SESSION_LOGGING:
            if (elapsed >= RESPONSIVE) session->next_wait = FIRST_WAIT;
            break;
        case C2J_SESSION_WAITING:
            if (elapsed >= session->wait) enter(session, C2J_SESSION_CONFIGURING, now, C2J_DO_CONFIGURE);
            break;
        case C2J_SESSION_DETACHED:
            break;
    }
    c2j_session_action due = session->due;
    if (due != C2J_DO_NOTHING) {
        // Timeouts count from when the action goes out, not from when it was scheduled.
        session->due = C2J_DO_NOTHING;
        session->since = now;
    }
    return due;
}
