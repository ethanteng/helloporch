import Foundation

public enum BedsideLanguage: String, Codable, CaseIterable {
    case english = "en"
    case traditionalChinese = "zh-Hant"

    public var locale: Locale { Locale(identifier: self == .traditionalChinese ? "zh_Hant_TW" : "en_US") }
    public var speechLanguage: String { self == .traditionalChinese ? "zh-TW" : "en-US" }
    public func text(_ english: String) -> String { self == .traditionalChinese ? Self.traditional[english] ?? english : english }
    public func format(_ english: String, arguments: [CVarArg]) -> String { String(format: text(english), locale: locale, arguments: arguments) }

    private static let traditional: [String: String] = [
        "Morning": "早上", "Afternoon": "下午", "Evening": "傍晚", "Night": "夜晚",
        "Spring": "春天", "Summer": "夏天", "Fall": "秋天", "Winter": "冬天",
        "Call someone": "打電話", "Caregiver mode": "照顧者設定",
        "Tap or hold to manage contacts and settings.": "輕點或長按，即可管理聯絡人與設定。",
        "Who would you like to call?": "您想打給誰？",
        "Tap a name or press their number on the keypad.": "請輕點姓名，或按下按鍵板上對應的數字。",
        "Back to clock": "返回時鐘", "Press %d": "按 %d",
        "Call %@, key %d": "打給%@，按 %d",
        "Your caregiver can add people using the settings icon on the clock screen.": "請照顧者使用時鐘畫面的設定圖示新增聯絡人。",
        "Use this key to answer or end a call.": "通話時，按此鍵即可接聽或掛斷。",
        "Use this key to turn your camera off or on during a video call.": "視訊通話時，按此鍵即可開啟或關閉鏡頭。",
        "No one is assigned to %d.\nPlease choose another number.": "%d 號尚未設定聯絡人。\n請選擇其他號碼。",
        "Finish Porch setup": "請完成 Porch 設定",
        "Open caregiver mode and invite this person to Porch or add their phone number.": "請照顧者邀請這位聯絡人加入 Porch，或新增電話號碼。",
        "Porch isn't ready": "Porch 尚未準備好",
        "Check Family & drop-in in caregiver mode, then try again.": "請照顧者檢查家人與自動接聽設定，再試一次。",
        "Couldn't call %@": "無法打給%@", "Please ask your caregiver for help, then try again.": "請照顧者協助檢查後，再試一次。",
        "OK": "好", "Connecting…": "正在連線…", "Your camera preview": "您的鏡頭畫面",
        "Voice call\nCamera is off": "語音通話\n鏡頭已關閉", "Waiting for video": "正在等待視訊畫面",
        "Mute": "關閉麥克風", "Unmute": "開啟麥克風", "Camera off": "關閉鏡頭", "Camera on": "開啟鏡頭", "End call": "掛斷",
        "Couldn't start the call.": "無法開始通話。", "Key %d: hang up": "按 %d：掛斷",
        "Key %d: video off / on": "按 %d：關閉／開啟鏡頭", "Phone call connected": "電話已接通",
        "Reconnecting phone call…": "正在重新連接電話…", "Calling %@'s phone…": "正在撥打%@的電話…",
        "Voice call connected": "語音已接通", "Video call connected": "視訊已接通", "Connecting audio…": "正在連接聲音…",
        "Waiting for %@…": "正在等待%@…", "Connecting with %@…": "正在與%@連線…", "Calling %@ on Porch…": "正在透過 Porch 打給%@…",
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
        "Press %d to stop this drop-in.": "按 %d 即可取消自動接聽。",
        "Tap %d to answer. Hold %d to decline.": "輕按 %d 接聽，長按 %d 拒接。",
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
