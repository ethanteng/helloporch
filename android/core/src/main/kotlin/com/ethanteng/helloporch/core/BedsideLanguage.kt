package com.ethanteng.helloporch.core

import java.util.Locale
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/** The language the bedside speaks and shows, which is independent of the device's own language. `code` is the value
 * the server and the iOS app use. */
@Serializable
enum class BedsideLanguage(val code: String) {
    @SerialName("en") ENGLISH("en"),
    @SerialName("zh-Hant") TRADITIONAL_CHINESE("zh-Hant"),
    @SerialName("zh-Hans") SIMPLIFIED_CHINESE("zh-Hans"),
    @SerialName("yue-Hant") CANTONESE("yue-Hant"),
    @SerialName("es") SPANISH("es"),
    /** Tagalog as spoken in the Philippines. Android, Apple and ElevenLabs call it Filipino (`fil`). */
    @SerialName("tl") TAGALOG("tl");

    val displayName: String get() = when (this) {
        ENGLISH -> "English"
        TRADITIONAL_CHINESE -> "繁體中文"
        SIMPLIFIED_CHINESE -> "简体中文"
        CANTONESE -> "廣東話"
        SPANISH -> "Español"
        TAGALOG -> "Tagalog"
    }
    /** The name in caregiver settings, which also says which language the Chinese choices speak. */
    val choiceLabel: String get() = when (this) {
        TRADITIONAL_CHINESE, SIMPLIFIED_CHINESE -> "$displayName · Mandarin"
        CANTONESE -> "$displayName · Cantonese"
        ENGLISH, SPANISH, TAGALOG -> displayName
    }
    val locale: Locale get() = when (this) {
        ENGLISH -> Locale.forLanguageTag("en-US")
        TRADITIONAL_CHINESE -> Locale.forLanguageTag("zh-Hant-TW")
        SIMPLIFIED_CHINESE -> Locale.forLanguageTag("zh-Hans-CN")
        CANTONESE -> Locale.forLanguageTag("zh-Hant-HK")
        SPANISH -> Locale.forLanguageTag("es-ES")
        TAGALOG -> Locale.forLanguageTag("fil-PH")
    }
    val speechLanguage: String get() = when (this) {
        ENGLISH -> "en-US"
        TRADITIONAL_CHINESE -> "zh-TW"
        SIMPLIFIED_CHINESE -> "zh-CN"
        CANTONESE -> "zh-HK"
        SPANISH -> "es-ES"
        TAGALOG -> "fil-PH"
    }
    /** English/Spanish allow regional accents. Chinese choices retain their dialect/region. Tagalog takes either of its codes. */
    fun supportsSpeechVoice(language: String): Boolean {
        val tag = language.replace("_", "-").lowercase()
        val base = tag.split("-").firstOrNull { it.isNotEmpty() }
        return when (this) {
            ENGLISH -> base == "en"
            SPANISH -> base == "es"
            TAGALOG -> base == "fil" || base == "tl"
            TRADITIONAL_CHINESE -> tag in setOf("zh-tw", "zh-hant-tw", "cmn-tw", "cmn-hant-tw")
            SIMPLIFIED_CHINESE -> tag in setOf("zh-cn", "zh-hans-cn", "cmn-cn", "cmn-hans-cn")
            CANTONESE -> tag in setOf("zh-hk", "zh-hant-hk", "yue-hk", "yue-hant-hk")
        }
    }
    internal val translations: Map<String, String> get() = when (this) {
        ENGLISH -> emptyMap()
        TRADITIONAL_CHINESE -> traditionalStrings
        SIMPLIFIED_CHINESE -> simplifiedStrings
        CANTONESE -> cantoneseStrings
        SPANISH -> spanishStrings
        TAGALOG -> tagalogStrings
    }
    fun text(english: String): String = translations[english] ?: english
    /** The strings keep iOS's `%@`, so both apps share them word for word; it formats as `%s`. */
    fun format(english: String, vararg arguments: Any?): String = text(english).replace("%@", "%s").format(locale, *arguments)

    companion object {
        fun fromCode(code: String?): BedsideLanguage? = entries.firstOrNull { it.code == code }

        private val simplifiedStrings = mapOf(
            "%@ didn't answer." to "%@没有接听。", "%@ isn't available right now." to "%@现在无法接听。",
            "Leave a message for %@" to "给%@留言", "Speak after the beep." to "请在嘀声后说话。", "Recording your message…" to "正在录制留言…",
            "Send message" to "发送留言", "Don't send" to "不发送", "Press %@ when you're finished." to "说完后请按 %@。",
            "Your message is on its way to %@." to "您的留言正在发送给%@。", "No message was recorded." to "没有录到留言。", "Message not sent." to "留言未发送。",
            "%@ didn't answer. Please leave a message after the beep." to "%@没有接听。请在嘀声后留言。",
            "%@ isn't available right now. Please leave a message after the beep." to "%@现在无法接听。请在嘀声后留言。",
            "Couldn't record a message." to "无法录制留言。",
            "Play 1 message" to "播放 1 则留言", "Play %d messages" to "播放 %d 则留言",
            "Message from %@" to "%@的留言", "Voicemail from %@" to "%@的语音留言",
            "Message from %@. Sent %@." to "%@的留言，发送于%@。", "Voicemail from %@. Sent %@." to "%@的语音留言，发送于%@。",
            "Text from %@" to "%@发来的短信", "Text from %@. Sent %@." to "%@发来的短信，发送于%@。", "Translated from %@" to "译自%@",
            "It came with a picture, which Porch can't show yet." to "这条短信附有一张图片，Porch 目前还无法显示。",
            "It came with %d pictures, which Porch can't show yet." to "这条短信附有 %d 张图片，Porch 目前还无法显示。",
            "It came with something Porch can't show yet." to "这条短信附有 Porch 目前还无法显示的内容。",
            "Sent %@" to "发送于%@", "Stop" to "停止", "No new messages." to "没有新留言。", "Unknown caller" to "未知来电", "You have 1 new message." to "你有 1 则新留言。", "You have %d new messages." to "你有 %d 则新留言。", "Not now" to "稍后",
            "Morning" to "早上", "Afternoon" to "下午", "Evening" to "傍晚", "Night" to "夜晚",
            "Spring" to "春天", "Summer" to "夏天", "Fall" to "秋天", "Winter" to "冬天",
            "Call someone" to "打电话", "Caregiver mode" to "照护者设置",
            "Tap or hold to manage contacts and settings." to "轻点或长按，即可管理联系人和设置。",
            "Who would you like to call?" to "您想打给谁？",
            "Tap a name or press their number on the keypad." to "请轻点姓名，或按下键盘上对应的数字。",
            "Back to clock" to "返回时钟", "Press %@" to "按 %@",
            "Call %@, key %@" to "打给%@，按 %@",
            "Your caregiver can add people using the settings icon on the clock screen." to "请照护者使用时钟画面的设置图标添加联系人。",
            "Use this key to answer or end a call." to "通话时，按此键即可接听或挂断。",
            "Use this key to turn your camera off or on during a video call." to "视频通话时，按此键即可开启或关闭摄像头。",
            "No one is assigned to %@.\nPlease choose another number." to "%@ 号尚未设置联系人。\n请选择其他号码。",
            "Finish Porch setup" to "请完成 Porch 设置",
            "Open caregiver mode and invite this person to Porch or add their phone number." to "请照护者邀请这位联系人加入 Porch，或添加电话号码。",
            "Porch isn't ready" to "Porch 尚未准备好",
            "Check People and Drop-in in caregiver mode, then try again." to "请照护者检查家人与自动接听设置，再试一次。",
            "Couldn't call %@" to "无法打给%@", "Please ask your caregiver for help, then try again." to "请照护者协助检查后，再试一次。",
            "OK" to "好", "Connecting…" to "正在连接…", "Your camera preview" to "您的摄像头画面",
            "Voice call\nCamera is off" to "语音通话\n摄像头已关闭", "Waiting for video" to "正在等待视频画面",
            "Mute" to "关闭麦克风", "Unmute" to "开启麦克风", "Camera off" to "关闭摄像头", "Camera on" to "开启摄像头", "End call" to "挂断",
            "Couldn't start the call." to "无法开始通话。", "Key %@: hang up" to "按 %@：挂断",
            "Key %@: video off / on" to "按 %@：关闭／开启摄像头", "Phone call connected" to "电话已接通",
            "Reconnecting phone call…" to "正在重新连接电话…", "Calling %@'s phone…" to "正在拨打%@的电话…",
            "Voice call connected" to "语音已接通", "Video call connected" to "视频已接通", "Connecting audio…" to "正在连接声音…",
            "Waiting for %@…" to "正在等待%@…", "Connecting with %@…" to "正在与%@连接…", "Calling %@ on Porch…" to "正在通过 Porch 打给%@…",
            "Calling %@…" to "正在呼叫%@…", "Calling %@." to "正在打给%@。", "%@ joined the call" to "%@已加入通话", "%@ left the call" to "%@已离开通话",
            "Trying %@ on Porch…\nTheir phone will ring if Porch isn't answered." to "正在通过 Porch 打给%@…\n若无人接听，将改拨电话。",
            "Couldn't connect the call. Please try again." to "无法接通，请再试一次。",
            "Couldn't change camera. Try again." to "无法切换摄像头，请再试一次。", "Couldn't change microphone. Try again." to "无法切换麦克风，请再试一次。",
            "Ending call…" to "正在结束通话…", "Reconnecting…" to "正在重新连接…",
            "Retry ending phone call" to "重试挂断电话",
            "Porch disconnected. Couldn't confirm the phone call ended. Check the internet connection and try again." to "Porch 已断开，无法确认电话是否已挂断。请检查网络后再试一次。",
            "Call ended. Returning to the clock…" to "通话已结束，正在返回时钟…", "Call ended. Returning to Porch…" to "通话已结束，正在返回 Porch…",
            "No one joined. Returning to the clock…" to "无人接听，正在返回时钟…",
            "The call disconnected. Returning to the clock…" to "通话已断开，正在返回时钟…",
            "The phone call ended before it was answered." to "电话尚未接听就已结束。",
            "Microphone access is required." to "需要开启麦克风权限。",
            "Allow Porch's microphone in Settings to make a phone call." to "请照护者在 iPad 设置中允许 Porch 使用麦克风。",
            "Couldn't switch to their phone." to "无法改拨电话。", "Couldn't finish connecting the Porch call." to "无法完成 Porch 连接。",
            "They answered Porch, but this device couldn't connect. Please try again." to "对方已接听，但此设备无法连接。请再试一次。",
            "Porch wasn't answered. Trying %@'s phone…" to "Porch 无人接听，正在改拨%@的电话…",
            "Phone call\nCamera is off" to "电话通话\n摄像头已关闭", "Couldn't connect their phone." to "无法接通电话。",
            "Their phone didn't answer. Returning to the clock…" to "电话无人接听，正在返回时钟…",
            "Answer" to "接听", "Answer video call" to "接听视频", "Answer audio call" to "接听语音", "Don't connect" to "不要接通", "Decline" to "拒接",
            "Press %@ to stop this drop-in." to "按 %@ 即可取消自动接听。",
            "Tap %@ to answer. Hold %@ to decline." to "轻按 %@ 接听，长按 %@ 拒接。",
            "Video drop-in\nConnecting in %d…" to "视频自动接听\n%d 秒后接通…",
            "Audio drop-in\nConnecting in %d…" to "语音自动接听\n%d 秒后接通…",
            "Incoming video call" to "有视频来电", "Incoming audio call" to "有语音来电",
            "Announcing video drop-in…" to "正在提示视频自动接听…", "Announcing audio drop-in…" to "正在提示语音自动接听…",
            "%@ is dropping in with video. Connecting in five seconds." to "%@要和您视频通话，五秒后接通。",
            "%@ is dropping in with audio. Connecting in five seconds." to "%@要和您语音通话，五秒后接通。",
            "The sound couldn't play. Tap Answer to connect." to "无法播放提示音，请按接听以接通。",
            "Allow microphone access in iPad Settings → Privacy & Security → Microphone to make calls." to "请照护者在 iPad「设置」→「隐私与安全性」→「麦克风」中允许 Porch 使用麦克风。",
            "Allow camera access in iPad Settings → Privacy & Security → Camera, or choose Voice in this person's setup." to "请照护者在 iPad 设置中允许 Porch 使用相机，或改用语音通话。",
            "A family member" to "家人"
        )

        private val cantoneseStrings = mapOf(
            "%@ didn't answer." to "%@冇接聽。", "%@ isn't available right now." to "%@而家未能接聽。",
            "Leave a message for %@" to "留言畀%@", "Speak after the beep." to "請喺嘟一聲之後講。", "Recording your message…" to "錄緊留言…",
            "Send message" to "傳送留言", "Don't send" to "唔傳送", "Press %@ when you're finished." to "講完請按 %@。",
            "Your message is on its way to %@." to "您嘅留言正傳送畀%@。", "No message was recorded." to "冇錄到留言。", "Message not sent." to "留言冇傳送。",
            "%@ didn't answer. Please leave a message after the beep." to "%@冇接聽。請喺嘟一聲之後留言。",
            "%@ isn't available right now. Please leave a message after the beep." to "%@而家未能接聽。請喺嘟一聲之後留言。",
            "Couldn't record a message." to "錄唔到留言。",
            "Play 1 message" to "播放 1 個留言", "Play %d messages" to "播放 %d 個留言",
            "Message from %@" to "%@嘅留言", "Voicemail from %@" to "%@嘅語音留言",
            "Message from %@. Sent %@." to "%@嘅留言，喺%@傳送。", "Voicemail from %@. Sent %@." to "%@嘅語音留言，喺%@傳送。",
            "Text from %@" to "%@嘅短訊", "Text from %@. Sent %@." to "%@嘅短訊，喺%@傳送。", "Translated from %@" to "譯自%@",
            "It came with a picture, which Porch can't show yet." to "呢個短訊附咗一張相，Porch 暫時未顯示到。",
            "It came with %d pictures, which Porch can't show yet." to "呢個短訊附咗 %d 張相，Porch 暫時未顯示到。",
            "It came with something Porch can't show yet." to "呢個短訊附咗啲 Porch 暫時未顯示到嘅嘢。",
            "Sent %@" to "喺%@傳送", "Stop" to "停止", "No new messages." to "冇新留言。", "Unknown caller" to "未知來電", "You have 1 new message." to "你有 1 個新留言。", "You have %d new messages." to "你有 %d 個新留言。", "Not now" to "遲啲先",
            "Morning" to "朝早", "Afternoon" to "下晝", "Evening" to "黃昏", "Night" to "夜晚",
            "Spring" to "春天", "Summer" to "夏天", "Fall" to "秋天", "Winter" to "冬天",
            "Call someone" to "打電話", "Caregiver mode" to "照顧者設定",
            "Tap or hold to manage contacts and settings." to "輕按或長按，就可以管理聯絡人同設定。",
            "Who would you like to call?" to "您想打畀邊個？",
            "Tap a name or press their number on the keypad." to "請輕按姓名，或者按鍵盤上對應嘅數字。",
            "Back to clock" to "返回時鐘", "Press %@" to "按 %@",
            "Call %@, key %@" to "打畀%@，按 %@",
            "Your caregiver can add people using the settings icon on the clock screen." to "請照顧者用時鐘畫面嘅設定圖示加入聯絡人。",
            "Use this key to answer or end a call." to "通話時，按呢個掣就可以接聽或者收線。",
            "Use this key to turn your camera off or on during a video call." to "視像通話時，按呢個掣就可以開關鏡頭。",
            "No one is assigned to %@.\nPlease choose another number." to "%@ 號未有設定聯絡人。\n請揀另一個號碼。",
            "Finish Porch setup" to "請完成 Porch 設定",
            "Open caregiver mode and invite this person to Porch or add their phone number." to "請照顧者邀請呢位聯絡人加入 Porch，或者加入電話號碼。",
            "Porch isn't ready" to "Porch 仲未準備好",
            "Check People and Drop-in in caregiver mode, then try again." to "請照顧者檢查家人同自動接聽設定，再試一次。",
            "Couldn't call %@" to "打唔到畀%@", "Please ask your caregiver for help, then try again." to "請照顧者幫手檢查，再試一次。",
            "OK" to "好", "Connecting…" to "連線中…", "Your camera preview" to "您嘅鏡頭畫面",
            "Voice call\nCamera is off" to "語音通話\n鏡頭已關閉", "Waiting for video" to "等緊視像畫面",
            "Mute" to "關閉咪高峰", "Unmute" to "開啟咪高峰", "Camera off" to "關閉鏡頭", "Camera on" to "開啟鏡頭", "End call" to "收線",
            "Couldn't start the call." to "開始唔到通話。", "Key %@: hang up" to "按 %@：收線",
            "Key %@: video off / on" to "按 %@：關閉／開啟鏡頭", "Phone call connected" to "電話已接通",
            "Reconnecting phone call…" to "重新接駁電話中…", "Calling %@'s phone…" to "打緊畀%@嘅電話…",
            "Voice call connected" to "語音已接通", "Video call connected" to "視像已接通", "Connecting audio…" to "接駁聲音中…",
            "Waiting for %@…" to "等緊%@…", "Connecting with %@…" to "同%@連線中…", "Calling %@ on Porch…" to "用緊 Porch 打畀%@…",
            "Calling %@…" to "打緊畀%@…", "Calling %@." to "打緊畀%@。", "%@ joined the call" to "%@加入咗通話", "%@ left the call" to "%@離開咗通話",
            "Trying %@ on Porch…\nTheir phone will ring if Porch isn't answered." to "用緊 Porch 打畀%@…\n如果冇人接聽，就會改打電話。",
            "Couldn't connect the call. Please try again." to "接唔通，請再試一次。",
            "Couldn't change camera. Try again." to "切換唔到鏡頭，請再試一次。", "Couldn't change microphone. Try again." to "切換唔到咪高峰，請再試一次。",
            "Ending call…" to "結束通話中…", "Reconnecting…" to "重新連線中…",
            "Retry ending phone call" to "再試收線",
            "Porch disconnected. Couldn't confirm the phone call ended. Check the internet connection and try again." to "Porch 已斷線，確認唔到電話係咪已經收線。請檢查網絡，再試一次。",
            "Call ended. Returning to the clock…" to "通話已結束，返回時鐘中…", "Call ended. Returning to Porch…" to "通話已結束，返回 Porch 中…",
            "No one joined. Returning to the clock…" to "冇人接聽，返回時鐘中…",
            "The call disconnected. Returning to the clock…" to "通話已斷線，返回時鐘中…",
            "The phone call ended before it was answered." to "電話未接聽就已經結束。",
            "Microphone access is required." to "需要開啟咪高峰權限。",
            "Allow Porch's microphone in Settings to make a phone call." to "請照顧者喺 iPad 設定入面允許 Porch 使用咪高峰。",
            "Couldn't switch to their phone." to "改打唔到電話。", "Couldn't finish connecting the Porch call." to "完成唔到 Porch 連線。",
            "They answered Porch, but this device couldn't connect. Please try again." to "對方已接聽，但呢部裝置連唔到線。請再試一次。",
            "Porch wasn't answered. Trying %@'s phone…" to "Porch 冇人接聽，改打%@嘅電話中…",
            "Phone call\nCamera is off" to "電話通話\n鏡頭已關閉", "Couldn't connect their phone." to "打唔通電話。",
            "Their phone didn't answer. Returning to the clock…" to "電話冇人接聽，返回時鐘中…",
            "Answer" to "接聽", "Answer video call" to "接聽視像", "Answer audio call" to "接聽語音", "Don't connect" to "唔好接通", "Decline" to "拒接",
            "Press %@ to stop this drop-in." to "按 %@ 就可以取消自動接聽。",
            "Tap %@ to answer. Hold %@ to decline." to "輕按 %@ 接聽，長按 %@ 拒接。",
            "Video drop-in\nConnecting in %d…" to "視像自動接聽\n%d 秒後接通…",
            "Audio drop-in\nConnecting in %d…" to "語音自動接聽\n%d 秒後接通…",
            "Incoming video call" to "有視像來電", "Incoming audio call" to "有語音來電",
            "Announcing video drop-in…" to "提示視像自動接聽中…", "Announcing audio drop-in…" to "提示語音自動接聽中…",
            "%@ is dropping in with video. Connecting in five seconds." to "%@想同您視像通話，五秒後接通。",
            "%@ is dropping in with audio. Connecting in five seconds." to "%@想同您語音通話，五秒後接通。",
            "The sound couldn't play. Tap Answer to connect." to "播唔到提示聲，請按接聽嚟接通。",
            "Allow microphone access in iPad Settings → Privacy & Security → Microphone to make calls." to "請照顧者喺 iPad「設定」→「私隱與保安」→「咪高峰」入面允許 Porch 使用咪高峰。",
            "Allow camera access in iPad Settings → Privacy & Security → Camera, or choose Voice in this person's setup." to "請照顧者喺 iPad 設定入面允許 Porch 使用相機，或者改用語音通話。",
            "A family member" to "屋企人"
        )

        private val spanishStrings = mapOf(
            "%@ didn't answer." to "%@ no ha contestado.", "%@ isn't available right now." to "%@ no está disponible ahora.",
            "Leave a message for %@" to "Deje un mensaje para %@", "Speak after the beep." to "Hable después del pitido.", "Recording your message…" to "Grabando su mensaje…",
            "Send message" to "Enviar mensaje", "Don't send" to "No enviar", "Press %@ when you're finished." to "Pulse %@ cuando termine.",
            "Your message is on its way to %@." to "Su mensaje se está enviando a %@.", "No message was recorded." to "No se ha grabado ningún mensaje.", "Message not sent." to "Mensaje no enviado.",
            "%@ didn't answer. Please leave a message after the beep." to "%@ no ha contestado. Deje un mensaje después del pitido.",
            "%@ isn't available right now. Please leave a message after the beep." to "%@ no está disponible ahora. Deje un mensaje después del pitido.",
            "Couldn't record a message." to "No se ha podido grabar el mensaje.",
            "Play 1 message" to "Reproducir 1 mensaje", "Play %d messages" to "Reproducir %d mensajes",
            "Message from %@" to "Mensaje de %@", "Voicemail from %@" to "Mensaje de voz de %@",
            "Message from %@. Sent %@." to "Mensaje de %@. Enviado %@.", "Voicemail from %@. Sent %@." to "Mensaje de voz de %@. Enviado %@.",
            "Text from %@" to "Mensaje de texto de %@", "Text from %@. Sent %@." to "Mensaje de texto de %@. Enviado %@.", "Translated from %@" to "Traducido del %@",
            "It came with a picture, which Porch can't show yet." to "Venía con una foto que Porch todavía no puede mostrar.",
            "It came with %d pictures, which Porch can't show yet." to "Venía con %d fotos que Porch todavía no puede mostrar.",
            "It came with something Porch can't show yet." to "Venía con algo que Porch todavía no puede mostrar.",
            "Sent %@" to "Enviado %@", "Stop" to "Detener", "No new messages." to "No hay mensajes nuevos.", "Unknown caller" to "Número desconocido", "You have 1 new message." to "Tienes 1 mensaje nuevo.", "You have %d new messages." to "Tienes %d mensajes nuevos.", "Not now" to "Ahora no",
            "Morning" to "Mañana", "Afternoon" to "Tarde", "Evening" to "Atardecer", "Night" to "Noche",
            "Spring" to "Primavera", "Summer" to "Verano", "Fall" to "Otoño", "Winter" to "Invierno",
            "Call someone" to "Llamar a alguien", "Caregiver mode" to "Ajustes del cuidador",
            "Tap or hold to manage contacts and settings." to "Toque o mantenga pulsado para gestionar contactos y ajustes.",
            "Who would you like to call?" to "¿A quién quiere llamar?",
            "Tap a name or press their number on the keypad." to "Toque un nombre o pulse su número en el teclado.",
            "Back to clock" to "Volver al reloj", "Press %@" to "Pulse %@",
            "Call %@, key %@" to "Llamar a %@, tecla %@",
            "Your caregiver can add people using the settings icon on the clock screen." to "Su cuidador puede añadir contactos con el icono de ajustes en la pantalla del reloj.",
            "Use this key to answer or end a call." to "Use esta tecla para contestar o colgar una llamada.",
            "Use this key to turn your camera off or on during a video call." to "Use esta tecla para apagar o encender la cámara durante una videollamada.",
            "No one is assigned to %@.\nPlease choose another number." to "No hay ningún contacto asignado al %@.\nElija otro número.",
            "Finish Porch setup" to "Complete la configuración de Porch",
            "Open caregiver mode and invite this person to Porch or add their phone number." to "Pida a su cuidador que invite a esta persona a Porch o añada su número de teléfono.",
            "Porch isn't ready" to "Porch aún no está listo",
            "Check People and Drop-in in caregiver mode, then try again." to "Pida a su cuidador que revise los ajustes de familia y conexión automática e inténtelo de nuevo.",
            "Couldn't call %@" to "No se pudo llamar a %@", "Please ask your caregiver for help, then try again." to "Pida ayuda a su cuidador e inténtelo de nuevo.",
            "OK" to "Aceptar", "Connecting…" to "Conectando…", "Your camera preview" to "Vista de su cámara",
            "Voice call\nCamera is off" to "Llamada de voz\nCámara apagada", "Waiting for video" to "Esperando el vídeo",
            "Mute" to "Silenciar", "Unmute" to "Activar micrófono", "Camera off" to "Apagar cámara", "Camera on" to "Encender cámara", "End call" to "Colgar",
            "Couldn't start the call." to "No se pudo iniciar la llamada.", "Key %@: hang up" to "Tecla %@: colgar",
            "Key %@: video off / on" to "Tecla %@: apagar / encender cámara", "Phone call connected" to "Llamada telefónica conectada",
            "Reconnecting phone call…" to "Reconectando la llamada telefónica…", "Calling %@'s phone…" to "Llamando al teléfono de %@…",
            "Voice call connected" to "Llamada de voz conectada", "Video call connected" to "Videollamada conectada", "Connecting audio…" to "Conectando el audio…",
            "Waiting for %@…" to "Esperando a %@…", "Connecting with %@…" to "Conectando con %@…", "Calling %@ on Porch…" to "Llamando a %@ por Porch…",
            "Calling %@…" to "Llamando a %@…", "Calling %@." to "Llamando a %@.", "%@ joined the call" to "%@ se unió a la llamada", "%@ left the call" to "%@ salió de la llamada",
            "Trying %@ on Porch…\nTheir phone will ring if Porch isn't answered." to "Llamando a %@ por Porch…\nSi no contesta, sonará su teléfono.",
            "Couldn't connect the call. Please try again." to "No se pudo conectar la llamada. Inténtelo de nuevo.",
            "Couldn't change camera. Try again." to "No se pudo cambiar la cámara. Inténtelo de nuevo.", "Couldn't change microphone. Try again." to "No se pudo cambiar el micrófono. Inténtelo de nuevo.",
            "Ending call…" to "Finalizando la llamada…", "Reconnecting…" to "Reconectando…",
            "Retry ending phone call" to "Intentar colgar de nuevo",
            "Porch disconnected. Couldn't confirm the phone call ended. Check the internet connection and try again." to "Porch se ha desconectado. No se pudo confirmar que la llamada haya terminado. Compruebe la conexión a internet e inténtelo de nuevo.",
            "Call ended. Returning to the clock…" to "Llamada finalizada. Volviendo al reloj…", "Call ended. Returning to Porch…" to "Llamada finalizada. Volviendo a Porch…",
            "No one joined. Returning to the clock…" to "Nadie ha contestado. Volviendo al reloj…",
            "The call disconnected. Returning to the clock…" to "Se ha desconectado la llamada. Volviendo al reloj…",
            "The phone call ended before it was answered." to "La llamada telefónica terminó antes de que contestaran.",
            "Microphone access is required." to "Se necesita acceso al micrófono.",
            "Allow Porch's microphone in Settings to make a phone call." to "Pida a su cuidador que permita a Porch usar el micrófono en los ajustes del iPad.",
            "Couldn't switch to their phone." to "No se pudo llamar a su teléfono.", "Couldn't finish connecting the Porch call." to "No se pudo completar la conexión de Porch.",
            "They answered Porch, but this device couldn't connect. Please try again." to "Han contestado en Porch, pero este dispositivo no pudo conectarse. Inténtelo de nuevo.",
            "Porch wasn't answered. Trying %@'s phone…" to "No han contestado en Porch. Llamando al teléfono de %@…",
            "Phone call\nCamera is off" to "Llamada telefónica\nCámara apagada", "Couldn't connect their phone." to "No se pudo conectar con su teléfono.",
            "Their phone didn't answer. Returning to the clock…" to "No han contestado al teléfono. Volviendo al reloj…",
            "Answer" to "Contestar", "Answer video call" to "Contestar videollamada", "Answer audio call" to "Contestar llamada de voz", "Don't connect" to "No conectar", "Decline" to "Rechazar",
            "Press %@ to stop this drop-in." to "Pulse %@ para cancelar esta conexión automática.",
            "Tap %@ to answer. Hold %@ to decline." to "Pulse %@ para contestar. Mantenga pulsado %@ para rechazar.",
            "Video drop-in\nConnecting in %d…" to "Videollamada automática\nConexión en %d…",
            "Audio drop-in\nConnecting in %d…" to "Llamada de voz automática\nConexión en %d…",
            "Incoming video call" to "Videollamada entrante", "Incoming audio call" to "Llamada de voz entrante",
            "Announcing video drop-in…" to "Anunciando videollamada automática…", "Announcing audio drop-in…" to "Anunciando llamada de voz automática…",
            "%@ is dropping in with video. Connecting in five seconds." to "%@ quiere hablar con usted por vídeo. La llamada se conectará en cinco segundos.",
            "%@ is dropping in with audio. Connecting in five seconds." to "%@ quiere hablar con usted por voz. La llamada se conectará en cinco segundos.",
            "The sound couldn't play. Tap Answer to connect." to "No se pudo reproducir el aviso. Toque Contestar para conectar.",
            "Allow microphone access in iPad Settings → Privacy & Security → Microphone to make calls." to "Pida a su cuidador que permita el acceso al micrófono en Ajustes del iPad → Privacidad y seguridad → Micrófono.",
            "Allow camera access in iPad Settings → Privacy & Security → Camera, or choose Voice in this person's setup." to "Pida a su cuidador que permita el acceso a la cámara en los ajustes del iPad o que elija una llamada de voz.",
            "A family member" to "Un familiar"
        )

        private val tagalogStrings = mapOf(
            "%@ didn't answer." to "Hindi po sumagot si %@.", "%@ isn't available right now." to "Hindi po makasagot si %@ ngayon.",
            "Leave a message for %@" to "Mag-iwan ng mensahe para kay %@", "Speak after the beep." to "Magsalita po pagkatapos ng beep.", "Recording your message…" to "Nire-record ang inyong mensahe…",
            "Send message" to "Ipadala ang mensahe", "Don't send" to "Huwag ipadala", "Press %@ when you're finished." to "Pindutin po ang %@ kapag tapos na kayo.",
            "Your message is on its way to %@." to "Ipinapadala na po ang inyong mensahe kay %@.", "No message was recorded." to "Walang na-record na mensahe.", "Message not sent." to "Hindi naipadala ang mensahe.",
            "%@ didn't answer. Please leave a message after the beep." to "Hindi po sumagot si %@. Mag-iwan po kayo ng mensahe pagkatapos ng beep.",
            "%@ isn't available right now. Please leave a message after the beep." to "Hindi po makasagot si %@ ngayon. Mag-iwan po kayo ng mensahe pagkatapos ng beep.",
            "Couldn't record a message." to "Hindi ma-record ang mensahe.",
            "Play 1 message" to "I-play ang 1 mensahe", "Play %d messages" to "I-play ang %d mensahe",
            "Message from %@" to "Mensahe mula kay %@", "Voicemail from %@" to "Voicemail mula kay %@",
            "Message from %@. Sent %@." to "Mensahe mula kay %@. Ipinadala %@.", "Voicemail from %@. Sent %@." to "Voicemail mula kay %@. Ipinadala %@.",
            "Text from %@" to "Text mula kay %@", "Text from %@. Sent %@." to "Text mula kay %@. Ipinadala %@.", "Translated from %@" to "Isinalin mula sa %@",
            "It came with a picture, which Porch can't show yet." to "May kasama itong litrato na hindi pa maipakita ng Porch.",
            "It came with %d pictures, which Porch can't show yet." to "May kasama itong %d litrato na hindi pa maipakita ng Porch.",
            "It came with something Porch can't show yet." to "May kasama itong hindi pa maipakita ng Porch.",
            "Sent %@" to "Ipinadala %@", "Stop" to "Itigil", "No new messages." to "Walang bagong mensahe.", "Unknown caller" to "Hindi kilalang tumatawag", "You have 1 new message." to "May 1 po kayong bagong mensahe.", "You have %d new messages." to "May %d po kayong bagong mensahe.", "Not now" to "Mamaya na",
            "Morning" to "Umaga", "Afternoon" to "Hapon", "Evening" to "Dapithapon", "Night" to "Gabi",
            "Spring" to "Tagsibol", "Summer" to "Tag-init", "Fall" to "Taglagas", "Winter" to "Taglamig",
            "Call someone" to "Tumawag", "Caregiver mode" to "Mga setting ng tagapag-alaga",
            "Tap or hold to manage contacts and settings." to "I-tap o pindutin nang matagal para ayusin ang mga contact at setting.",
            "Who would you like to call?" to "Sino po ang gusto ninyong tawagan?",
            "Tap a name or press their number on the keypad." to "I-tap po ang pangalan, o pindutin ang numero nila sa keypad.",
            "Back to clock" to "Bumalik sa orasan", "Press %@" to "Pindutin ang %@",
            "Call %@, key %@" to "Tawagan si %@, pindutin ang %@",
            "Your caregiver can add people using the settings icon on the clock screen." to "Makakapagdagdag ng mga tao ang inyong tagapag-alaga gamit ang icon ng setting sa screen ng orasan.",
            "Use this key to answer or end a call." to "Gamitin ang pindutang ito para sumagot o magbaba ng tawag.",
            "Use this key to turn your camera off or on during a video call." to "Gamitin ang pindutang ito para patayin o buksan ang kamera habang naka-video call.",
            "No one is assigned to %@.\nPlease choose another number." to "Wala pang nakatalaga sa %@.\nPumili po ng ibang numero.",
            "Finish Porch setup" to "Tapusin ang setup ng Porch",
            "Open caregiver mode and invite this person to Porch or add their phone number." to "Ipakisuyo sa tagapag-alaga na imbitahan ang taong ito sa Porch o idagdag ang kanyang numero ng telepono.",
            "Porch isn't ready" to "Hindi pa handa ang Porch",
            "Check People and Drop-in in caregiver mode, then try again." to "Ipakisuyo sa tagapag-alaga na tingnan ang mga setting ng pamilya at awtomatikong pagsagot, saka subukang muli.",
            "Couldn't call %@" to "Hindi matawagan si %@", "Please ask your caregiver for help, then try again." to "Humingi po ng tulong sa inyong tagapag-alaga, saka subukang muli.",
            "OK" to "Sige", "Connecting…" to "Kumokonekta…", "Your camera preview" to "Ang nakikita ng inyong kamera",
            "Voice call\nCamera is off" to "Voice call\nNakapatay ang kamera", "Waiting for video" to "Hinihintay ang video",
            "Mute" to "Patayin ang mikropono", "Unmute" to "Buksan ang mikropono", "Camera off" to "Patayin ang kamera", "Camera on" to "Buksan ang kamera", "End call" to "Ibaba ang tawag",
            "Couldn't start the call." to "Hindi masimulan ang tawag.", "Key %@: hang up" to "Pindutan %@: ibaba ang tawag",
            "Key %@: video off / on" to "Pindutan %@: patayin / buksan ang kamera", "Phone call connected" to "Nakakonekta na ang tawag sa telepono",
            "Reconnecting phone call…" to "Ikinokonekta muli ang tawag sa telepono…", "Calling %@'s phone…" to "Tinatawagan ang telepono ni %@…",
            "Voice call connected" to "Nakakonekta na ang voice call", "Video call connected" to "Nakakonekta na ang video call", "Connecting audio…" to "Ikinokonekta ang tunog…",
            "Waiting for %@…" to "Hinihintay si %@…", "Connecting with %@…" to "Kumokonekta kay %@…", "Calling %@ on Porch…" to "Tinatawagan si %@ sa Porch…",
            "Calling %@…" to "Tinatawagan si %@…", "Calling %@." to "Tinatawagan si %@.", "%@ joined the call" to "Sumali si %@ sa tawag", "%@ left the call" to "Umalis si %@ sa tawag",
            "Trying %@ on Porch…\nTheir phone will ring if Porch isn't answered." to "Tinatawagan si %@ sa Porch…\nTatawagan ang kanyang telepono kung walang sumagot sa Porch.",
            "Couldn't connect the call. Please try again." to "Hindi maikonekta ang tawag. Pakisubukang muli.",
            "Couldn't change camera. Try again." to "Hindi mabago ang kamera. Subukang muli.", "Couldn't change microphone. Try again." to "Hindi mabago ang mikropono. Subukang muli.",
            "Ending call…" to "Tinatapos ang tawag…", "Reconnecting…" to "Kumokonekta muli…",
            "Retry ending phone call" to "Subukang ibaba muli ang tawag",
            "Porch disconnected. Couldn't confirm the phone call ended. Check the internet connection and try again." to "Nawalan ng koneksyon ang Porch. Hindi matiyak kung natapos na ang tawag sa telepono. Tingnan ang koneksyon sa internet at subukang muli.",
            "Call ended. Returning to the clock…" to "Tapos na ang tawag. Bumabalik sa orasan…", "Call ended. Returning to Porch…" to "Tapos na ang tawag. Bumabalik sa Porch…",
            "No one joined. Returning to the clock…" to "Walang sumagot. Bumabalik sa orasan…",
            "The call disconnected. Returning to the clock…" to "Naputol ang tawag. Bumabalik sa orasan…",
            "The phone call ended before it was answered." to "Natapos ang tawag bago ito nasagot.",
            "Microphone access is required." to "Kailangan ng pahintulot sa mikropono.",
            "Allow Porch's microphone in Settings to make a phone call." to "Ipakisuyo sa tagapag-alaga na payagan ang Porch na gumamit ng mikropono sa Settings ng iPad.",
            "Couldn't switch to their phone." to "Hindi matawagan ang kanyang telepono.", "Couldn't finish connecting the Porch call." to "Hindi natapos ang pagkonekta ng tawag sa Porch.",
            "They answered Porch, but this device couldn't connect. Please try again." to "Sumagot sila sa Porch, pero hindi makakonekta ang device na ito. Pakisubukang muli.",
            "Porch wasn't answered. Trying %@'s phone…" to "Walang sumagot sa Porch. Tinatawagan ang telepono ni %@…",
            "Phone call\nCamera is off" to "Tawag sa telepono\nNakapatay ang kamera", "Couldn't connect their phone." to "Hindi maikonekta ang kanyang telepono.",
            "Their phone didn't answer. Returning to the clock…" to "Walang sumagot sa telepono. Bumabalik sa orasan…",
            "Answer" to "Sagutin", "Answer video call" to "Sagutin ang video call", "Answer audio call" to "Sagutin ang voice call", "Don't connect" to "Huwag ikonekta", "Decline" to "Tanggihan",
            "Press %@ to stop this drop-in." to "Pindutin po ang %@ para kanselahin ang awtomatikong pagsagot.",
            "Tap %@ to answer. Hold %@ to decline." to "I-tap ang %@ para sumagot. Pindutin nang matagal ang %@ para tumanggi.",
            "Video drop-in\nConnecting in %d…" to "Awtomatikong video call\nKokonekta sa loob ng %d…",
            "Audio drop-in\nConnecting in %d…" to "Awtomatikong voice call\nKokonekta sa loob ng %d…",
            "Incoming video call" to "Papasok na video call", "Incoming audio call" to "Papasok na voice call",
            "Announcing video drop-in…" to "Ipinapaalam ang awtomatikong video call…", "Announcing audio drop-in…" to "Ipinapaalam ang awtomatikong voice call…",
            "%@ is dropping in with video. Connecting in five seconds." to "Tumatawag po si %@ sa video call. Kokonekta ito sa loob ng limang segundo.",
            "%@ is dropping in with audio. Connecting in five seconds." to "Tumatawag po si %@ sa voice call. Kokonekta ito sa loob ng limang segundo.",
            "The sound couldn't play. Tap Answer to connect." to "Hindi ma-play ang tunog. I-tap ang Sagutin para kumonekta.",
            "Allow microphone access in iPad Settings → Privacy & Security → Microphone to make calls." to "Ipakisuyo sa tagapag-alaga na payagan ang mikropono sa Settings ng iPad → Privacy & Security → Microphone.",
            "Allow camera access in iPad Settings → Privacy & Security → Camera, or choose Voice in this person's setup." to "Ipakisuyo sa tagapag-alaga na payagan ang kamera sa Settings ng iPad, o piliin ang voice call para sa taong ito.",
            "A family member" to "Kapamilya"
        )

        private val traditionalStrings = mapOf(
            "%@ didn't answer." to "%@沒有接聽。", "%@ isn't available right now." to "%@現在無法接聽。",
            "Leave a message for %@" to "留言給%@", "Speak after the beep." to "請在嗶聲後說話。", "Recording your message…" to "正在錄製留言…",
            "Send message" to "傳送留言", "Don't send" to "不要傳送", "Press %@ when you're finished." to "說完後請按 %@。",
            "Your message is on its way to %@." to "您的留言正在傳送給%@。", "No message was recorded." to "沒有錄到留言。", "Message not sent." to "留言未傳送。",
            "%@ didn't answer. Please leave a message after the beep." to "%@沒有接聽。請在嗶聲後留言。",
            "%@ isn't available right now. Please leave a message after the beep." to "%@現在無法接聽。請在嗶聲後留言。",
            "Couldn't record a message." to "無法錄製留言。",
            "Play 1 message" to "播放 1 則留言", "Play %d messages" to "播放 %d 則留言",
            "Message from %@" to "%@的留言", "Voicemail from %@" to "%@的語音留言",
            "Message from %@. Sent %@." to "%@的留言，傳送於%@。", "Voicemail from %@. Sent %@." to "%@的語音留言，傳送於%@。",
            "Text from %@" to "%@傳來的簡訊", "Text from %@. Sent %@." to "%@傳來的簡訊，傳送於%@。", "Translated from %@" to "譯自%@",
            "It came with a picture, which Porch can't show yet." to "這則簡訊附有一張圖片，Porch 目前還無法顯示。",
            "It came with %d pictures, which Porch can't show yet." to "這則簡訊附有 %d 張圖片，Porch 目前還無法顯示。",
            "It came with something Porch can't show yet." to "這則簡訊附有 Porch 目前還無法顯示的內容。",
            "Sent %@" to "傳送於%@", "Stop" to "停止", "No new messages." to "沒有新留言。", "Unknown caller" to "未知來電", "You have 1 new message." to "你有 1 則新留言。", "You have %d new messages." to "你有 %d 則新留言。", "Not now" to "稍後",
            "A family member" to "家人",
            "Morning" to "早上", "Afternoon" to "下午", "Evening" to "傍晚", "Night" to "夜晚",
            "Spring" to "春天", "Summer" to "夏天", "Fall" to "秋天", "Winter" to "冬天",
            "Call someone" to "打電話", "Caregiver mode" to "照顧者設定",
            "Tap or hold to manage contacts and settings." to "輕點或長按，即可管理聯絡人與設定。",
            "Who would you like to call?" to "您想打給誰？",
            "Tap a name or press their number on the keypad." to "請輕點姓名，或按下按鍵板上對應的數字。",
            "Back to clock" to "返回時鐘", "Press %@" to "按 %@",
            "Call %@, key %@" to "打給%@，按 %@",
            "Your caregiver can add people using the settings icon on the clock screen." to "請照顧者使用時鐘畫面的設定圖示新增聯絡人。",
            "Use this key to answer or end a call." to "通話時，按此鍵即可接聽或掛斷。",
            "Use this key to turn your camera off or on during a video call." to "視訊通話時，按此鍵即可開啟或關閉鏡頭。",
            "No one is assigned to %@.\nPlease choose another number." to "%@ 號尚未設定聯絡人。\n請選擇其他號碼。",
            "Finish Porch setup" to "請完成 Porch 設定",
            "Open caregiver mode and invite this person to Porch or add their phone number." to "請照顧者邀請這位聯絡人加入 Porch，或新增電話號碼。",
            "Porch isn't ready" to "Porch 尚未準備好",
            "Check People and Drop-in in caregiver mode, then try again." to "請照顧者檢查家人與自動接聽設定，再試一次。",
            "Couldn't call %@" to "無法打給%@", "Please ask your caregiver for help, then try again." to "請照顧者協助檢查後，再試一次。",
            "OK" to "好", "Connecting…" to "正在連線…", "Your camera preview" to "您的鏡頭畫面",
            "Voice call\nCamera is off" to "語音通話\n鏡頭已關閉", "Waiting for video" to "正在等待視訊畫面",
            "Mute" to "關閉麥克風", "Unmute" to "開啟麥克風", "Camera off" to "關閉鏡頭", "Camera on" to "開啟鏡頭", "End call" to "掛斷",
            "Couldn't start the call." to "無法開始通話。", "Key %@: hang up" to "按 %@：掛斷",
            "Key %@: video off / on" to "按 %@：關閉／開啟鏡頭", "Phone call connected" to "電話已接通",
            "Reconnecting phone call…" to "正在重新連接電話…", "Calling %@'s phone…" to "正在撥打%@的電話…",
            "Voice call connected" to "語音已接通", "Video call connected" to "視訊已接通", "Connecting audio…" to "正在連接聲音…",
            "Waiting for %@…" to "正在等待%@…", "Connecting with %@…" to "正在與%@連線…", "Calling %@ on Porch…" to "正在透過 Porch 打給%@…",
            "Calling %@…" to "正在撥打給%@…", "Calling %@." to "正在打給%@。", "%@ joined the call" to "%@已加入通話", "%@ left the call" to "%@已離開通話",
            "Trying %@ on Porch…\nTheir phone will ring if Porch isn't answered." to "正在透過 Porch 打給%@…\n若無人接聽，將改撥電話。",
            "Couldn't connect the call. Please try again." to "無法接通，請再試一次。",
            "Couldn't change camera. Try again." to "無法切換鏡頭，請再試一次。", "Couldn't change microphone. Try again." to "無法切換麥克風，請再試一次。",
            "Ending call…" to "正在結束通話…", "Reconnecting…" to "正在重新連線…",
            "Retry ending phone call" to "重試掛斷電話",
            "Porch disconnected. Couldn't confirm the phone call ended. Check the internet connection and try again." to "Porch 已中斷，無法確認電話是否已掛斷。請檢查網路後再試一次。",
            "Call ended. Returning to the clock…" to "通話已結束，正在返回時鐘…", "Call ended. Returning to Porch…" to "通話已結束，正在返回 Porch…",
            "No one joined. Returning to the clock…" to "無人接聽，正在返回時鐘…",
            "The call disconnected. Returning to the clock…" to "通話已中斷，正在返回時鐘…",
            "The phone call ended before it was answered." to "電話尚未接聽就已結束。",
            "Microphone access is required." to "需要開啟麥克風權限。",
            "Allow Porch's microphone in Settings to make a phone call." to "請照顧者在 iPad 設定中允許 Porch 使用麥克風。",
            "Couldn't switch to their phone." to "無法改撥電話。", "Couldn't finish connecting the Porch call." to "無法完成 Porch 連線。",
            "They answered Porch, but this device couldn't connect. Please try again." to "對方已接聽，但此裝置無法連線。請再試一次。",
            "Porch wasn't answered. Trying %@'s phone…" to "Porch 無人接聽，正在改撥%@的電話…",
            "Phone call\nCamera is off" to "電話通話\n鏡頭已關閉", "Couldn't connect their phone." to "無法接通電話。",
            "Their phone didn't answer. Returning to the clock…" to "電話無人接聽，正在返回時鐘…",
            "Answer" to "接聽", "Answer video call" to "接聽視訊", "Answer audio call" to "接聽語音", "Don't connect" to "不要接通", "Decline" to "拒接",
            "Press %@ to stop this drop-in." to "按 %@ 即可取消自動接聽。",
            "Tap %@ to answer. Hold %@ to decline." to "輕按 %@ 接聽，長按 %@ 拒接。",
            "Video drop-in\nConnecting in %d…" to "視訊自動接聽\n%d 秒後接通…",
            "Audio drop-in\nConnecting in %d…" to "語音自動接聽\n%d 秒後接通…",
            "Incoming video call" to "有視訊來電", "Incoming audio call" to "有語音來電",
            "Announcing video drop-in…" to "正在提示視訊自動接聽…", "Announcing audio drop-in…" to "正在提示語音自動接聽…",
            "%@ is dropping in with video. Connecting in five seconds." to "%@要和您視訊通話，五秒後接通。",
            "%@ is dropping in with audio. Connecting in five seconds." to "%@要和您語音通話，五秒後接通。",
            "The sound couldn't play. Tap Answer to connect." to "無法播放提示音，請按接聽以接通。",
            "Allow microphone access in iPad Settings → Privacy & Security → Microphone to make calls." to "請照顧者在 iPad「設定」→「隱私權與安全性」→「麥克風」中允許 Porch 使用麥克風。",
            "Allow camera access in iPad Settings → Privacy & Security → Camera, or choose Voice in this person's setup." to "請照顧者在 iPad 設定中允許 Porch 使用相機，或改用語音通話。"
        )
    }
}
