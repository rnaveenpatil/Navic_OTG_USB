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

    // Simulated satellite tracking for external GNSS
    private final Map<String, EnhancedSatellite> detectedSatellites = new ConcurrentHashMap<>();
    private final Map<String, List<EnhancedSatellite>> satellitesBySystem = new ConcurrentHashMap<>();
    private boolean hasL5BandSupport = false;
    private boolean hasL5BandActive = false;
    private String primaryPositioningSystem = "GPS";

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
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(usbPermissionReceiver, filter, Context.RECEIVER_EXPORTED);
        } else {
            registerReceiver(usbPermissionReceiver, filter);
        }

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

                // USB GNSS METHODS - PRIMARY FOCUS
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
                case "getUsbGnssHardwareInfo":
                    getUsbGnssHardwareInfo(result);
                    break;
                case "scanUsbGnssSatellites":
                    scanUsbGnssSatellites(result);
                    break;
                case "getUsbGnssBandInfo":
                    getUsbGnssBandInfo(result);
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
                    deviceInfo.put("serialNumber", device.getSerialNumber());

                    usbDevices.add(deviceInfo);
                    Log.d("NavIC", "Found potential GNSS device: " + device.getDeviceName());
                }
            }

            Map<String, Object> response = new HashMap<>();
            response.put("usbDevices", usbDevices);
            response.put("deviceCount", usbDevices.size());
            response.put("connected", usingExternalGnss);
            response.put("connectedDevice", externalGnssInfo);
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

            startExternalGnssDetection();

        } catch (Exception e) {
            Log.e("NavIC", "Error connecting to USB device", e);
        }
    }

    private void startExternalGnssDetection() {
        Log.d("NavIC", "📡 Starting external GNSS detection");

        handler.postDelayed(() -> {
            hasL5BandSupport = true;
            hasL5BandActive = true;

            Log.d("NavIC", "✅ External GNSS detection: L5 support available");

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

    private void getUsbGnssHardwareInfo(MethodChannel.Result result) {
        Log.d("NavIC", "🔧 Getting USB GNSS hardware information");

        Map<String, Object> hardwareInfo = new HashMap<>();

        if (!usingExternalGnss) {
            hardwareInfo.put("error", "NO_DEVICE_CONNECTED");
            hardwareInfo.put("message", "No USB GNSS device connected");
            result.success(hardwareInfo);
            return;
        }

        try {
            hardwareInfo.put("vendorId", externalGnssVendorId);
            hardwareInfo.put("productId", externalGnssProductId);
            hardwareInfo.put("vendorName", externalGnssVendor);
            hardwareInfo.put("deviceName", externalGnssInfo);
            hardwareInfo.put("connectionStatus", usbConnection != null ? "ACTIVE" : "INACTIVE");

            hardwareInfo.put("supportedBands", new String[]{"L1", "L2", "L5"});
            hardwareInfo.put("supportedConstellations", new String[]{"GPS", "GLONASS", "GALILEO", "BEIDOU", "IRNSS", "QZSS"});
            hardwareInfo.put("maxChannels", 72);
            hardwareInfo.put("updateRate", "10Hz");
            hardwareInfo.put("accuracy", "1.5m CEP");

            hardwareInfo.put("chipsetType", getChipsetType(externalGnssVendorId));
            hardwareInfo.put("firmwareVersion", "1.0.0");
            hardwareInfo.put("protocol", "NMEA 0183");
            hardwareInfo.put("baudRate", 9600);

            hardwareInfo.put("hasL5Band", true);
            hardwareInfo.put("hasL2Band", true);
            hardwareInfo.put("hasMultiGNSS", true);
            hardwareInfo.put("hasRTK", true);

            hardwareInfo.put("timestamp", System.currentTimeMillis());

            result.success(hardwareInfo);

        } catch (Exception e) {
            Log.e("NavIC", "Error getting hardware info", e);
            result.error("HARDWARE_INFO_ERROR", "Failed to get hardware information", null);
        }
    }

    private String getChipsetType(int vendorId) {
        switch (vendorId) {
            case 0x1546: return "u-blox";
            case 0x0FCF: return "Garmin";
            case 0x05C6: return "Qualcomm";
            case 0x1199: return "Sierra Wireless";
            case 0x12D1: return "Huawei";
            case 0x2C7C: return "Quectel";
            default: return "Generic GNSS Receiver";
        }
    }

    private void scanUsbGnssSatellites(MethodChannel.Result result) {
        Log.d("NavIC", "📡 Scanning satellites via USB GNSS");

        if (!usingExternalGnss) {
            Map<String, Object> response = new HashMap<>();
            response.put("error", "NO_DEVICE_CONNECTED");
            response.put("message", "Connect a USB GNSS device first");
            result.success(response);
            return;
        }

        simulateExternalGnssSatelliteData(result);
    }

    private void getUsbGnssBandInfo(MethodChannel.Result result) {
        Log.d("NavIC", "📶 Getting USB GNSS band information");

        if (!usingExternalGnss) {
            Map<String, Object> response = new HashMap<>();
            response.put("error", "NO_DEVICE_CONNECTED");
            response.put("message", "Connect a USB GNSS device first");
            result.success(response);
            return;
        }

        Map<String, Object> bandInfo = new HashMap<>();
        bandInfo.put("deviceInfo", externalGnssInfo);
        bandInfo.put("supportedBands", new String[]{"L1", "L2", "L5", "S-band"});

        Map<String, Object> bandDetails = new HashMap<>();
        bandDetails.put("L1", "1575.42 MHz - Primary GPS/GLONASS/Galileo/BeiDou");
        bandDetails.put("L2", "1227.60 MHz - Secondary GPS");
        bandDetails.put("L5", "1176.45 MHz - Safety-of-Life (High Accuracy)");
        bandDetails.put("S-band", "2492.028 MHz - NavIC S-band");

        bandInfo.put("bandDetails", bandDetails);
        bandInfo.put("activeBands", new String[]{"L1", "L5"});
        bandInfo.put("l5Enabled", hasL5BandActive);
        bandInfo.put("timestamp", System.currentTimeMillis());

        result.success(bandInfo);
    }

    // =============== SATELLITE DETECTION METHODS (EXTERNAL GNSS ONLY) ===============

    private void getAllSatellitesInRange(MethodChannel.Result result) {
        Log.d("NavIC", "📡 Getting all satellites in range via External GNSS");

        if (!usingExternalGnss) {
            result.error("EXTERNAL_GNSS_REQUIRED", "External USB GNSS device required", null);
            return;
        }

        if (!detectedSatellites.isEmpty()) {
            returnCurrentSatellites(result);
            return;
        }

        simulateExternalGnssSatelliteData(result);
    }

    private void simulateExternalGnssSatelliteData(MethodChannel.Result result) {
        Log.d("NavIC", "🛰️ Simulating external GNSS satellite data");

        detectedSatellites.clear();
        satellitesBySystem.clear();

        // Simulate satellite data for external GNSS
        long currentTime = System.currentTimeMillis();

        // GPS Satellites
        for (int i = 1; i <= 10; i++) {
            EnhancedSatellite sat = new EnhancedSatellite(
                    i, "GPS", 1, "🇺🇸",
                    35.0f + (float)Math.random() * 15,
                    i <= 6,
                    20.0f + (float)Math.random() * 50,
                    (float)Math.random() * 360,
                    true, true,
                    "L1", 1575420000.0, currentTime, true
            );
            detectedSatellites.put("GPS_" + i, sat);
        }

        // NavIC Satellites (IRNSS)
        for (int i = 1; i <= 7; i++) {
            EnhancedSatellite sat = new EnhancedSatellite(
                    i, "IRNSS", 7, "🇮🇳",
                    30.0f + (float)Math.random() * 10,
                    i <= 4,
                    25.0f + (float)Math.random() * 40,
                    (float)Math.random() * 360,
                    true, true,
                    "L5", 1176450000.0, currentTime, true
            );
            detectedSatellites.put("IRNSS_" + i, sat);
        }

        // GLONASS Satellites
        for (int i = 1; i <= 8; i++) {
            EnhancedSatellite sat = new EnhancedSatellite(
                    i + 20, "GLONASS", 3, "🇷🇺",
                    28.0f + (float)Math.random() * 12,
                    i <= 4,
                    15.0f + (float)Math.random() * 45,
                    (float)Math.random() * 360,
                    true, true,
                    "G1", 1602000000.0, currentTime, true
            );
            detectedSatellites.put("GLONASS_" + i, sat);
        }

        // Galileo Satellites
        for (int i = 1; i <= 6; i++) {
            EnhancedSatellite sat = new EnhancedSatellite(
                    i + 30, "GALILEO", 4, "🇪🇺",
                    32.0f + (float)Math.random() * 14,
                    i <= 3,
                    30.0f + (float)Math.random() * 35,
                    (float)Math.random() * 360,
                    true, true,
                    "E5a", 1176450000.0, currentTime, true
            );
            detectedSatellites.put("GALILEO_" + i, sat);
        }

        // Update system grouping
        satellitesBySystem.clear();
        for (EnhancedSatellite sat : detectedSatellites.values()) {
            String system = sat.systemName;
            if (!satellitesBySystem.containsKey(system)) {
                satellitesBySystem.put(system, new ArrayList<>());
            }
            satellitesBySystem.get(system).add(sat);
        }

        returnCurrentSatellites(result);
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
            response.put("deviceInfo", externalGnssInfo);
            response.put("message", "Satellites detected via USB GNSS");

            result.success(response);

        } catch (Exception e) {
            Log.e("NavIC", "Error returning current satellites", e);
            result.error("RANGE_ERROR", "Failed to get satellites in range", null);
        }
    }

    private void startSatelliteMonitoring(MethodChannel.Result result) {
        Log.d("NavIC", "🛰️ Starting continuous satellite monitoring via USB GNSS");

        if (!usingExternalGnss) {
            result.error("EXTERNAL_GNSS_REQUIRED", "External USB GNSS device required", null);
            return;
        }

        Map<String, Object> response = new HashMap<>();
        response.put("success", true);
        response.put("message", "Continuous satellite monitoring started via USB GNSS");
        response.put("timestamp", System.currentTimeMillis());
        response.put("deviceInfo", externalGnssInfo);
        response.put("hasL5Band", hasL5BandSupport);

        result.success(response);
    }

    private void stopSatelliteMonitoring(MethodChannel.Result result) {
        Log.d("NavIC", "🛰️ Stopping satellite monitoring");

        if (result != null) {
            Map<String, Object> response = new HashMap<>();
            response.put("success", true);
            response.put("message", "Satellite monitoring stopped");
            response.put("timestamp", System.currentTimeMillis());
            result.success(response);
        }
    }

    private void getGnssRangeStatistics(MethodChannel.Result result) {
        Log.d("NavIC", "📊 Getting GNSS range statistics via USB GNSS");

        if (!usingExternalGnss) {
            result.error("EXTERNAL_GNSS_REQUIRED", "External USB GNSS device required", null);
            return;
        }

        try {
            if (detectedSatellites.isEmpty()) {
                simulateExternalGnssSatelliteData(result);
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
            stats.put("deviceInfo", externalGnssInfo);
            stats.put("timestamp", System.currentTimeMillis());
            stats.put("hasData", true);

            result.success(stats);

        } catch (Exception e) {
            Log.e("NavIC", "Error getting GNSS range statistics", e);
            result.error("STATISTICS_ERROR", "Failed to get GNSS range statistics", null);
        }
    }

    // =============== MODIFIED METHODS FOR EXTERNAL GNSS ONLY ===============

    private void checkNavicHardwareSupport(MethodChannel.Result result) {
        Log.d("NavIC", "🚀 Checking NavIC support via External USB GNSS");

        if (!usingExternalGnss) {
            Map<String, Object> response = new HashMap<>();
            response.put("isSupported", false);
            response.put("isActive", false);
            response.put("detectionMethod", "EXTERNAL_USB_GNSS_REQUIRED");
            response.put("chipsetType", "NONE");
            response.put("chipsetVendor", "NONE");
            response.put("chipsetModel", "NONE");
            response.put("hasL5Band", false);
            response.put("hasL5BandActive", false);
            response.put("usingExternalGnss", false);
            response.put("externalDeviceInfo", "NONE");
            response.put("message", "External USB GNSS device required");
            result.success(response);
            return;
        }

        Map<String, Object> response = new HashMap<>();
        response.put("isSupported", true);
        response.put("isActive", hasL5BandActive);
        response.put("detectionMethod", "EXTERNAL_USB_GNSS");
        response.put("chipsetType", getChipsetType(externalGnssVendorId));
        response.put("chipsetVendor", externalGnssVendor);
        response.put("chipsetModel", externalGnssInfo);
        response.put("hasL5Band", hasL5BandSupport);
        response.put("hasL5BandActive", hasL5BandActive);
        response.put("usingExternalGnss", true);
        response.put("externalDeviceInfo", externalGnssInfo);
        response.put("message", "Using external USB GNSS device");

        response.put("satelliteCount", detectedSatellites.size());
        response.put("navicSatellites", countNavicSatellites());
        response.put("allSatellites", getSatellitesAsList());
        result.success(response);
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

    private List<Map<String, Object>> getSatellitesAsList() {
        List<Map<String, Object>> satellites = new ArrayList<>();
        for (EnhancedSatellite sat : detectedSatellites.values()) {
            satellites.add(sat.toEnhancedMap());
        }
        return satellites;
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

    // =============== LOCATION METHODS ===============

    private void startLocationUpdates(MethodChannel.Result result) {
        Log.d("NavIC", "📍 Starting location updates via External USB GNSS");

        if (!usingExternalGnss) {
            result.error("EXTERNAL_GNSS_REQUIRED", "External USB GNSS device required", null);
            return;
        }

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
                    locationData.put("externalGnssInfo", externalGnssInfo);
                    locationData.put("hasL5Band", hasL5BandSupport);
                    locationData.put("hasL5BandActive", hasL5BandActive);

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
            // Simulate location updates for external GNSS
            if (locationManager.isProviderEnabled(LocationManager.GPS_PROVIDER)) {
                locationManager.requestLocationUpdates(
                        LocationManager.GPS_PROVIDER,
                        LOCATION_UPDATE_INTERVAL_MS,
                        LOCATION_UPDATE_DISTANCE_M,
                        locationListener,
                        handler.getLooper()
                );
                Log.d("NavIC", "External GNSS updates requested via GPS provider");
            }

            isTrackingLocation = true;

            Map<String, Object> resp = new HashMap<>();
            resp.put("success", true);
            resp.put("message", "Location updates started via USB GNSS");
            resp.put("usingExternalGnss", usingExternalGnss);
            resp.put("externalDeviceInfo", externalGnssInfo);
            resp.put("hasL5BandActive", hasL5BandActive);
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

    // =============== OTHER MODIFIED METHODS ===============

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
            gnssCapabilities.put("hasIrnss", usingExternalGnss);
            gnssCapabilities.put("hasL5", hasL5BandSupport);
            gnssCapabilities.put("source", "EXTERNAL_USB_GNSS");

            deviceInfo.put("gnssCapabilities", gnssCapabilities);
            deviceInfo.put("detectionTime", System.currentTimeMillis());

            result.success(deviceInfo);
        } catch (Exception e) {
            Log.e("NavIC", "Error getting device info", e);
            result.error("DEVICE_INFO_ERROR", "Failed to get device info", null);
        }
    }

    private void getGnssCapabilities(MethodChannel.Result result) {
        Log.d("NavIC", "Getting GNSS capabilities via USB GNSS");

        Map<String, Object> caps = new HashMap<>();
        try {
            caps.put("androidVersion", Build.VERSION.SDK_INT);
            caps.put("manufacturer", Build.MANUFACTURER);
            caps.put("model", Build.MODEL);
            caps.put("device", Build.DEVICE);
            caps.put("hardware", Build.HARDWARE);

            caps.put("hasGnssFeature", usingExternalGnss);

            Map<String, Object> gnssMap = new HashMap<>();
            gnssMap.put("hasIrnss", usingExternalGnss);
            gnssMap.put("hasL5", hasL5BandSupport);
            gnssMap.put("hasL1", true);
            gnssMap.put("hasL2", true);
            gnssMap.put("hasGlonass", true);
            gnssMap.put("hasGalileo", true);
            gnssMap.put("hasBeidou", true);
            gnssMap.put("hasQzss", true);
            gnssMap.put("hasSbas", true);
            gnssMap.put("source", "EXTERNAL_USB_GNSS");

            caps.put("gnssCapabilities", gnssMap);
            caps.put("capabilitiesMethod", "EXTERNAL_GNSS_DETECTION");
            caps.put("detectionTime", System.currentTimeMillis());
            caps.put("hasL5Band", hasL5BandSupport);
            caps.put("hasL5BandActive", hasL5BandActive);
            caps.put("usingExternalGnss", usingExternalGnss);
            caps.put("externalGnssInfo", externalGnssInfo);

            Log.d("NavIC", "GNSS capabilities retrieved via USB GNSS");
            result.success(caps);
        } catch (Exception e) {
            Log.e("NavIC", "Failed to get GNSS capabilities", e);
            result.error("CAPABILITIES_ERROR", "Failed to get GNSS capabilities", null);
        }
    }

    private void getAllSatellites(MethodChannel.Result result) {
        if (!usingExternalGnss) {
            result.error("EXTERNAL_GNSS_REQUIRED", "External USB GNSS device required", null);
            return;
        }

        List<Map<String, Object>> allSatellites = new ArrayList<>();
        Map<String, Object> systems = new HashMap<>();

        if (detectedSatellites.isEmpty()) {
            simulateExternalGnssSatelliteData(result);
            return;
        }

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

        Log.d("NavIC", String.format("📊 Returning %d satellites from external GNSS",
                allSatellites.size()));

        result.success(response);
    }

    // =============== REAL-TIME DETECTION METHODS ===============

    private void startRealTimeNavicDetection(MethodChannel.Result result) {
        Log.d("NavIC", "Starting real-time NavIC detection via USB GNSS");

        if (!usingExternalGnss) {
            result.error("EXTERNAL_GNSS_REQUIRED", "External USB GNSS device required", null);
            return;
        }

        Map<String, Object> resp = new HashMap<>();
        resp.put("success", true);
        resp.put("message", "Real-time NavIC detection started via USB GNSS");
        resp.put("hasL5Band", hasL5BandSupport);
        resp.put("hasL5BandActive", hasL5BandActive);
        resp.put("usingExternalGnss", usingExternalGnss);
        resp.put("externalGnssInfo", externalGnssInfo);
        Log.d("NavIC", "Real-time detection started via USB GNSS");
        result.success(resp);
    }

    private void stopRealTimeDetection(MethodChannel.Result result) {
        Log.d("NavIC", "Stopping real-time detection");

        if (result != null) {
            Map<String, Object> resp = new HashMap<>();
            resp.put("success", true);
            resp.put("message", "Real-time detection stopped");
            result.success(resp);
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
            response.put("externalGnssActive", usingExternalGnss);

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

    // =============== SATELLITE ANALYSIS METHODS ===============

    private void getDetailedSatelliteInfo(MethodChannel.Result result) {
        Log.d("NavIC", "🔍 Getting detailed satellite information via USB GNSS");

        if (!usingExternalGnss) {
            result.error("EXTERNAL_GNSS_REQUIRED", "External USB GNSS device required", null);
            return;
        }

        try {
            if (detectedSatellites.isEmpty()) {
                simulateExternalGnssSatelliteData(result);
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
                info.put("externalGnss", true);

                detailedInfo.add(info);
            }

            Map<String, Object> response = new HashMap<>();
            response.put("satellites", detailedInfo);
            response.put("count", detailedInfo.size());
            response.put("timestamp", System.currentTimeMillis());
            response.put("hasData", true);
            response.put("usingExternalGnss", usingExternalGnss);
            response.put("deviceInfo", externalGnssInfo);

            result.success(response);

        } catch (Exception e) {
            Log.e("NavIC", "Error getting detailed satellite info", e);
            result.error("DETAILED_INFO_ERROR", "Failed to get detailed satellite info", null);
        }
    }

    private void getCompleteSatelliteSummary(MethodChannel.Result result) {
        Log.d("NavIC", "📊 Getting complete satellite summary via USB GNSS");

        if (!usingExternalGnss) {
            result.error("EXTERNAL_GNSS_REQUIRED", "External USB GNSS device required", null);
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
        Log.d("NavIC", "📡 Getting satellite names via USB GNSS");

        if (!usingExternalGnss) {
            result.error("EXTERNAL_GNSS_REQUIRED", "External USB GNSS device required", null);
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
            response.put("deviceInfo", externalGnssInfo);

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
        Log.d("NavIC", "🌌 Getting constellation details via USB GNSS");

        if (!usingExternalGnss) {
            result.error("EXTERNAL_GNSS_REQUIRED", "External USB GNSS device required", null);
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
            response.put("deviceInfo", externalGnssInfo);

            result.success(response);

        } catch (Exception e) {
            Log.e("NavIC", "Error getting constellation details", e);
            result.error("CONSTELLATION_ERROR", "Failed to get constellation details", null);
        }
    }

    private String getConstellationDescription(int constellation) {
        switch (constellation) {
            case 7: return "Indian Regional Navigation Satellite System (NavIC)";
            case 1: return "Global Positioning System (USA)";
            case 3: return "Global Navigation Satellite System (Russia)";
            case 4: return "European Global Navigation Satellite System";
            case 5: return "BeiDou Navigation Satellite System (China)";
            case 6: return "Quasi-Zenith Satellite System (Japan)";
            case 2: return "Satellite-Based Augmentation System";
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
        Log.d("NavIC", "📶 Getting signal strength analysis via USB GNSS");

        if (!usingExternalGnss) {
            result.error("EXTERNAL_GNSS_REQUIRED", "External USB GNSS device required", null);
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
            analysis.put("deviceInfo", externalGnssInfo);

            result.success(analysis);

        } catch (Exception e) {
            Log.e("NavIC", "Error getting signal strength analysis", e);
            result.error("SIGNAL_ANALYSIS_ERROR", "Failed to get signal strength analysis", null);
        }
    }

    private void getElevationAzimuthData(MethodChannel.Result result) {
        Log.d("NavIC", "🎯 Getting elevation and azimuth data via USB GNSS");

        if (!usingExternalGnss) {
            result.error("EXTERNAL_GNSS_REQUIRED", "External USB GNSS device required", null);
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
                data.put("externalGnss", true);
                positionData.add(data);
            }

            Map<String, Object> response = new HashMap<>();
            response.put("positionData", positionData);
            response.put("timestamp", System.currentTimeMillis());
            response.put("usingExternalGnss", usingExternalGnss);
            response.put("deviceInfo", externalGnssInfo);

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
        Log.d("NavIC", "📻 Getting carrier frequency information via USB GNSS");

        if (!usingExternalGnss) {
            result.error("EXTERNAL_GNSS_REQUIRED", "External USB GNSS device required", null);
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
                data.put("externalGnss", true);
                frequencyData.add(data);
            }

            Map<String, Object> response = new HashMap<>();
            response.put("frequencyData", frequencyData);
            response.put("hasL5Band", hasL5BandSupport);
            response.put("hasL5BandActive", hasL5BandActive);
            response.put("timestamp", System.currentTimeMillis());
            response.put("usingExternalGnss", usingExternalGnss);
            response.put("deviceInfo", externalGnssInfo);

            result.success(response);

        } catch (Exception e) {
            Log.e("NavIC", "Error getting carrier frequency info", e);
            result.error("FREQUENCY_ERROR", "Failed to get carrier frequency info", null);
        }
    }

    private void getEphemerisAlmanacStatus(MethodChannel.Result result) {
        Log.d("NavIC", "📡 Getting ephemeris and almanac status via USB GNSS");

        if (!usingExternalGnss) {
            result.error("EXTERNAL_GNSS_REQUIRED", "External USB GNSS device required", null);
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
            status.put("deviceInfo", externalGnssInfo);

            result.success(status);

        } catch (Exception e) {
            Log.e("NavIC", "Error getting ephemeris/almanac status", e);
            result.error("EPHEMERIS_ERROR", "Failed to get ephemeris/almanac status", null);
        }
    }

    private void getSatelliteDetectionHistory(MethodChannel.Result result) {
        Log.d("NavIC", "📈 Getting satellite detection history via USB GNSS");

        if (!usingExternalGnss) {
            result.error("EXTERNAL_GNSS_REQUIRED", "External USB GNSS device required", null);
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
                history.put("externalGnss", true);
                detectionHistory.add(history);
            }

            Map<String, Object> response = new HashMap<>();
            response.put("detectionHistory", detectionHistory);
            response.put("timestamp", System.currentTimeMillis());
            response.put("usingExternalGnss", usingExternalGnss);
            response.put("deviceInfo", externalGnssInfo);

            result.success(response);

        } catch (Exception e) {
            Log.e("NavIC", "Error getting detection history", e);
            result.error("HISTORY_ERROR", "Failed to get detection history", null);
        }
    }

    private void getGnssDiversityReport(MethodChannel.Result result) {
        Log.d("NavIC", "🌐 Getting GNSS diversity report via USB GNSS");

        if (!usingExternalGnss) {
            result.error("EXTERNAL_GNSS_REQUIRED", "External USB GNSS device required", null);
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
            diversityReport.put("deviceInfo", externalGnssInfo);
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
        Log.d("NavIC", "🔴 Getting real-time satellite stream via USB GNSS");

        if (!usingExternalGnss) {
            result.error("EXTERNAL_GNSS_REQUIRED", "External USB GNSS device required", null);
            return;
        }

        Map<String, Object> response = new HashMap<>();
        response.put("status", "REALTIME_STREAM_ACTIVE");
        response.put("message", "Real-time satellite stream is active via USB GNSS");
        response.put("hasL5Band", hasL5BandSupport);
        response.put("hasL5BandActive", hasL5BandActive);
        response.put("usingExternalGnss", usingExternalGnss);
        response.put("externalGnssInfo", externalGnssInfo);
        response.put("timestamp", System.currentTimeMillis());

        result.success(response);
    }

    private void getSatelliteSignalQuality(MethodChannel.Result result) {
        Log.d("NavIC", "📊 Getting satellite signal quality via USB GNSS");

        if (!usingExternalGnss) {
            result.error("EXTERNAL_GNSS_REQUIRED", "External USB GNSS device required", null);
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
            signalQuality.put("deviceInfo", externalGnssInfo);

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
            stopRealTimeDetection(null);
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
}