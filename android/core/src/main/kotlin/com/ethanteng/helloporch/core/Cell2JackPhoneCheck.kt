package com.ethanteng.helloporch.core

/**
 * Setup's check of the corded phone, as on iOS (SetupPhoneViewController): connected once the Cell2Jack answers, then
 * a key heard, then the receiver put back. With Hang up when the receiver is put back off, there's no hang-up to
 * check, so the key is the whole check. Keys only show here; nothing acts on them.
 */
sealed interface Cell2JackPhoneCheck {
    data object Waiting : Cell2JackPhoneCheck
    data object Connected : Cell2JackPhoneCheck
    data class Heard(val symbol: String) : Cell2JackPhoneCheck
    data class Done(val message: String) : Cell2JackPhoneCheck

    val checked: Boolean get() = this is Done

    val status: String
        get() = when (this) {
            Waiting -> "Waiting for the phone…"
            Connected -> "The phone is connected. Lift the receiver and press a key."
            is Heard -> "Porch heard $symbol. Now put the receiver back."
            is Done -> message
        }

    /** The Cell2Jack started or stopped answering. Unplugged before the check finished, a hang-up meanwhile went
     * unheard, so the phone has to be heard again, including a key that was already heard. */
    fun answering(ready: Boolean): Cell2JackPhoneCheck = when {
        ready -> if (this == Waiting) Connected else this
        this == Connected || this is Heard -> Waiting
        else -> this
    }

    /** The key the phone sent, such as "5" or "*". */
    fun key(symbol: String, receiverHangUp: Boolean): Cell2JackPhoneCheck = when {
        this is Done -> this
        // Without hanging up on the receiver, there's no hang-up to check.
        receiverHangUp -> Heard(symbol)
        else -> Done("Porch heard $symbol. The phone is ready.")
    }

    /** A hang-up before a key doesn't count: there's no key to have heard yet. */
    fun hangUp(): Cell2JackPhoneCheck = if (this is Heard) Done("Porch heard you hang up. The phone is ready.") else this
}
