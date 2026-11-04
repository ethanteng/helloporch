package com.ethanteng.helloporch.core

import com.ethanteng.helloporch.core.KeypadActionPreview.Context
import com.ethanteng.helloporch.core.KeypadActionPreview.Result.Kind
import com.ethanteng.helloporch.core.ModelFixtures.noPhotos
import com.ethanteng.helloporch.core.ModelFixtures.withStore
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

class KeypadActionPreviewTest {
    private fun configured(): CallSlots {
        val slots = CallSlots()
        slots.setContact(CallContact("Alex", NativeCall("preview-alex", NativeCall.Mode.VOICE)), 1)
        slots.setContact(CallContact("Sam", NativeCall("preview-sam", NativeCall.Mode.VIDEO)), 2)
        return slots
    }

    @Test fun peopleEmptyAndUnmappedSymbols() {
        val slots = configured()
        val preview = KeypadActionPreview(slots)
        assertEquals("Alex", preview.receive("1").contactName)
        assertEquals("Would call Sam", preview.receive("2").title)
        assertTrue(preview.receive("2").detail.startsWith("Video"))
        assertEquals(Kind.UNASSIGNED, preview.receive("3").kind)
        for (key in listOf("*", "#")) assertEquals(Kind.UNASSIGNED, preview.receive(key).kind)
        for (key in listOf("A", "D", "10", "12", "", "١")) assertEquals(Kind.UNMAPPED, preview.receive(key).kind)
        assertEquals(slots, preview.slots, "Preview must not edit the saved mapping")
    }

    @Test fun savedRemappingsAndSimulatedStates() {
        val slots = configured()
        val person = assertNotNull(slots.contact(1))
        slots.setContact(person, 0)
        slots.setContact(person, CallSlots.star)
        slots.setAction(KeypadAction.CALL_CONTROL, 4)
        slots.setAction(KeypadAction.TOGGLE_VIDEO, 7)
        slots.setAction(KeypadAction.MESSAGES, 8)
        val preview = KeypadActionPreview(slots)
        assertEquals(Kind.PERSON, preview.receive("0").kind)
        assertEquals(Kind.PERSON, preview.receive("*").kind)
        assertEquals(CallSlots.star, preview.receive("*").selectedDigit)
        assertEquals(Kind.IGNORED, preview.receive("4").kind)
        assertEquals(Kind.PLAY_MESSAGES, preview.receive("8").kind)
        preview.setContext(Context.INCOMING)
        assertEquals(Kind.ANSWER, preview.receive("4").kind)
        assertEquals(Kind.IGNORED, preview.receive("0").kind)
        preview.setContext(Context.VIDEO_CALL)
        assertEquals(Kind.HANG_UP, preview.receive("4").kind)
        assertEquals(false, preview.receive("7").cameraOn)
        assertEquals(true, preview.receive("7").cameraOn, "Repeated digits must remain distinct preview inputs")
        preview.setContext(Context.VOICE_CALL)
        assertEquals(Kind.IGNORED, preview.receive("7").kind)
        preview.setContext(Context.DROP_IN)
        assertEquals(Kind.CANCEL_DROP_IN, preview.receive("4").kind)
        preview.setContext(Context.MESSAGES)
        assertEquals(Kind.STOP_MESSAGES, preview.receive("4").kind)
        assertEquals(Kind.STOP_MESSAGES, preview.receive("8").kind)
        assertEquals(slots, preview.slots)
    }

    @Test fun snapshotPreservesSavedAssignmentsWithoutChangingSource() = withStore { settings, store ->
        val slots = configured()
        slots.setAction(KeypadAction.MESSAGES, 5)
        slots.setAction(KeypadAction.CALL_CONTROL, CallSlots.pound)
        slots.save(settings, store)
        val bytes = assertNotNull(settings.getString("porch.slots.v2"))
        val symbols = assertNotNull(settings.getString("porch.slots.v2.symbols"))
        val snapshot = CallSlots.snapshot(bytes, symbols, noPhotos)
        assertEquals(slots, snapshot)
        assertEquals(KeypadAction.CALL_CONTROL, snapshot.action(CallSlots.pound))
        assertEquals(KeypadAction.UNASSIGNED, CallSlots.snapshot(bytes, null, noPhotos).action(CallSlots.pound), "A snapshot from before * and # leaves them empty")
        assertEquals(bytes, settings.getString("porch.slots.v2"))
        assertFailsWith<ValidationException> { CallSlots.snapshot("[]", null, noPhotos) }
    }
}
