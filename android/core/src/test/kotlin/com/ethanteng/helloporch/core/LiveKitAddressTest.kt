package com.ethanteng.helloporch.core

import kotlin.test.Test
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class LiveKitAddressTest {
    @Test fun secureAddressesAreAllowed() {
        assertTrue(LiveKitAddress.isAllowed("wss://porch.livekit.cloud"))
        assertTrue(LiveKitAddress.isAllowed("WSS://Porch.LiveKit.Cloud:443"))
    }

    @Test fun anUnencryptedAddressMustBeThisDevice() {
        assertTrue(LiveKitAddress.isAllowed("ws://localhost:7880"))
        assertTrue(LiveKitAddress.isAllowed("ws://127.0.0.1:7880"))
        assertFalse(LiveKitAddress.isAllowed("ws://porch.livekit.cloud"))
        assertFalse(LiveKitAddress.isAllowed("ws://192.168.1.20:7880"))
        assertFalse(LiveKitAddress.isAllowed("ws://localhost.example.com:7880"))
    }

    @Test fun otherAddressesAreNot() {
        assertFalse(LiveKitAddress.isAllowed("https://porch.livekit.cloud"))
        assertFalse(LiveKitAddress.isAllowed("wss://someone@porch.livekit.cloud"))
        assertFalse(LiveKitAddress.isAllowed("not a url"))
        assertFalse(LiveKitAddress.isAllowed(""))
    }
}
