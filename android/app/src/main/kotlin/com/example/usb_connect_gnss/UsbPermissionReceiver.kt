package com.example.usb_connect_gnss

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbManager
import android.util.Log
import android.os.Build

class UsbPermissionReceiver : BroadcastReceiver() {
    private val TAG = "UsbPermissionReceiver"

    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action

        when (action) {
            UsbManager.ACTION_USB_DEVICE_ATTACHED -> {
                val device: UsbDevice? = intent.getParcelableExtra(UsbManager.EXTRA_DEVICE)
                if (device != null) {
                    Log.d(TAG, "USB device attached: ${device.deviceName} " +
                            "VID:0x${device.vendorId.toString(16).uppercase()} " +
                            "PID:0x${device.productId.toString(16).uppercase()}")

                    // Check if it's a real hardware device
                    if (isRealHardwareDevice(device)) {
                        Log.d(TAG, "Real hardware device detected: ${device.deviceName}")
                        
                        if (isGnssDeviceEnhanced(device)) {
                            Log.d(TAG, "GNSS device detected: ${device.deviceName}")
                            val gnssType = getGnssDeviceType(device)
                            val supportsIrnss = supportsIrnss(device)
                            Log.d(TAG, "GNSS Type: $gnssType, IRNSS Support: $supportsIrnss")

                            // Auto-request permission for real GNSS devices
                            requestPermission(context, device)
                        }
                    } else {
                        Log.w(TAG, "Non-hardware device filtered out: ${device.deviceName}")
                    }
                }
            }

            UsbManager.ACTION_USB_DEVICE_DETACHED -> {
                val device: UsbDevice? = intent.getParcelableExtra(UsbManager.EXTRA_DEVICE)
                if (device != null) {
                    Log.d(TAG, "USB device detached: ${device.deviceName}")
                }
            }

            "com.example.usb_connect_gnss.USB_PERMISSION" -> {
                val device: UsbDevice? = intent.getParcelableExtra(UsbManager.EXTRA_DEVICE)
                val permissionGranted = intent.getBooleanExtra(UsbManager.EXTRA_PERMISSION_GRANTED, false)

                if (device != null) {
                    if (permissionGranted) {
                        Log.d(TAG, "USB permission granted for: ${device.deviceName}")
                        val isRealDevice = isRealHardwareDevice(device)
                        val supportsIrnss = supportsIrnss(device)
                        Log.d(TAG, "Real hardware: $isRealDevice, IRNSS Support: $supportsIrnss")
                    } else {
                        Log.d(TAG, "USB permission denied for: ${device.deviceName}")
                    }
                }
            }
        }
    }

    private fun isRealHardwareDevice(device: UsbDevice): Boolean {
        // Basic validation
        if (device.vendorId == 0 || device.productId == 0) return false
        if (device.deviceName.isBlank()) return false
        if (device.interfaceCount <= 0) return false
        
        return true
    }

    private fun isGnssDeviceEnhanced(device: UsbDevice): Boolean {
        // Known GNSS vendors
        val gnssVendors = mapOf(
            0x1a86 to listOf(0x55d3), // QinHeng
            0x067b to listOf(0x2303, 0x04bb), // Prolific
            0x0403 to listOf(0x6001, 0x6015, 0x6010, 0x6011, 0x6014), // FTDI
            0x10c4 to listOf(0xea60, 0xea70, 0xea61), // Silicon Labs
            0x0e8d to listOf(), // MediaTek
            0x1546 to listOf(), // U-blox
            0x2c7c to listOf(0x0125, 0x0295, 0x0306), // Quectel
        )

        // Check by vendor/product ID
        gnssVendors[device.vendorId]?.let { productIds ->
            if (productIds.isEmpty() || productIds.contains(device.productId)) {
                return true
            }
        }

        // Check for CDC/ACM
        for (i in 0 until device.interfaceCount) {
            val usbInterface = device.getInterface(i)
            if (usbInterface.interfaceClass == 2 && usbInterface.interfaceSubclass == 2) {
                return true
            }
        }

        // Check names
        val productName = device.productName?.lowercase() ?: ""
        val manufacturer = device.manufacturerName?.lowercase() ?: ""

        val gnssKeywords = listOf(
            "gps", "gnss", "navic", "irnss", "beidou", "galileo", "glonass",
            "ublox", "mediatek", "quectel", "skytraq", "trimble", "novatel"
        )

        for (keyword in gnssKeywords) {
            if (productName.contains(keyword) || manufacturer.contains(keyword)) {
                return true
            }
        }

        return false
    }

    private fun getGnssDeviceType(device: UsbDevice): String {
        val productName = device.productName?.lowercase() ?: ""
        val manufacturer = device.manufacturerName?.lowercase() ?: ""

        return when {
            productName.contains("navic") || productName.contains("irnss") -> "IRNSS/NavIC"
            productName.contains("beidou") || manufacturer.contains("beidou") -> "BeiDou"
            productName.contains("galileo") || manufacturer.contains("galileo") -> "Galileo"
            productName.contains("glonass") || manufacturer.contains("glonass") -> "GLONASS"
            productName.contains("gps") || manufacturer.contains("gps") -> "GPS"
            productName.contains("qzss") || manufacturer.contains("qzss") -> "QZSS"
            productName.contains("gnss") || manufacturer.contains("gnss") -> "Multi-GNSS"
            productName.contains("ublox") -> "U-blox Multi-GNSS"
            productName.contains("mediatek") || productName.contains("mtk") -> "MediaTek Multi-GNSS"
            productName.contains("quectel") -> "Quectel Multi-GNSS"
            else -> "USB Device"
        }
    }

    private fun supportsIrnss(device: UsbDevice): Boolean {
        val irnssDevices = listOf(
            Pair(0x0e8d, 0x0000), // MediaTek
            Pair(0x2c7c, 0x0125), // Quectel LC29H
            Pair(0x2c7c, 0x0295), // Quectel LC79H
            Pair(0x2c7c, 0x0306), // Quectel LC76G
            Pair(0x10c4, 0xea60), // SkyTraq
            Pair(0x1546, 0x01a9), // U-blox ZED-F9P
            Pair(0x1546, 0x01ab), // U-blox ZED-F9T
            Pair(0x1546, 0x01ac), // U-blox ZED-F9R
            Pair(0x1546, 0x01ad), // U-blox ZED-F9K
            Pair(0x1546, 0x01b3), // U-blox NEO-D9S
        )

        for (deviceId in irnssDevices) {
            if (device.vendorId == deviceId.first &&
                (deviceId.second == 0x0000 || device.productId == deviceId.second)) {
                return true
            }
        }

        val productName = device.productName?.lowercase() ?: ""
        val manufacturer = device.manufacturerName?.lowercase() ?: ""

        val irnssKeywords = listOf("navic", "irnss", "lc29", "lc79", "zed-f9", "neo-d9")
        for (keyword in irnssKeywords) {
            if (productName.contains(keyword) || manufacturer.contains(keyword)) {
                return true
            }
        }

        return isGnssDeviceEnhanced(device) &&
                (productName.contains("multi") ||
                        manufacturer.contains("mediatek") ||
                        manufacturer.contains("ublox") ||
                        manufacturer.contains("quectel"))
    }

    private fun requestPermission(context: Context, device: UsbDevice) {
        val usbManager = context.getSystemService(Context.USB_SERVICE) as UsbManager

        if (usbManager.hasPermission(device)) {
            Log.d(TAG, "Permission already granted for: ${device.deviceName}")
            return
        }

        val permissionIntent = PendingIntent.getBroadcast(
            context,
            0,
            Intent("com.example.usb_connect_gnss.USB_PERMISSION").apply {
                putExtra(UsbManager.EXTRA_DEVICE, device)
            },
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                PendingIntent.FLAG_MUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            } else {
                PendingIntent.FLAG_UPDATE_CURRENT
            }
        )

        usbManager.requestPermission(device, permissionIntent)
        Log.d(TAG, "Requested permission for: ${device.deviceName}")
    }
}