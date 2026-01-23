package com.example.navic;

import android.app.PendingIntent;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.content.pm.PackageManager;
import android.hardware.usb.UsbDevice;
import android.hardware.usb.UsbDeviceConnection;
import android.hardware.usb.UsbManager;
import android.location.GnssStatus;
import android.location.Location;
import android.location.LocationListener;
import android.location.LocationManager;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.provider.Settings;
import android.util.Log;

import androidx.annotation.NonNull;
import androidx.core.app.ActivityCompat;
import androidx.core.content.ContextCompat;

import io.flutter.embedding.android.FlutterActivity;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodChannel;

import java.lang.reflect.Method;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicInteger;

public class MainActivity extends FlutterActivity {
    private static final String CHANNEL = "navic_support";
    private static final String USB_PERMISSION = "com.example.navic.USB_PERMISSION";
    private static final long SATELLITE_DETECTION_TIMEOUT_MS = 30000L;
    private static final long LOCATION_UPDATE_INTERVAL_MS = 1000L;
    private static final float LOCATION_UPDATE_DISTANCE_M = 0.5f;
    private static final float MIN_NAVIC_SIGNAL_STRENGTH = 15.0f;

    // GNSS frequencies
    private static final Map<String, Double[]> GNSS_FREQUENCIES = new HashMap<String, Double[]>() {{
        put("GPS", new Double[]{1575.42, 1227.60, 1176.45});
        put("GLONASS", new Double[]{1602.00, 1246.00, 1202.025});
        put("GALILEO", new Double[]{1575.42, 1207.14, 1176.45});
        put("BEIDOU", new Double[]{1561.098, 1207.14, 1176.45});
        put("IRNSS", new Double[]{1176.45, 2492.028});
        put("QZSS", new Double[]{1575.42, 1227.60, 1176.45});
    }};

    // Country flags for GNSS systems
    private static final Map<String, String> GNSS_COUNTRIES = new HashMap<String, String>() {{
        put("GPS", "🇺🇸");
        put("GLONASS", "🇷🇺");
        put("GALILEO", "🇪🇺");
        put("BEIDOU", "🇨🇳");
        put("IRNSS", "🇮🇳");
        put("QZSS", "🇯🇵");
        put("SBAS", "🌍");
        put("UNKNOWN", "🌐");
    }};

    // USB GNSS Vendor IDs
    private static final Map<Integer, String> USB_GNSS_VENDORS = new HashMap<Integer, String>() {{
        put(0x067B, "Prolific");
        put(0x0403, "FTDI");
        put(0x10C4, "Silicon Labs");
        put(0x1D6B, "Linux Foundation");
        put(0x0FCF, "Garmin");
        put(0x1546, "u-blox");
        put(0x05C6, "Qualcomm");
        put(0x1199, "Sierra Wireless");
        put(0x12D1, "Huawei");
        put(0x2C7C, "Quectel");
    }};

    private LocationManager locationManager;
    private UsbManager usbManager;
    private GnssStatus.Callback realtimeCallback;
    private LocationListener locationListener;
    private Handler handler;
    private boolean isTrackingLocation = false;
    private MethodChannel methodChannel;
    private UsbPermissionReceiver usbPermissionReceiver;

    // External USB GNSS variables
    private boolean usingExternalGnss = false;
    private UsbDevice externalGnssDevice = null;
    private UsbDeviceConnection usbConnection = null;
    private String externalGnssInfo = "NONE";
    private String externalGnssVendor = "UNKNOWN";
    private int externalGnssVendorId = 0;
    private int externalGnssProductId = 0;

    // Satellite tracking
    private final Map<String, EnhancedSatellite> detectedSatellites = new ConcurrentHashMap<>();
    private final Map<String, List<EnhancedSatellite>> satellitesBySystem = new ConcurrentHashMap<>();
    private final AtomicInteger consecutiveNavicDetections = new AtomicInteger(0);
    private final AtomicBoolean navicDetectionCompleted = new AtomicBoolean(false);
    private boolean hasL5BandSupport = false;
    private boolean hasL5BandActive = false;
    private String primaryPositioningSystem = "GPS";

    // Continuous monitoring
    private GnssStatus.Callback continuousMonitoringCallback;
    private boolean isContinuousMonitoring = false;

    // USB Broadcast Receiver
    private class UsbPermissionReceiver extends BroadcastReceiver {
        @Override
        public void onReceive(Context context, Intent intent) {
            String action = intent.getAction();
            if (USB_PERMISSION.equals(action)) {
                synchronized (this) {
                    UsbDevice device = intent.getParcelableExtra(UsbManager.EXTRA_DEVICE);
                    if (intent.getBooleanExtra(UsbManager.EXTRA_PERMISSION_GRANTED, false)) {
                        if (device != null) {
                            Log.d("NavIC", "USB permission granted for device: " + device.getDeviceName());
                            connectToUsbDevice(device);
                        }
                    } else {
                        Log.d("NavIC", "USB permission denied for device: " + device);
                        Map<String, Object> response = new HashMap<>();
                        response.put("success", false);
                        response.put("message", "USB permission denied");
                        try {
                            methodChannel.invokeMethod("onUsbPermissionResult", response);
                        } catch (Exception e) {
                            Log.e("NavIC", "Error sending USB permission result", e);
                        }
                    }
                }
            }
        }
    }

    @Override
    public void configureFlutterEngine(@NonNull FlutterEngine flutterEngine) {
        super.configureFlutterEngine(flutterEngine);

        locationManager = (LocationManager) getSystemService(Context.LOCATION_SERVICE);
        usbManager = (UsbManager) getSystemService(Context.USB_SERVICE);
        handler = new Handler(Looper.getMainLooper());

        // Setup USB permission receiver
        usbPermissionReceiver = new UsbPermissionReceiver();
        IntentFilter filter = new IntentFilter(USB_PERMISSION);
        registerReceiver(usbPermissionReceiver, filter);

        methodChannel = new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), CHANNEL);
        methodChannel.setMethodCallHandler((call, result) -> {
            Log.d("NavIC", "Method called: " + call.method);
            switch (call.method) {
                case "checkNavicHardware":
                    checkNavicHardwareSupport(result);
                    break;
                case "getGnssCapabilities":
                    getGnssCapabilities(result);
                    break;
                case "startRealTimeDetection":
                    startRealTimeNavicDetection(result);
                    break;
                case "stopRealTimeDetection":
                    stopRealTimeDetection(result);
                    break;
                case "checkLocationPermissions":
                    checkLocationPermissions(result);
                    break;
                case "requestLocationPermissions":
                    requestLocationPermissions(result);
                    break;
                case "startLocationUpdates":
                    startLocationUpdates(result);
                    break;
                case "stopLocationUpdates":
                    stopLocationUpdates(result);
                    break;
                case "getAllSatellites":
                    getAllSatellites(result);
                    break;
                case "getAllSatellitesInRange":
                    getAllSatellitesInRange(result);
                    break;
                case "getGnssRangeStatistics":
                    getGnssRangeStatistics(result);
                    break;
                case "getDetailedSatelliteInfo":
                    getDetailedSatelliteInfo(result);
                    break;
                case "getCompleteSatelliteSummary":
                    getCompleteSatelliteSummary(result);
                    break;
                case "getSatelliteNames":
                    getSatelliteNames(result);
                    break;
                case "getConstellationDetails":
                    getConstellationDetails(result);
                    break;
                case "getSignalStrengthAnalysis":
                    getSignalStrengthAnalysis(result);
                    break;
                case "getElevationAzimuthData":
                    getElevationAzimuthData(result);
                    break;
                case "getCarrierFrequencyInfo":
                    getCarrierFrequencyInfo(result);
                    break;
                case "getEphemerisAlmanacStatus":
                    getEphemerisAlmanacStatus(result);
                    break;
                case "getSatelliteDetectionHistory":
                    getSatelliteDetectionHistory(result);
                    break;
                case "getGnssDiversityReport":
                    getGnssDiversityReport(result);
                    break;
                case "getRealTimeSatelliteStream":
                    getRealTimeSatelliteStream(result);
                    break;
                case "getSatelliteSignalQuality":
                    getSatelliteSignalQuality(result);
                    break;
                case "openLocationSettings":
                    openLocationSettings(result);
                    break;
                case "isLocationEnabled":
                    isLocationEnabled(result);
                    break;
                case "getDeviceInfo":
                    getDeviceInfo(result);
                    break;
                case "startSatelliteMonitoring":
                    startSatelliteMonitoring(result);
                    break;
                case "stopSatelliteMonitoring":
                    stopSatelliteMonitoring(result);
                    break;

                // USB GNSS METHODS
                case "checkUsbGnssDevices":
                    checkUsbGnssDevices(result);
                    break;
                case "connectToUsbGnss":
                    connectToUsbGnss(result);
                    break;
                case "disconnectUsbGnss":
                    disconnectUsbGnss(result);
                    break;
                case "getUsbGnssStatus":
                    getUsbGnssStatus(result);
                    break;
                case "forceExternalGnssMode":
                    forceExternalGnssMode(call.arguments, result);
                    break;

                default:
                    Log.w("NavIC", "Unknown method: " + call.method);
                    result.notImplemented();
            }
        });
    }

    // =============== USB GNSS SUPPORT METHODS ===============

    private void checkUsbGnssDevices(MethodChannel.Result result) {
        Log.d("NavIC", "🔌 Checking for USB GNSS devices");

        try {
            Map<String, UsbDevice> deviceList = usbManager.getDeviceList();
            List<Map<String, Object>> usbDevices = new ArrayList<>();

            for (UsbDevice device : deviceList.values()) {
                if (isPotentialGnssDevice(device)) {
                    Map<String, Object> deviceInfo = new HashMap<>();
                    deviceInfo.put("deviceName", device.getDeviceName());
                    deviceInfo.put("vendorId", device.getVendorId());
                    deviceInfo.put("productId", device.getProductId());
                    deviceInfo.put("vendorName", USB_GNSS_VENDORS.getOrDefault(device.getVendorId(), "Unknown"));
                    deviceInfo.put("deviceClass", device.getDeviceClass());
                    deviceInfo.put("deviceSubclass", device.getDeviceSubclass());
                    deviceInfo.put("deviceProtocol", device.getDeviceProtocol());
                    deviceInfo.put("interfaceCount", device.getInterfaceCount());

                    usbDevices.add(deviceInfo);
                    Log.d("NavIC", "Found potential GNSS device: " + device.getDeviceName());
                }
            }

            Map<String, Object> response = new HashMap<>();
            response.put("usbDevices", usbDevices);
            response.put("deviceCount", usbDevices.size());
            response.put("usingExternalGnss", usingExternalGnss);
            response.put("externalGnssInfo", externalGnssInfo);
            response.put("timestamp", System.currentTimeMillis());

            result.success(response);

        } catch (Exception e) {
            Log.e("NavIC", "Error checking USB devices", e);
            result.error("USB_ERROR", "Failed to check USB devices: " + e.getMessage(), null);
        }
    }

    private boolean isPotentialGnssDevice(UsbDevice device) {
        int vendorId = device.getVendorId();
        int deviceClass = device.getDeviceClass();

        if (USB_GNSS_VENDORS.containsKey(vendorId)) {
            return true;
        }

        if (deviceClass == 0x02 || deviceClass == 0xEF) {
            return true;
        }

        return false;
    }

    private void connectToUsbGnss(MethodChannel.Result result) {
        Log.d("NavIC", "🔌 Connecting to USB GNSS device");

        try {
            Map<String, UsbDevice> deviceList = usbManager.getDeviceList();
            UsbDevice gnssDevice = null;

            for (UsbDevice device : deviceList.values()) {
                if (isPotentialGnssDevice(device)) {
                    gnssDevice = device;
                    break;
                }
            }

            if (gnssDevice == null) {
                Map<String, Object> response = new HashMap<>();
                response.put("success", false);
                response.put("message", "No USB GNSS device found");
                result.success(response);
                return;
            }

            if (!usbManager.hasPermission(gnssDevice)) {
                PendingIntent permissionIntent = PendingIntent.getBroadcast(this, 0,
                        new Intent(USB_PERMISSION),
                        Build.VERSION.SDK_INT >= Build.VERSION_CODES.S ?
                                PendingIntent.FLAG_MUTABLE : 0);
                usbManager.requestPermission(gnssDevice, permissionIntent);

                Map<String, Object> response = new HashMap<>();
                response.put("success", false);
                response.put("message", "USB permission requested");
                result.success(response);
                return;
            }

            connectToUsbDevice(gnssDevice);

            Map<String, Object> response = new HashMap<>();
            response.put("success", true);
            response.put("message", "Connected to USB GNSS device");
            response.put("deviceInfo", externalGnssInfo);
            response.put("vendorId", externalGnssVendorId);
            response.put("productId", externalGnssProductId);
            response.put("vendor", externalGnssVendor);
            response.put("timestamp", System.currentTimeMillis());

            result.success(response);

        } catch (Exception e) {
            Log.e("NavIC", "Error connecting to USB GNSS", e);
            result.error("USB_CONNECT_ERROR", "Failed to connect to USB GNSS: " + e.getMessage(), null);
        }
    }

    private void connectToUsbDevice(UsbDevice device) {
        try {
            usbConnection = usbManager.openDevice(device);
            if (usbConnection == null) {
                Log.e("NavIC", "Failed to open USB connection");
                return;
            }

            externalGnssDevice = device;
            externalGnssVendorId = device.getVendorId();
            externalGnssProductId = device.getProductId();
            externalGnssVendor = USB_GNSS_VENDORS.getOrDefault(device.getVendorId(), "Unknown");
            externalGnssInfo = String.format("%s (VID: 0x%04X, PID: 0x%04X)",
                    externalGnssVendor, externalGnssVendorId, externalGnssProductId);
            usingExternalGnss = true;

            Log.d("NavIC", "✅ Connected to USB GNSS: " + externalGnssInfo);

            startExternalGnssL5Detection();

        } catch (Exception e) {
            Log.e("NavIC", "Error connecting to USB device", e);
        }
    }

    private void startExternalGnssL5Detection() {
        Log.d("NavIC", "📡 Starting L5 band detection for external GNSS");

        handler.postDelayed(() -> {
            hasL5BandSupport = true;
            hasL5BandActive = true;

            Log.d("NavIC", "✅ External GNSS L5 detection: Assuming L5 support available");

            Map<String, Object> statusUpdate = new HashMap<>();
            statusUpdate.put("type", "EXTERNAL_GNSS_CONNECTED");
            statusUpdate.put("deviceInfo", externalGnssInfo);
            statusUpdate.put("hasL5Band", true);
            statusUpdate.put("hasL5BandActive", true);
            statusUpdate.put("timestamp", System.currentTimeMillis());

            try {
                methodChannel.invokeMethod("onExternalGnssStatus", statusUpdate);
            } catch (Exception e) {
                Log.e("NavIC", "Error sending external GNSS status", e);
            }
        }, 1000);
    }

    private void disconnectUsbGnss(MethodChannel.Result result) {
        Log.d("NavIC", "🔌 Disconnecting from USB GNSS");

        try {
            if (usbConnection != null) {
                usbConnection.close();
                usbConnection = null;
            }

            externalGnssDevice = null;
            externalGnssInfo = "NONE";
            externalGnssVendor = "UNKNOWN";
            externalGnssVendorId = 0;
            externalGnssProductId = 0;
            usingExternalGnss = false;
            hasL5BandActive = false;

            Log.d("NavIC", "✅ Disconnected from USB GNSS");

            if (result != null) {
                Map<String, Object> response = new HashMap<>();
                response.put("success", true);
                response.put("message", "Disconnected from USB GNSS");
                response.put("timestamp", System.currentTimeMillis());
                result.success(response);
            }

        } catch (Exception e) {
            Log.e("NavIC", "Error disconnecting from USB GNSS", e);
            if (result != null) {
                result.error("USB_DISCONNECT_ERROR", "Failed to disconnect from USB GNSS", null);
            }
        }
    }

    private void getUsbGnssStatus(MethodChannel.Result result) {
        Map<String, Object> status = new HashMap<>();
        status.put("usingExternalGnss", usingExternalGnss);
        status.put("deviceInfo", externalGnssInfo);
        status.put("vendorId", externalGnssVendorId);
        status.put("productId", externalGnssProductId);
        status.put("vendor", externalGnssVendor);
        status.put("hasL5Band", hasL5BandSupport);
        status.put("hasL5BandActive", hasL5BandActive);
        status.put("connectionActive", usbConnection != null);
        status.put("timestamp", System.currentTimeMillis());

        result.success(status);
    }

    private void forceExternalGnssMode(Object arguments, MethodChannel.Result result) {
        boolean enable = arguments instanceof Boolean ? (Boolean) arguments : false;

        if (enable) {
            usingExternalGnss = true;
            externalGnssInfo = "FORCED_EXTERNAL_MODE";
            externalGnssVendor = "SIMULATED";
            hasL5BandSupport = true;
            hasL5BandActive = true;

            Log.d("NavIC", "🔄 Forced external GNSS mode enabled");
        } else {
            usingExternalGnss = false;
            externalGnssInfo = "NONE";
            hasL5BandActive = false;

            Log.d("NavIC", "🔄 Forced external GNSS mode disabled");
        }

        Map<String, Object> response = new HashMap<>();
        response.put("success", true);
        response.put("usingExternalGnss", usingExternalGnss);
        response.put("mode", enable ? "FORCED_EXTERNAL" : "INTERNAL");
        response.put("timestamp", System.currentTimeMillis());

        result.success(response);
    }

    // =============== SATELLITE DETECTION METHODS ===============

    private void getAllSatellitesInRange(MethodChannel.Result result) {
        Log.d("NavIC", "📡 Getting all satellites in range" +
                (usingExternalGnss ? " (External GNSS)" : " (Internal GNSS)"));

        if (!hasLocationPermissions()) {
            result.error("PERMISSION_DENIED", "Location permissions required", null);
            return;
        }

        if (!isLocationEnabled() && !usingExternalGnss) {
            result.error("LOCATION_DISABLED", "GPS/Location services are disabled", null);
            return;
        }

        if (usingExternalGnss) {
            Log.d("NavIC", "Using external GNSS - bypassing internal GPS check");
        }

        if (!detectedSatellites.isEmpty() &&
                (System.currentTimeMillis() - getLatestSatelliteTime()) < 5000) {
            returnCurrentSatellites(result);
            return;
        }

        startSatelliteDetection(result, 10000L);
    }

    private void startSatelliteDetection(final MethodChannel.Result result, long timeoutMs) {
        Log.d("NavIC", "🛰️ Starting satellite detection" +
                (usingExternalGnss ? " with external GNSS" : " with internal GNSS"));

        detectedSatellites.clear();
        satellitesBySystem.clear();
        consecutiveNavicDetections.set(0);
        navicDetectionCompleted.set(false);

        final long startTime = System.currentTimeMillis();
        final GnssStatus.Callback[] detectionCallback = new GnssStatus.Callback[1];
        final AtomicBoolean resultSent = new AtomicBoolean(false);

        detectionCallback[0] = new GnssStatus.Callback() {
            @Override
            public void onSatelliteStatusChanged(GnssStatus status) {
                long currentTime = System.currentTimeMillis();
                long elapsedTime = currentTime - startTime;

                EnhancedSatelliteScanResult scanResult = processEnhancedSatellites(
                        status,
                        elapsedTime,
                        hasL5BandSupport,
                        usingExternalGnss
                );

                updateSatelliteTracking(scanResult);

                Log.d("NavIC", "📡 Satellite update - Total: " + status.getSatelliteCount() +
                        ", Detected: " + detectedSatellites.size() +
                        ", Time: " + elapsedTime + "ms");

                if (!detectedSatellites.isEmpty() && elapsedTime > 3000) {
                    if (resultSent.compareAndSet(false, true)) {
                        cleanupCallback(detectionCallback[0]);
                        returnCurrentSatellites(result);
                    }
                }
            }

            @Override
            public void onStarted() {
                Log.d("NavIC", "✅ GNSS monitoring started");
            }

            @Override
            public void onStopped() {
                Log.d("NavIC", "❌ GNSS monitoring stopped");
            }
        };

        try {
            locationManager.registerGnssStatusCallback(detectionCallback[0], handler);
            Log.d("NavIC", "✅ GNSS callback registered successfully");

            handler.postDelayed(() -> {
                if (resultSent.compareAndSet(false, true)) {
                    cleanupCallback(detectionCallback[0]);

                    Map<String, Object> response = new HashMap<>();
                    response.put("satellites", getSatellitesAsList());
                    response.put("count", detectedSatellites.size());
                    response.put("timestamp", System.currentTimeMillis());
                    response.put("hasData", !detectedSatellites.isEmpty());
                    response.put("usingExternalGnss", usingExternalGnss);
                    response.put("message", detectedSatellites.isEmpty() ?
                            "No satellites detected within timeout" :
                            "Satellites detected successfully");

                    result.success(response);
                }
            }, timeoutMs);

        } catch (SecurityException se) {
            Log.e("NavIC", "🔒 Permission error: " + se.getMessage());
            result.error("PERMISSION_DENIED", "Location permissions required", null);
        } catch (Exception e) {
            Log.e("NavIC", "❌ Failed to register GNSS callback: " + e.getMessage(), e);
            result.error("DETECTION_ERROR", "Failed to start satellite detection: " + e.getMessage(), null);
        }
    }

    private void returnCurrentSatellites(MethodChannel.Result result) {
        try {
            List<Map<String, Object>> satellitesInRange = new ArrayList<>();

            for (EnhancedSatellite sat : detectedSatellites.values()) {
                if (sat.cn0 > 0) {
                    satellitesInRange.add(sat.toEnhancedMap());
                }
            }

            Map<String, Object> response = new HashMap<>();
            response.put("satellites", satellitesInRange);
            response.put("count", satellitesInRange.size());
            response.put("timestamp", System.currentTimeMillis());
            response.put("hasData", true);
            response.put("usingExternalGnss", usingExternalGnss);
            response.put("message", "Satellites detected successfully");

            result.success(response);

        } catch (Exception e) {
            Log.e("NavIC", "Error returning current satellites", e);
            result.error("RANGE_ERROR", "Failed to get satellites in range", null);
        }
    }

    private void startSatelliteMonitoring(MethodChannel.Result result) {
        Log.d("NavIC", "🛰️ Starting continuous satellite monitoring");

        if (!hasLocationPermissions()) {
            result.error("PERMISSION_DENIED", "Location permissions required", null);
            return;
        }

        if (!isLocationEnabled() && !usingExternalGnss) {
            result.error("LOCATION_DISABLED", "GPS/Location services are disabled", null);
            return;
        }

        stopSatelliteMonitoring(null);

        continuousMonitoringCallback = new GnssStatus.Callback() {
            @Override
            public void onSatelliteStatusChanged(GnssStatus status) {
                long currentTime = System.currentTimeMillis();
                EnhancedSatelliteScanResult scanResult = processEnhancedSatellites(
                        status,
                        currentTime,
                        hasL5BandSupport,
                        usingExternalGnss
                );

                updateSatelliteTracking(scanResult);

                Map<String, Object> update = new HashMap<>();
                update.put("type", "SATELLITE_MONITOR_UPDATE");
                update.put("timestamp", currentTime);
                update.put("totalSatellites", detectedSatellites.size());
                update.put("satellites", getSatellitesAsList());
                update.put("systemsDetected", new ArrayList<>(satellitesBySystem.keySet()));
                update.put("usingExternalGnss", usingExternalGnss);
                update.put("hasL5BandActive", hasL5BandActive);

                try {
                    handler.post(() -> {
                        methodChannel.invokeMethod("onSatelliteMonitorUpdate", update);
                    });
                } catch (Exception e) {
                    Log.e("NavIC", "Error sending monitor update", e);
                }
            }

            @Override
            public void onStarted() {
                Log.d("NavIC", "✅ Continuous satellite monitoring started");
                isContinuousMonitoring = true;
            }

            @Override
            public void onStopped() {
                Log.d("NavIC", "❌ Continuous satellite monitoring stopped");
                isContinuousMonitoring = false;
            }
        };

        try {
            locationManager.registerGnssStatusCallback(continuousMonitoringCallback, handler);

            Map<String, Object> response = new HashMap<>();
            response.put("success", true);
            response.put("message", "Continuous satellite monitoring started");
            response.put("timestamp", System.currentTimeMillis());
            response.put("usingExternalGnss", usingExternalGnss);

            result.success(response);

        } catch (Exception e) {
            Log.e("NavIC", "Failed to start continuous monitoring", e);
            result.error("MONITOR_ERROR", "Failed to start satellite monitoring", null);
        }
    }

    private void stopSatelliteMonitoring(MethodChannel.Result result) {
        Log.d("NavIC", "🛰️ Stopping continuous satellite monitoring");

        if (continuousMonitoringCallback != null) {
            try {
                locationManager.unregisterGnssStatusCallback(continuousMonitoringCallback);
                continuousMonitoringCallback = null;
                isContinuousMonitoring = false;
                Log.d("NavIC", "✅ Continuous monitoring stopped");
            } catch (Exception e) {
                Log.e("NavIC", "Error stopping continuous monitoring", e);
            }
        }

        if (result != null) {
            Map<String, Object> response = new HashMap<>();
            response.put("success", true);
            response.put("message", "Satellite monitoring stopped");
            response.put("timestamp", System.currentTimeMillis());
            result.success(response);
        }
    }

    private List<Map<String, Object>> getSatellitesAsList() {
        List<Map<String, Object>> satellites = new ArrayList<>();
        for (EnhancedSatellite sat : detectedSatellites.values()) {
            satellites.add(sat.toEnhancedMap());
        }
        return satellites;
    }

    private void getGnssRangeStatistics(MethodChannel.Result result) {
        Log.d("NavIC", "📊 Getting GNSS range statistics");

        if (!hasLocationPermissions()) {
            result.error("PERMISSION_DENIED", "Location permissions required", null);
            return;
        }

        try {
            if (detectedSatellites.isEmpty()) {
                Log.d("NavIC", "No satellites detected, starting quick detection...");
                startQuickSatelliteDetection(result, "STATISTICS");
                return;
            }

            Map<String, Object> stats = new HashMap<>();

            int totalSatellites = detectedSatellites.size();
            int satellitesWithSignal = 0;
            int satellitesUsedInFix = 0;
            float totalSignalStrength = 0;

            Map<String, Integer> systemCounts = new HashMap<>();
            Map<String, Integer> systemUsedCounts = new HashMap<>();
            Map<String, Float> systemSignalTotals = new HashMap<>();
            Map<String, Integer> systemSignalCounts = new HashMap<>();

            for (EnhancedSatellite sat : detectedSatellites.values()) {
                String system = sat.systemName;

                systemCounts.put(system, systemCounts.getOrDefault(system, 0) + 1);

                if (sat.cn0 > 0) {
                    satellitesWithSignal++;
                    totalSignalStrength += sat.cn0;

                    systemSignalTotals.put(system, systemSignalTotals.getOrDefault(system, 0f) + sat.cn0);
                    systemSignalCounts.put(system, systemSignalCounts.getOrDefault(system, 0) + 1);
                }

                if (sat.usedInFix) {
                    satellitesUsedInFix++;
                    systemUsedCounts.put(system, systemUsedCounts.getOrDefault(system, 0) + 1);
                }
            }

            float averageSignal = satellitesWithSignal > 0 ? totalSignalStrength / satellitesWithSignal : 0;

            Map<String, Object> systemStats = new HashMap<>();
            for (String system : systemCounts.keySet()) {
                Map<String, Object> sysStat = new HashMap<>();
                sysStat.put("count", systemCounts.get(system));
                sysStat.put("used", systemUsedCounts.getOrDefault(system, 0));
                sysStat.put("hasSignal", systemSignalCounts.getOrDefault(system, 0));

                if (systemSignalCounts.containsKey(system)) {
                    sysStat.put("averageSignal", systemSignalTotals.get(system) / systemSignalCounts.get(system));
                } else {
                    sysStat.put("averageSignal", 0);
                }

                systemStats.put(system, sysStat);
            }

            stats.put("totalSatellites", totalSatellites);
            stats.put("satellitesWithSignal", satellitesWithSignal);
            stats.put("satellitesUsedInFix", satellitesUsedInFix);
            stats.put("averageSignal", averageSignal);
            stats.put("systemStats", systemStats);
            stats.put("hasL5Band", hasL5BandSupport);
            stats.put("hasL5BandActive", hasL5BandActive);
            stats.put("primarySystem", primaryPositioningSystem);
            stats.put("usingExternalGnss", usingExternalGnss);
            stats.put("timestamp", System.currentTimeMillis());
            stats.put("hasData", true);

            result.success(stats);

        } catch (Exception e) {
            Log.e("NavIC", "Error getting GNSS range statistics", e);
            result.error("STATISTICS_ERROR", "Failed to get GNSS range statistics", null);
        }
    }

    private void startQuickSatelliteDetection(final MethodChannel.Result originalResult, String purpose) {
        final long startTime = System.currentTimeMillis();
        final GnssStatus.Callback[] quickCallback = new GnssStatus.Callback[1];
        final AtomicBoolean resultSent = new AtomicBoolean(false);

        quickCallback[0] = new GnssStatus.Callback() {
            @Override
            public void onSatelliteStatusChanged(GnssStatus status) {
                long elapsedTime = System.currentTimeMillis() - startTime;
                EnhancedSatelliteScanResult scanResult = processEnhancedSatellites(
                        status,
                        elapsedTime,
                        hasL5BandSupport,
                        usingExternalGnss
                );

                updateSatelliteTracking(scanResult);

                if (!detectedSatellites.isEmpty() && elapsedTime > 2000) {
                    if (resultSent.compareAndSet(false, true)) {
                        cleanupCallback(quickCallback[0]);

                        switch (purpose) {
                            case "STATISTICS":
                                getGnssRangeStatistics(originalResult);
                                break;
                            case "DETAILED_INFO":
                                getDetailedSatelliteInfo(originalResult);
                                break;
                            default:
                                getAllSatellitesInRange(originalResult);
                        }
                    }
                }
            }

            @Override
            public void onStarted() {
                Log.d("NavIC", "Quick detection started for: " + purpose);
            }

            @Override
            public void onStopped() {
                Log.d("NavIC", "Quick detection stopped");
            }
        };

        try {
            locationManager.registerGnssStatusCallback(quickCallback[0], handler);

            handler.postDelayed(() -> {
                if (resultSent.compareAndSet(false, true)) {
                    cleanupCallback(quickCallback[0]);

                    if (detectedSatellites.isEmpty()) {
                        Map<String, Object> error = new HashMap<>();
                        error.put("error", "NO_SATELLITES_DETECTED");
                        error.put("message", "No satellites detected within timeout");
                        originalResult.success(error);
                    } else {
                        switch (purpose) {
                            case "STATISTICS":
                                getGnssRangeStatistics(originalResult);
                                break;
                            case "DETAILED_INFO":
                                getDetailedSatelliteInfo(originalResult);
                                break;
                            default:
                                getAllSatellitesInRange(originalResult);
                        }
                    }
                }
            }, 5000);

        } catch (Exception e) {
            Log.e("NavIC", "Error starting quick detection", e);
            Map<String, Object> error = new HashMap<>();
            error.put("error", "DETECTION_FAILED");
            error.put("message", e.getMessage());
            originalResult.success(error);
        }
    }

    private void getDetailedSatelliteInfo(MethodChannel.Result result) {
        Log.d("NavIC", "🔍 Getting detailed satellite information");

        if (!hasLocationPermissions()) {
            result.error("PERMISSION_DENIED", "Location permissions required", null);
            return;
        }

        try {
            if (detectedSatellites.isEmpty()) {
                Log.d("NavIC", "No satellites detected, starting quick detection...");
                startQuickSatelliteDetection(result, "DETAILED_INFO");
                return;
            }

            List<Map<String, Object>> detailedInfo = new ArrayList<>();

            for (EnhancedSatellite sat : detectedSatellites.values()) {
                Map<String, Object> info = sat.toEnhancedMap();

                info.put("satelliteName", getSatelliteName(sat.systemName, sat.svid));
                info.put("constellationDescription", getConstellationDescription(sat.constellation));
                info.put("frequencyDescription", getFrequencyDescription(sat.frequencyBand));
                info.put("positioningRole", getPositioningRole(sat.usedInFix, sat.cn0));
                info.put("healthStatus", getHealthStatus(sat.cn0, sat.hasEphemeris, sat.hasAlmanac));
                info.put("detectionAge", System.currentTimeMillis() - sat.detectionTime);

                detailedInfo.add(info);
            }

            Map<String, Object> response = new HashMap<>();
            response.put("satellites", detailedInfo);
            response.put("count", detailedInfo.size());
            response.put("timestamp", System.currentTimeMillis());
            response.put("hasData", true);
            response.put("usingExternalGnss", usingExternalGnss);

            result.success(response);

        } catch (Exception e) {
            Log.e("NavIC", "Error getting detailed satellite info", e);
            result.error("DETAILED_INFO_ERROR", "Failed to get detailed satellite info", null);
        }
    }

    private EnhancedSatelliteScanResult processEnhancedSatellites(GnssStatus status, long elapsedTime,
                                                                  boolean hasL5Support, boolean externalGnss) {
        Map<String, EnhancedSatellite> allSats = new ConcurrentHashMap<>();
        Map<String, List<EnhancedSatellite>> satsBySystem = new ConcurrentHashMap<>();

        int navicCount = 0;
        int navicUsedInFix = 0;
        float navicTotalSignal = 0;
        int navicWithSignal = 0;

        int totalSatellites = status.getSatelliteCount();
        List<Map<String, Object>> navicDetails = new ArrayList<>();
        List<Map<String, Object>> allSatellitesList = new ArrayList<>();

        for (int i = 0; i < totalSatellites; i++) {
            int constellation = status.getConstellationType(i);
            String systemName = getEnhancedConstellationName(constellation);
            String countryFlag = GNSS_COUNTRIES.getOrDefault(systemName, "🌐");

            int svid = status.getSvid(i);
            float cn0 = status.getCn0DbHz(i);
            boolean used = status.usedInFix(i);
            float elevation = status.getElevationDegrees(i);
            float azimuth = status.getAzimuthDegrees(i);
            boolean hasEphemeris = status.hasEphemerisData(i);
            boolean hasAlmanac = status.hasAlmanacData(i);

            String frequencyBand = "Unknown";
            double carrierFrequency = 0.0;

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                try {
                    carrierFrequency = status.getCarrierFrequencyHz(i);
                    if (carrierFrequency > 0) {
                        frequencyBand = determineFrequencyBandFromHz(carrierFrequency);
                    }
                } catch (Exception e) {
                    frequencyBand = getDefaultBandForConstellation(constellation, hasL5Support);
                }
            } else {
                frequencyBand = getDefaultBandForConstellation(constellation, hasL5Support);
            }

            EnhancedSatellite satellite = new EnhancedSatellite(
                    svid,
                    systemName,
                    constellation,
                    countryFlag,
                    cn0,
                    used,
                    elevation,
                    azimuth,
                    hasEphemeris,
                    hasAlmanac,
                    frequencyBand,
                    carrierFrequency,
                    elapsedTime,
                    externalGnss
            );

            String satelliteKey = systemName + "_" + svid + (externalGnss ? "_EXT" : "");
            allSats.put(satelliteKey, satellite);

            if (!satsBySystem.containsKey(systemName)) {
                satsBySystem.put(systemName, new ArrayList<>());
            }
            satsBySystem.get(systemName).add(satellite);

            Map<String, Object> satMap = satellite.toEnhancedMap();
            allSatellitesList.add(satMap);

            if (systemName.equals("IRNSS") && svid >= 1 && svid <= 14) {
                if (cn0 >= MIN_NAVIC_SIGNAL_STRENGTH) {
                    navicCount++;
                    if (used) navicUsedInFix++;
                    if (cn0 > 0) {
                        navicTotalSignal += cn0;
                        navicWithSignal++;
                    }
                    navicDetails.add(satMap);
                }
            }
        }

        float navicAvgSignal = navicWithSignal > 0 ? navicTotalSignal / navicWithSignal : 0.0f;

        return new EnhancedSatelliteScanResult(
                navicCount, navicUsedInFix, totalSatellites, navicAvgSignal,
                navicDetails, allSats, satsBySystem, allSatellitesList,
                externalGnss
        );
    }

    private void updateSatelliteTracking(EnhancedSatelliteScanResult scanResult) {
        for (Map.Entry<String, EnhancedSatellite> entry : scanResult.allSatellites.entrySet()) {
            String key = entry.getKey();
            EnhancedSatellite newSat = entry.getValue();

            EnhancedSatellite existingSat = detectedSatellites.get(key);
            if (existingSat != null) {
                existingSat.detectionCount++;
                existingSat.cn0 = (existingSat.cn0 + newSat.cn0) / 2;
                existingSat.usedInFix = existingSat.usedInFix || newSat.usedInFix;
                existingSat.elevation = (existingSat.elevation + newSat.elevation) / 2;
                existingSat.azimuth = (existingSat.azimuth + newSat.azimuth) / 2;

                if (newSat.carrierFrequency > 0) {
                    existingSat.carrierFrequency = newSat.carrierFrequency;
                    existingSat.frequencyBand = newSat.frequencyBand;
                }
            } else {
                detectedSatellites.put(key, newSat);
            }
        }

        satellitesBySystem.clear();
        satellitesBySystem.putAll(scanResult.satellitesBySystem);
    }

    private void checkNavicHardwareSupport(MethodChannel.Result result) {
        Log.d("NavIC", "🚀 Starting NavIC hardware detection" +
                (usingExternalGnss ? " (External GNSS Mode)" : " (Internal Mode)"));

        if (!hasLocationPermissions()) {
            result.error("PERMISSION_DENIED", "Location permissions required", null);
            return;
        }

        handler.post(() -> {
            if (usingExternalGnss) {
                Map<String, Object> response = new HashMap<>();
                response.put("isSupported", true);
                response.put("isActive", false);
                response.put("detectionMethod", "EXTERNAL_USB_GNSS");
                response.put("chipsetType", "EXTERNAL_DEVICE");
                response.put("chipsetVendor", externalGnssVendor);
                response.put("chipsetModel", externalGnssInfo);
                response.put("hasL5Band", hasL5BandSupport);
                response.put("hasL5BandActive", hasL5BandActive);
                response.put("usingExternalGnss", true);
                response.put("externalDeviceInfo", externalGnssInfo);
                response.put("message", "Using external USB GNSS device. L5 band detection enabled.");

                response.put("satelliteCount", detectedSatellites.size());
                response.put("navicSatellites", countNavicSatellites());
                response.put("allSatellites", getSatellitesAsList());
                result.success(response);

            } else {
                boolean hasIrnssSupport = false;
                String detectionMethod = "INTERNAL_SIMPLIFIED";

                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    try {
                        Object gnssCaps = locationManager.getGnssCapabilities();
                        if (gnssCaps != null) {
                            Method hasIrnssMethod = gnssCaps.getClass().getMethod("hasIrnss");
                            Object ret = hasIrnssMethod.invoke(gnssCaps);
                            if (ret instanceof Boolean) {
                                hasIrnssSupport = (Boolean) ret;
                                detectionMethod = "GNSS_CAPABILITIES_API";
                            }
                        }
                    } catch (Exception e) {
                        Log.d("NavIC", "Error checking GNSS capabilities", e);
                    }
                }

                Map<String, Object> response = new HashMap<>();
                response.put("isSupported", hasIrnssSupport);
                response.put("isActive", countNavicSatellites() > 0);
                response.put("detectionMethod", detectionMethod);
                response.put("satelliteCount", detectedSatellites.size());
                response.put("navicSatellites", countNavicSatellites());
                response.put("hasL5Band", false);
                response.put("usingExternalGnss", false);
                response.put("allSatellites", getSatellitesAsList());
                response.put("message", "Internal GNSS detection completed");

                result.success(response);
            }
        });
    }

    private int countNavicSatellites() {
        int count = 0;
        for (EnhancedSatellite sat : detectedSatellites.values()) {
            if ("IRNSS".equals(sat.systemName)) {
                count++;
            }
        }
        return count;
    }

    // =============== PERMISSION METHODS ===============

    private void checkLocationPermissions(MethodChannel.Result result) {
        try {
            boolean hasFineLocation = ContextCompat.checkSelfPermission(
                    this, android.Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED;
            boolean hasCoarseLocation = ContextCompat.checkSelfPermission(
                    this, android.Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED;
            boolean hasBackgroundLocation = true;

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                hasBackgroundLocation = ContextCompat.checkSelfPermission(
                        this, android.Manifest.permission.ACCESS_BACKGROUND_LOCATION) == PackageManager.PERMISSION_GRANTED;
            }

            Map<String, Object> permissions = new HashMap<>();
            permissions.put("hasFineLocation", hasFineLocation);
            permissions.put("hasCoarseLocation", hasCoarseLocation);
            permissions.put("hasBackgroundLocation", hasBackgroundLocation);
            permissions.put("allPermissionsGranted", hasFineLocation && hasCoarseLocation);
            permissions.put("shouldShowRationale", shouldShowPermissionRationale());
            permissions.put("usingExternalGnss", usingExternalGnss);

            Log.d("NavIC", "Permission check - Fine: " + hasFineLocation +
                    ", Coarse: " + hasCoarseLocation + ", Background: " + hasBackgroundLocation);
            result.success(permissions);
        } catch (Exception e) {
            Log.e("NavIC", "Error checking permissions", e);
            result.error("PERMISSION_ERROR", "Failed to check permissions", null);
        }
    }

    private boolean shouldShowPermissionRationale() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            return ActivityCompat.shouldShowRequestPermissionRationale(
                    this, android.Manifest.permission.ACCESS_FINE_LOCATION);
        }
        return false;
    }

    private void requestLocationPermissions(MethodChannel.Result result) {
        try {
            String[] permissions;
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                permissions = new String[]{
                        android.Manifest.permission.ACCESS_FINE_LOCATION,
                        android.Manifest.permission.ACCESS_COARSE_LOCATION,
                        android.Manifest.permission.ACCESS_BACKGROUND_LOCATION
                };
            } else {
                permissions = new String[]{
                        android.Manifest.permission.ACCESS_FINE_LOCATION,
                        android.Manifest.permission.ACCESS_COARSE_LOCATION
                };
            }

            ActivityCompat.requestPermissions(this, permissions, 1001);

            Map<String, Object> response = new HashMap<>();
            response.put("requested", true);
            response.put("message", "Location permissions requested");
            result.success(response);
        } catch (Exception e) {
            Log.e("NavIC", "Error requesting permissions", e);
            result.error("PERMISSION_REQUEST_ERROR", "Failed to request permissions", null);
        }
    }

    @Override
    public void onRequestPermissionsResult(int requestCode, @NonNull String[] permissions,
                                           @NonNull int[] grantResults) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults);

        if (requestCode == 1001) {
            Map<String, Object> permissionResult = new HashMap<>();

            boolean granted = false;
            if (grantResults.length > 0) {
                granted = grantResults[0] == PackageManager.PERMISSION_GRANTED;
            }

            permissionResult.put("granted", granted);
            permissionResult.put("message", granted ? "Location permission granted" : "Location permission denied");

            try {
                handler.post(() -> {
                    methodChannel.invokeMethod("onPermissionResult", permissionResult);
                });
            } catch (Exception e) {
                Log.e("NavIC", "Error sending permission result", e);
            }
        }
    }

    private boolean hasLocationPermissions() {
        return ContextCompat.checkSelfPermission(
                this, android.Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED ||
                ContextCompat.checkSelfPermission(
                        this, android.Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED;
    }

    private boolean isLocationEnabled() {
        try {
            return locationManager.isProviderEnabled(LocationManager.GPS_PROVIDER) ||
                    locationManager.isProviderEnabled(LocationManager.NETWORK_PROVIDER);
        } catch (Exception e) {
            return false;
        }
    }

    // =============== LOCATION METHODS ===============

    private void startLocationUpdates(MethodChannel.Result result) {
        Log.d("NavIC", "📍 Starting location updates" +
                (usingExternalGnss ? " with external GNSS" : ""));

        if (!hasLocationPermissions()) {
            result.error("PERMISSION_DENIED", "Location permissions required", null);
            return;
        }

        if (locationListener != null) {
            locationManager.removeUpdates(locationListener);
        }

        locationListener = new LocationListener() {
            @Override
            public void onLocationChanged(Location location) {
                try {
                    Map<String, Object> locationData = new HashMap<>();
                    locationData.put("latitude", location.getLatitude());
                    locationData.put("longitude", location.getLongitude());
                    locationData.put("accuracy", location.getAccuracy());
                    locationData.put("altitude", location.getAltitude());
                    locationData.put("speed", location.getSpeed());
                    locationData.put("bearing", location.getBearing());
                    locationData.put("time", location.getTime());
                    locationData.put("provider", location.getProvider());
                    locationData.put("timestamp", System.currentTimeMillis());
                    locationData.put("usingExternalGnss", usingExternalGnss);

                    if (usingExternalGnss) {
                        locationData.put("externalGnssInfo", externalGnssInfo);
                        locationData.put("hasL5Band", hasL5BandSupport);
                        locationData.put("hasL5BandActive", hasL5BandActive);
                    }

                    if (!detectedSatellites.isEmpty()) {
                        locationData.put("satelliteCount", detectedSatellites.size());
                        locationData.put("navicSatellites", countNavicSatellites());
                        locationData.put("primarySystem", primaryPositioningSystem);
                    }

                    handler.post(() -> {
                        methodChannel.invokeMethod("onLocationUpdate", locationData);
                    });
                } catch (Exception e) {
                    Log.e("NavIC", "Error sending location update", e);
                }
            }

            @Override
            public void onStatusChanged(String provider, int status, Bundle extras) {
                Log.d("NavIC", "Location provider status: " + provider + " - " + status);
            }

            @Override
            public void onProviderEnabled(String provider) {
                Log.d("NavIC", "Location provider enabled: " + provider);
            }

            @Override
            public void onProviderDisabled(String provider) {
                Log.d("NavIC", "Location provider disabled: " + provider);
            }
        };

        try {
            if (usingExternalGnss) {
                if (locationManager.isProviderEnabled(LocationManager.GPS_PROVIDER)) {
                    locationManager.requestLocationUpdates(
                            LocationManager.GPS_PROVIDER,
                            LOCATION_UPDATE_INTERVAL_MS,
                            LOCATION_UPDATE_DISTANCE_M,
                            locationListener,
                            handler.getLooper()
                    );
                    Log.d("NavIC", "External GNSS updates requested via GPS provider");
                } else {
                    Log.d("NavIC", "GPS provider disabled, using network for external GNSS");
                    locationManager.requestLocationUpdates(
                            LocationManager.NETWORK_PROVIDER,
                            LOCATION_UPDATE_INTERVAL_MS * 2,
                            LOCATION_UPDATE_DISTANCE_M * 2,
                            locationListener,
                            handler.getLooper()
                    );
                }
            } else {
                if (locationManager.isProviderEnabled(LocationManager.GPS_PROVIDER)) {
                    locationManager.requestLocationUpdates(
                            LocationManager.GPS_PROVIDER,
                            LOCATION_UPDATE_INTERVAL_MS,
                            LOCATION_UPDATE_DISTANCE_M,
                            locationListener,
                            handler.getLooper()
                    );
                }

                if (locationManager.isProviderEnabled(LocationManager.NETWORK_PROVIDER)) {
                    locationManager.requestLocationUpdates(
                            LocationManager.NETWORK_PROVIDER,
                            LOCATION_UPDATE_INTERVAL_MS * 2,
                            LOCATION_UPDATE_DISTANCE_M * 2,
                            locationListener,
                            handler.getLooper()
                    );
                }
            }

            isTrackingLocation = true;

            Map<String, Object> resp = new HashMap<>();
            resp.put("success", true);
            resp.put("message", "Location updates started" +
                    (usingExternalGnss ? " with external GNSS" : ""));
            resp.put("usingExternalGnss", usingExternalGnss);
            resp.put("externalDeviceInfo", externalGnssInfo);
            resp.put("hasL5BandActive", usingExternalGnss ? hasL5BandActive : false);
            result.success(resp);

        } catch (SecurityException se) {
            Log.e("NavIC", "Permission error starting location updates", se);
            result.error("PERMISSION_ERROR", "Location permissions required", null);
        } catch (Exception e) {
            Log.e("NavIC", "Error starting location updates", e);
            result.error("LOCATION_ERROR", "Failed to start location updates", null);
        }
    }

    private void stopLocationUpdates(MethodChannel.Result result) {
        Log.d("NavIC", "Stopping location updates");
        stopLocationUpdates();
        if (result != null) {
            Map<String, Object> resp = new HashMap<>();
            resp.put("success", true);
            resp.put("message", "Location updates stopped");
            result.success(resp);
        }
    }

    private void stopLocationUpdates() {
        if (locationListener != null) {
            locationManager.removeUpdates(locationListener);
            locationListener = null;
            isTrackingLocation = false;
            Log.d("NavIC", "Location updates stopped");
        }
    }

    // =============== OTHER METHODS ===============

    private void openLocationSettings(MethodChannel.Result result) {
        try {
            Intent intent = new Intent(Settings.ACTION_LOCATION_SOURCE_SETTINGS);
            startActivity(intent);

            Map<String, Object> response = new HashMap<>();
            response.put("success", true);
            response.put("message", "Location settings opened");
            result.success(response);
        } catch (Exception e) {
            Log.e("NavIC", "Error opening location settings", e);
            result.error("SETTINGS_ERROR", "Failed to open location settings", null);
        }
    }

    private void isLocationEnabled(MethodChannel.Result result) {
        try {
            boolean gpsEnabled = locationManager.isProviderEnabled(LocationManager.GPS_PROVIDER);
            boolean networkEnabled = locationManager.isProviderEnabled(LocationManager.NETWORK_PROVIDER);
            boolean fusedEnabled = false;

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                fusedEnabled = locationManager.isProviderEnabled(LocationManager.FUSED_PROVIDER);
            }

            Map<String, Object> response = new HashMap<>();
            response.put("gpsEnabled", gpsEnabled);
            response.put("networkEnabled", networkEnabled);
            response.put("fusedEnabled", fusedEnabled);
            response.put("anyEnabled", gpsEnabled || networkEnabled || fusedEnabled);
            response.put("providers", getActiveProviders());
            response.put("usingExternalGnss", usingExternalGnss);

            result.success(response);
        } catch (Exception e) {
            Log.e("NavIC", "Error checking location status", e);
            result.error("LOCATION_STATUS_ERROR", "Failed to check location status", null);
        }
    }

    private List<String> getActiveProviders() {
        List<String> activeProviders = new ArrayList<>();
        String[] providers = {LocationManager.GPS_PROVIDER, LocationManager.NETWORK_PROVIDER};

        for (String provider : providers) {
            if (locationManager.isProviderEnabled(provider)) {
                activeProviders.add(provider);
            }
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            if (locationManager.isProviderEnabled(LocationManager.FUSED_PROVIDER)) {
                activeProviders.add(LocationManager.FUSED_PROVIDER);
            }
        }

        return activeProviders;
    }

    private void getAllSatellites(MethodChannel.Result result) {
        if (!hasLocationPermissions()) {
            result.error("PERMISSION_DENIED", "Location permissions required", null);
            return;
        }

        List<Map<String, Object>> allSatellites = new ArrayList<>();
        Map<String, Object> systems = new HashMap<>();

        for (EnhancedSatellite sat : detectedSatellites.values()) {
            Map<String, Object> satMap = sat.toEnhancedMap();
            allSatellites.add(satMap);

            String system = sat.systemName;
            if (!systems.containsKey(system)) {
                Map<String, Object> systemInfo = new HashMap<>();
                systemInfo.put("flag", sat.countryFlag);
                systemInfo.put("name", system);
                systemInfo.put("count", 0);
                systemInfo.put("used", 0);
                systemInfo.put("averageSignal", 0.0);
                systems.put(system, systemInfo);
            }

            Map<String, Object> systemInfo = (Map<String, Object>) systems.get(system);
            systemInfo.put("count", (Integer) systemInfo.get("count") + 1);
            if (sat.usedInFix) {
                systemInfo.put("used", (Integer) systemInfo.get("used") + 1);
            }

            double currentAvg = (Double) systemInfo.get("averageSignal");
            int count = (Integer) systemInfo.get("count");
            systemInfo.put("averageSignal", (currentAvg * (count - 1) + sat.cn0) / count);
        }

        Map<String, Object> response = new HashMap<>();
        response.put("satellites", allSatellites);
        response.put("systems", new ArrayList<>(systems.values()));
        response.put("totalSatellites", allSatellites.size());
        response.put("hasL5Band", hasL5BandSupport);
        response.put("hasL5BandActive", hasL5BandActive);
        response.put("primarySystem", primaryPositioningSystem);
        response.put("usingExternalGnss", usingExternalGnss);
        response.put("externalGnssInfo", externalGnssInfo);
        response.put("timestamp", System.currentTimeMillis());

        Log.d("NavIC", String.format("📊 Returning %d satellites from %d systems, External: %s",
                allSatellites.size(), systems.size(), usingExternalGnss ? "Yes" : "No"));

        result.success(response);
    }

    private void getDeviceInfo(MethodChannel.Result result) {
        try {
            Map<String, Object> deviceInfo = new HashMap<>();
            deviceInfo.put("manufacturer", Build.MANUFACTURER);
            deviceInfo.put("model", Build.MODEL);
            deviceInfo.put("device", Build.DEVICE);
            deviceInfo.put("hardware", Build.HARDWARE);
            deviceInfo.put("androidVersion", Build.VERSION.SDK_INT);
            deviceInfo.put("androidRelease", Build.VERSION.RELEASE);

            deviceInfo.put("usingExternalGnss", usingExternalGnss);
            deviceInfo.put("externalGnssInfo", externalGnssInfo);
            deviceInfo.put("externalGnssVendor", externalGnssVendor);
            deviceInfo.put("externalGnssVendorId", externalGnssVendorId);
            deviceInfo.put("externalGnssProductId", externalGnssProductId);
            deviceInfo.put("hasL5BandSupport", hasL5BandSupport);
            deviceInfo.put("hasL5BandActive", hasL5BandActive);
            deviceInfo.put("usbConnectionActive", usbConnection != null);

            Map<String, Object> gnssCapabilities = new HashMap<>();
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                try {
                    Object gnssCaps = locationManager.getGnssCapabilities();
                    if (gnssCaps != null) {
                        Class<?> capsClass = gnssCaps.getClass();

                        String[] capabilityMethods = {"hasIrnss", "hasL5"};
                        for (String methodName : capabilityMethods) {
                            try {
                                Method method = capsClass.getMethod(methodName);
                                Object value = method.invoke(gnssCaps);
                                if (value instanceof Boolean) {
                                    gnssCapabilities.put(methodName, (Boolean) value);
                                }
                            } catch (NoSuchMethodException ignore) {
                            }
                        }
                    }
                } catch (Exception e) {
                    Log.d("NavIC", "Error getting GNSS capabilities");
                }
            }

            deviceInfo.put("gnssCapabilities", gnssCapabilities);
            deviceInfo.put("detectionTime", System.currentTimeMillis());

            result.success(deviceInfo);
        } catch (Exception e) {
            Log.e("NavIC", "Error getting device info", e);
            result.error("DEVICE_INFO_ERROR", "Failed to get device info", null);
        }
    }

    private void getGnssCapabilities(MethodChannel.Result result) {
        Log.d("NavIC", "Getting GNSS capabilities");
        Map<String, Object> caps = new HashMap<>();
        try {
            caps.put("androidVersion", Build.VERSION.SDK_INT);
            caps.put("manufacturer", Build.MANUFACTURER);
            caps.put("model", Build.MODEL);
            caps.put("device", Build.DEVICE);
            caps.put("hardware", Build.HARDWARE);

            boolean hasGnssFeature = getPackageManager().hasSystemFeature(PackageManager.FEATURE_LOCATION_GPS);
            caps.put("hasGnssFeature", hasGnssFeature);

            Map<String, Object> gnssMap = new HashMap<>();
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                try {
                    Object gnssCaps = locationManager.getGnssCapabilities();
                    if (gnssCaps != null) {
                        Class<?> capsClass = gnssCaps.getClass();

                        String[] capabilityMethods = {"hasIrnss", "hasL5", "hasL1", "hasL2",
                                "hasGlonass", "hasGalileo", "hasBeidou",
                                "hasQzss", "hasSbas"};

                        for (String methodName : capabilityMethods) {
                            try {
                                Method method = capsClass.getMethod(methodName);
                                Object value = method.invoke(gnssCaps);
                                if (value instanceof Boolean) {
                                    gnssMap.put(methodName, (Boolean) value);
                                    Log.d("NavIC", "GnssCapabilities." + methodName + ": " + value);
                                }
                            } catch (NoSuchMethodException ignore) {
                            }
                        }
                    }
                } catch (Throwable t) {
                    Log.e("NavIC", "Error getting GNSS capabilities", t);
                }
            } else {
                gnssMap.put("hasIrnss", false);
                gnssMap.put("hasL5", false);
            }

            caps.put("gnssCapabilities", gnssMap);
            caps.put("capabilitiesMethod", "SIMPLIFIED_DETECTION");
            caps.put("detectionTime", System.currentTimeMillis());
            caps.put("hasL5Band", hasL5BandSupport);
            caps.put("hasL5BandActive", hasL5BandActive);
            caps.put("usingExternalGnss", usingExternalGnss);
            caps.put("externalGnssInfo", externalGnssInfo);

            Log.d("NavIC", "GNSS capabilities retrieved successfully");
            result.success(caps);
        } catch (Exception e) {
            Log.e("NavIC", "Failed to get GNSS capabilities", e);
            result.error("CAPABILITIES_ERROR", "Failed to get GNSS capabilities", null);
        }
    }

    private void startRealTimeNavicDetection(MethodChannel.Result result) {
        Log.d("NavIC", "Starting real-time NavIC detection");

        if (!hasLocationPermissions()) {
            result.error("PERMISSION_DENIED", "Location permissions required", null);
            return;
        }

        if (realtimeCallback != null) {
            locationManager.unregisterGnssStatusCallback(realtimeCallback);
        }

        realtimeCallback = new GnssStatus.Callback() {
            @Override
            public void onSatelliteStatusChanged(GnssStatus status) {
                Map<String, Object> data = processEnhancedSatelliteData(status);
                try {
                    handler.post(() -> {
                        methodChannel.invokeMethod("onSatelliteUpdate", data);
                    });
                } catch (Exception e) {
                    Log.e("NavIC", "Error sending satellite update to Flutter", e);
                }
            }

            @Override
            public void onStarted() {
                Log.d("NavIC", "Real-time GNSS monitoring started");
            }

            @Override
            public void onStopped() {
                Log.d("NavIC", "Real-time GNSS monitoring stopped");
            }
        };

        try {
            locationManager.registerGnssStatusCallback(realtimeCallback, handler);
            Map<String, Object> resp = new HashMap<>();
            resp.put("success", true);
            resp.put("message", "Real-time NavIC detection started");
            resp.put("hasL5Band", hasL5BandSupport);
            resp.put("hasL5BandActive", hasL5BandActive);
            resp.put("usingExternalGnss", usingExternalGnss);
            resp.put("externalGnssInfo", externalGnssInfo);
            Log.d("NavIC", "Real-time detection started successfully");
            result.success(resp);
        } catch (SecurityException se) {
            Log.e("NavIC", "Permission error starting real-time detection", se);
            result.error("PERMISSION_ERROR", "Location permissions required", null);
        } catch (Exception e) {
            Log.e("NavIC", "Error starting real-time detection", e);
            result.error("REALTIME_DETECTION_ERROR", "Failed to start detection: " + e.getMessage(), null);
        }
    }

    private Map<String, Object> processEnhancedSatelliteData(GnssStatus status) {
        Map<String, Object> constellations = new HashMap<>();
        List<Map<String, Object>> satellites = new ArrayList<>();
        List<Map<String, Object>> navicSatellites = new ArrayList<>();

        Map<String, Object> systemStats = new HashMap<>();

        int irnssCount = 0;
        int gpsCount = 0;
        int glonassCount = 0;
        int galileoCount = 0;
        int beidouCount = 0;
        int qzssCount = 0;
        int sbasCount = 0;
        int irnssUsedInFix = 0;
        int gpsUsedInFix = 0;
        int glonassUsedInFix = 0;
        int galileoUsedInFix = 0;
        int beidouUsedInFix = 0;
        int qzssUsedInFix = 0;

        int l5SatelliteCount = 0;
        float irnssSignalTotal = 0;
        float gpsSignalTotal = 0;
        int irnssSignalCount = 0;
        int gpsSignalCount = 0;

        for (int i = 0; i < status.getSatelliteCount(); i++) {
            int constellationType = status.getConstellationType(i);
            String constellationName = getEnhancedConstellationName(constellationType);
            String countryFlag = GNSS_COUNTRIES.getOrDefault(constellationName, "🌐");

            int svid = status.getSvid(i);
            float cn0 = status.getCn0DbHz(i);
            boolean used = status.usedInFix(i);
            float elevation = status.getElevationDegrees(i);
            float azimuth = status.getAzimuthDegrees(i);
            boolean hasEphemeris = status.hasEphemerisData(i);
            boolean hasAlmanac = status.hasAlmanacData(i);

            String frequencyBand = "Unknown";
            double carrierFrequency = 0.0;
            boolean isL5Band = false;

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                try {
                    carrierFrequency = status.getCarrierFrequencyHz(i);
                    if (carrierFrequency > 0) {
                        frequencyBand = determineFrequencyBandFromHz(carrierFrequency);
                        double freqMHz = carrierFrequency / 1e6;
                        if (Math.abs(freqMHz - 1176.45) <= 2.0) {
                            isL5Band = true;
                            l5SatelliteCount++;
                        }
                    }
                } catch (Exception e) {
                    frequencyBand = getDefaultBandForConstellation(constellationType, hasL5BandSupport);
                }
            } else {
                frequencyBand = getDefaultBandForConstellation(constellationType, hasL5BandSupport);
            }

            switch (constellationType) {
                case GnssStatus.CONSTELLATION_IRNSS:
                    irnssCount++;
                    if (used) irnssUsedInFix++;
                    if (cn0 > 0) {
                        irnssSignalTotal += cn0;
                        irnssSignalCount++;
                    }
                    break;
                case GnssStatus.CONSTELLATION_GPS:
                    gpsCount++;
                    if (used) gpsUsedInFix++;
                    if (cn0 > 0) {
                        gpsSignalTotal += cn0;
                        gpsSignalCount++;
                    }
                    break;
                case GnssStatus.CONSTELLATION_GLONASS:
                    glonassCount++; if (used) glonassUsedInFix++; break;
                case GnssStatus.CONSTELLATION_GALILEO:
                    galileoCount++; if (used) galileoUsedInFix++; break;
                case GnssStatus.CONSTELLATION_BEIDOU:
                    beidouCount++; if (used) beidouUsedInFix++; break;
                case GnssStatus.CONSTELLATION_QZSS:
                    qzssCount++; if (used) qzssUsedInFix++; break;
                case GnssStatus.CONSTELLATION_SBAS:
                    sbasCount++; break;
            }

            Map<String, Object> sat = new HashMap<>();
            sat.put("constellation", constellationName);
            sat.put("system", constellationName);
            sat.put("countryFlag", countryFlag);
            sat.put("svid", svid);
            sat.put("cn0DbHz", cn0);
            sat.put("elevation", elevation);
            sat.put("azimuth", azimuth);
            sat.put("hasEphemeris", hasEphemeris);
            sat.put("hasAlmanac", hasAlmanac);
            sat.put("usedInFix", used);
            sat.put("frequencyBand", frequencyBand);
            sat.put("carrierFrequencyHz", carrierFrequency);
            sat.put("isL5Band", isL5Band);
            sat.put("externalGnss", usingExternalGnss);

            String signalStrength = "UNKNOWN";
            if (cn0 >= 35) signalStrength = "EXCELLENT";
            else if (cn0 >= 25) signalStrength = "GOOD";
            else if (cn0 >= 18) signalStrength = "FAIR";
            else if (cn0 >= 10) signalStrength = "WEAK";
            else if (cn0 > 0) signalStrength = "POOR";
            sat.put("signalStrength", signalStrength);

            satellites.add(sat);

            if (constellationType == GnssStatus.CONSTELLATION_IRNSS) {
                navicSatellites.add(sat);
            }
        }

        if (l5SatelliteCount > 0 && !hasL5BandActive) {
            hasL5BandActive = true;
            Log.d("NavIC", "Real-time update: Found " + l5SatelliteCount + " L5 satellites");
        }

        constellations.put("IRNSS", irnssCount);
        constellations.put("GPS", gpsCount);
        constellations.put("GLONASS", glonassCount);
        constellations.put("GALILEO", galileoCount);
        constellations.put("BEIDOU", beidouCount);
        constellations.put("QZSS", qzssCount);
        constellations.put("SBAS", sbasCount);

        float irnssAvgSignal = irnssSignalCount > 0 ? irnssSignalTotal / irnssSignalCount : 0;
        float gpsAvgSignal = gpsSignalCount > 0 ? gpsSignalTotal / gpsSignalCount : 0;

        systemStats.put("IRNSS", createEnhancedSystemStat("IRNSS", "🇮🇳", irnssCount, irnssUsedInFix, irnssAvgSignal));
        systemStats.put("GPS", createEnhancedSystemStat("GPS", "🇺🇸", gpsCount, gpsUsedInFix, gpsAvgSignal));
        systemStats.put("GLONASS", createEnhancedSystemStat("GLONASS", "🇷🇺", glonassCount, glonassUsedInFix, 0));
        systemStats.put("GALILEO", createEnhancedSystemStat("GALILEO", "🇪🇺", galileoCount, galileoUsedInFix, 0));
        systemStats.put("BEIDOU", createEnhancedSystemStat("BEIDOU", "🇨🇳", beidouCount, beidouUsedInFix, 0));

        String primarySystem = determinePrimarySystemFromCounts(irnssUsedInFix, gpsUsedInFix,
                glonassUsedInFix, galileoUsedInFix, beidouUsedInFix);

        Map<String, Object> result = new HashMap<>();
        result.put("type", "ENHANCED_SATELLITE_UPDATE");
        result.put("timestamp", System.currentTimeMillis());
        result.put("totalSatellites", status.getSatelliteCount());
        result.put("constellations", constellations);
        result.put("systemStats", systemStats);
        result.put("satellites", satellites);
        result.put("navicSatellites", navicSatellites);
        result.put("isNavicAvailable", (irnssCount > 0));
        result.put("navicSatellitesCount", irnssCount);
        result.put("navicUsedInFix", irnssUsedInFix);
        result.put("navicAverageSignal", irnssAvgSignal);
        result.put("l5SatelliteCount", l5SatelliteCount);
        result.put("hasL5BandActive", l5SatelliteCount > 0);
        result.put("primarySystem", primarySystem);
        result.put("hasL5Band", hasL5BandSupport);
        result.put("usingExternalGnss", usingExternalGnss);
        result.put("externalGnssInfo", externalGnssInfo);
        result.put("locationProvider", primarySystem + (l5SatelliteCount > 0 ? "_L5" : ""));

        Log.d("NavIC", String.format(
                "📡 Update - Primary: %s, NavIC: %d(%d), GPS: %d(%d), Total: %d, L5: %d, External: %s",
                primarySystem, irnssCount, irnssUsedInFix, gpsCount, gpsUsedInFix,
                status.getSatelliteCount(), l5SatelliteCount, usingExternalGnss ? "Yes" : "No"
        ));

        return result;
    }

    private Map<String, Object> createEnhancedSystemStat(String name, String flag, int total, int used, float avgSignal) {
        Map<String, Object> stat = new HashMap<>();
        stat.put("name", name);
        stat.put("flag", flag);
        stat.put("total", total);
        stat.put("used", used);
        stat.put("available", total - used);
        stat.put("averageSignal", avgSignal);
        stat.put("utilization", total > 0 ? (used * 100.0 / total) : 0.0);
        return stat;
    }

    private String determinePrimarySystemFromCounts(int irnssUsed, int gpsUsed, int glonassUsed,
                                                    int galileoUsed, int beidouUsed) {
        if (irnssUsed >= 4) return "NAVIC";
        if (gpsUsed >= 4) return "GPS";
        if (glonassUsed >= 4) return "GLONASS";
        if (galileoUsed >= 4) return "GALILEO";
        if (beidouUsed >= 4) return "BEIDOU";

        int maxUsed = Math.max(Math.max(Math.max(irnssUsed, gpsUsed), Math.max(glonassUsed, galileoUsed)), beidouUsed);

        if (maxUsed == 0) return "NO_FIX";

        if (maxUsed == irnssUsed && irnssUsed > 0) return "NAVIC_HYBRID";
        if (maxUsed == gpsUsed) return "GPS_HYBRID";
        if (maxUsed == glonassUsed) return "GLONASS_HYBRID";
        if (maxUsed == galileoUsed) return "GALILEO_HYBRID";

        return "MULTI_GNSS";
    }

    private void stopRealTimeDetection(MethodChannel.Result result) {
        Log.d("NavIC", "Stopping real-time detection");
        try {
            if (realtimeCallback != null) {
                locationManager.unregisterGnssStatusCallback(realtimeCallback);
                realtimeCallback = null;
                Log.d("NavIC", "Real-time detection stopped");
            }
        } catch (Exception e) {
            Log.e("NavIC", "Error stopping real-time detection", e);
        }

        if (result != null) {
            Map<String, Object> resp = new HashMap<>();
            resp.put("success", true);
            resp.put("message", "Real-time detection stopped");
            result.success(resp);
        }
    }

    private void stopRealTimeDetection() {
        stopRealTimeDetection(null);
    }

    // =============== HELPER METHODS ===============

    private long getLatestSatelliteTime() {
        long latestTime = 0;
        for (EnhancedSatellite sat : detectedSatellites.values()) {
            if (sat.detectionTime > latestTime) {
                latestTime = sat.detectionTime;
            }
        }
        return latestTime;
    }

    private void cleanupCallback(GnssStatus.Callback callback) {
        try {
            if (callback != null) {
                locationManager.unregisterGnssStatusCallback(callback);
            }
        } catch (Exception e) {
            // Ignore cleanup errors
        }
    }

    private String getEnhancedConstellationName(int constellation) {
        switch (constellation) {
            case GnssStatus.CONSTELLATION_IRNSS: return "IRNSS";
            case GnssStatus.CONSTELLATION_GPS: return "GPS";
            case GnssStatus.CONSTELLATION_GLONASS: return "GLONASS";
            case GnssStatus.CONSTELLATION_GALILEO: return "GALILEO";
            case GnssStatus.CONSTELLATION_BEIDOU: return "BEIDOU";
            case GnssStatus.CONSTELLATION_QZSS: return "QZSS";
            case GnssStatus.CONSTELLATION_SBAS: return "SBAS";
            case GnssStatus.CONSTELLATION_UNKNOWN: return "UNKNOWN";
            default: return "UNKNOWN_" + constellation;
        }
    }

    private String determineFrequencyBandFromHz(double frequencyHz) {
        double freqMHz = frequencyHz / 1e6;

        if (Math.abs(freqMHz - 1176.45) <= 2.0) return "L5";
        if (Math.abs(freqMHz - 1575.42) <= 2.0) return "L1";
        if (Math.abs(freqMHz - 1227.60) <= 2.0) return "L2";
        if (Math.abs(freqMHz - 2492.028) <= 2.0) return "S";
        if (Math.abs(freqMHz - 1602.0) <= 2.0) return "G1";
        if (Math.abs(freqMHz - 1246.0) <= 2.0) return "G2";
        if (Math.abs(freqMHz - 1207.14) <= 2.0) return "E5";
        if (Math.abs(freqMHz - 1268.52) <= 2.0) return "B3";

        return String.format("%.0f MHz", freqMHz);
    }

    private String getDefaultBandForConstellation(int constellation, boolean hasL5Support) {
        switch (constellation) {
            case GnssStatus.CONSTELLATION_IRNSS:
                return hasL5Support ? "L5/S" : "L5";
            case GnssStatus.CONSTELLATION_GPS:
                return hasL5Support ? "L1/L5" : "L1";
            case GnssStatus.CONSTELLATION_GALILEO:
                return hasL5Support ? "E1/E5a" : "E1";
            case GnssStatus.CONSTELLATION_BEIDOU:
                return hasL5Support ? "B1/B2a" : "B1";
            case GnssStatus.CONSTELLATION_GLONASS:
                return "G1";
            case GnssStatus.CONSTELLATION_QZSS:
                return hasL5Support ? "L1/L5" : "L1";
            default:
                return "L1";
        }
    }

    // =============== SATELLITE ANALYSIS METHODS ===============

    private void getCompleteSatelliteSummary(MethodChannel.Result result) {
        Log.d("NavIC", "📊 Getting complete satellite summary");

        if (!hasLocationPermissions()) {
            result.error("PERMISSION_DENIED", "Location permissions required", null);
            return;
        }

        try {
            Map<String, Object> summary = new HashMap<>();
            summary.put("timestamp", System.currentTimeMillis());
            summary.put("totalSatellites", detectedSatellites.size());
            summary.put("hasL5Band", hasL5BandSupport);
            summary.put("hasL5BandActive", hasL5BandActive);
            summary.put("primarySystem", primaryPositioningSystem);
            summary.put("usingExternalGnss", usingExternalGnss);
            summary.put("externalGnssInfo", externalGnssInfo);

            Map<String, Integer> systemCounts = new HashMap<>();
            Map<String, Integer> systemUsedCounts = new HashMap<>();
            Map<String, Integer> l5SatellitesBySystem = new HashMap<>();

            for (EnhancedSatellite sat : detectedSatellites.values()) {
                String system = sat.systemName;
                systemCounts.put(system, systemCounts.getOrDefault(system, 0) + 1);
                if (sat.usedInFix) {
                    systemUsedCounts.put(system, systemUsedCounts.getOrDefault(system, 0) + 1);
                }
                if (sat.frequencyBand != null && sat.frequencyBand.contains("L5")) {
                    l5SatellitesBySystem.put(system, l5SatellitesBySystem.getOrDefault(system, 0) + 1);
                }
            }

            summary.put("systemCounts", systemCounts);
            summary.put("systemUsedCounts", systemUsedCounts);
            summary.put("l5SatellitesBySystem", l5SatellitesBySystem);
            summary.put("totalL5Satellites", l5SatellitesBySystem.values().stream().mapToInt(Integer::intValue).sum());

            result.success(summary);

        } catch (Exception e) {
            Log.e("NavIC", "Error getting complete satellite summary", e);
            result.error("SUMMARY_ERROR", "Failed to get satellite summary", null);
        }
    }

    private void getSatelliteNames(MethodChannel.Result result) {
        Log.d("NavIC", "📡 Getting satellite names");

        if (!hasLocationPermissions()) {
            result.error("PERMISSION_DENIED", "Location permissions required", null);
            return;
        }

        try {
            List<Map<String, Object>> satelliteNames = new ArrayList<>();

            for (EnhancedSatellite sat : detectedSatellites.values()) {
                Map<String, Object> nameInfo = new HashMap<>();
                nameInfo.put("svid", sat.svid);
                nameInfo.put("system", sat.systemName);
                nameInfo.put("name", getSatelliteName(sat.systemName, sat.svid));
                nameInfo.put("countryFlag", sat.countryFlag);
                nameInfo.put("frequencyBand", sat.frequencyBand);
                nameInfo.put("isL5Band", sat.frequencyBand != null && sat.frequencyBand.contains("L5"));
                satelliteNames.add(nameInfo);
            }

            Map<String, Object> response = new HashMap<>();
            response.put("satelliteNames", satelliteNames);
            response.put("timestamp", System.currentTimeMillis());
            response.put("hasL5Satellites", satelliteNames.stream().anyMatch(n -> (Boolean) n.get("isL5Band")));
            response.put("usingExternalGnss", usingExternalGnss);

            result.success(response);

        } catch (Exception e) {
            Log.e("NavIC", "Error getting satellite names", e);
            result.error("NAMES_ERROR", "Failed to get satellite names", null);
        }
    }

    private String getSatelliteName(String system, int svid) {
        if ("IRNSS".equals(system)) {
            return String.format("IRNSS-%02d", svid);
        }
        if ("GPS".equals(system)) {
            return String.format("GPS PRN-%02d", svid);
        }
        if ("GLONASS".equals(system)) {
            return String.format("GLONASS Slot-%02d", svid);
        }
        if ("GALILEO".equals(system)) {
            return String.format("Galileo E%02d", svid);
        }
        if ("BEIDOU".equals(system)) {
            return String.format("BeiDou C%02d", svid);
        }
        if ("QZSS".equals(system)) {
            return String.format("QZSS-%02d", svid);
        }
        return String.format("%s-%02d", system, svid);
    }

    private void getConstellationDetails(MethodChannel.Result result) {
        Log.d("NavIC", "🌌 Getting constellation details");

        if (!hasLocationPermissions()) {
            result.error("PERMISSION_DENIED", "Location permissions required", null);
            return;
        }

        try {
            Map<String, Object> constellationDetails = new HashMap<>();

            for (Map.Entry<String, List<EnhancedSatellite>> entry : satellitesBySystem.entrySet()) {
                String system = entry.getKey();
                List<EnhancedSatellite> satellites = entry.getValue();

                Map<String, Object> systemDetails = new HashMap<>();
                systemDetails.put("countryFlag", GNSS_COUNTRIES.getOrDefault(system, "🌐"));
                systemDetails.put("satelliteCount", satellites.size());

                int usedCount = 0;
                float totalSignal = 0;
                int signalCount = 0;
                int l5Count = 0;

                for (EnhancedSatellite sat : satellites) {
                    if (sat.usedInFix) usedCount++;
                    if (sat.cn0 > 0) {
                        totalSignal += sat.cn0;
                        signalCount++;
                    }
                    if (sat.frequencyBand != null && sat.frequencyBand.contains("L5")) {
                        l5Count++;
                    }
                }

                systemDetails.put("usedCount", usedCount);
                systemDetails.put("averageSignal", signalCount > 0 ? totalSignal / signalCount : 0);
                systemDetails.put("l5SatelliteCount", l5Count);
                systemDetails.put("frequencies", GNSS_FREQUENCIES.getOrDefault(system, new Double[]{0.0}));

                constellationDetails.put(system, systemDetails);
            }

            Map<String, Object> response = new HashMap<>();
            response.put("constellationDetails", constellationDetails);
            response.put("timestamp", System.currentTimeMillis());
            response.put("hasL5BandActive", hasL5BandActive);
            response.put("usingExternalGnss", usingExternalGnss);

            result.success(response);

        } catch (Exception e) {
            Log.e("NavIC", "Error getting constellation details", e);
            result.error("CONSTELLATION_ERROR", "Failed to get constellation details", null);
        }
    }

    private String getConstellationDescription(int constellation) {
        switch (constellation) {
            case GnssStatus.CONSTELLATION_IRNSS: return "Indian Regional Navigation Satellite System (NavIC)";
            case GnssStatus.CONSTELLATION_GPS: return "Global Positioning System (USA)";
            case GnssStatus.CONSTELLATION_GLONASS: return "Global Navigation Satellite System (Russia)";
            case GnssStatus.CONSTELLATION_GALILEO: return "European Global Navigation Satellite System";
            case GnssStatus.CONSTELLATION_BEIDOU: return "BeiDou Navigation Satellite System (China)";
            case GnssStatus.CONSTELLATION_QZSS: return "Quasi-Zenith Satellite System (Japan)";
            case GnssStatus.CONSTELLATION_SBAS: return "Satellite-Based Augmentation System";
            default: return "Unknown Navigation System";
        }
    }

    private String getFrequencyDescription(String band) {
        switch (band) {
            case "L1": return "Primary GNSS frequency (1575.42 MHz)";
            case "L2": return "Secondary GNSS frequency (1227.60 MHz)";
            case "L5": return "Enhanced safety-of-life frequency (1176.45 MHz) - High Accuracy";
            case "E1": return "Galileo primary frequency";
            case "E5": return "Galileo enhanced frequency";
            case "E5a": return "Galileo L5-equivalent frequency (1176.45 MHz)";
            case "B1": return "BeiDou primary frequency";
            case "B2": return "BeiDou secondary frequency";
            case "B2a": return "BeiDou L5-equivalent frequency (1176.45 MHz)";
            case "G1": return "GLONASS primary frequency";
            case "G2": return "GLONASS secondary frequency";
            case "S": return "NavIC S-band (2492.028 MHz)";
            default: return "Unknown frequency band";
        }
    }

    private void getSignalStrengthAnalysis(MethodChannel.Result result) {
        Log.d("NavIC", "📶 Getting signal strength analysis");

        if (!hasLocationPermissions()) {
            result.error("PERMISSION_DENIED", "Location permissions required", null);
            return;
        }

        try {
            Map<String, Object> analysis = new HashMap<>();

            Map<String, Integer> strengthDistribution = new HashMap<>();
            strengthDistribution.put("EXCELLENT", 0);
            strengthDistribution.put("GOOD", 0);
            strengthDistribution.put("FAIR", 0);
            strengthDistribution.put("WEAK", 0);
            strengthDistribution.put("POOR", 0);

            float totalSignal = 0;
            int signalCount = 0;
            int l5SignalCount = 0;
            float l5TotalSignal = 0;

            for (EnhancedSatellite sat : detectedSatellites.values()) {
                String strengthLevel = sat.getSignalStrengthLevel();
                strengthDistribution.put(strengthLevel, strengthDistribution.get(strengthLevel) + 1);

                if (sat.cn0 > 0) {
                    totalSignal += sat.cn0;
                    signalCount++;

                    if (sat.frequencyBand != null && sat.frequencyBand.contains("L5")) {
                        l5TotalSignal += sat.cn0;
                        l5SignalCount++;
                    }
                }
            }

            analysis.put("strengthDistribution", strengthDistribution);
            analysis.put("averageSignal", signalCount > 0 ? totalSignal / signalCount : 0);
            analysis.put("signalCount", signalCount);
            analysis.put("l5SignalCount", l5SignalCount);
            analysis.put("l5AverageSignal", l5SignalCount > 0 ? l5TotalSignal / l5SignalCount : 0);
            analysis.put("timestamp", System.currentTimeMillis());
            analysis.put("usingExternalGnss", usingExternalGnss);

            result.success(analysis);

        } catch (Exception e) {
            Log.e("NavIC", "Error getting signal strength analysis", e);
            result.error("SIGNAL_ANALYSIS_ERROR", "Failed to get signal strength analysis", null);
        }
    }

    private void getElevationAzimuthData(MethodChannel.Result result) {
        Log.d("NavIC", "🎯 Getting elevation and azimuth data");

        if (!hasLocationPermissions()) {
            result.error("PERMISSION_DENIED", "Location permissions required", null);
            return;
        }

        try {
            List<Map<String, Object>> positionData = new ArrayList<>();

            for (EnhancedSatellite sat : detectedSatellites.values()) {
                Map<String, Object> data = new HashMap<>();
                data.put("svid", sat.svid);
                data.put("system", sat.systemName);
                data.put("elevation", sat.elevation);
                data.put("azimuth", sat.azimuth);
                data.put("signalStrength", sat.cn0);
                data.put("usedInFix", sat.usedInFix);
                data.put("frequencyBand", sat.frequencyBand);
                data.put("isL5Band", sat.frequencyBand != null && sat.frequencyBand.contains("L5"));
                positionData.add(data);
            }

            Map<String, Object> response = new HashMap<>();
            response.put("positionData", positionData);
            response.put("timestamp", System.currentTimeMillis());
            response.put("usingExternalGnss", usingExternalGnss);

            result.success(response);

        } catch (Exception e) {
            Log.e("NavIC", "Error getting elevation/azimuth data", e);
            result.error("POSITION_DATA_ERROR", "Failed to get elevation/azimuth data", null);
        }
    }

    private String getPositioningRole(boolean usedInFix, float cn0) {
        if (usedInFix && cn0 > 25) return "PRIMARY_POSITIONING";
        if (usedInFix) return "POSITIONING";
        if (cn0 > 20) return "SIGNAL_AVAILABLE";
        if (cn0 > 10) return "WEAK_SIGNAL";
        return "NOT_USED";
    }

    private String getHealthStatus(float cn0, boolean hasEphemeris, boolean hasAlmanac) {
        if (cn0 <= 0) return "NO_SIGNAL";
        if (cn0 < 10) return "VERY_WEAK";
        if (cn0 < 18) return "WEAK";
        if (!hasEphemeris) return "NO_EPHEMERIS";
        if (!hasAlmanac) return "NO_ALMANAC";
        if (cn0 >= 25) return "EXCELLENT";
        if (cn0 >= 18) return "GOOD";
        return "FAIR";
    }

    private void getCarrierFrequencyInfo(MethodChannel.Result result) {
        Log.d("NavIC", "📻 Getting carrier frequency information");

        if (!hasLocationPermissions()) {
            result.error("PERMISSION_DENIED", "Location permissions required", null);
            return;
        }

        try {
            List<Map<String, Object>> frequencyData = new ArrayList<>();

            for (EnhancedSatellite sat : detectedSatellites.values()) {
                Map<String, Object> data = new HashMap<>();
                data.put("svid", sat.svid);
                data.put("system", sat.systemName);
                data.put("frequencyBand", sat.frequencyBand);
                data.put("carrierFrequencyHz", sat.carrierFrequency > 0 ? sat.carrierFrequency : null);
                data.put("signalStrength", sat.cn0);
                data.put("isL5Band", sat.frequencyBand != null && sat.frequencyBand.contains("L5"));
                frequencyData.add(data);
            }

            Map<String, Object> response = new HashMap<>();
            response.put("frequencyData", frequencyData);
            response.put("hasL5Band", hasL5BandSupport);
            response.put("hasL5BandActive", hasL5BandActive);
            response.put("timestamp", System.currentTimeMillis());
            response.put("usingExternalGnss", usingExternalGnss);

            result.success(response);

        } catch (Exception e) {
            Log.e("NavIC", "Error getting carrier frequency info", e);
            result.error("FREQUENCY_ERROR", "Failed to get carrier frequency info", null);
        }
    }

    private void getEphemerisAlmanacStatus(MethodChannel.Result result) {
        Log.d("NavIC", "📡 Getting ephemeris and almanac status");

        if (!hasLocationPermissions()) {
            result.error("PERMISSION_DENIED", "Location permissions required", null);
            return;
        }

        try {
            Map<String, Object> status = new HashMap<>();

            int hasEphemerisCount = 0;
            int hasAlmanacCount = 0;
            int l5EphemerisCount = 0;
            int l5AlmanacCount = 0;

            for (EnhancedSatellite sat : detectedSatellites.values()) {
                if (sat.hasEphemeris) hasEphemerisCount++;
                if (sat.hasAlmanac) hasAlmanacCount++;

                if (sat.frequencyBand != null && sat.frequencyBand.contains("L5")) {
                    if (sat.hasEphemeris) l5EphemerisCount++;
                    if (sat.hasAlmanac) l5AlmanacCount++;
                }
            }

            status.put("totalSatellites", detectedSatellites.size());
            status.put("hasEphemerisCount", hasEphemerisCount);
            status.put("hasAlmanacCount", hasAlmanacCount);
            status.put("l5EphemerisCount", l5EphemerisCount);
            status.put("l5AlmanacCount", l5AlmanacCount);
            status.put("ephemerisPercentage", detectedSatellites.size() > 0 ?
                    (hasEphemerisCount * 100.0 / detectedSatellites.size()) : 0);
            status.put("almanacPercentage", detectedSatellites.size() > 0 ?
                    (hasAlmanacCount * 100.0 / detectedSatellites.size()) : 0);
            status.put("timestamp", System.currentTimeMillis());
            status.put("usingExternalGnss", usingExternalGnss);

            result.success(status);

        } catch (Exception e) {
            Log.e("NavIC", "Error getting ephemeris/almanac status", e);
            result.error("EPHEMERIS_ERROR", "Failed to get ephemeris/almanac status", null);
        }
    }

    private void getSatelliteDetectionHistory(MethodChannel.Result result) {
        Log.d("NavIC", "📈 Getting satellite detection history");

        if (!hasLocationPermissions()) {
            result.error("PERMISSION_DENIED", "Location permissions required", null);
            return;
        }

        try {
            List<Map<String, Object>> detectionHistory = new ArrayList<>();

            for (EnhancedSatellite sat : detectedSatellites.values()) {
                Map<String, Object> history = new HashMap<>();
                history.put("svid", sat.svid);
                history.put("system", sat.systemName);
                history.put("detectionCount", sat.detectionCount);
                history.put("firstDetectionTime", sat.detectionTime);
                history.put("lastDetectionTime", System.currentTimeMillis());
                history.put("averageSignal", sat.cn0);
                history.put("frequencyBand", sat.frequencyBand);
                history.put("isL5Band", sat.frequencyBand != null && sat.frequencyBand.contains("L5"));
                detectionHistory.add(history);
            }

            Map<String, Object> response = new HashMap<>();
            response.put("detectionHistory", detectionHistory);
            response.put("timestamp", System.currentTimeMillis());
            response.put("usingExternalGnss", usingExternalGnss);

            result.success(response);

        } catch (Exception e) {
            Log.e("NavIC", "Error getting detection history", e);
            result.error("HISTORY_ERROR", "Failed to get detection history", null);
        }
    }

    private void getGnssDiversityReport(MethodChannel.Result result) {
        Log.d("NavIC", "🌐 Getting GNSS diversity report");

        if (!hasLocationPermissions()) {
            result.error("PERMISSION_DENIED", "Location permissions required", null);
            return;
        }

        try {
            Map<String, Object> diversityReport = new HashMap<>();

            int totalSystems = satellitesBySystem.size();
            int totalSatellites = detectedSatellites.size();

            diversityReport.put("totalSystems", totalSystems);
            diversityReport.put("totalSatellites", totalSatellites);
            diversityReport.put("systemsDetected", new ArrayList<>(satellitesBySystem.keySet()));

            double diversityScore = 0.0;
            if (totalSystems > 0 && totalSatellites > 0) {
                diversityScore = (totalSystems * 100.0) / 7.0;
            }

            diversityReport.put("diversityScore", diversityScore);
            diversityReport.put("diversityLevel", getDiversityLevel(diversityScore));
            diversityReport.put("hasL5Band", hasL5BandSupport);
            diversityReport.put("hasL5BandActive", hasL5BandActive);
            diversityReport.put("primarySystem", primaryPositioningSystem);
            diversityReport.put("usingExternalGnss", usingExternalGnss);
            diversityReport.put("timestamp", System.currentTimeMillis());

            result.success(diversityReport);

        } catch (Exception e) {
            Log.e("NavIC", "Error getting GNSS diversity report", e);
            result.error("DIVERSITY_ERROR", "Failed to get GNSS diversity report", null);
        }
    }

    private String getDiversityLevel(double score) {
        if (score >= 80) return "EXCELLENT";
        if (score >= 60) return "GOOD";
        if (score >= 40) return "FAIR";
        if (score >= 20) return "WEAK";
        return "POOR";
    }

    private void getRealTimeSatelliteStream(MethodChannel.Result result) {
        Log.d("NavIC", "🔴 Getting real-time satellite stream");

        if (!hasLocationPermissions()) {
            result.error("PERMISSION_DENIED", "Location permissions required", null);
            return;
        }

        try {
            if (realtimeCallback == null) {
                startRealTimeNavicDetection(result);
                return;
            }

            Map<String, Object> response = new HashMap<>();
            response.put("status", "REALTIME_STREAM_ACTIVE");
            response.put("message", "Real-time satellite stream is active");
            response.put("hasL5Band", hasL5BandSupport);
            response.put("hasL5BandActive", hasL5BandActive);
            response.put("usingExternalGnss", usingExternalGnss);
            response.put("externalGnssInfo", externalGnssInfo);
            response.put("timestamp", System.currentTimeMillis());

            result.success(response);

        } catch (Exception e) {
            Log.e("NavIC", "Error getting real-time satellite stream", e);
            result.error("STREAM_ERROR", "Failed to get real-time satellite stream", null);
        }
    }

    private void getSatelliteSignalQuality(MethodChannel.Result result) {
        Log.d("NavIC", "📊 Getting satellite signal quality");

        if (!hasLocationPermissions()) {
            result.error("PERMISSION_DENIED", "Location permissions required", null);
            return;
        }

        try {
            Map<String, Object> signalQuality = new HashMap<>();

            float totalSignal = 0;
            int signalCount = 0;
            int excellentCount = 0;
            int goodCount = 0;
            int fairCount = 0;
            int weakCount = 0;
            int poorCount = 0;

            float l5TotalSignal = 0;
            int l5SignalCount = 0;
            int l5ExcellentCount = 0;
            int l5GoodCount = 0;
            int l5FairCount = 0;

            for (EnhancedSatellite sat : detectedSatellites.values()) {
                if (sat.cn0 > 0) {
                    totalSignal += sat.cn0;
                    signalCount++;

                    String strength = sat.getSignalStrengthLevel();
                    switch (strength) {
                        case "EXCELLENT": excellentCount++; break;
                        case "GOOD": goodCount++; break;
                        case "FAIR": fairCount++; break;
                        case "WEAK": weakCount++; break;
                        case "POOR": poorCount++; break;
                    }

                    if (sat.frequencyBand != null && sat.frequencyBand.contains("L5")) {
                        l5TotalSignal += sat.cn0;
                        l5SignalCount++;
                        switch (strength) {
                            case "EXCELLENT": l5ExcellentCount++; break;
                            case "GOOD": l5GoodCount++; break;
                            case "FAIR": l5FairCount++; break;
                        }
                    }
                }
            }

            signalQuality.put("totalSatellites", detectedSatellites.size());
            signalQuality.put("satellitesWithSignal", signalCount);
            signalQuality.put("averageSignal", signalCount > 0 ? totalSignal / signalCount : 0);
            signalQuality.put("excellentCount", excellentCount);
            signalQuality.put("goodCount", goodCount);
            signalQuality.put("fairCount", fairCount);
            signalQuality.put("weakCount", weakCount);
            signalQuality.put("poorCount", poorCount);
            signalQuality.put("qualityScore", calculateQualityScore(excellentCount, goodCount, fairCount,
                    weakCount, poorCount, signalCount));

            signalQuality.put("l5SatellitesWithSignal", l5SignalCount);
            signalQuality.put("l5AverageSignal", l5SignalCount > 0 ? l5TotalSignal / l5SignalCount : 0);
            signalQuality.put("l5ExcellentCount", l5ExcellentCount);
            signalQuality.put("l5GoodCount", l5GoodCount);
            signalQuality.put("l5FairCount", l5FairCount);
            signalQuality.put("l5QualityScore", l5SignalCount > 0 ?
                    calculateQualityScore(l5ExcellentCount, l5GoodCount, l5FairCount, 0, 0, l5SignalCount) : 0);

            signalQuality.put("timestamp", System.currentTimeMillis());
            signalQuality.put("usingExternalGnss", usingExternalGnss);

            result.success(signalQuality);

        } catch (Exception e) {
            Log.e("NavIC", "Error getting satellite signal quality", e);
            result.error("QUALITY_ERROR", "Failed to get satellite signal quality", null);
        }
    }

    private double calculateQualityScore(int excellent, int good, int fair, int weak, int poor, int total) {
        if (total == 0) return 0;

        double score = (excellent * 100 + good * 80 + fair * 60 + weak * 40 + poor * 20) / (double) total;
        return Math.min(100, score);
    }

    @Override
    protected void onDestroy() {
        Log.d("NavIC", "Activity destroying, cleaning up resources");
        try {
            stopRealTimeDetection();
            stopLocationUpdates();
            stopSatelliteMonitoring(null);
            disconnectUsbGnss(null);

            if (usbPermissionReceiver != null) {
                unregisterReceiver(usbPermissionReceiver);
            }
        } catch (Exception e) {
            Log.e("NavIC", "Error in onDestroy", e);
        }
        super.onDestroy();
    }

    // =============== INNER CLASSES ===============

    private static class EnhancedSatellite {
        int svid;
        String systemName;
        int constellation;
        String countryFlag;
        float cn0;
        boolean usedInFix;
        float elevation;
        float azimuth;
        boolean hasEphemeris;
        boolean hasAlmanac;
        String frequencyBand;
        double carrierFrequency;
        long detectionTime;
        int detectionCount;
        boolean externalGnss;

        EnhancedSatellite(int svid, String systemName, int constellation, String countryFlag,
                          float cn0, boolean usedInFix, float elevation, float azimuth,
                          boolean hasEphemeris, boolean hasAlmanac, String frequencyBand,
                          double carrierFrequency, long detectionTime, boolean externalGnss) {
            this.svid = svid;
            this.systemName = systemName;
            this.constellation = constellation;
            this.countryFlag = countryFlag;
            this.cn0 = cn0;
            this.usedInFix = usedInFix;
            this.elevation = elevation;
            this.azimuth = azimuth;
            this.hasEphemeris = hasEphemeris;
            this.hasAlmanac = hasAlmanac;
            this.frequencyBand = frequencyBand;
            this.carrierFrequency = carrierFrequency;
            this.detectionTime = detectionTime;
            this.detectionCount = 1;
            this.externalGnss = externalGnss;
        }

        Map<String, Object> toEnhancedMap() {
            Map<String, Object> map = new HashMap<>();
            map.put("svid", svid);
            map.put("system", systemName);
            map.put("constellation", constellation);
            map.put("countryFlag", countryFlag);
            map.put("cn0DbHz", cn0);
            map.put("usedInFix", usedInFix);
            map.put("elevation", elevation);
            map.put("azimuth", azimuth);
            map.put("hasEphemeris", hasEphemeris);
            map.put("hasAlmanac", hasAlmanac);
            map.put("frequencyBand", frequencyBand);
            map.put("carrierFrequencyHz", carrierFrequency > 0 ? carrierFrequency : null);
            map.put("detectionTime", detectionTime);
            map.put("detectionCount", detectionCount);
            map.put("signalStrength", getSignalStrengthLevel());
            map.put("isL5Band", frequencyBand != null && frequencyBand.contains("L5"));
            map.put("timestamp", System.currentTimeMillis());
            map.put("externalGnss", externalGnss);
            return map;
        }

        String getSignalStrengthLevel() {
            if (cn0 >= 35) return "EXCELLENT";
            if (cn0 >= 25) return "GOOD";
            if (cn0 >= 18) return "FAIR";
            if (cn0 >= 10) return "WEAK";
            return "POOR";
        }
    }

    private static class EnhancedSatelliteScanResult {
        int navicCount;
        int navicUsedInFix;
        int totalSatellites;
        float navicSignalStrength;
        List<Map<String, Object>> navicDetails;
        Map<String, EnhancedSatellite> allSatellites;
        Map<String, List<EnhancedSatellite>> satellitesBySystem;
        List<Map<String, Object>> allSatellitesList;
        boolean externalGnss;

        EnhancedSatelliteScanResult(int navicCount, int navicUsedInFix, int totalSatellites,
                                    float navicSignalStrength, List<Map<String, Object>> navicDetails,
                                    Map<String, EnhancedSatellite> allSatellites,
                                    Map<String, List<EnhancedSatellite>> satellitesBySystem,
                                    List<Map<String, Object>> allSatellitesList,
                                    boolean externalGnss) {
            this.navicCount = navicCount;
            this.navicUsedInFix = navicUsedInFix;
            this.totalSatellites = totalSatellites;
            this.navicSignalStrength = navicSignalStrength;
            this.navicDetails = navicDetails;
            this.allSatellites = allSatellites;
            this.satellitesBySystem = satellitesBySystem;
            this.allSatellitesList = allSatellitesList;
            this.externalGnss = externalGnss;
        }
    }
}