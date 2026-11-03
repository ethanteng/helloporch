// Porch phone adapter: makes a Cell2Jack look like a USB keypad, so a
// big-button phone works with any iPad and the TestFlight build, with no
// DriverKit driver. Runs on an Adafruit Feather RP2040 with USB Type A Host:
// the Cell2Jack plugs into its USB-A port, and its USB-C port goes to the
// iPad's hub. Build and flash with phone-adapter/build.sh; see the README.
//
// Core 1 owns the USB-A host port: it configures the Cell2Jack, turns on its
// debug log and parses key presses out of it. Core 0 owns the USB-C device
// port: it types each key into the iPad as a keypad key, and F24 when the
// receiver goes back on the cradle. Nothing else crosses between the cores.

// First, so the build finds Pico PIO USB before TinyUSB checks for it with
// __has_include; otherwise TinyUSB builds for a MAX3421E host chip instead.
#include "pio_usb.h"
#include "Adafruit_TinyUSB.h"
#include "pico/util/queue.h"

#include "cell2jack_parser.h"
#include "cell2jack_session.h"
#include "porch_keys.h"

// Set to 0 if an iPad refuses the adapter because of its serial port. The
// serial port only carries this log, for a Mac during bring-up.
#define PORCH_ADAPTER_SERIAL_LOG 1

static const uint16_t CELL2JACK_VENDOR = 0x1a86, CELL2JACK_PRODUCT = 0x7523;
static const uint32_t CELL2JACK_BAUD = 2000000;
static const uint8_t NO_CELL2JACK = 0xff;

static const uint32_t KEY_HOLD_MS = 40, KEY_GAP_MS = 40;
// Porch ignores Cell2Jack keys more than a second old; so does the adapter.
static const uint32_t KEY_STALE_MS = 1000;

typedef struct {
    uint8_t key;
    uint32_t at;
} typed_key;

typedef enum : uint8_t { STATUS_NO_CELL2JACK, STATUS_CONNECTING, STATUS_READY } adapter_status;

static queue_t keys;
#if PORCH_ADAPTER_SERIAL_LOG
static queue_t log_bytes;
#endif
static volatile bool queues_ready = false;
static volatile adapter_status status = STATUS_NO_CELL2JACK;

//------------- Core 0: the keyboard the iPad sees -------------//

static const uint8_t hid_report_descriptor[] = {TUD_HID_REPORT_DESC_KEYBOARD()};
static Adafruit_USBD_HID keyboard;

void setup() {
    queue_init(&keys, sizeof(typed_key), 16);
#if PORCH_ADAPTER_SERIAL_LOG
    queue_init(&log_bytes, 1, 2048);
#endif
    queues_ready = true;

    if (!TinyUSBDevice.isInitialized()) TinyUSBDevice.begin(0);
#if !PORCH_ADAPTER_SERIAL_LOG
    TinyUSBDevice.clearConfiguration();
#endif
    TinyUSBDevice.setManufacturerDescriptor("Porch");
    TinyUSBDevice.setProductDescriptor("Porch Phone Adapter");
    keyboard.setBootProtocol(HID_ITF_PROTOCOL_KEYBOARD);
    keyboard.setPollInterval(2);
    keyboard.setReportDescriptor(hid_report_descriptor, sizeof hid_report_descriptor);
    keyboard.setStringDescriptor("Porch Phone Adapter");
    keyboard.begin();
#if PORCH_ADAPTER_SERIAL_LOG
    Serial.begin(115200);
#endif
    // Enumerate again so the iPad sees the keyboard added above.
    if (TinyUSBDevice.mounted()) {
        TinyUSBDevice.detach();
        delay(10);
        TinyUSBDevice.attach();
    }
    pinMode(PIN_LED, OUTPUT);
    digitalWrite(PIN_LED, LOW);
}

static uint32_t last_key_shown;

// One key at a time: press, hold briefly, release, and a short gap, so the
// iPad sees two presses of the same key as two presses.
static void type_keys() {
    static bool pressed = false, waiting = false;
    static uint32_t changed_at;
    static typed_key next;
    uint32_t now = millis();
    if (pressed) {
        if (now - changed_at >= KEY_HOLD_MS && keyboard.ready()) {
            keyboard.keyboardRelease(0);
            pressed = false;
            changed_at = now;
        }
        return;
    }
    if (now - changed_at < KEY_GAP_MS) return;
    if (!waiting) waiting = queue_try_remove(&keys, &next);
    if (!waiting) return;
    if (now - next.at > KEY_STALE_MS || !TinyUSBDevice.mounted()) {
        waiting = false;
#if PORCH_ADAPTER_SERIAL_LOG
        Serial.printf("[adapter] dropped key 0x%02x: %s\r\n", next.key, TinyUSBDevice.mounted() ? "too old" : "no iPad");
#endif
        return;
    }
    if (!keyboard.ready()) return;
    uint8_t report[6] = {next.key};
    keyboard.keyboardReport(0, 0, report);
    pressed = true;
    waiting = false;
    changed_at = last_key_shown = now;
#if PORCH_ADAPTER_SERIAL_LOG
    Serial.printf("[adapter] typed key 0x%02x\r\n", next.key);
#endif
}

// The red LED: off with no Cell2Jack, blinking while connecting, on when keys
// will work, with a short flicker for each key typed.
static void show_status() {
    uint32_t now = millis();
    adapter_status current = status;
    bool on = current == STATUS_READY || (current == STATUS_CONNECTING && (now / 500) % 2 == 0);
    if (now - last_key_shown < 100) on = !on;
    digitalWrite(PIN_LED, on ? HIGH : LOW);
#if PORCH_ADAPTER_SERIAL_LOG
    static adapter_status shown = STATUS_NO_CELL2JACK;
    if (current != shown) {
        static const char *names[] = {"no Cell2Jack", "connecting to the Cell2Jack", "ready"};
        Serial.printf("[adapter] %s\r\n", names[current]);
        shown = current;
    }
#endif
}

#if PORCH_ADAPTER_SERIAL_LOG
static void echo_log() {
    uint8_t buffer[64];
    size_t count = 0;
    while (count < sizeof buffer && queue_try_remove(&log_bytes, &buffer[count])) count++;
    if (count) Serial.write(buffer, count);
}
#endif

void loop() {
#ifdef TINYUSB_NEED_POLLING_TASK
    TinyUSBDevice.task();
#endif
    type_keys();
    show_status();
#if PORCH_ADAPTER_SERIAL_LOG
    echo_log();
#endif
}

//------------- Core 1: the Cell2Jack -------------//

static Adafruit_USBH_Host host;
static uint8_t cell2jack = NO_CELL2JACK; // its CDC interface index
static c2j_session session;
static c2j_parser parser;

void setup1() {
    while (!queues_ready) tight_loop_contents();
    c2j_session_init(&session);
    c2j_parser_init(&parser);
    // Power the USB-A port, then run the host port in software. PIO USB needs a
    // CPU clock that's a multiple of 12 MHz; build.sh selects 120 MHz.
    pinMode(PIN_5V_EN, OUTPUT);
    digitalWrite(PIN_5V_EN, HIGH);
    pio_usb_configuration_t pio = PIO_USB_DEFAULT_CONFIG;
    pio.pin_dp = PIN_USB_HOST_DP;
    host.configure_pio_usb(1, &pio);
    host.begin(1);
}

static void send_key(const c2j_event *event, void *) {
    uint8_t key = porch_key_for_event(event);
    if (!key) return;
    typed_key typed = {key, millis()};
    queue_try_add(&keys, &typed);
}

enum { CONFIGURE_LINES, CONFIGURE_BAUD, CONFIGURE_FORMAT };

// The iPad driver's settings, in three steps: DTR and RTS off, 2,000,000
// baud, then 8N1. TinyUSB's CH34x driver writes the same baud register the
// driver does (0xfd83 on the Cell2Jack's chip revision 0x31).
static void configure_step(tuh_xfer_t *xfer) {
    if (session.state != C2J_SESSION_CONFIGURING || cell2jack == NO_CELL2JACK) return;
    bool ok = xfer->result == XFER_RESULT_SUCCESS;
    if (ok && xfer->user_data == CONFIGURE_LINES) {
        if (tuh_cdc_set_baudrate(cell2jack, CELL2JACK_BAUD, configure_step, CONFIGURE_BAUD)) return;
        ok = false;
    } else if (ok && xfer->user_data == CONFIGURE_BAUD) {
        if (tuh_cdc_set_data_format(cell2jack, CDC_LINE_CODING_STOP_BITS_1, CDC_LINE_CODING_PARITY_NONE, 8,
                                    configure_step, CONFIGURE_FORMAT)) return;
        ok = false;
    }
    c2j_session_configured(&session, millis(), ok);
}

// Only the literal two-byte commands the driver sends: /v, /d and /q.
static bool send_command(char command) {
    const uint8_t bytes[2] = {'/', (uint8_t)command};
    bool written = tuh_cdc_write(cell2jack, bytes, sizeof bytes) == sizeof bytes;
    tuh_cdc_write_flush(cell2jack);
    return written;
}

static void perform(c2j_session_action action) {
    bool ok = true;
    switch (action) {
        case C2J_DO_NOTHING: return;
        case C2J_DO_CONFIGURE:
            if (!tuh_cdc_set_control_line_state(cell2jack, 0, configure_step, CONFIGURE_LINES))
                c2j_session_configured(&session, millis(), false);
            return;
        case C2J_DO_SEND_VERSION: ok = send_command('v'); break;
        case C2J_DO_SEND_LOGS_ON: ok = send_command('d'); break;
        case C2J_DO_SEND_LOGS_OFF: ok = send_command('q'); break;
    }
    if (!ok) c2j_session_failed(&session, millis());
}

void loop1() {
    host.task();
    if (cell2jack != NO_CELL2JACK) {
        uint8_t bytes[64];
        uint32_t count;
        while ((count = tuh_cdc_read(cell2jack, bytes, sizeof bytes)) > 0) {
            c2j_session_received(&session, millis(), bytes, count);
            c2j_parser_append(&parser, bytes, count, send_key, NULL);
#if PORCH_ADAPTER_SERIAL_LOG
            for (uint32_t i = 0; i < count; i++) queue_try_add(&log_bytes, &bytes[i]);
#endif
        }
        perform(c2j_session_poll(&session, millis()));
    }
    status = session.state == C2J_SESSION_DETACHED ? STATUS_NO_CELL2JACK
           : session.state == C2J_SESSION_LOGGING  ? STATUS_READY
                                                   : STATUS_CONNECTING;
}

// TinyUSB calls these from host.task(), on core 1. Any other device on the
// USB-A port, including other CH34x adapters with a different product ID, is
// left alone.
extern "C" void tuh_cdc_mount_cb(uint8_t idx) {
    tuh_itf_info_t info;
    uint16_t vendor = 0, product = 0;
    if (cell2jack != NO_CELL2JACK || !tuh_cdc_itf_get_info(idx, &info) ||
        !tuh_vid_pid_get(info.daddr, &vendor, &product) ||
        vendor != CELL2JACK_VENDOR || product != CELL2JACK_PRODUCT) return;
    cell2jack = idx;
    c2j_parser_init(&parser);
    c2j_session_attached(&session, millis());
}

extern "C" void tuh_cdc_umount_cb(uint8_t idx) {
    if (idx != cell2jack) return;
    cell2jack = NO_CELL2JACK;
    c2j_session_detached(&session);
}
