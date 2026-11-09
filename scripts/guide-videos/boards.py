#!/usr/bin/env python3
# Writes one storyboard per guide video. Tap points are in the screenshot's own units (iOS points or Android
# pixels) and become fractions here. Run: python3 -I boards.py <screenshots dir> <output dir>
import json, os, sys

# The renderer reads image paths against the storyboard's own folder, so give it absolute ones.
shots, out = os.path.abspath(sys.argv[1]), sys.argv[2]
os.makedirs(out, exist_ok=True)

IPAD, IPHONE = (1180, 820), (402, 874)
TABLET, PHONE = (2560, 1600), (1080, 2400)

def beat(caption, main, tap=None, size=None, side=None, on="main", label=None):
    b = {"caption": caption, "main": f"{shots}/{main}.png"}
    if side:
        b["side"] = f"{shots}/{side}.png"
    if label:
        b["label"] = label
    if tap:
        w, h = size
        b["tap"] = {"on": on, "x": round(tap[0] / w, 4), "y": round(tap[1] / h, 4)}
    return b

def board(name, layout, label, beats):
    for b in beats:
        b.setdefault("label", label)
    json.dump({"output": f"{name}.mp4", "poster": f"{name}.jpg", "layout": layout, "beats": beats},
              open(f"{out}/{name}.json", "w"), indent=1, ensure_ascii=False)

# iPad and iPhone ------------------------------------------------------------------------------------------------
I = lambda caption, main, tap=None, **k: beat(caption, f"ios/{main}", tap, IPAD, **k)
P = lambda caption, main, tap=None, **k: beat(caption, f"ios/{main}", tap, IPHONE, **k)

board("ios-setup", "tablet", None, [
    I("Install Porch with TestFlight. It appears on the iPad’s Home Screen.", "i00-home", (664, 113), label="Install Porch on the iPad"),
    I("Tap your private setup link on the iPad. Porch opens and asks who it’s for.", "i01-who",
      label="Open your setup link on the iPad"),
    I("Enter the name family members use, then tap Continue.", "i02-who-typed", (590, 337),
      label="Set up your loved one’s Porch"),
    I("Choose a six-digit caregiver PIN. Enter it twice and keep it somewhere safe.", "i04-pin-typed", (590, 437),
      label="Set up your loved one’s Porch"),
    I("Tap Get number to get a phone number for Rose’s Porch.", "i05-number", (590, 277),
      label="Set up your loved one’s Porch"),
    I("When the number appears, tap Continue.", "i06-number-got", (590, 356), label="Set up your loved one’s Porch"),
    I("Tap Continue to turn on the microphone and camera.", "i07-perms", (590, 238),
      label="Set up your loved one’s Porch"),
    I("Allow the microphone, so family can hear Rose.", "i08-perm-mic", (664, 500), label="Set up your loved one’s Porch"),
    I("Allow the camera, so family can see Rose.", "i09-perm-cam", (664, 550), label="Set up your loved one’s Porch"),
    I("Choose Corded phone.", "i10-how", (590, 249), label="Set up your loved one’s Porch"),
    I("If the phone adapter hasn’t arrived yet, tap Do this later.", "i11-connect", (277, 412),
      label="Set up your loved one’s Porch"),
])

pair = lambda caption, main, side, tap=None, on="main": beat(
    caption, f"ios/{main}", tap, IPAD if on == "main" else IPHONE, side=f"ios/{side}", on=on)
board("ios-your-phone", "pair", "Add your own phone", [
    pair("If you have an iPhone, install TestFlight first.", "j01-add-phone", "k00-p-home"),
    pair("On the iPad, type your name, then tap Show QR code.", "j02-name", "k00-p-home", (590, 358)),
    pair("Open the Camera app on your phone and point it at the code. Tap the link that appears.", "j03-qr", "k00-p-home"),
    pair("Porch opens on your phone. Tap Join family.", "j03-qr", "k01-p-join", (201, 387), on="side"),
    pair("Allow the microphone, so people can hear you.", "j04-joined", "k02-p-mic", (274, 552), on="side"),
    pair("Allow notifications, so calls can ring your iPhone.", "j04-joined", "k03-p-notif", (274, 518), on="side"),
    pair("The iPad says your phone joined. Tap Continue.", "j04-joined", "k04-p-home", (590, 300)),
    pair("You’re set: call Rose and change Porch’s settings from your iPhone.", "j05-ready", "k04-p-home"),
])

board("ios-keypad", "tablet", "Set up the phone’s number keys", [
    I("When setup ends, tap Put people on the keypad.", "j05-ready", (590, 344)),
    I("Tap the key you want to set up, such as 1.", "m01-people", (513, 218)),
    I("Any key can call a person, answer and hang up, turn video off and on, or play messages.", "m02-key1"),
    I("To have it call someone, choose Call a person.", "m02-key1", (513, 254)),
    I("If they’ve joined, tap Choose from Family on Porch.", "m03-call-person", (770, 576)),
    I("Choose them from the list.", "m04-family-pick", (945, 575)),
    I("Under Calls start as, choose Video or Voice.", "m05-david"),
    I("To try their regular phone when they miss a call, turn on Call their phone.", "m06-scrolled", (1100, 676)),
    I("Enter their primary number. Porch tries it after 20 seconds.", "m09-number-typed"),
    I("Tap Save. Repeat for each key.", "m09-number-typed", (1134, 54)),
    I("Key 1 now calls David. Pressing 1 on the phone rings him.", "m10-saved"),
])

board("ios-invite", "phone", "Invite family members", [
    P("In Porch on your iPhone, tap the person icon in the top right corner.", "k04-p-home", (364, 84)),
    P("Tap Caregiver mode.", "p01-menu", (201, 570)),
    P("Enter the PIN and tap Open caregiver mode.", "p03-gate-typed", (201, 367)),
    P("Open Family.", "p04-caregiver", (201, 336)),
    P("Tap Invite someone.", "p05-family", (131, 254)),
    P("Enter their name. Turn off drop-in if their calls should ring first.", "p07-invite-filled"),
    P("Turn on Caregiver mode for people who should change settings. Tap Create invitation.", "p07-invite-filled", (201, 724)),
    P("Send the invitation by text or email, then tap Done.", "p09-ready", (349, 84)),
    P("Each invitation works once and expires after 24 hours.", "p10-family-after"),
])

board("ios-language", "tablet", "Change the language or voice", [
    I("On the clock, tap the gear in the top right corner.", "g00-clock", (1131, 44)),
    I("Enter your PIN and tap Open caregiver mode.", "g02-gate-typed", (590, 299)),
    I("Open Display & voice.", "g03-caregiver", (180, 548)),
    I("Under Bedside language, choose a language, such as Español.", "n02-languages", (496, 222)),
    I("To pick a voice, tap the menu under Announcement voice.", "n03-espanol", (770, 490)),
    I("Choose a voice. Preview announcement lets you hear it.", "n04-voices", (997, 475)),
    I("Tap Save.", "n05-voice-picked", (1134, 54)),
    I("Tap Back to clock.", "n06-saved", (280, 54)),
    I("Porch now speaks and shows the clock in Spanish.", "n07-clock-es"),
])

# Android tablet and phone ---------------------------------------------------------------------------------------
T = lambda caption, main, tap=None, **k: beat(caption, f"android/{main}", tap, TABLET, **k)
F = lambda caption, main, tap=None, **k: beat(caption, f"android/{main}", tap, PHONE, **k)

board("android-setup", "tablet", None, [
    T("Install Porch from the Google Play test. It appears with the tablet’s apps.", "t-home", (1975, 1468),
      label="Install Porch on the tablet"),
    T("Tap your private setup link on the tablet. Porch opens and asks who it’s for.", "a01-who",
      label="Open your setup link on the tablet"),
    T("Enter the name family members use, then tap Continue.", "a02-who-typed", (1280, 604),
      label="Set up your loved one’s Porch"),
    T("Choose a six-digit caregiver PIN. Enter it twice and keep it somewhere safe.", "a04-pin-typed", (1280, 764),
      label="Set up your loved one’s Porch"),
    T("Tap Get number to get a phone number for Rose’s Porch.", "a05-number", (1280, 524),
      label="Set up your loved one’s Porch"),
    T("When the number appears, tap Continue.", "a06-number-got", (1280, 684), label="Set up your loved one’s Porch"),
    T("Tap Continue to turn on the microphone, camera and notifications.", "a07-perms", (1280, 492),
      label="Set up your loved one’s Porch"),
    T("For the camera, choose While using the app.", "a08-perm-camera", (1280, 769), label="Set up your loved one’s Porch"),
    T("Do the same for the microphone.", "a09-perm-mic", (1280, 769), label="Set up your loved one’s Porch"),
    T("Allow notifications.", "a10-perm-notif", (1280, 829), label="Set up your loved one’s Porch"),
    T("Choose Corded phone.", "a11-how", (1280, 470), label="Set up your loved one’s Porch"),
    T("If you’re waiting for a part, tap Do this later.", "a12-connect", (621, 704), label="Set up your loved one’s Porch"),
])

apair = lambda caption, main, side, tap=None, on="main": beat(
    caption, f"android/{main}", tap, TABLET if on == "main" else PHONE, side=f"android/{side}", on=on)
board("android-your-phone", "pair", "Add your phone", [
    apair("Install Porch on your phone first, the same way you did on the tablet.", "b01-add-phone", "p-home"),
    apair("On the tablet, type your name, then tap Show QR code.", "b02-name", "p-home", (1280, 652)),
    apair("Open the Camera app on your phone and point it at the code. Tap the link that appears.", "b03-qr", "p-home"),
    apair("Porch opens on your phone. Tap Join family.", "b03-qr", "b04-p-join", (540, 925), on="side"),
    apair("The tablet says your phone joined. Tap Continue.", "b05-t-joined", "b05-p-joined", (1280, 580)),
    apair("Then tap Back to the clock.", "b06-t-ready", "b07-p-home", (1280, 664)),
    apair("You’re set: call Rose and change Porch’s settings from your phone.", "c01-clock", "b07-p-home"),
])

board("android-keypad", "tablet", "Set up the phone’s number keys", [
    T("On the clock, tap the gear in the top right corner.", "c01-clock", (2480, 80)),
    T("Enter your PIN and tap Open caregiver mode.", "c03-gate-typed", (1280, 524)),
    T("People shows a keypad laid out like the phone’s. Tap the key you want to set up, such as 1.", "c04-caregiver",
      (1160, 448)),
    T("Any key can call a person, answer and hang up, turn video off and on, or play messages.", "c05-key1"),
    T("To have it call someone, choose Call a person.", "c05-key1", (1128, 484)),
    T("If they’ve joined, tap Choose from Family on Porch.", "c06-call-person", (1641, 1068)),
    T("Choose them from the list.", "c07-family-pick", (1041, 1182)),
    T("Under Calls start as, choose Video or Voice.", "c08-david", (2023, 1358)),
    T("To try their regular phone when they miss a call, turn on Call their phone.", "c10-scrolled", (2269, 1288)),
    T("Enter their primary number. Porch tries it after 20 seconds.", "c12-number"),
    T("Tap Save. Repeat for each key.", "c13-save", (1641, 1310)),
    T("Key 1 now calls David. Pressing 1 on the phone rings him.", "c14-saved"),
])

board("android-invite", "phone", "Invite family members", [
    F("In Porch on your phone, scroll down and tap Caregiver mode.", "d01-p-scrolled", (540, 1696)),
    F("Enter the PIN and tap Open caregiver mode.", "d03-p-gate-typed", (540, 862)),
    F("Open Family.", "d04-p-caregiver", (540, 820)),
    F("Tap Invite someone.", "d05-p-family", (540, 642)),
    F("Enter their name. Turn off drop-in if their calls should ring first.", "d07-p-invite-name"),
    F("Turn on Caregiver mode for people who should change settings. Tap Create invitation.", "d07-p-invite-name", (540, 1716)),
    F("Tap Share invitation and send it by text or email. Nearby, they can scan the code.", "d09-p-share", (540, 2040)),
    F("Then tap Done.", "d09-p-share", (97, 207)),
    F("Each invitation works once and expires after 24 hours.", "d11-p-family-after"),
])

board("android-language", "tablet", "Change the language or voice", [
    T("On the clock, tap the gear in the top right corner.", "c01-clock", (2480, 80)),
    T("Enter your PIN and tap Open caregiver mode.", "c03-gate-typed", (1280, 524)),
    T("Open Display & voice.", "c04-caregiver", (360, 1028)),
    T("Under Bedside language, choose a language, such as Español.", "e02-scrolled", (1091, 815)),
    T("To pick a voice, tap the menu under Announcement voice.", "e04-bottom", (1641, 534)),
    T("Choose a voice for that language.", "e05-voices", (1209, 1168)),
    T("Tap Save.", "e06-voice-picked", (1641, 1438)),
    T("Tap Back to clock.", "e07-saved", (127, 104)),
    T("Porch now speaks and shows the clock in Spanish.", "e08-clock-es"),
])
print("\n".join(sorted(f for f in os.listdir(out) if f.endswith(".json"))))
