// lib/services/location_service.dart
import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:navic_ss/services/hardware_services.dart';
import 'package:navic_ss/models/gnss_satellite.dart';
import 'package:navic_ss/models/enhanced_position.dart';

class EnhancedLocationService {
  // Hardware state (matches Java response)
  bool _isNavicSupported = false;
  bool _isNavicActive = false;
  int _navicSatelliteCount = 0;
  int _totalSatelliteCount = 0;
  int _navicUsedInFix = 0;
  String _detectionMethod = "EXTERNAL_USB_GNSS_REQUIRED";
  bool _hasL5Band = false;
  bool _hasL5BandActive = false;

  // USB GNSS state
  bool _usingExternalGnss = false;
  String _externalDeviceInfo = "NONE";
  String _externalGnssVendor = "UNKNOWN";
  bool _usbConnectionActive = false;
  String _usbConnectionStatus = "DISCONNECTED"; // For UI display

  // Derived state
  String _primarySystem = "GPS";
  Map<String, dynamic> _systemStats = {};
  List<GnssSatellite> _allSatellites = [];

  // State listeners for homescreen
  final StreamController<bool> _isDetectingController =
      StreamController<bool>.broadcast();
  final StreamController<Map<String, dynamic>> _hardwareStateController =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<List<GnssSatellite>> _satellitesController =
      StreamController<List<GnssSatellite>>.broadcast();
  final StreamController<EnhancedPosition?> _positionController =
      StreamController<EnhancedPosition?>.broadcast();

  // Current state for quick access
  EnhancedPosition? _lastPosition;
  bool _isDetecting = false;

  static final EnhancedLocationService _instance =
      EnhancedLocationService._internal();
  factory EnhancedLocationService() => _instance;

  EnhancedLocationService._internal() {
    print("✅ EnhancedLocationService created");
  }

  /// Initialize service
  Future<void> initializeService() async {
    print("🚀 Initializing Location Service...");
    try {
      // Initialize hardware service
      NavicHardwareService.initialize();
      await NavicHardwareService.isLocationEnabled();
      print("✅ NavicHardwareService initialized");

      // Set up callbacks
      NavicHardwareService.setLocationUpdateCallback(_handleLocationUpdate);
      NavicHardwareService.setExternalGnssStatusCallback(
          _handleExternalGnssStatus);

      // Initial hardware check
      await _performHardwareDetection();
    } catch (e) {
      print("❌ Failed to initialize: $e");
    }
  }

  /// Handle location updates from Java
  void _handleLocationUpdate(Map<String, dynamic> data) {
    try {
      print('📍 Location update received in Dart: $data');

      // Create enhanced position from Java data
      final enhancedPosition = EnhancedPosition.create(
        latitude: data['latitude'] as double? ?? 0.0,
        longitude: data['longitude'] as double? ?? 0.0,
        accuracy: data['accuracy'] as double?,
        altitude: data['altitude'] as double?,
        speed: data['speed'] as double?,
        bearing: data['bearing'] as double?,
        timestamp:
            data['time'] as int? ?? DateTime.now().millisecondsSinceEpoch,
        isNavicSupported:
            data['isNavicSupported'] as bool? ?? _isNavicSupported,
        isNavicActive: data['isNavicActive'] as bool? ?? _isNavicActive,
        isNavicEnhanced: (data['isNavicActive'] as bool? ?? false) &&
            (data['isNavicSupported'] as bool? ?? false),
        confidenceScore: data['confidenceScore'] as double? ?? 0.5,
        locationSource:
            data['locationSource'] as String? ?? 'EXTERNAL_USB_GNSS',
        detectionReason:
            data['detectionReason'] as String? ?? 'Using external USB GNSS',
        navicSatellites:
            data['navicSatellites'] as int? ?? _navicSatelliteCount,
        totalSatellites:
            data['totalSatellites'] as int? ?? _totalSatelliteCount,
        navicUsedInFix: data['navicUsedInFix'] as int? ?? _navicUsedInFix,
        hasL5Band: data['hasL5Band'] as bool? ?? _hasL5Band,
        hasL5BandActive: data['hasL5BandActive'] as bool? ?? _hasL5BandActive,
        positioningMethod:
            data['positioningMethod'] as String? ?? 'EXTERNAL_USB_GNSS',
        systemStats:
            data['systemStats'] as Map<String, dynamic>? ?? _systemStats,
        primarySystem: data['primarySystem'] as String? ?? _primarySystem,
        usingExternalGnss:
            data['usingExternalGnss'] as bool? ?? _usingExternalGnss,
        externalGnssInfo:
            data['externalGnssInfo'] as String? ?? _externalDeviceInfo,
        externalGnssVendor:
            data['externalGnssVendor'] as String? ?? _externalGnssVendor,
        usbConnectionActive:
            data['usbConnectionActive'] as bool? ?? _usbConnectionActive,
        message: data['message'] as String? ?? 'Location update from USB GNSS',
      );

      _lastPosition = enhancedPosition;

      // Broadcast position to UI
      _positionController.add(enhancedPosition);

      // Update satellite data if available
      if (data.containsKey('satelliteCount')) {
        _totalSatelliteCount = data['satelliteCount'] as int? ?? 0;
      }
      if (data.containsKey('navicSatellites')) {
        _navicSatelliteCount = data['navicSatellites'] as int? ?? 0;
      }

      // Broadcast updated state
      _broadcastHardwareState("Location updated via USB GNSS");
    } catch (e) {
      print('❌ Error handling location update: $e');
    }
  }

  /// Handle external GNSS status updates
  void _handleExternalGnssStatus(Map<String, dynamic> data) {
    try {
      print('🔌 External GNSS status update: $data');

      final type = data['type'] as String?;

      switch (type) {
        case 'EXTERNAL_GNSS_CONNECTED':
          _usingExternalGnss = true;
          _externalDeviceInfo = data['deviceInfo'] as String? ?? 'CONNECTED';
          _hasL5Band = data['hasL5Band'] as bool? ?? false;
          _hasL5BandActive = data['hasL5BandActive'] as bool? ?? false;
          _usbConnectionActive = true;
          _usbConnectionStatus = "CONNECTED";
          _broadcastHardwareState("USB GNSS connected");
          break;

        case 'EXTERNAL_GNSS_DISCONNECTED':
          _usingExternalGnss = false;
          _usbConnectionActive = false;
          _usbConnectionStatus = "DISCONNECTED";
          _externalDeviceInfo = "NONE";
          _hasL5BandActive = false;
          _allSatellites.clear();
          _broadcastHardwareState("USB GNSS disconnected");
          break;
      }
    } catch (e) {
      print('❌ Error handling external GNSS status: $e');
    }
  }

  /// Main method to get location - enhanced for homescreen
  Future<EnhancedPosition?> getLocationWithNavICFlow() async {
    try {
      print("\n🎯 ========= STARTING LOCATION FLOW ==========");

      // Notify UI that detection is starting
      _setDetectingState(true);

      // Step 1: Check if USB GNSS is connected
      if (!_usingExternalGnss) {
        print("❌ External USB GNSS not connected");
        _broadcastHardwareState("Connect USB GNSS device first");
        _setDetectingState(false);
        return null;
      }

      // Step 2: Check permissions
      final hasPermission = await checkLocationPermission();
      if (!hasPermission) {
        print("❌ Location permission denied");
        _setDetectingState(false);
        return null;
      }

      // Step 3: Perform hardware detection (with UI updates)
      await _performHardwareDetectionWithUpdates();

      // Step 4: Get GPS location via external GNSS
      print("🎯 Getting location via external USB GNSS...");
      _broadcastHardwareState("Acquiring location via USB GNSS...");

      // Start location updates
      final locationResult = await NavicHardwareService.startLocationUpdates();
      if (locationResult['success'] != true) {
        print("❌ Failed to start location updates");
        _broadcastHardwareState("Location acquisition failed");
        _setDetectingState(false);
        return null;
      }

      // Wait for location update
      await Future.delayed(Duration(seconds: 2));

      if (_lastPosition == null) {
        print("❌ No location received");
        _broadcastHardwareState("No location data received");
        _setDetectingState(false);
        return null;
      }

      // Broadcast satellites to UI
      _satellitesController.add(_allSatellites);

      print("\n🎯 ========= LOCATION FLOW COMPLETE ==========");
      print(
          "✅ Position: ${_lastPosition!.latitude.toStringAsFixed(6)}, ${_lastPosition!.longitude.toStringAsFixed(6)}");
      print("✅ Accuracy: ${_lastPosition!.accuracy?.toStringAsFixed(2)}m");
      print("✅ NavIC Supported: $_isNavicSupported");
      print("✅ NavIC Active: $_isNavicActive");
      print(
          "✅ Satellites: $_totalSatelliteCount total, $_navicSatelliteCount NavIC");
      print("✅ L5 Band: $_hasL5Band (Active: $_hasL5BandActive)");
      print("✅ External GNSS: $_usingExternalGnss");
      print("✅ USB Device: $_externalDeviceInfo");
      print("==========================================\n");

      // Broadcast final hardware state
      _broadcastHardwareState("Location acquired via USB GNSS");

      // Reset detecting state
      _setDetectingState(false);

      return _lastPosition;
    } catch (e) {
      print("❌ Location acquisition failed: $e");
      _broadcastHardwareState("Error: $e");
      _setDetectingState(false);
      return null;
    }
  }

  /// Perform hardware detection with UI updates
  Future<void> _performHardwareDetectionWithUpdates() async {
    try {
      print("🔍 Performing hardware detection via USB GNSS...");
      _broadcastHardwareState("Detecting USB GNSS hardware...");

      final hardwareResult = await NavicHardwareService.checkNavicHardware();

      // Update state from Java response
      _isNavicSupported = hardwareResult.isSupported;
      _isNavicActive = hardwareResult.isActive;
      _navicSatelliteCount = hardwareResult.navicSatellites;
      _totalSatelliteCount = hardwareResult.satelliteCount;
      _navicUsedInFix = hardwareResult.usedInFixCount;
      _detectionMethod = hardwareResult.detectionMethod;
      _hasL5Band = hardwareResult.hasL5Band;
      _hasL5BandActive = hardwareResult.hasL5BandActive;
      _usingExternalGnss = hardwareResult.usingExternalGnss;
      _externalDeviceInfo = hardwareResult.externalDeviceInfo;
      _allSatellites = hardwareResult.gnssSatellites;

      // Update chipset info
      _externalGnssVendor = hardwareResult.chipsetVendor;

      // Update system stats
      _updateSystemStats();

      // Update USB connection status
      if (_usingExternalGnss && _externalDeviceInfo != "NONE") {
        _usbConnectionActive = true;
        _usbConnectionStatus = "CONNECTED";
      } else {
        _usbConnectionActive = false;
        _usbConnectionStatus = "DISCONNECTED";
      }

      // Broadcast updated state
      _broadcastHardwareState("USB GNSS hardware detection complete");

      print("\n🎯 Hardware Detection Results:");
      print("  ✅ NavIC Supported: $_isNavicSupported");
      print("  📡 NavIC Active: $_isNavicActive");
      print(
          "  🛰️ NavIC Sats: $_navicSatelliteCount ($_navicUsedInFix in fix)");
      print("  📊 Total Sats: $_totalSatelliteCount");
      print("  🔧 Method: $_detectionMethod");
      print("  📡 L5 Band: $_hasL5Band (Active: $_hasL5BandActive)");
      print("  🔌 Using External GNSS: $_usingExternalGnss");
      print("  📡 External Device: $_externalDeviceInfo");
      print("  🔌 USB Status: $_usbConnectionStatus");
    } catch (e) {
      print("❌ Hardware detection failed: $e");
      _broadcastHardwareState("Hardware detection failed: $e");
      _resetToDefaultState();
    }
  }

  /// Get simplified hardware status for homescreen display
  Map<String, dynamic> getHardwareStatus() {
    return {
      'isNavicSupported': _isNavicSupported,
      'isNavicActive': _isNavicActive,
      'hasL5Band': _hasL5Band,
      'hasL5BandActive': _hasL5BandActive,
      'usingExternalGnss': _usingExternalGnss,
      'externalDeviceInfo': _externalDeviceInfo,
      'externalGnssVendor': _externalGnssVendor,
      'usbConnectionActive': _usbConnectionActive,
      'usbConnectionStatus': _usbConnectionStatus,
      'navicSatelliteCount': _navicSatelliteCount,
      'totalSatelliteCount': _totalSatelliteCount,
      'navicUsedInFix': _navicUsedInFix,
      'primarySystem': _primarySystem,
      'detectionMethod': _detectionMethod,
      'systemStats': _systemStats,
      'lastPosition': _lastPosition?.toJson() ?? {},
      'isDetecting': _isDetecting,
    };
  }

  /// Get satellite summary for homescreen
  Map<String, dynamic> getSatelliteSummary() {
    final gpsCount = _allSatellites.where((s) => s.system == 'GPS').length;
    final navicCount = _allSatellites
        .where((s) => s.system == 'IRNSS' || s.system == 'NAVIC')
        .length;
    final glonassCount =
        _allSatellites.where((s) => s.system == 'GLONASS').length;
    final galileoCount =
        _allSatellites.where((s) => s.system == 'GALILEO').length;
    final beidouCount =
        _allSatellites.where((s) => s.system == 'BEIDOU').length;

    final inUseCount = _allSatellites.where((s) => s.usedInFix).length;

    return {
      'total': _allSatellites.length,
      'inUse': inUseCount,
      'gps': gpsCount,
      'navic': navicCount,
      'glonass': glonassCount,
      'galileo': galileoCount,
      'beidou': beidouCount,
      'systems': _systemStats.keys.toList(),
      'list': _allSatellites.map((sat) => sat.toString()).toList(),
    };
  }

  /// Check USB GNSS devices with UI-friendly response
  Future<Map<String, dynamic>> checkUsbGnssDevices() async {
    try {
      _broadcastHardwareState("Scanning for USB devices...");

      final result = await NavicHardwareService.checkUsbGnssDevices();

      // Update local state
      if (result['connected'] != null) {
        _usingExternalGnss = result['connected'] as bool;
      }
      if (result['externalGnssInfo'] != null) {
        _externalDeviceInfo = result['externalGnssInfo'].toString();
      }

      // Update connection status
      if (result['availableDevices'] is List) {
        final devices = result['availableDevices'] as List;
        if (devices.isNotEmpty) {
          _usbConnectionStatus = "DEVICES_FOUND";
        } else {
          _usbConnectionStatus = "NO_DEVICES";
        }
      }

      // Broadcast updated state
      _broadcastHardwareState("USB scan complete");

      return {
        'success': true,
        'status': _usbConnectionStatus,
        'availableDevices': result['availableDevices'] ?? [],
        'currentDevice': _externalDeviceInfo,
        'isConnected': _usingExternalGnss,
      };
    } catch (e) {
      print("❌ Error checking USB GNSS devices: $e");
      _broadcastHardwareState("USB scan failed: $e");
      return {'success': false, 'message': 'Error: $e', 'status': 'ERROR'};
    }
  }

  /// Connect to USB GNSS with UI updates
  Future<Map<String, dynamic>> connectToUsbGnss() async {
    try {
      _broadcastHardwareState("Connecting to USB GNSS...");

      final result = await NavicHardwareService.connectToUsbGnss();

      if (result['success'] as bool == true) {
        _usingExternalGnss = true;
        _externalDeviceInfo = result['deviceInfo']?.toString() ?? 'CONNECTED';
        _hasL5Band = result['hasL5Band'] as bool? ?? false;
        _hasL5BandActive = result['hasL5BandActive'] as bool? ?? false;
        _usbConnectionActive = true;
        _usbConnectionStatus = "CONNECTED";

        // Get hardware info after connection
        await _performHardwareDetection();

        print("✅ Connected to USB GNSS: $_externalDeviceInfo");

        // Broadcast updated state
        _broadcastHardwareState("USB GNSS connected");

        return {
          'success': true,
          'status': 'CONNECTED',
          'deviceInfo': _externalDeviceInfo,
          'hasL5Band': _hasL5Band,
          'hasL5BandActive': _hasL5BandActive,
        };
      } else {
        _usbConnectionStatus = "CONNECTION_FAILED";
        _broadcastHardwareState("USB connection failed");

        return {
          'success': false,
          'status': 'CONNECTION_FAILED',
          'message': result['message'] ?? 'Unknown error',
        };
      }
    } catch (e) {
      print("❌ Error connecting to USB GNSS: $e");
      _usbConnectionStatus = "ERROR";
      _broadcastHardwareState("USB connection error: $e");

      return {
        'success': false,
        'status': 'ERROR',
        'message': 'Error: $e',
      };
    }
  }

  /// Disconnect from USB GNSS
  Future<Map<String, dynamic>> disconnectUsbGnss() async {
    try {
      final result = await NavicHardwareService.disconnectUsbGnss();

      if (result['success'] as bool == true) {
        _usingExternalGnss = false;
        _usbConnectionActive = false;
        _usbConnectionStatus = "DISCONNECTED";
        _externalDeviceInfo = "NONE";
        _hasL5BandActive = false;

        // Reset satellite data
        _allSatellites.clear();
        _systemStats.clear();

        _broadcastHardwareState("USB GNSS disconnected");

        return {
          'success': true,
          'status': 'DISCONNECTED',
        };
      }

      return {
        'success': false,
        'status': 'DISCONNECT_FAILED',
        'message': result['message'] ?? 'Unknown error',
      };
    } catch (e) {
      print("❌ Error disconnecting USB GNSS: $e");
      return {
        'success': false,
        'status': 'ERROR',
        'message': 'Error: $e',
      };
    }
  }

  /// Scan USB GNSS satellites
  Future<Map<String, dynamic>> scanUsbGnssSatellites() async {
    try {
      if (!_usingExternalGnss) {
        return {'success': false, 'message': 'Connect USB GNSS device first'};
      }

      _broadcastHardwareState("Scanning USB GNSS satellites...");

      final result = await NavicHardwareService.scanUsbGnssSatellites();

      if (result.containsKey('satellites')) {
        // Update local satellite data
        final satellites = result['satellites'] as List<dynamic>;
        _allSatellites = _convertToSatelliteList(satellites);

        // Update satellite counts
        _totalSatelliteCount = _allSatellites.length;
        _navicSatelliteCount = _allSatellites
            .where((s) => s.system == 'IRNSS' || s.system == 'NAVIC')
            .length;

        // Broadcast updates
        _satellitesController.add(_allSatellites);
        _updateSystemStats();

        _broadcastHardwareState("Satellite scan complete");

        return {
          'success': true,
          'satelliteCount': _totalSatelliteCount,
          'navicCount': _navicSatelliteCount,
        };
      }

      return {'success': false, 'message': result['message'] ?? 'Scan failed'};
    } catch (e) {
      print("❌ Error scanning USB GNSS satellites: $e");
      return {'success': false, 'message': 'Error: $e'};
    }
  }

  /// Get USB GNSS hardware information
  Future<Map<String, dynamic>> getUsbGnssHardwareInfo() async {
    try {
      if (!_usingExternalGnss) {
        return {'success': false, 'message': 'Connect USB GNSS device first'};
      }

      final result = await NavicHardwareService.getUsbGnssHardwareInfo();
      return result;
    } catch (e) {
      print("❌ Error getting USB GNSS hardware info: $e");
      return {'success': false, 'message': 'Error: $e'};
    }
  }

  /// Start continuous location updates (for homescreen tracking)
  Stream<EnhancedPosition> startLocationUpdates() {
    final controller = StreamController<EnhancedPosition>();

    Timer.periodic(const Duration(seconds: 5), (timer) async {
      try {
        final position = await getLocationWithNavICFlow();
        if (position != null) {
          controller.add(position);
        }
      } catch (e) {
        print("❌ Continuous location update error: $e");
      }
    });

    return controller.stream;
  }

  /// Get current location (simplified for homescreen)
  Future<EnhancedPosition?> getCurrentLocation() async {
    return await getLocationWithNavICFlow();
  }

  /// ============ UI STREAM GETTERS ============

  Stream<bool> get isDetectingStream => _isDetectingController.stream;
  Stream<Map<String, dynamic>> get hardwareStateStream =>
      _hardwareStateController.stream;
  Stream<List<GnssSatellite>> get satellitesStream =>
      _satellitesController.stream;
  Stream<EnhancedPosition?> get positionStream => _positionController.stream;

  /// ============ PRIVATE HELPERS ============

  void _setDetectingState(bool isDetecting) {
    _isDetecting = isDetecting;
    _isDetectingController.add(isDetecting);
  }

  void _broadcastHardwareState(String status) {
    final state = getHardwareStatus();
    state['statusMessage'] = status;
    _hardwareStateController.add(state);
  }

  /// Check location permission
  Future<bool> checkLocationPermission() async {
    try {
      final permissionResult =
          await NavicHardwareService.checkLocationPermissions();
      return permissionResult['allPermissionsGranted'] as bool? ?? false;
    } catch (e) {
      print("❌ Error checking location permission: $e");
      return false;
    }
  }

  /// Perform hardware detection (original - kept for backward compatibility)
  Future<void> _performHardwareDetection() async {
    try {
      print("🔍 Performing hardware detection...");
      final hardwareResult = await NavicHardwareService.checkNavicHardware();

      // Update state from Java response
      _isNavicSupported = hardwareResult.isSupported;
      _isNavicActive = hardwareResult.isActive;
      _navicSatelliteCount = hardwareResult.navicSatellites;
      _totalSatelliteCount = hardwareResult.satelliteCount;
      _navicUsedInFix = hardwareResult.usedInFixCount;
      _detectionMethod = hardwareResult.detectionMethod;
      _hasL5Band = hardwareResult.hasL5Band;
      _hasL5BandActive = hardwareResult.hasL5BandActive;
      _usingExternalGnss = hardwareResult.usingExternalGnss;
      _externalDeviceInfo = hardwareResult.externalDeviceInfo;
      _allSatellites = hardwareResult.gnssSatellites;

      // Update chipset info
      _externalGnssVendor = hardwareResult.chipsetVendor;

      // Update USB connection status
      if (_usingExternalGnss && _externalDeviceInfo != "NONE") {
        _usbConnectionActive = true;
        _usbConnectionStatus = "CONNECTED";
      }

      // Update system stats
      _updateSystemStats();

      print("\n🎯 Hardware Detection Results:");
      print("  ✅ NavIC Supported: $_isNavicSupported");
      print("  📡 NavIC Active: $_isNavicActive");
      print(
          "  🛰️ NavIC Sats: $_navicSatelliteCount ($_navicUsedInFix in fix)");
      print("  📊 Total Sats: $_totalSatelliteCount");
      print("  🔧 Method: $_detectionMethod");
      print("  📡 L5 Band: $_hasL5Band (Active: $_hasL5BandActive)");
      print("  🔌 Using External GNSS: $_usingExternalGnss");
      print("  📡 External Device: $_externalDeviceInfo");
    } catch (e) {
      print("❌ Hardware detection failed: $e");
      _resetToDefaultState();
    }
  }

  /// Update system statistics
  void _updateSystemStats() {
    final systemCounts = <String, int>{};

    for (final sat in _allSatellites) {
      final system = sat.system;
      systemCounts[system] = (systemCounts[system] ?? 0) + 1;
    }

    _systemStats.clear();
    for (final entry in systemCounts.entries) {
      _systemStats[entry.key] = {
        'name': entry.key,
        'total': entry.value,
        'flag': _getCountryFlag(entry.key),
      };
    }

    // Determine primary system
    if (systemCounts.isNotEmpty) {
      _primarySystem =
          systemCounts.entries.reduce((a, b) => a.value > b.value ? a : b).key;
    }
  }

  String _getCountryFlag(String system) {
    const flags = {
      'GPS': '🇺🇸',
      'GLONASS': '🇷🇺',
      'GALILEO': '🇪🇺',
      'BEIDOU': '🇨🇳',
      'IRNSS': '🇮🇳',
      'NAVIC': '🇮🇳',
      'QZSS': '🇯🇵',
      'SBAS': '🌍',
    };
    return flags[system] ?? '🌐';
  }

  void _resetToDefaultState() {
    _isNavicSupported = false;
    _isNavicActive = false;
    _navicSatelliteCount = 0;
    _totalSatelliteCount = 0;
    _navicUsedInFix = 0;
    _detectionMethod = "EXTERNAL_USB_GNSS_REQUIRED";
    _hasL5Band = false;
    _hasL5BandActive = false;
    _usingExternalGnss = false;
    _externalDeviceInfo = "NONE";
    _externalGnssVendor = "UNKNOWN";
    _usbConnectionActive = false;
    _usbConnectionStatus = "DISCONNECTED";
    _primarySystem = "GPS";
    _systemStats = {};
    _allSatellites = [];
  }

  /// Convert dynamic list to GnssSatellite list
  List<GnssSatellite> _convertToSatelliteList(List<dynamic> dynamicList) {
    final List<GnssSatellite> satellites = [];

    for (final item in dynamicList) {
      if (item is Map<String, dynamic>) {
        try {
          final satellite = GnssSatellite.fromMap(item);
          satellites.add(satellite);
        } catch (e) {
          print('⚠️ Error converting satellite: $e');
        }
      }
    }

    return satellites;
  }

  void dispose() {
    print("🧹 EnhancedLocationService disposed");
    _isDetectingController.close();
    _hardwareStateController.close();
    _satellitesController.close();
    _positionController.close();

    // Clean up hardware service
    NavicHardwareService.dispose();
  }
}
