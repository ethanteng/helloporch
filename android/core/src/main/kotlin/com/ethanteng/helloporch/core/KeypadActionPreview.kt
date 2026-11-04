package com.ethanteng.helloporch.core

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/** A pure description of a key's meaning. It has no call, media, URL-launch,
 * network, settings-write, or action-execution dependency. */
class KeypadActionPreview(slots: CallSlots) {
    @Serializable
    enum class Context(val title: String) {
        @SerialName("clock") CLOCK("Clock"),
        @SerialName("incoming") INCOMING("Incoming call"),
        @SerialName("voiceCall") VOICE_CALL("Voice call"),
        @SerialName("videoCall") VIDEO_CALL("Video call"),
        @SerialName("dropIn") DROP_IN("Drop-in countdown"),
        @SerialName("messages") MESSAGES("Playing messages"),
    }

    @Serializable
    data class Result(
        val symbol: String,
        val context: Context,
        val action: KeypadAction? = null,
        val kind: Kind,
        val title: String,
        val detail: String,
        val contactName: String? = null,
        val selectedDigit: Int? = null,
        val cameraOn: Boolean? = null,
    ) {
        @Serializable
        enum class Kind {
            @SerialName("person") PERSON,
            @SerialName("unassigned") UNASSIGNED,
            @SerialName("answer") ANSWER,
            @SerialName("hangUp") HANG_UP,
            @SerialName("cancelDropIn") CANCEL_DROP_IN,
            @SerialName("camera") CAMERA,
            @SerialName("playMessages") PLAY_MESSAGES,
            @SerialName("stopMessages") STOP_MESSAGES,
            @SerialName("unmapped") UNMAPPED,
            @SerialName("ignored") IGNORED,
        }
    }

    private val saved = slots.copy()
    /** The keypad being previewed, which the preview never changes. */
    val slots: CallSlots get() = saved.copy()
    var context: Context = Context.CLOCK
        private set
    var cameraOn = true
        private set

    fun setContext(context: Context) {
        this.context = context
        cameraOn = true
    }

    fun receive(symbol: String): Result {
        fun result(kind: Result.Kind, title: String, detail: String, action: KeypadAction? = null, name: String? = null, selected: Int? = null,
            camera: Boolean? = null) = Result(symbol, context, action, kind, title, detail, name, selected, camera)

        val digit = CallSlots.digit(symbol)
        val action = digit?.let(saved::action)
        if (digit == null || action == null) {
            return result(Result.Kind.UNMAPPED, "No action assigned to $symbol", "Only saved key assignments are previewed. No action was performed.")
        }
        if (action == KeypadAction.CALL_CONTROL) {
            return when (context) {
                Context.INCOMING -> result(Result.Kind.ANSWER, "Would answer the incoming call", "Tap behavior only. These digit reports do not provide hold/release timing for declining.", action)
                Context.VOICE_CALL, Context.VIDEO_CALL -> result(Result.Kind.HANG_UP, "Would hang up", "The simulated call would end. No real call is active in this preview.", action)
                Context.DROP_IN -> result(Result.Kind.CANCEL_DROP_IN, "Would stop the drop-in", "The simulated countdown would be cancelled.", action)
                Context.MESSAGES -> result(Result.Kind.STOP_MESSAGES, "Would stop the message", "No message audio is played in this preview.", action)
                Context.CLOCK -> result(Result.Kind.IGNORED, "No call to answer or end", "This is the saved call-control key. Choose a simulated call state to test it.", action)
            }
        }
        if (action == KeypadAction.TOGGLE_VIDEO) {
            if (context == Context.VIDEO_CALL) {
                cameraOn = !cameraOn
                return result(Result.Kind.CAMERA, "Would turn the camera ${if (cameraOn) "on" else "off"}", "Preview state only. The camera is never opened.", action, camera = cameraOn)
            }
            return result(Result.Kind.IGNORED, "Camera key · no video call", "This key toggles the camera during a Porch video call.", action)
        }
        if (context == Context.MESSAGES && action == KeypadAction.MESSAGES) {
            return result(Result.Kind.STOP_MESSAGES, "Would stop the message", "No message audio is played in this preview.", action)
        }
        if (context != Context.CLOCK) {
            return result(Result.Kind.IGNORED, "Key $symbol has no action in this state",
                if (action == KeypadAction.UNASSIGNED) "This key is set to No action." else "The saved ${action.title.lowercase()} action is available from the clock.", action)
        }
        if (action == KeypadAction.MESSAGES) {
            return result(Result.Kind.PLAY_MESSAGES, "Would open messages", "Message availability is not fetched or changed in this preview.", action)
        }
        val person = saved.contact(digit)
            ?: return result(Result.Kind.UNASSIGNED, "No action assigned to $symbol", "This key is set to No action in the saved HelloPorch setup.", action, selected = digit)
        return result(Result.Kind.PERSON, "Would call ${person.name}",
            "${if (person.nativeCall.mode == NativeCall.Mode.VIDEO) "Video" else "Voice"} call selected from the saved HelloPorch assignment. No call was placed.",
            action, person.name, digit)
    }
}
