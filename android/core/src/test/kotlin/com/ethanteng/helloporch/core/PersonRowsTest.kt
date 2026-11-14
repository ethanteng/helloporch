package com.ethanteng.helloporch.core

import kotlin.test.Test
import kotlin.test.assertEquals

class PersonRowsTest {
    @Test fun dropInSaysWhatsOn() {
        assertEquals("Audio and video", PersonRows.dropIn(paused = false, app = DropInPermissions(audio = true, video = true), phone = false))
        assertEquals("Audio and video · Phone", PersonRows.dropIn(paused = false, app = DropInPermissions(audio = true, video = true), phone = true))
        assertEquals("Audio", PersonRows.dropIn(paused = false, app = DropInPermissions(audio = true, video = false), phone = false))
        assertEquals("Video · Phone", PersonRows.dropIn(paused = false, app = DropInPermissions(audio = false, video = true), phone = true))
        assertEquals("Phone", PersonRows.dropIn(paused = false, app = null, phone = true))
        assertEquals("Phone", PersonRows.dropIn(paused = false, app = DropInPermissions(audio = false, video = false), phone = true))
        assertEquals("Off", PersonRows.dropIn(paused = false, app = DropInPermissions(audio = false, video = false), phone = false))
        assertEquals("Off", PersonRows.dropIn(paused = false, app = null, phone = false))
        assertEquals("Paused", PersonRows.dropIn(paused = true, app = DropInPermissions(audio = true, video = true), phone = true), "Paused for everyone wins")
    }

    @Test fun porchAppFollowsTheKeysInvitation() {
        val open = listOf(PendingFamilyInvitation(id = "a", name = "Linda", expiresAt = 1))
        assertEquals(PersonRows.PorchApp.CONNECTED, PersonRows.porchApp(member = true, invitationID = "gone", open = open))
        assertEquals(PersonRows.PorchApp.INVITE_SENT, PersonRows.porchApp(member = false, invitationID = "a", open = open))
        assertEquals(PersonRows.PorchApp.INVITE_EXPIRED, PersonRows.porchApp(member = false, invitationID = "b", open = open))
        assertEquals(PersonRows.PorchApp.INVITE_EXPIRED, PersonRows.porchApp(member = false, invitationID = "a", open = null))
        assertEquals(PersonRows.PorchApp.NOT_ON_PORCH, PersonRows.porchApp(member = false, invitationID = null, open = open))
        assertEquals(listOf("Connected", "Invite sent", "Invite expired", "Invite"), PersonRows.PorchApp.entries.map { it.value })
    }
}
