package com.example.usb_connect_gnss

import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbManager
import android.hardware.usb.UsbDeviceConnection
import android.hardware.usb.UsbInterface
import android.hardware.usb.UsbEndpoint
import android.content.Context
import android.content.Intent
import android.app.PendingIntent
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.os.Bundle
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledFuture
import java.util.concurrent.TimeUnit
import java.io.IOException

class MainActivity: FlutterActivity() {
    private val TAG = "MainActivity"
    private val CHANNEL = "com.example.usb_connect_gnss/usb"
    private val USB_PERMISSION_REQUEST_CODE = 1
    private val USB_PERMISSION_ACTION = "com.example.usb_connect_gnss.USB_PERMISSION"

    private lateinit var usbManager: UsbManager
    private lateinit var methodChannel: MethodChannel
    private val handler = Handler(Looper.getMainLooper())
    private val isScanning = AtomicBoolean(false)
    private val deviceCache = ConcurrentHashMap<String, UsbDevice>()
    private var lastUsbScanTime: Long = 0
    private val SCAN_INTERVAL_MS = 3000L

    // Connection management
    private data class ConnectionInfo(
        val connection: UsbDeviceConnection,
        val device: UsbDevice,
        var lastHeartbeat: Long = System.currentTimeMillis(),
        var isStable: Boolean = false,
        var retryCount: Int = 0,
        var claimedInterfaces: MutableList<UsbInterface> = mutableListOf()
    )

    private val connections = ConcurrentHashMap<String, ConnectionInfo>()
    private val connectionTimestamps = ConcurrentHashMap<String, Long>()
    private val connectionRetryCount = ConcurrentHashMap<String, Int>()
    private val MAX_RETRY_COUNT = 3
    private val CONNECTION_TIMEOUT_MS = 15000L
    private val HEARTBEAT_INTERVAL = 3000L
    private val STABILITY_CHECK_INTERVAL = 5000L

    // Executor for background tasks
    private val executor = Executors.newScheduledThreadPool(2)
    private var connectionMonitor: ScheduledFuture<*>? = null
    private var heartbeatMonitor: ScheduledFuture<*>? = null

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        usbManager = getSystemService(Context.USB_SERVICE) as UsbManager

        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)

        methodChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "getUsbDevices" -> {
                    val currentTime = System.currentTimeMillis()
                    if (currentTime - lastUsbScanTime > SCAN_INTERVAL_MS) {
                        lastUsbScanTime = currentTime
                        result.success(getRealUsbDevices())
                    } else {
                        result.success(getCachedUsbDevices())
                    }
                }
                "requestUsbPermission" -> {
                    val deviceInfo = call.arguments as? Map<*, *>
                    if (deviceInfo != null) {
                        val deviceName = deviceInfo["deviceName"] as? String
                        val vendorId = deviceInfo["vendorId"] as? Int
                        val productId = deviceInfo["productId"] as? Int
                        requestUsbPermission(deviceName, vendorId, productId, result)
                    } else {
                        result.error("INVALID_ARGUMENT", "Device info is null", null)
                    }
                }
                "checkUsbPermission" -> {
                    val deviceInfo = call.arguments as? Map<*, *>
                    if (deviceInfo != null) {
                        val deviceName = deviceInfo["deviceName"] as? String
                        val vendorId = deviceInfo["vendorId"] as? Int
                        val productId = deviceInfo["productId"] as? Int
                        result.success(hasUsbPermission(deviceName, vendorId, productId))
                    } else {
                        result.error("INVALID_ARGUMENT", "Device info is null", null)
                    }
                }
                "openUsbDevice" -> {
                    val deviceInfo = call.arguments as? Map<*, *>
                    if (deviceInfo != null) {
                        val deviceName = deviceInfo["deviceName"] as? String
                        val vendorId = deviceInfo["vendorId"] as? Int
                        val productId = deviceInfo["productId"] as? Int
                        openRealUsbDevice(deviceName, vendorId, productId, result)
                    } else {
                        result.error("INVALID_ARGUMENT", "Device info is null", null)
                    }
                }
                "closeUsbDevice" -> {
                    val deviceInfo = call.arguments as? Map<*, *>
                    if (deviceInfo != null) {
                        val vendorId = deviceInfo["vendorId"] as? Int
                        val productId = deviceInfo["productId"] as? Int
                        closeUsbDevice(vendorId, productId, result)
                    } else {
                        result.error("INVALID_ARGUMENT", "Device info is null", null)
                    }
                }
                "isUsbDeviceConnected" -> {
                    val deviceInfo = call.arguments as? Map<*, *>
                    if (deviceInfo != null) {
                        val vendorId = deviceInfo["vendorId"] as? Int
                        val productId = deviceInfo["productId"] as? Int
                        result.success(isUsbDeviceConnectedAndStable(vendorId, productId))
                    } else {
                        result.error("INVALID_ARGUMENT", "Device info is null", null)
                    }
                }
                "clearDeviceCache" -> {
                    deviceCache.clear()
                    result.success(true)
                }
                "testUsbConnection" -> {
                    val deviceInfo = call.arguments as? Map<*, *>
                    if (deviceInfo != null) {
                        val vendorId = deviceInfo["vendorId"] as? Int
                        val productId = deviceInfo["productId"] as? Int
                        testUsbConnection(vendorId, productId, result)
                    } else {
                        result.error("INVALID_ARGUMENT", "Device info is null", null)
                    }
                }
                "keepAlivePing" -> {
                    val deviceInfo = call.arguments as? Map<*, *>
                    if (deviceInfo != null) {
                        val vendorId = deviceInfo["vendorId"] as? Int
                        val productId = deviceInfo["productId"] as? Int
                        val connectionKey = "$vendorId:$productId"
                        val connInfo = connections[connectionKey]
                        if (connInfo != null) {
                            connInfo.lastHeartbeat = System.currentTimeMillis()
                            connInfo.isStable = true
                            connectionTimestamps[connectionKey] = System.currentTimeMillis()
                            result.success(true)
                        } else {
                            result.success(false)
                        }
                    } else {
                        result.success(false)
                    }
                }
                "getDeviceStatistics" -> {
                    val deviceInfo = call.arguments as? Map<*, *>
                    if (deviceInfo != null) {
                        val vendorId = deviceInfo["vendorId"] as? Int
                        val productId = deviceInfo["productId"] as? Int
                        result.success(getDeviceStatistics(vendorId, productId))
                    } else {
                        result.error("INVALID_ARGUMENT", "Device info is null", null)
                    }
                }
                "resetConnection" -> {
                    val deviceInfo = call.arguments as? Map<*, *>
                    if (deviceInfo != null) {
                        val vendorId = deviceInfo["vendorId"] as? Int
                        val productId = deviceInfo["productId"] as? Int
                        resetConnection(vendorId, productId, result)
                    } else {
                        result.error("INVALID_ARGUMENT", "Device info is null", null)
                    }
                }
                // NO NEW LOCATION METHODS ADDED - Compatible with existing code
                else -> {
                    result.notImplemented()
                }
            }
        }

        // Start connection monitoring
        startConnectionMonitoring()
    }

    private fun startConnectionMonitoring() {
        connectionMonitor?.cancel(false)
        heartbeatMonitor?.cancel(false)

        connectionMonitor = executor.scheduleAtFixedRate({
            checkAllConnections()
        }, 0, STABILITY_CHECK_INTERVAL, TimeUnit.MILLISECONDS)

        heartbeatMonitor = executor.scheduleAtFixedRate({
            sendHeartbeats()
        }, 0, HEARTBEAT_INTERVAL, TimeUnit.MILLISECONDS)
    }

    private fun checkAllConnections() {
        val currentTime = System.currentTimeMillis()
        val keysToRemove = mutableListOf<String>()

        for ((connectionKey, connInfo) in connections) {
            try {
                // Check if connection is stale
                if (currentTime - connInfo.lastHeartbeat > CONNECTION_TIMEOUT_MS) {
                    Log.w(TAG, "Connection $connectionKey appears stale")
                    connInfo.isStable = false
                    
                    // Try to revive the connection
                    if (!verifyConnectionHealth(connInfo)) {
                        Log.w(TAG, "Failed to revive connection $connectionKey")
                        keysToRemove.add(connectionKey)
                    } else {
                        connInfo.lastHeartbeat = currentTime
                        connInfo.isStable = true
                    }
                } else {
                    // Verify connection is still healthy
                    if (!verifyConnectionHealth(connInfo)) {
                        connInfo.retryCount++
                        if (connInfo.retryCount > MAX_RETRY_COUNT) {
                            keysToRemove.add(connectionKey)
                            Log.w(TAG, "Max retries exceeded for $connectionKey")
                        } else {
                            Log.w(TAG, "Connection $connectionKey unstable, retry ${connInfo.retryCount}/$MAX_RETRY_COUNT")
                        }
                    } else {
                        connInfo.isStable = true
                        connInfo.retryCount = 0
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "Error checking connection $connectionKey: ${e.message}")
                keysToRemove.add(connectionKey)
            }
        }

        // Clean up dead connections
        for (key in keysToRemove) {
            removeConnection(key)
            
            handler.post {
                methodChannel.invokeMethod("usbConnectionLost", mapOf(
                    "connectionKey" to key,
                    "reason" to "connection_timeout"
                ))
            }
        }
    }

    private fun verifyConnectionHealth(connInfo: ConnectionInfo): Boolean {
        return try {
            // Try to claim an interface
            var interfaceClaimed = false
            for (i in 0 until connInfo.device.interfaceCount) {
                val usbInterface = connInfo.device.getInterface(i)
                if (connInfo.connection.claimInterface(usbInterface, true)) {
                    interfaceClaimed = true
                    if (!connInfo.claimedInterfaces.contains(usbInterface)) {
                        connInfo.claimedInterfaces.add(usbInterface)
                    }
                    // Release immediately for check
                    connInfo.connection.releaseInterface(usbInterface)
                    break
                }
            }
            
            // For CDC devices, try control transfer
            if (isCdcDevice(connInfo.device) && interfaceClaimed) {
                try {
                    connInfo.connection.controlTransfer(
                        0x21, // REQUEST_TYPE_CLASS | RECIPIENT_INTERFACE
                        0x20, // SET_LINE_CODING
                        0,
                        0,
                        null,
                        0,
                        500
                    )
                    true
                } catch (e: Exception) {
                    false
                }
            } else {
                interfaceClaimed
            }
        } catch (e: Exception) {
            false
        }
    }

    private fun sendHeartbeats() {
        for ((_, connInfo) in connections) {
            if (connInfo.isStable) {
                try {
                    // Send minimal heartbeat
                    if (isCdcDevice(connInfo.device)) {
                        connInfo.connection.controlTransfer(
                            0xA1, // REQUEST_TYPE_CLASS | RECIPIENT_INTERFACE | ENDPOINT_IN
                            0x21, // GET_LINE_CODING
                            0,
                            0,
                            ByteArray(7),
                            7,
                            500
                        )
                    }
                } catch (e: Exception) {
                    // Silent fail for heartbeat
                }
            }
        }
    }

    private fun getRealUsbDevices(): Map<String, Any> {
        if (isScanning.getAndSet(true)) {
            return getCachedUsbDevices()
        }

        try {
            val deviceList = usbManager.deviceList
            val devices = mutableMapOf<String, Any>()

            for ((key, device) in deviceList) {
                // Basic validation - REAL devices only
                if (device.vendorId == 0 || device.productId == 0) continue
                if (device.deviceName.isBlank()) continue
                if (device.interfaceCount <= 0) continue

                // Use composite key
                val deviceKey = "${device.vendorId}:${device.productId}:${device.deviceName}"
                deviceCache[deviceKey] = device

                val deviceInfo = mutableMapOf<String, Any>()
                deviceInfo["deviceName"] = device.deviceName
                deviceInfo["vendorId"] = device.vendorId
                deviceInfo["productId"] = device.productId
                deviceInfo["deviceId"] = device.deviceId
                deviceInfo["deviceClass"] = device.deviceClass
                deviceInfo["deviceSubclass"] = device.deviceSubclass
                deviceInfo["deviceProtocol"] = device.deviceProtocol
                deviceInfo["productName"] = device.productName ?: ""
                deviceInfo["manufacturerName"] = device.manufacturerName ?: ""
                deviceInfo["serialNumber"] = device.serialNumber ?: ""
                deviceInfo["hasPermission"] = usbManager.hasPermission(device)
                deviceInfo["interfaceCount"] = device.interfaceCount
                deviceInfo["isCdcDevice"] = isCdcDevice(device)
                deviceInfo["isOpen"] = isDeviceOpen(device.vendorId, device.productId)
                deviceInfo["isRealHardware"] = true

                devices[deviceKey] = deviceInfo
            }

            return devices
        } finally {
            isScanning.set(false)
        }
    }

    private fun openRealUsbDevice(deviceName: String?, vendorId: Int?, productId: Int?, result: MethodChannel.Result) {
        val device = findDevice(deviceName, vendorId, productId)

        if (device == null) {
            result.error("DEVICE_NOT_FOUND", "USB device not found", null)
            return
        }

        if (!usbManager.hasPermission(device)) {
            result.error("NO_PERMISSION", "No permission to access USB device", null)
            return
        }

        val connectionKey = "${device.vendorId}:${device.productId}"
        val existingConn = connections[connectionKey]

        if (existingConn != null) {
            if (existingConn.isStable) {
                Log.d(TAG, "Device already connected and stable: ${device.deviceName}")
                result.success(getRealConnectionInfo(existingConn))
                return
            } else {
                // Remove unstable connection
                removeConnection(connectionKey)
            }
        }

        try {
            // Open with timeout handling
            val connection = usbManager.openDevice(device) ?: run {
                result.error("CONNECTION_FAILED", "Failed to open USB device", null)
                return
            }

            // Create connection info
            val connInfo = ConnectionInfo(
                connection = connection,
                device = device,
                lastHeartbeat = System.currentTimeMillis(),
                isStable = false,
                retryCount = 0,
                claimedInterfaces = mutableListOf()
            )

            // Claim interfaces
            var interfaceClaimed = false
            for (i in 0 until device.interfaceCount) {
                val usbInterface = device.getInterface(i)
                if (connection.claimInterface(usbInterface, true)) {
                    connInfo.claimedInterfaces.add(usbInterface)
                    interfaceClaimed = true
                    Log.d(TAG, "Claimed interface ${usbInterface.id} for ${device.deviceName}")
                }
            }

            if (!interfaceClaimed) {
                connection.close()
                result.error("NO_INTERFACE", "No interfaces could be claimed", null)
                return
            }

            // Configure CDC devices
            if (isCdcDevice(device)) {
                configureCdcDevice(connection, device)
            }

            // Store the connection
            connections[connectionKey] = connInfo
            connectionTimestamps[connectionKey] = System.currentTimeMillis()
            connectionRetryCount[connectionKey] = 0

            // Mark as stable after successful configuration
            connInfo.isStable = true
            connInfo.lastHeartbeat = System.currentTimeMillis()

            Log.d(TAG, "Successfully opened USB device: ${device.deviceName}")
            result.success(getRealConnectionInfo(connInfo))

        } catch (e: SecurityException) {
            result.error("SECURITY_ERROR", "Security exception: ${e.message}", null)
        } catch (e: Exception) {
            result.error("OPEN_ERROR", "Error opening device: ${e.message}", null)
        }
    }

    private fun configureCdcDevice(connection: UsbDeviceConnection, device: UsbDevice) {
        try {
            // Set control line state
            connection.controlTransfer(
                0x21, // REQUEST_TYPE_CLASS | RECIPIENT_INTERFACE
                0x22, // SET_CONTROL_LINE_STATE
                0x01, // DTR
                0,
                null,
                0,
                1000
            )

            // Set line coding for GNSS (9600 8N1 is common)
            val lineCoding = byteArrayOf(
                0x80.toByte(), 0x25.toByte(), 0x00.toByte(), 0x00.toByte(), // 9600 baud
                0x00.toByte(), // Stop bits 1
                0x00.toByte(), // Parity none
                0x08.toByte()  // 8 data bits
            )
            
            connection.controlTransfer(
                0x21,
                0x20, // SET_LINE_CODING
                0,
                0,
                lineCoding,
                lineCoding.size,
                1000
            )

            Log.d(TAG, "Configured CDC device for serial communication")
        } catch (e: Exception) {
            Log.w(TAG, "Failed to configure CDC device: ${e.message}")
        }
    }

    private fun closeUsbDevice(vendorId: Int?, productId: Int?, result: MethodChannel.Result) {
        if (vendorId == null || productId == null) {
            result.error("INVALID_ARGUMENTS", "Vendor ID or Product ID is null", null)
            return
        }

        val connectionKey = "$vendorId:$productId"
        removeConnection(connectionKey)
        
        result.success(true)
    }

    private fun removeConnection(connectionKey: String) {
        val connInfo = connections[connectionKey]
        if (connInfo != null) {
            try {
                // Release all interfaces
                for (usbInterface in connInfo.claimedInterfaces) {
                    try {
                        connInfo.connection.releaseInterface(usbInterface)
                    } catch (e: Exception) {
                        // Ignore
                    }
                }
                
                // Close connection
                connInfo.connection.close()
                Log.d(TAG, "Closed connection for $connectionKey")
            } catch (e: Exception) {
                Log.e(TAG, "Error closing connection: ${e.message}")
            }
        }
        
        connections.remove(connectionKey)
        connectionTimestamps.remove(connectionKey)
        connectionRetryCount.remove(connectionKey)
    }

    private fun testUsbConnection(vendorId: Int?, productId: Int?, result: MethodChannel.Result) {
        val device = findDevice(null, vendorId, productId)

        if (device == null) {
            result.error("DEVICE_NOT_FOUND", "Device not found", null)
            return
        }

        if (!usbManager.hasPermission(device)) {
            result.error("NO_PERMISSION", "No permission for device", null)
            return
        }

        try {
            val connection = usbManager.openDevice(device)
            if (connection != null) {
                // Simple test - can we claim an interface?
                var interfaceClaimed = false
                
                for (i in 0 until device.interfaceCount) {
                    val usbInterface = device.getInterface(i)
                    if (connection.claimInterface(usbInterface, true)) {
                        interfaceClaimed = true
                        connection.releaseInterface(usbInterface)
                        break
                    }
                }

                connection.close()

                result.success(mapOf(
                    "success" to interfaceClaimed,
                    "isRealDevice" to true,
                    "message" to if (interfaceClaimed) {
                        "Device opened successfully"
                    } else {
                        "Failed to claim interface"
                    }
                ))
            } else {
                result.success(mapOf(
                    "success" to false,
                    "isRealDevice" to false,
                    "message" to "Failed to open device"
                ))
            }
        } catch (e: Exception) {
            result.success(mapOf(
                "success" to false,
                "isRealDevice" to false,
                "message" to "Error: ${e.message}"
            ))
        }
    }

    private fun getRealConnectionInfo(connInfo: ConnectionInfo): Map<String, Any> {
        val connectionInfo = mutableMapOf<String, Any>()
        connectionInfo["opened"] = true
        connectionInfo["deviceName"] = connInfo.device.deviceName
        connectionInfo["vendorId"] = connInfo.device.vendorId
        connectionInfo["productId"] = connInfo.device.productId
        connectionInfo["isStable"] = connInfo.isStable
        connectionInfo["lastHeartbeat"] = connInfo.lastHeartbeat
        connectionInfo["claimedInterfaces"] = connInfo.claimedInterfaces.size
        connectionInfo["isCdcDevice"] = isCdcDevice(connInfo.device)
        connectionInfo["isRealHardware"] = true

        // Interface information
        val interfaces = mutableListOf<Map<String, Any>>()
        for (i in 0 until connInfo.device.interfaceCount) {
            val usbInterface = connInfo.device.getInterface(i)
            val interfaceInfo = mutableMapOf<String, Any>()
            interfaceInfo["id"] = usbInterface.id
            interfaceInfo["interfaceClass"] = usbInterface.interfaceClass
            interfaceInfo["interfaceSubclass"] = usbInterface.interfaceSubclass
            interfaceInfo["interfaceProtocol"] = usbInterface.interfaceProtocol
            interfaceInfo["endpointCount"] = usbInterface.endpointCount
            interfaceInfo["isClaimed"] = connInfo.claimedInterfaces.any { it.id == usbInterface.id }

            interfaces.add(interfaceInfo)
        }
        connectionInfo["interfaces"] = interfaces

        return connectionInfo
    }

    private fun getDeviceStatistics(vendorId: Int?, productId: Int?): Map<String, Any> {
        val connectionKey = "${vendorId ?: 0}:${productId ?: 0}"
        val connInfo = connections[connectionKey]
        
        return if (connInfo != null) {
            mapOf(
                "connectionTime" to (System.currentTimeMillis() - (connectionTimestamps[connectionKey] ?: System.currentTimeMillis())),
                "isStable" to connInfo.isStable,
                "retryCount" to connInfo.retryCount,
                "lastHeartbeat" to connInfo.lastHeartbeat,
                "claimedInterfaces" to connInfo.claimedInterfaces.size,
                "signalQuality" to if (connInfo.isStable) "GOOD" else "POOR",
                "dataIntegrity" to "REAL"
            )
        } else {
            emptyMap()
        }
    }

    private fun resetConnection(vendorId: Int?, productId: Int?, result: MethodChannel.Result) {
        val connectionKey = "${vendorId ?: 0}:${productId ?: 0}"
        removeConnection(connectionKey)
        
        // Clear retry count
        connectionRetryCount.remove(connectionKey)
        
        result.success(mapOf(
            "success" to true,
            "message" to "Connection reset successfully"
        ))
    }

    private fun isUsbDeviceConnectedAndStable(vendorId: Int?, productId: Int?): Boolean {
        if (vendorId == null || productId == null) return false
        
        val connectionKey = "$vendorId:$productId"
        val connInfo = connections[connectionKey]
        
        return connInfo != null && connInfo.isStable
    }

    private fun isDeviceOpen(vendorId: Int?, productId: Int?): Boolean {
        if (vendorId == null || productId == null) return false
        return connections.containsKey("$vendorId:$productId")
    }

    private fun requestUsbPermission(deviceName: String?, vendorId: Int?, productId: Int?, result: MethodChannel.Result) {
        val device = findDevice(deviceName, vendorId, productId)

        if (device == null) {
            result.error("DEVICE_NOT_FOUND", "USB device not found", null)
            return
        }

        if (usbManager.hasPermission(device)) {
            result.success(true)
        } else {
            val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                PendingIntent.FLAG_MUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            } else {
                PendingIntent.FLAG_UPDATE_CURRENT
            }

            val permissionIntent = PendingIntent.getBroadcast(
                this,
                USB_PERMISSION_REQUEST_CODE,
                Intent(USB_PERMISSION_ACTION).apply {
                    putExtra(UsbManager.EXTRA_DEVICE, device)
                },
                flags
            )

            usbManager.requestPermission(device, permissionIntent)
            result.success(false)
        }
    }

    private fun hasUsbPermission(deviceName: String?, vendorId: Int?, productId: Int?): Boolean {
        val device = findDevice(deviceName, vendorId, productId) ?: return false
        return usbManager.hasPermission(device)
    }

    private fun findDevice(deviceName: String?, vendorId: Int?, productId: Int?): UsbDevice? {
        val deviceList = usbManager.deviceList
        
        for ((_, device) in deviceList) {
            // Basic validation
            if (device.vendorId == 0 || device.productId == 0) continue
            if (device.deviceName.isBlank()) continue
            
            if (vendorId != null && productId != null) {
                if (device.vendorId == vendorId && device.productId == productId) {
                    return device
                }
            } else if (deviceName != null && device.deviceName == deviceName) {
                return device
            }
        }
        
        return null
    }

    private fun getCachedUsbDevices(): Map<String, Any> {
        val devices = mutableMapOf<String, Any>()

        for ((key, device) in deviceCache) {
            if (key.contains(":")) {
                val deviceInfo = mutableMapOf<String, Any>()
                deviceInfo["deviceName"] = device.deviceName
                deviceInfo["vendorId"] = device.vendorId
                deviceInfo["productId"] = device.productId
                deviceInfo["deviceId"] = device.deviceId
                deviceInfo["deviceClass"] = device.deviceClass
                deviceInfo["deviceSubclass"] = device.deviceSubclass
                deviceInfo["deviceProtocol"] = device.deviceProtocol
                deviceInfo["productName"] = device.productName ?: ""
                deviceInfo["manufacturerName"] = device.manufacturerName ?: ""
                deviceInfo["serialNumber"] = device.serialNumber ?: ""
                deviceInfo["hasPermission"] = usbManager.hasPermission(device)
                deviceInfo["interfaceCount"] = device.interfaceCount
                deviceInfo["isCdcDevice"] = isCdcDevice(device)
                deviceInfo["isOpen"] = isDeviceOpen(device.vendorId, device.productId)
                deviceInfo["isRealHardware"] = true

                devices[key] = deviceInfo
            }
        }

        return devices
    }

    private fun isCdcDevice(device: UsbDevice): Boolean {
        for (i in 0 until device.interfaceCount) {
            val usbInterface = device.getInterface(i)
            if (usbInterface.interfaceClass == 2 && usbInterface.interfaceSubclass == 2) {
                return true
            }
        }
        return false
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)

        when (intent.action) {
            UsbManager.ACTION_USB_DEVICE_ATTACHED -> {
                val device: UsbDevice? = intent.getParcelableExtra(UsbManager.EXTRA_DEVICE)
                if (device != null) {
                    // Basic validation
                    if (device.vendorId == 0 || device.productId == 0) return
                    if (device.deviceName.isBlank()) return
                    
                    Log.d(TAG, "Real USB device attached: ${device.deviceName}")
                    
                    // Update cache
                    val compositeKey = "${device.vendorId}:${device.productId}:${device.deviceName}"
                    deviceCache[compositeKey] = device
                    
                    handler.post {
                        methodChannel.invokeMethod("usbDeviceAttached", mapOf(
                            "deviceName" to device.deviceName,
                            "vendorId" to device.vendorId,
                            "productId" to device.productId,
                            "isRealHardware" to true
                        ))
                    }
                }
            }
            UsbManager.ACTION_USB_DEVICE_DETACHED -> {
                val device: UsbDevice? = intent.getParcelableExtra(UsbManager.EXTRA_DEVICE)
                if (device != null) {
                    Log.d(TAG, "USB device detached: ${device.deviceName}")
                    
                    // Remove from cache
                    val keysToRemove = deviceCache.filter { 
                        it.value.deviceName == device.deviceName || 
                        (it.value.vendorId == device.vendorId && it.value.productId == device.productId)
                    }.keys.toList()
                    
                    keysToRemove.forEach { deviceCache.remove(it) }
                    
                    // Remove connection
                    val connectionKey = "${device.vendorId}:${device.productId}"
                    removeConnection(connectionKey)
                    
                    handler.post {
                        methodChannel.invokeMethod("usbDeviceDetached", mapOf(
                            "deviceName" to device.deviceName,
                            "vendorId" to device.vendorId,
                            "productId" to device.productId
                        ))
                    }
                }
            }
            USB_PERMISSION_ACTION -> {
                val device: UsbDevice? = intent.getParcelableExtra(UsbManager.EXTRA_DEVICE)
                val permissionGranted = intent.getBooleanExtra(UsbManager.EXTRA_PERMISSION_GRANTED, false)

                if (device != null) {
                    Log.d(TAG, "USB permission result: $permissionGranted for ${device.deviceName}")
                    
                    handler.post {
                        methodChannel.invokeMethod("usbPermissionResult", mapOf(
                            "deviceName" to device.deviceName,
                            "vendorId" to device.vendorId,
                            "productId" to device.productId,
                            "permissionGranted" to permissionGranted,
                            "isRealHardware" to true
                        ))
                    }
                }
            }
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        
        // Stop monitoring
        connectionMonitor?.cancel(true)
        heartbeatMonitor?.cancel(true)
        executor.shutdown()
        
        // Close all connections
        connections.keys.forEach { removeConnection(it) }
        connections.clear()
        
        methodChannel.setMethodCallHandler(null)
        handler.removeCallbacksAndMessages(null)
        deviceCache.clear()
    }
}