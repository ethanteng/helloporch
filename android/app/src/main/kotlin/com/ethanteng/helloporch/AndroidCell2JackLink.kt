package com.ethanteng.helloporch

import android.hardware.usb.UsbConstants
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbDeviceConnection
import android.hardware.usb.UsbEndpoint
import android.hardware.usb.UsbInterface
import android.hardware.usb.UsbManager
import com.ethanteng.helloporch.core.Cell2JackException
import com.ethanteng.helloporch.core.Cell2JackLink
import com.ethanteng.helloporch.core.Cell2JackProtocol

/**
 * The Cell2Jack over Android's USB host API, with no driver: interface 0, claimed from any kernel serial driver, and
 * its first bulk IN and bulk OUT endpoints, as the iPad driver picks them. The calls block, so [Cell2JackKeypad] makes
 * them from one USB thread.
 */
class AndroidCell2JackLink private constructor(
    private val connection: UsbDeviceConnection,
    private val usbInterface: UsbInterface,
    private val input: UsbEndpoint,
    private val output: UsbEndpoint,
) : Cell2JackLink {
    // The low 11 bits are the size; the rest are high-bandwidth bits, which bulk endpoints don't use.
    override val packetSize = input.maxPacketSize and 0x7FF

    override suspend fun controlTransfer(requestType: Int, request: Int, value: Int, index: Int, buffer: ByteArray?, length: Int, timeoutMs: Int) =
        connection.controlTransfer(requestType, request, value, index, buffer, length, timeoutMs)

    override suspend fun bulkIn(buffer: ByteArray, length: Int, timeoutMs: Int) = connection.bulkTransfer(input, buffer, length, timeoutMs)

    override suspend fun bulkOut(buffer: ByteArray, length: Int, timeoutMs: Int) = connection.bulkTransfer(output, buffer, length, timeoutMs)

    /** Android has no public call for clearing a halt, so this sends the standard request itself: CLEAR_FEATURE
     * (ENDPOINT_HALT) to the endpoint. */
    override suspend fun clearHalt(input: Boolean): Int {
        val endpoint = if (input) this.input else output
        return connection.controlTransfer(recipientEndpoint, clearFeature, endpointHalt, endpoint.address, null, 0, 500)
    }

    override fun close() {
        connection.releaseInterface(usbInterface)
        connection.close()
    }

    companion object {
        private const val recipientEndpoint = 0x02 // host to device, standard, endpoint
        private const val clearFeature = 0x01
        private const val endpointHalt = 0

        fun matches(device: UsbDevice) = device.vendorId == Cell2JackProtocol.vendorID && device.productId == Cell2JackProtocol.productID

        /** Opens the Cell2Jack, which Porch must already have permission to use. Throws, saying why, when it can't. */
        fun open(manager: UsbManager, device: UsbDevice): AndroidCell2JackLink {
            if (device.interfaceCount == 0) throw Cell2JackException("The Cell2Jack has no USB interface")
            val usbInterface = device.getInterface(0)
            var input: UsbEndpoint? = null
            var output: UsbEndpoint? = null
            for (index in 0 until usbInterface.endpointCount) {
                val endpoint = usbInterface.getEndpoint(index)
                if (endpoint.type != UsbConstants.USB_ENDPOINT_XFER_BULK) continue // bulk only
                if (endpoint.direction == UsbConstants.USB_DIR_IN) { if (input == null) input = endpoint }
                else if (output == null) output = endpoint
            }
            if (input == null || output == null) throw Cell2JackException("The Cell2Jack's USB endpoints are missing")
            val connection = manager.openDevice(device) ?: throw Cell2JackException("Android couldn't open the Cell2Jack")
            // Force: the kernel's own serial driver, on a tablet that has one, lets go of it.
            if (!connection.claimInterface(usbInterface, true)) {
                connection.close()
                throw Cell2JackException("Android couldn't claim the Cell2Jack's USB interface")
            }
            return AndroidCell2JackLink(connection, usbInterface, input, output)
        }
    }
}
