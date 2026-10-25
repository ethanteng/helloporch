import Foundation

public enum BedsideLanguage: String, Codable, CaseIterable {
    case english = "en"
    case traditionalChinese = "zh-Hant"
    case simplifiedChinese = "zh-Hans"
    case cantonese = "yue-Hant"
    case spanish = "es"

    public var displayName: String {
        switch self {
        case .english: return "English"
        case .traditionalChinese: return "繁體中文"
        case .simplifiedChinese: return "简体中文"
        case .cantonese: return "廣東話"
        case .spanish: return "Español"
        }
    }
    public var locale: Locale {
        switch self {
        case .english: return Locale(identifier: "en_US")
        case .traditionalChinese: return Locale(identifier: "zh_Hant_TW")
        case .simplifiedChinese: return Locale(identifier: "zh_Hans_CN")
        case .cantonese: return Locale(identifier: "zh_Hant_HK")
        case .spanish: return Locale(identifier: "es_ES")
        }
    }
    public var speechLanguage: String {
        switch self {
        case .english: return "en-US"
        case .traditionalChinese: return "zh-TW"
        case .simplifiedChinese: return "zh-CN"
        case .cantonese: return "zh-HK"
        case .spanish: return "es-ES"
        }
    }
    /// English/Spanish allow regional accents. Chinese choices retain their dialect/region.
    public func supportsSpeechVoice(language tag: String) -> Bool {
        let tag = tag.replacingOccurrences(of: "_", with: "-").lowercased()
        let base = tag.split(separator: "-").first.map(String.init)
        switch self {
        case .english: return base == "en"
        case .spanish: return base == "es"
        case .traditionalChinese: return ["zh-tw", "zh-hant-tw", "cmn-tw", "cmn-hant-tw"].contains(tag)
        case .simplifiedChinese: return ["zh-cn", "zh-hans-cn", "cmn-cn", "cmn-hans-cn"].contains(tag)
        case .cantonese: return ["zh-hk", "zh-hant-hk", "yue-hk", "yue-hant-hk"].contains(tag)
        }
    }
    var translations: [String: String] {
        switch self {
        case .english: return [:]
        case .traditionalChinese: return Self.traditionalStrings
        case .simplifiedChinese: return Self.simplifiedStrings
        case .cantonese: return Self.cantoneseStrings
        case .spanish: return Self.spanishStrings
        }
    }
    public func text(_ english: String) -> String { translations[english] ?? english }
    public func format(_ english: String, arguments: [CVarArg]) -> String { String(format: text(english), locale: locale, arguments: arguments) }

    private static let simplifiedStrings: [String: String] = [
        "%@ didn't answer.": "%@没有接听。", "%@ isn't available right now.": "%@现在无法接听。",
        "Leave a message for %@": "给%@留言", "Speak after the beep.": "请在嘀声后说话。", "Recording your message…": "正在录制留言…",
        "Send message": "发送留言", "Don't send": "不发送", "Press %@ when you're finished.": "说完后请按 %@。",
        "Your message is on its way to %@.": "您的留言正在发送给%@。", "No message was recorded.": "没有录到留言。", "Message not sent.": "留言未发送。",
        "%@ didn't answer. Please leave a message after the beep.": "%@没有接听。请在嘀声后留言。",
        "%@ isn't available right now. Please leave a message after the beep.": "%@现在无法接听。请在嘀声后留言。",
        "Couldn't record a message.": "无法录制留言。",
        "Play 1 message": "播放 1 则留言", "Play %d messages": "播放 %d 则留言",
        "Message from %@": "%@的留言", "Voicemail from %@": "%@的语音留言",
        "Message from %@. Sent %@.": "%@的留言，发送于%@。", "Voicemail from %@. Sent %@.": "%@的语音留言，发送于%@。",
        "Sent %@": "发送于%@", "Stop": "停止", "No new messages.": "没有新留言。", "Unknown caller": "未知来电", "You have 1 new message.": "你有 1 则新留言。", "You have %d new messages.": "你有 %d 则新留言。", "Not now": "稍后",
        "Morning": "早上", "Afternoon": "下午", "Evening": "傍晚", "Night": "夜晚",
        "Spring": "春天", "Summer": "夏天", "Fall": "秋天", "Winter": "冬天",
        "Call someone": "打电话", "Caregiver mode": "照护者设置",
        "Tap or hold to manage contacts and settings.": "轻点或长按，即可管理联系人和设置。",
        "Who would you like to call?": "您想打给谁？",
        "Tap a name or press their number on the keypad.": "请轻点姓名，或按下键盘上对应的数字。",
        "Back to clock": "返回时钟", "Press %@": "按 %@",
        "Call %@, key %@": "打给%@，按 %@",
        "Your caregiver can add people using the settings icon on the clock screen.": "请照护者使用时钟画面的设置图标添加联系人。",
        "Use this key to answer or end a call.": "通话时，按此键即可接听或挂断。",
        "Use this key to turn your camera off or on during a video call.": "视频通话时，按此键即可开启或关闭摄像头。",
        "No one is assigned to %@.\nPlease choose another number.": "%@ 号尚未设置联系人。\n请选择其他号码。",
        "Finish Porch setup": "请完成 Porch 设置",
        "Open caregiver mode and invite this person to Porch or add their phone number.": "请照护者邀请这位联系人加入 Porch，或添加电话号码。",
        "Porch isn't ready": "Porch 尚未准备好",
        "Check Family & drop-in in caregiver mode, then try again.": "请照护者检查家人与自动接听设置，再试一次。",
        "Couldn't call %@": "无法打给%@", "Please ask your caregiver for help, then try again.": "请照护者协助检查后，再试一次。",
        "OK": "好", "Connecting…": "正在连接…", "Your camera preview": "您的摄像头画面",
        "Voice call\nCamera is off": "语音通话\n摄像头已关闭", "Waiting for video": "正在等待视频画面",
        "Mute": "关闭麦克风", "Unmute": "开启麦克风", "Camera off": "关闭摄像头", "Camera on": "开启摄像头", "End call": "挂断",
        "Couldn't start the call.": "无法开始通话。", "Key %@: hang up": "按 %@：挂断",
        "Key %@: video off / on": "按 %@：关闭／开启摄像头", "Phone call connected": "电话已接通",
        "Reconnecting phone call…": "正在重新连接电话…", "Calling %@'s phone…": "正在拨打%@的电话…",
        "Voice call connected": "语音已接通", "Video call connected": "视频已接通", "Connecting audio…": "正在连接声音…",
        "Waiting for %@…": "正在等待%@…", "Connecting with %@…": "正在与%@连接…", "Calling %@ on Porch…": "正在通过 Porch 打给%@…",
        "Calling %@…": "正在呼叫%@…", "Calling %@.": "正在打给%@。", "%@ joined the call": "%@已加入通话", "%@ left the call": "%@已离开通话",
        "Trying %@ on Porch…\nTheir phone will ring if Porch isn't answered.": "正在通过 Porch 打给%@…\n若无人接听，将改拨电话。",
        "Couldn't connect the call. Please try again.": "无法接通，请再试一次。",
        "Couldn't change camera. Try again.": "无法切换摄像头，请再试一次。", "Couldn't change microphone. Try again.": "无法切换麦克风，请再试一次。",
        "Ending call…": "正在结束通话…", "Reconnecting…": "正在重新连接…",
        "Retry ending phone call": "重试挂断电话",
        "Porch disconnected. Couldn't confirm the phone call ended. Check the internet connection and try again.": "Porch 已断开，无法确认电话是否已挂断。请检查网络后再试一次。",
        "Call ended. Returning to the clock…": "通话已结束，正在返回时钟…", "Call ended. Returning to Porch…": "通话已结束，正在返回 Porch…",
        "No one joined. Returning to the clock…": "无人接听，正在返回时钟…",
        "The call disconnected. Returning to the clock…": "通话已断开，正在返回时钟…",
        "The phone call ended before it was answered.": "电话尚未接听就已结束。",
        "Microphone access is required.": "需要开启麦克风权限。",
        "Allow Porch's microphone in Settings to make a phone call.": "请照护者在 iPad 设置中允许 Porch 使用麦克风。",
        "Couldn't switch to their phone.": "无法改拨电话。", "Couldn't finish connecting the Porch call.": "无法完成 Porch 连接。",
        "They answered Porch, but this device couldn't connect. Please try again.": "对方已接听，但此设备无法连接。请再试一次。",
        "Porch wasn't answered. Trying %@'s phone…": "Porch 无人接听，正在改拨%@的电话…",
        "Phone call\nCamera is off": "电话通话\n摄像头已关闭", "Couldn't connect their phone.": "无法接通电话。",
        "Their phone didn't answer. Returning to the clock…": "电话无人接听，正在返回时钟…",
        "Answer": "接听", "Answer video call": "接听视频", "Answer audio call": "接听语音", "Don't connect": "不要接通", "Decline": "拒接",
        "Press %@ to stop this drop-in.": "按 %@ 即可取消自动接听。",
        "Tap %@ to answer. Hold %@ to decline.": "轻按 %@ 接听，长按 %@ 拒接。",
        "Video drop-in\nConnecting in %d…": "视频自动接听\n%d 秒后接通…",
        "Audio drop-in\nConnecting in %d…": "语音自动接听\n%d 秒后接通…",
        "Incoming video call": "有视频来电", "Incoming audio call": "有语音来电",
        "Announcing video drop-in…": "正在提示视频自动接听…", "Announcing audio drop-in…": "正在提示语音自动接听…",
        "%@ is dropping in with video. Connecting in five seconds.": "%@要和您视频通话，五秒后接通。",
        "%@ is dropping in with audio. Connecting in five seconds.": "%@要和您语音通话，五秒后接通。",
        "The sound couldn't play. Tap Answer to connect.": "无法播放提示音，请按接听以接通。",
        "Allow microphone access in iPad Settings → Privacy & Security → Microphone to make calls.": "请照护者在 iPad「设置」→「隐私与安全性」→「麦克风」中允许 Porch 使用麦克风。",
        "Allow camera access in iPad Settings → Privacy & Security → Camera, or choose Voice in this person's setup.": "请照护者在 iPad 设置中允许 Porch 使用相机，或改用语音通话。",
        "A family member": "家人"
    ]

    private static let cantoneseStrings: [String: String] = [
        "%@ didn't answer.": "%@冇接聽。", "%@ isn't available right now.": "%@而家未能接聽。",
        "Leave a message for %@": "留言畀%@", "Speak after the beep.": "請喺嘟一聲之後講。", "Recording your message…": "錄緊留言…",
        "Send message": "傳送留言", "Don't send": "唔傳送", "Press %@ when you're finished.": "講完請按 %@。",
        "Your message is on its way to %@.": "您嘅留言正傳送畀%@。", "No message was recorded.": "冇錄到留言。", "Message not sent.": "留言冇傳送。",
        "%@ didn't answer. Please leave a message after the beep.": "%@冇接聽。請喺嘟一聲之後留言。",
        "%@ isn't available right now. Please leave a message after the beep.": "%@而家未能接聽。請喺嘟一聲之後留言。",
        "Couldn't record a message.": "錄唔到留言。",
        "Play 1 message": "播放 1 個留言", "Play %d messages": "播放 %d 個留言",
        "Message from %@": "%@嘅留言", "Voicemail from %@": "%@嘅語音留言",
        "Message from %@. Sent %@.": "%@嘅留言，喺%@傳送。", "Voicemail from %@. Sent %@.": "%@嘅語音留言，喺%@傳送。",
        "Sent %@": "喺%@傳送", "Stop": "停止", "No new messages.": "冇新留言。", "Unknown caller": "未知來電", "You have 1 new message.": "你有 1 個新留言。", "You have %d new messages.": "你有 %d 個新留言。", "Not now": "遲啲先",
        "Morning": "朝早", "Afternoon": "下晝", "Evening": "黃昏", "Night": "夜晚",
        "Spring": "春天", "Summer": "夏天", "Fall": "秋天", "Winter": "冬天",
        "Call someone": "打電話", "Caregiver mode": "照顧者設定",
        "Tap or hold to manage contacts and settings.": "輕按或長按，就可以管理聯絡人同設定。",
        "Who would you like to call?": "您想打畀邊個？",
        "Tap a name or press their number on the keypad.": "請輕按姓名，或者按鍵盤上對應嘅數字。",
        "Back to clock": "返回時鐘", "Press %@": "按 %@",
        "Call %@, key %@": "打畀%@，按 %@",
        "Your caregiver can add people using the settings icon on the clock screen.": "請照顧者用時鐘畫面嘅設定圖示加入聯絡人。",
        "Use this key to answer or end a call.": "通話時，按呢個掣就可以接聽或者收線。",
        "Use this key to turn your camera off or on during a video call.": "視像通話時，按呢個掣就可以開關鏡頭。",
        "No one is assigned to %@.\nPlease choose another number.": "%@ 號未有設定聯絡人。\n請揀另一個號碼。",
        "Finish Porch setup": "請完成 Porch 設定",
        "Open caregiver mode and invite this person to Porch or add their phone number.": "請照顧者邀請呢位聯絡人加入 Porch，或者加入電話號碼。",
        "Porch isn't ready": "Porch 仲未準備好",
        "Check Family & drop-in in caregiver mode, then try again.": "請照顧者檢查家人同自動接聽設定，再試一次。",
        "Couldn't call %@": "打唔到畀%@", "Please ask your caregiver for help, then try again.": "請照顧者幫手檢查，再試一次。",
        "OK": "好", "Connecting…": "連線中…", "Your camera preview": "您嘅鏡頭畫面",
        "Voice call\nCamera is off": "語音通話\n鏡頭已關閉", "Waiting for video": "等緊視像畫面",
        "Mute": "關閉咪高峰", "Unmute": "開啟咪高峰", "Camera off": "關閉鏡頭", "Camera on": "開啟鏡頭", "End call": "收線",
        "Couldn't start the call.": "開始唔到通話。", "Key %@: hang up": "按 %@：收線",
        "Key %@: video off / on": "按 %@：關閉／開啟鏡頭", "Phone call connected": "電話已接通",
        "Reconnecting phone call…": "重新接駁電話中…", "Calling %@'s phone…": "打緊畀%@嘅電話…",
        "Voice call connected": "語音已接通", "Video call connected": "視像已接通", "Connecting audio…": "接駁聲音中…",
        "Waiting for %@…": "等緊%@…", "Connecting with %@…": "同%@連線中…", "Calling %@ on Porch…": "用緊 Porch 打畀%@…",
        "Calling %@…": "打緊畀%@…", "Calling %@.": "打緊畀%@。", "%@ joined the call": "%@加入咗通話", "%@ left the call": "%@離開咗通話",
        "Trying %@ on Porch…\nTheir phone will ring if Porch isn't answered.": "用緊 Porch 打畀%@…\n如果冇人接聽，就會改打電話。",
        "Couldn't connect the call. Please try again.": "接唔通，請再試一次。",
        "Couldn't change camera. Try again.": "切換唔到鏡頭，請再試一次。", "Couldn't change microphone. Try again.": "切換唔到咪高峰，請再試一次。",
        "Ending call…": "結束通話中…", "Reconnecting…": "重新連線中…",
        "Retry ending phone call": "再試收線",
        "Porch disconnected. Couldn't confirm the phone call ended. Check the internet connection and try again.": "Porch 已斷線，確認唔到電話係咪已經收線。請檢查網絡，再試一次。",
        "Call ended. Returning to the clock…": "通話已結束，返回時鐘中…", "Call ended. Returning to Porch…": "通話已結束，返回 Porch 中…",
        "No one joined. Returning to the clock…": "冇人接聽，返回時鐘中…",
        "The call disconnected. Returning to the clock…": "通話已斷線，返回時鐘中…",
        "The phone call ended before it was answered.": "電話未接聽就已經結束。",
        "Microphone access is required.": "需要開啟咪高峰權限。",
        "Allow Porch's microphone in Settings to make a phone call.": "請照顧者喺 iPad 設定入面允許 Porch 使用咪高峰。",
        "Couldn't switch to their phone.": "改打唔到電話。", "Couldn't finish connecting the Porch call.": "完成唔到 Porch 連線。",
        "They answered Porch, but this device couldn't connect. Please try again.": "對方已接聽，但呢部裝置連唔到線。請再試一次。",
        "Porch wasn't answered. Trying %@'s phone…": "Porch 冇人接聽，改打%@嘅電話中…",
        "Phone call\nCamera is off": "電話通話\n鏡頭已關閉", "Couldn't connect their phone.": "打唔通電話。",
        "Their phone didn't answer. Returning to the clock…": "電話冇人接聽，返回時鐘中…",
        "Answer": "接聽", "Answer video call": "接聽視像", "Answer audio call": "接聽語音", "Don't connect": "唔好接通", "Decline": "拒接",
        "Press %@ to stop this drop-in.": "按 %@ 就可以取消自動接聽。",
        "Tap %@ to answer. Hold %@ to decline.": "輕按 %@ 接聽，長按 %@ 拒接。",
        "Video drop-in\nConnecting in %d…": "視像自動接聽\n%d 秒後接通…",
        "Audio drop-in\nConnecting in %d…": "語音自動接聽\n%d 秒後接通…",
        "Incoming video call": "有視像來電", "Incoming audio call": "有語音來電",
        "Announcing video drop-in…": "提示視像自動接聽中…", "Announcing audio drop-in…": "提示語音自動接聽中…",
        "%@ is dropping in with video. Connecting in five seconds.": "%@想同您視像通話，五秒後接通。",
        "%@ is dropping in with audio. Connecting in five seconds.": "%@想同您語音通話，五秒後接通。",
        "The sound couldn't play. Tap Answer to connect.": "播唔到提示聲，請按接聽嚟接通。",
        "Allow microphone access in iPad Settings → Privacy & Security → Microphone to make calls.": "請照顧者喺 iPad「設定」→「私隱與保安」→「咪高峰」入面允許 Porch 使用咪高峰。",
        "Allow camera access in iPad Settings → Privacy & Security → Camera, or choose Voice in this person's setup.": "請照顧者喺 iPad 設定入面允許 Porch 使用相機，或者改用語音通話。",
        "A family member": "屋企人"
    ]

    private static let spanishStrings: [String: String] = [
        "%@ didn't answer.": "%@ no ha contestado.", "%@ isn't available right now.": "%@ no está disponible ahora.",
        "Leave a message for %@": "Deje un mensaje para %@", "Speak after the beep.": "Hable después del pitido.", "Recording your message…": "Grabando su mensaje…",
        "Send message": "Enviar mensaje", "Don't send": "No enviar", "Press %@ when you're finished.": "Pulse %@ cuando termine.",
        "Your message is on its way to %@.": "Su mensaje se está enviando a %@.", "No message was recorded.": "No se ha grabado ningún mensaje.", "Message not sent.": "Mensaje no enviado.",
        "%@ didn't answer. Please leave a message after the beep.": "%@ no ha contestado. Deje un mensaje después del pitido.",
        "%@ isn't available right now. Please leave a message after the beep.": "%@ no está disponible ahora. Deje un mensaje después del pitido.",
        "Couldn't record a message.": "No se ha podido grabar el mensaje.",
        "Play 1 message": "Reproducir 1 mensaje", "Play %d messages": "Reproducir %d mensajes",
        "Message from %@": "Mensaje de %@", "Voicemail from %@": "Mensaje de voz de %@",
        "Message from %@. Sent %@.": "Mensaje de %@. Enviado %@.", "Voicemail from %@. Sent %@.": "Mensaje de voz de %@. Enviado %@.",
        "Sent %@": "Enviado %@", "Stop": "Detener", "No new messages.": "No hay mensajes nuevos.", "Unknown caller": "Número desconocido", "You have 1 new message.": "Tienes 1 mensaje nuevo.", "You have %d new messages.": "Tienes %d mensajes nuevos.", "Not now": "Ahora no",
        "Morning": "Mañana", "Afternoon": "Tarde", "Evening": "Atardecer", "Night": "Noche",
        "Spring": "Primavera", "Summer": "Verano", "Fall": "Otoño", "Winter": "Invierno",
        "Call someone": "Llamar a alguien", "Caregiver mode": "Ajustes del cuidador",
        "Tap or hold to manage contacts and settings.": "Toque o mantenga pulsado para gestionar contactos y ajustes.",
        "Who would you like to call?": "¿A quién quiere llamar?",
        "Tap a name or press their number on the keypad.": "Toque un nombre o pulse su número en el teclado.",
        "Back to clock": "Volver al reloj", "Press %@": "Pulse %@",
        "Call %@, key %@": "Llamar a %@, tecla %@",
        "Your caregiver can add people using the settings icon on the clock screen.": "Su cuidador puede añadir contactos con el icono de ajustes en la pantalla del reloj.",
        "Use this key to answer or end a call.": "Use esta tecla para contestar o colgar una llamada.",
        "Use this key to turn your camera off or on during a video call.": "Use esta tecla para apagar o encender la cámara durante una videollamada.",
        "No one is assigned to %@.\nPlease choose another number.": "No hay ningún contacto asignado al %@.\nElija otro número.",
        "Finish Porch setup": "Complete la configuración de Porch",
        "Open caregiver mode and invite this person to Porch or add their phone number.": "Pida a su cuidador que invite a esta persona a Porch o añada su número de teléfono.",
        "Porch isn't ready": "Porch aún no está listo",
        "Check Family & drop-in in caregiver mode, then try again.": "Pida a su cuidador que revise los ajustes de familia y conexión automática e inténtelo de nuevo.",
        "Couldn't call %@": "No se pudo llamar a %@", "Please ask your caregiver for help, then try again.": "Pida ayuda a su cuidador e inténtelo de nuevo.",
        "OK": "Aceptar", "Connecting…": "Conectando…", "Your camera preview": "Vista de su cámara",
        "Voice call\nCamera is off": "Llamada de voz\nCámara apagada", "Waiting for video": "Esperando el vídeo",
        "Mute": "Silenciar", "Unmute": "Activar micrófono", "Camera off": "Apagar cámara", "Camera on": "Encender cámara", "End call": "Colgar",
        "Couldn't start the call.": "No se pudo iniciar la llamada.", "Key %@: hang up": "Tecla %@: colgar",
        "Key %@: video off / on": "Tecla %@: apagar / encender cámara", "Phone call connected": "Llamada telefónica conectada",
        "Reconnecting phone call…": "Reconectando la llamada telefónica…", "Calling %@'s phone…": "Llamando al teléfono de %@…",
        "Voice call connected": "Llamada de voz conectada", "Video call connected": "Videollamada conectada", "Connecting audio…": "Conectando el audio…",
        "Waiting for %@…": "Esperando a %@…", "Connecting with %@…": "Conectando con %@…", "Calling %@ on Porch…": "Llamando a %@ por Porch…",
        "Calling %@…": "Llamando a %@…", "Calling %@.": "Llamando a %@.", "%@ joined the call": "%@ se unió a la llamada", "%@ left the call": "%@ salió de la llamada",
        "Trying %@ on Porch…\nTheir phone will ring if Porch isn't answered.": "Llamando a %@ por Porch…\nSi no contesta, sonará su teléfono.",
        "Couldn't connect the call. Please try again.": "No se pudo conectar la llamada. Inténtelo de nuevo.",
        "Couldn't change camera. Try again.": "No se pudo cambiar la cámara. Inténtelo de nuevo.", "Couldn't change microphone. Try again.": "No se pudo cambiar el micrófono. Inténtelo de nuevo.",
        "Ending call…": "Finalizando la llamada…", "Reconnecting…": "Reconectando…",
        "Retry ending phone call": "Intentar colgar de nuevo",
        "Porch disconnected. Couldn't confirm the phone call ended. Check the internet connection and try again.": "Porch se ha desconectado. No se pudo confirmar que la llamada haya terminado. Compruebe la conexión a internet e inténtelo de nuevo.",
        "Call ended. Returning to the clock…": "Llamada finalizada. Volviendo al reloj…", "Call ended. Returning to Porch…": "Llamada finalizada. Volviendo a Porch…",
        "No one joined. Returning to the clock…": "Nadie ha contestado. Volviendo al reloj…",
        "The call disconnected. Returning to the clock…": "Se ha desconectado la llamada. Volviendo al reloj…",
        "The phone call ended before it was answered.": "La llamada telefónica terminó antes de que contestaran.",
        "Microphone access is required.": "Se necesita acceso al micrófono.",
        "Allow Porch's microphone in Settings to make a phone call.": "Pida a su cuidador que permita a Porch usar el micrófono en los ajustes del iPad.",
        "Couldn't switch to their phone.": "No se pudo llamar a su teléfono.", "Couldn't finish connecting the Porch call.": "No se pudo completar la conexión de Porch.",
        "They answered Porch, but this device couldn't connect. Please try again.": "Han contestado en Porch, pero este dispositivo no pudo conectarse. Inténtelo de nuevo.",
        "Porch wasn't answered. Trying %@'s phone…": "No han contestado en Porch. Llamando al teléfono de %@…",
        "Phone call\nCamera is off": "Llamada telefónica\nCámara apagada", "Couldn't connect their phone.": "No se pudo conectar con su teléfono.",
        "Their phone didn't answer. Returning to the clock…": "No han contestado al teléfono. Volviendo al reloj…",
        "Answer": "Contestar", "Answer video call": "Contestar videollamada", "Answer audio call": "Contestar llamada de voz", "Don't connect": "No conectar", "Decline": "Rechazar",
        "Press %@ to stop this drop-in.": "Pulse %@ para cancelar esta conexión automática.",
        "Tap %@ to answer. Hold %@ to decline.": "Pulse %@ para contestar. Mantenga pulsado %@ para rechazar.",
        "Video drop-in\nConnecting in %d…": "Videollamada automática\nConexión en %d…",
        "Audio drop-in\nConnecting in %d…": "Llamada de voz automática\nConexión en %d…",
        "Incoming video call": "Videollamada entrante", "Incoming audio call": "Llamada de voz entrante",
        "Announcing video drop-in…": "Anunciando videollamada automática…", "Announcing audio drop-in…": "Anunciando llamada de voz automática…",
        "%@ is dropping in with video. Connecting in five seconds.": "%@ quiere hablar con usted por vídeo. La llamada se conectará en cinco segundos.",
        "%@ is dropping in with audio. Connecting in five seconds.": "%@ quiere hablar con usted por voz. La llamada se conectará en cinco segundos.",
        "The sound couldn't play. Tap Answer to connect.": "No se pudo reproducir el aviso. Toque Contestar para conectar.",
        "Allow microphone access in iPad Settings → Privacy & Security → Microphone to make calls.": "Pida a su cuidador que permita el acceso al micrófono en Ajustes del iPad → Privacidad y seguridad → Micrófono.",
        "Allow camera access in iPad Settings → Privacy & Security → Camera, or choose Voice in this person's setup.": "Pida a su cuidador que permita el acceso a la cámara en los ajustes del iPad o que elija una llamada de voz.",
        "A family member": "Un familiar"
    ]

    private static let traditionalStrings: [String: String] = [
        "%@ didn't answer.": "%@沒有接聽。", "%@ isn't available right now.": "%@現在無法接聽。",
        "Leave a message for %@": "留言給%@", "Speak after the beep.": "請在嗶聲後說話。", "Recording your message…": "正在錄製留言…",
        "Send message": "傳送留言", "Don't send": "不要傳送", "Press %@ when you're finished.": "說完後請按 %@。",
        "Your message is on its way to %@.": "您的留言正在傳送給%@。", "No message was recorded.": "沒有錄到留言。", "Message not sent.": "留言未傳送。",
        "%@ didn't answer. Please leave a message after the beep.": "%@沒有接聽。請在嗶聲後留言。",
        "%@ isn't available right now. Please leave a message after the beep.": "%@現在無法接聽。請在嗶聲後留言。",
        "Couldn't record a message.": "無法錄製留言。",
        "Play 1 message": "播放 1 則留言", "Play %d messages": "播放 %d 則留言",
        "Message from %@": "%@的留言", "Voicemail from %@": "%@的語音留言",
        "Message from %@. Sent %@.": "%@的留言，傳送於%@。", "Voicemail from %@. Sent %@.": "%@的語音留言，傳送於%@。",
        "Sent %@": "傳送於%@", "Stop": "停止", "No new messages.": "沒有新留言。", "Unknown caller": "未知來電", "You have 1 new message.": "你有 1 則新留言。", "You have %d new messages.": "你有 %d 則新留言。", "Not now": "稍後",
        "A family member": "家人",
        "Morning": "早上", "Afternoon": "下午", "Evening": "傍晚", "Night": "夜晚",
        "Spring": "春天", "Summer": "夏天", "Fall": "秋天", "Winter": "冬天",
        "Call someone": "打電話", "Caregiver mode": "照顧者設定",
        "Tap or hold to manage contacts and settings.": "輕點或長按，即可管理聯絡人與設定。",
        "Who would you like to call?": "您想打給誰？",
        "Tap a name or press their number on the keypad.": "請輕點姓名，或按下按鍵板上對應的數字。",
        "Back to clock": "返回時鐘", "Press %@": "按 %@",
        "Call %@, key %@": "打給%@，按 %@",
        "Your caregiver can add people using the settings icon on the clock screen.": "請照顧者使用時鐘畫面的設定圖示新增聯絡人。",
        "Use this key to answer or end a call.": "通話時，按此鍵即可接聽或掛斷。",
        "Use this key to turn your camera off or on during a video call.": "視訊通話時，按此鍵即可開啟或關閉鏡頭。",
        "No one is assigned to %@.\nPlease choose another number.": "%@ 號尚未設定聯絡人。\n請選擇其他號碼。",
        "Finish Porch setup": "請完成 Porch 設定",
        "Open caregiver mode and invite this person to Porch or add their phone number.": "請照顧者邀請這位聯絡人加入 Porch，或新增電話號碼。",
        "Porch isn't ready": "Porch 尚未準備好",
        "Check Family & drop-in in caregiver mode, then try again.": "請照顧者檢查家人與自動接聽設定，再試一次。",
        "Couldn't call %@": "無法打給%@", "Please ask your caregiver for help, then try again.": "請照顧者協助檢查後，再試一次。",
        "OK": "好", "Connecting…": "正在連線…", "Your camera preview": "您的鏡頭畫面",
        "Voice call\nCamera is off": "語音通話\n鏡頭已關閉", "Waiting for video": "正在等待視訊畫面",
        "Mute": "關閉麥克風", "Unmute": "開啟麥克風", "Camera off": "關閉鏡頭", "Camera on": "開啟鏡頭", "End call": "掛斷",
        "Couldn't start the call.": "無法開始通話。", "Key %@: hang up": "按 %@：掛斷",
        "Key %@: video off / on": "按 %@：關閉／開啟鏡頭", "Phone call connected": "電話已接通",
        "Reconnecting phone call…": "正在重新連接電話…", "Calling %@'s phone…": "正在撥打%@的電話…",
        "Voice call connected": "語音已接通", "Video call connected": "視訊已接通", "Connecting audio…": "正在連接聲音…",
        "Waiting for %@…": "正在等待%@…", "Connecting with %@…": "正在與%@連線…", "Calling %@ on Porch…": "正在透過 Porch 打給%@…",
        "Calling %@…": "正在撥打給%@…", "Calling %@.": "正在打給%@。", "%@ joined the call": "%@已加入通話", "%@ left the call": "%@已離開通話",
        "Trying %@ on Porch…\nTheir phone will ring if Porch isn't answered.": "正在透過 Porch 打給%@…\n若無人接聽，將改撥電話。",
        "Couldn't connect the call. Please try again.": "無法接通，請再試一次。",
        "Couldn't change camera. Try again.": "無法切換鏡頭，請再試一次。", "Couldn't change microphone. Try again.": "無法切換麥克風，請再試一次。",
        "Ending call…": "正在結束通話…", "Reconnecting…": "正在重新連線…",
        "Retry ending phone call": "重試掛斷電話",
        "Porch disconnected. Couldn't confirm the phone call ended. Check the internet connection and try again.": "Porch 已中斷，無法確認電話是否已掛斷。請檢查網路後再試一次。",
        "Call ended. Returning to the clock…": "通話已結束，正在返回時鐘…", "Call ended. Returning to Porch…": "通話已結束，正在返回 Porch…",
        "No one joined. Returning to the clock…": "無人接聽，正在返回時鐘…",
        "The call disconnected. Returning to the clock…": "通話已中斷，正在返回時鐘…",
        "The phone call ended before it was answered.": "電話尚未接聽就已結束。",
        "Microphone access is required.": "需要開啟麥克風權限。",
        "Allow Porch's microphone in Settings to make a phone call.": "請照顧者在 iPad 設定中允許 Porch 使用麥克風。",
        "Couldn't switch to their phone.": "無法改撥電話。", "Couldn't finish connecting the Porch call.": "無法完成 Porch 連線。",
        "They answered Porch, but this device couldn't connect. Please try again.": "對方已接聽，但此裝置無法連線。請再試一次。",
        "Porch wasn't answered. Trying %@'s phone…": "Porch 無人接聽，正在改撥%@的電話…",
        "Phone call\nCamera is off": "電話通話\n鏡頭已關閉", "Couldn't connect their phone.": "無法接通電話。",
        "Their phone didn't answer. Returning to the clock…": "電話無人接聽，正在返回時鐘…",
        "Answer": "接聽", "Answer video call": "接聽視訊", "Answer audio call": "接聽語音", "Don't connect": "不要接通", "Decline": "拒接",
        "Press %@ to stop this drop-in.": "按 %@ 即可取消自動接聽。",
        "Tap %@ to answer. Hold %@ to decline.": "輕按 %@ 接聽，長按 %@ 拒接。",
        "Video drop-in\nConnecting in %d…": "視訊自動接聽\n%d 秒後接通…",
        "Audio drop-in\nConnecting in %d…": "語音自動接聽\n%d 秒後接通…",
        "Incoming video call": "有視訊來電", "Incoming audio call": "有語音來電",
        "Announcing video drop-in…": "正在提示視訊自動接聽…", "Announcing audio drop-in…": "正在提示語音自動接聽…",
        "%@ is dropping in with video. Connecting in five seconds.": "%@要和您視訊通話，五秒後接通。",
        "%@ is dropping in with audio. Connecting in five seconds.": "%@要和您語音通話，五秒後接通。",
        "The sound couldn't play. Tap Answer to connect.": "無法播放提示音，請按接聽以接通。",
        "Allow microphone access in iPad Settings → Privacy & Security → Microphone to make calls.": "請照顧者在 iPad「設定」→「隱私權與安全性」→「麥克風」中允許 Porch 使用麥克風。",
        "Allow camera access in iPad Settings → Privacy & Security → Camera, or choose Voice in this person's setup.": "請照顧者在 iPad 設定中允許 Porch 使用相機，或改用語音通話。"
    ]
}
