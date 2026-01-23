// lib/services/location_service.dart
import 'dart:async';
//import 'dart:js_interop';
import 'package:geolocator/geolocator.dart';
import 'package:navic_ss/services/hardware_services.dart';
import 'package:navic_ss/models/gnss_satellite.dart';
import 'package:navic_ss/models/satellite_data_model.dart';

class EnhancedLocationService {
  // Hardware state (matches Java response)
  bool _isNavicSupported = false;
  bool _isNavicActive = false;
  int _navicSatelliteCount = 0;
  int _totalSatelliteCount = 0;
  int _navicUsedInFix = 0;
  String _detectionMethod = "UNKNOWN";
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
  final StreamController<bool> _isDetectingController = StreamController<bool>.broadcast();
  final StreamController<Map<String, dynamic>> _hardwareStateController = StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<List<GnssSatellite>> _satellitesController = StreamController<List<GnssSatellite>>.broadcast();
  final StreamController<EnhancedPosition?> _positionController = StreamController<EnhancedPosition?>.broadcast();

  // Current state for quick access
  EnhancedPosition? _lastPosition;
  bool _isDetecting = false;

  static final EnhancedLocationService _instance = EnhancedLocationService._internal();
  factory EnhancedLocationService() => _instance;

  EnhancedLocationService._internal() {
    print("✅ EnhancedLocationService created");
  }

  /// Initialize service
  Future<void> initializeService() async {
    print("🚀 Initializing Location Service...");
    try {
      await NavicHardwareService.isLocationEnabled();
      print("✅ NavicHardwareService initialized");

      // Initial hardware check
      await _performHardwareDetection();
    } catch (e) {
      print("❌ Failed to initialize: $e");
    }
  }

  /// Main method to get location - enhanced for homescreen
  Future<EnhancedPosition?> getLocationWithNavICFlow() async {
    try {
      print("\n🎯 ========= STARTING LOCATION FLOW ==========");

      // Notify UI that detection is starting
      _setDetectingState(true);

      // Step 1: Check permissions
      final hasPermission = await checkLocationPermission();
      if (!hasPermission) {
        print("❌ Location permission denied");
        _setDetectingState(false);
        return null;
      }

      // Step 2: Perform hardware detection (with UI updates)
      await _performHardwareDetectionWithUpdates();

      // Step 3: Get GPS location
      print("🎯 Getting GPS location...");
      _broadcastHardwareState("Acquiring location...");
      final position = await _getGpsLocation();
      if (position == null) {
        print("❌ Failed to get GPS location");
        _broadcastHardwareState("Location acquisition failed");
        _setDetectingState(false);
        return null;
      }

      // Step 4: Create enhanced position
      final enhancedPosition = _createEnhancedPosition(position);
      _lastPosition = enhancedPosition;

      // Broadcast position to UI
      _positionController.add(enhancedPosition);

      // Broadcast satellites to UI
      _satellitesController.add(_allSatellites);

      print("\n🎯 ========= LOCATION FLOW COMPLETE ==========");
      print("✅ Position: ${position.latitude.toStringAsFixed(6)}, ${position.longitude.toStringAsFixed(6)}");
      print("✅ Accuracy: ${position.accuracy?.toStringAsFixed(2)}m");
      print("✅ NavIC Supported: $_isNavicSupported");
      print("✅ NavIC Active: $_isNavicActive");
      print("✅ Satellites: $_totalSatelliteCount total, $_navicSatelliteCount NavIC");
      print("✅ L5 Band: $_hasL5Band (Active: $_hasL5BandActive)");
      print("✅ External GNSS: $_usingExternalGnss");
      print("==========================================\n");

      // Broadcast final hardware state
      _broadcastHardwareState("Location acquired");

      // Reset detecting state
      _setDetectingState(false);

      return enhancedPosition;

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
      print("🔍 Performing hardware detection...");
      _broadcastHardwareState("Detecting hardware...");

      final hardwareResult = await NavicHardwareService.checkNavicHardware();

      // Update state from Java response
      _isNavicSupported = hardwareResult.isSupported;
      _isNavicActive = hardwareResult.isActive;
      _navicSatelliteCount = hardwareResult.satelliteCount;
      _totalSatelliteCount = hardwareResult.totalSatellites;
      _navicUsedInFix = hardwareResult.usedInFixCount;
      _detectionMethod = hardwareResult.detectionMethod;
      _hasL5Band = hardwareResult.hasL5Band;
      _hasL5BandActive = hardwareResult.hasL5BandActive;
      _usingExternalGnss = hardwareResult.usingExternalGnss;
      _externalDeviceInfo = hardwareResult.externalDeviceInfo;
      _allSatellites = hardwareResult.gnssSatellites;

      // Update system stats
      _updateSystemStats();

      // Broadcast updated state
      _broadcastHardwareState("Hardware detection complete");

      print("\n🎯 Hardware Detection Results:");
      print("  ✅ NavIC Supported: $_isNavicSupported");
      print("  📡 NavIC Active: $_isNavicActive");
      print("  🛰️ NavIC Sats: $_navicSatelliteCount ($_navicUsedInFix in fix)");
      print("  📊 Total Sats: $_totalSatelliteCount");
      print("  🔧 Method: $_detectionMethod");
      print("  📡 L5 Band: $_hasL5Band (Active: $_hasL5BandActive)");
      print("  🔌 Using External GNSS: $_usingExternalGnss");
      if (_usingExternalGnss) {
        print("  📡 External Device: $_externalDeviceInfo");
      }

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
    final navicCount = _allSatellites.where((s) => s.system == 'NAVIC' || s.system == 'IRNSS').length;
    final glonassCount = _allSatellites.where((s) => s.system == 'GLONASS').length;
    final galileoCount = _allSatellites.where((s) => s.system == 'GALILEO').length;
    final beidouCount = _allSatellites.where((s) => s.system == 'BEIDOU').length;

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
      if (result['usingExternalGnss'] != null) {
        _usingExternalGnss = result['usingExternalGnss'] as bool;
      }
      if (result['externalGnssInfo'] != null) {
        _externalDeviceInfo = result['externalGnssInfo'].toString();
      }
      if (result['availableDevices'] != null) {
        _usbConnectionStatus = "DEVICES_FOUND";
      } else {
        _usbConnectionStatus = "NO_DEVICES";
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
      return {
        'success': false,
        'message': 'Error: $e',
        'status': 'ERROR'
      };
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
  Stream<Map<String, dynamic>> get hardwareStateStream => _hardwareStateController.stream;
  Stream<List<GnssSatellite>> get satellitesStream => _satellitesController.stream;
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

  /// Check location permission (unchanged)
  Future<bool> checkLocationPermission() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled && !_usingExternalGnss) {
        print("⚠️ Location services disabled");
        return false;
      }

      LocationPermission permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.deniedForever) {
        print("❌ Location permission denied forever");
        return false;
      }

      if (permission == LocationPermission.denied) {
        print("📍 Location permission denied, requesting...");
        permission = await Geolocator.requestPermission();
      }

      final granted = permission == LocationPermission.whileInUse ||
          permission == LocationPermission.always;

      print("📍 Permission status: $permission (Granted: $granted)");
      return granted;

    } catch (e) {
      print("❌ Error checking location permission: $e");
      return false;
    }
  }

  /// Get GPS location (unchanged)
  Future<Position?> _getGpsLocation() async {
    try {
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
        timeLimit: const Duration(seconds: 10),
      );

      print("✅ GPS position acquired: ${position.latitude}, ${position.longitude}");
      print("✅ GPS Accuracy: ${position.accuracy?.toStringAsFixed(2) ?? 'unknown'} meters");

      return position;
    } catch (e) {
      print("❌ GPS acquisition failed: $e");
      return null;
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
      _navicSatelliteCount = hardwareResult.satelliteCount;
      _totalSatelliteCount = hardwareResult.totalSatellites;
      _navicUsedInFix = hardwareResult.usedInFixCount;
      _detectionMethod = hardwareResult.detectionMethod;
      _hasL5Band = hardwareResult.hasL5Band;
      _hasL5BandActive = hardwareResult.hasL5BandActive;
      _usingExternalGnss = hardwareResult.usingExternalGnss;
      _externalDeviceInfo = hardwareResult.externalDeviceInfo;
      _allSatellites = hardwareResult.gnssSatellites;

      // Update system stats
      _updateSystemStats();

      print("\n🎯 Hardware Detection Results:");
      print("  ✅ NavIC Supported: $_isNavicSupported");
      print("  📡 NavIC Active: $_isNavicActive");
      print("  🛰️ NavIC Sats: $_navicSatelliteCount ($_navicUsedInFix in fix)");
      print("  📊 Total Sats: $_totalSatelliteCount");
      print("  🔧 Method: $_detectionMethod");
      print("  📡 L5 Band: $_hasL5Band (Active: $_hasL5BandActive)");
      print("  🔌 Using External GNSS: $_usingExternalGnss");
      if (_usingExternalGnss) {
        print("  📡 External Device: $_externalDeviceInfo");
      }

    } catch (e) {
      print("❌ Hardware detection failed: $e");
      _resetToDefaultState();
    }
  }

  /// Update system statistics (unchanged)
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
      _primarySystem = systemCounts.entries
          .reduce((a, b) => a.value > b.value ? a : b)
          .key;
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
    _detectionMethod = "ERROR";
    _hasL5Band = false;
    _hasL5BandActive = false;
    _usingExternalGnss = false;
    _externalDeviceInfo = "NONE";
    _primarySystem = "GPS";
    _systemStats = {};
    _allSatellites = [];
  }

  /// Create enhanced position (unchanged)
  EnhancedPosition _createEnhancedPosition(Position position) {
    final isNavicEnhanced = _isNavicSupported && _isNavicActive;

    // Determine location source
    String locationSource;
    if (_usingExternalGnss) {
      locationSource = "EXTERNAL_GNSS";
    } else if (isNavicEnhanced) {
      locationSource = "NAVIC";
    } else {
      locationSource = _primarySystem;
    }

    // Determine chipset info based on mode
    String chipsetType = _usingExternalGnss ? "EXTERNAL_DEVICE" : "INTERNAL_GNSS";
    String chipsetVendor = _usingExternalGnss ? _externalGnssVendor : "UNKNOWN";
    String chipsetModel = _usingExternalGnss ? _externalDeviceInfo : "UNKNOWN";

    // Determine positioning method
    String positioningMethod = _determinePositioningMethod(isNavicEnhanced);

    // Calculate confidence score (simplified)
    double confidenceScore = 0.5;
    if (_hasL5Band && _hasL5BandActive) confidenceScore += 0.2;
    if (isNavicEnhanced) confidenceScore += 0.15;
    if (_usingExternalGnss) confidenceScore += 0.2;
    if (position.accuracy != null && position.accuracy! < 10.0) confidenceScore += 0.15;
    confidenceScore = confidenceScore.clamp(0.0, 1.0);

    return EnhancedPosition.create(
      latitude: position.latitude,
      longitude: position.longitude,
      accuracy: position.accuracy,
      altitude: position.altitude,
      speed: position.speed,
      bearing: position.heading,
      timestamp: position.timestamp,
      isNavicSupported: _isNavicSupported,
      isNavicActive: _isNavicActive,
      isNavicEnhanced: isNavicEnhanced,
      confidenceScore: confidenceScore,
      locationSource: locationSource,
      detectionReason: _generateStatusMessage(),
      navicSatellites: _navicSatelliteCount,
      totalSatellites: _totalSatelliteCount,
      navicUsedInFix: _navicUsedInFix,
      hasL5Band: _hasL5Band,
      hasL5BandActive: _hasL5BandActive,
      positioningMethod: positioningMethod,
      systemStats: _systemStats,
      primarySystem: _primarySystem,
      usingExternalGnss: _usingExternalGnss,
      externalGnssInfo: _externalDeviceInfo,
      externalGnssVendor: chipsetVendor,
      usbConnectionActive: _usbConnectionActive,
      message: _generateStatusMessage(),
    );
  }

  String _determinePositioningMethod(bool isNavicEnhanced) {
    if (_usingExternalGnss) {
      return _hasL5BandActive ? "EXTERNAL_GNSS_L5" : "EXTERNAL_GNSS";
    } else if (isNavicEnhanced && _navicUsedInFix >= 4) {
      return _hasL5BandActive ? "NAVIC_PRIMARY_L5" : "NAVIC_PRIMARY";
    } else if (isNavicEnhanced && _navicUsedInFix >= 2) {
      return "NAVIC_HYBRID";
    } else if (isNavicEnhanced && _navicUsedInFix >= 1) {
      return "NAVIC_ASSISTED";
    } else {
      return "GPS_PRIMARY";
    }
  }

  String _generateStatusMessage() {
    if (_usingExternalGnss) {
      return "Using external USB GNSS: $_externalDeviceInfo";
    }
    if (_isNavicSupported && _isNavicActive) {
      return "NavIC positioning available. L5 Band: ${_hasL5BandActive ? 'Active' : 'Inactive'}.";
    } else if (_hasL5Band) {
      return "L5 band support available. Using $_primarySystem positioning.";
    } else {
      return "Using $_primarySystem positioning.";
    }
  }

  void dispose() {
    print("🧹 EnhancedLocationService disposed");
    _isDetectingController.close();
    _hardwareStateController.close();
    _satellitesController.close();
    _positionController.close();
  }
}