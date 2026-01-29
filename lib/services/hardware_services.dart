// lib/services/hardware_services.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:navic_ss/models/gnss_satellite.dart';
import 'package:navic_ss/services/usb_gnss_device.dart';

// ============ HELPER FUNCTIONS ============

int _parseInt(dynamic value) {
  if (value == null) return 0;
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) {
    if (value.startsWith('0x')) {
      return int.tryParse(value.substring(2), radix: 16) ?? 0;
    }
    return int.tryParse(value) ?? 0;
  }
  return 0;
}

double _parseDouble(dynamic value) {
  if (value == null) return 0.0;
  if (value is double) return value;
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? 0.0;
  return 0.0;
}

bool _parseBool(dynamic value) {
  if (value == null) return false;
  if (value is bool) return value;
  if (value is String) {
    return value.toLowerCase() == 'true' || value == '1';
  }
  if (value is num) return value != 0;
  return false;
}

String _parseString(dynamic value) {
  if (value == null) return '';
  if (value is String) return value;
  return value.toString();
}

List<dynamic> _convertJavaList(dynamic value) {
  if (value == null) return [];
  if (value is List) {
    try {
      return List<dynamic>.from(value);
    } catch (e) {
      print('⚠️ Error converting Java list: $e');
      return [];
    }
  }
  return [];
}

Map<String, dynamic> _convertJavaMap(dynamic value) {
  if (value == null) return {};
  if (value is Map) {
    final Map<String, dynamic> result = {};
    for (final entry in value.entries) {
      try {
        final key = entry.key.toString();
        final val = entry.value;

        if (val is Map) {
          result[key] = _convertJavaMap(val);
        } else if (val is List) {
          result[key] = _convertJavaList(val);
        } else if (val is num) {
          result[key] = val.toDouble();
        } else if (val is String) {
          result[key] = val;
        } else if (val is bool) {
          result[key] = val;
        } else {
          result[key] = val?.toString() ?? '';
        }
      } catch (e) {
        print('⚠️ Error converting map entry: $e');
      }
    }
    return result;
  }
  return {};
}

// ============ GNSS SATELLITE CONVERSION ============

List<GnssSatellite> _convertToGnssSatellites(List<dynamic> javaList) {
  final List<GnssSatellite> converted = [];

  for (final item in javaList) {
    if (item is Map) {
      try {
        final Map<String, dynamic> satMap = {};

        for (final entry in item.entries) {
          final key = entry.key.toString();
          final value = entry.value;

          // Convert Java types to Dart types
          if (value == null) {
            satMap[key] = null;
          } else if (value is num) {
            satMap[key] = value.toDouble();
          } else if (value is bool) {
            satMap[key] = value;
          } else if (value is String) {
            satMap[key] = value;
          } else if (value is List) {
            satMap[key] = _convertJavaList(value);
          } else if (value is Map) {
            satMap[key] = _convertJavaMap(value);
          } else {
            satMap[key] = value.toString();
          }
        }

        // Create GnssSatellite from map
        final satellite = GnssSatellite.fromMap(satMap);
        converted.add(satellite);

      } catch (e) {
        print('⚠️ Error converting satellite: $e');
      }
    }
  }

  return converted;
}

List<UsbGnssDevice> _convertToUsbGnssDevices(List<dynamic> javaList) {
  final List<UsbGnssDevice> converted = [];

  for (final item in javaList) {
    if (item is Map) {
      try {
        final Map<String, dynamic> deviceMap = {};

        for (final entry in item.entries) {
          final key = entry.key.toString();
          final value = entry.value;

          if (value == null) {
            deviceMap[key] = null;
          } else if (value is num) {
            deviceMap[key] = value.toDouble();
          } else if (value is bool) {
            deviceMap[key] = value;
          } else if (value is String) {
            deviceMap[key] = value;
          } else if (value is List) {
            deviceMap[key] = _convertJavaList(value);
          } else if (value is Map) {
            deviceMap[key] = _convertJavaMap(value);
          } else {
            deviceMap[key] = value.toString();
          }
        }

        final device = UsbGnssDevice.fromMap(deviceMap);
        converted.add(device);
      } catch (e) {
        print('⚠️ Error converting USB device: $e');
      }
    }
  }

  return converted;
}

// ============ DATA CLASSES ============

class NavicDetectionResult {
  final bool isSupported;
  final bool isActive;
  final int navicSatellites;
  final int satelliteCount;
  final int usedInFixCount;
  final String detectionMethod;
  final bool hasL5Band;
  final bool hasL5BandActive;
  final String chipsetType;
  final String chipsetVendor;
  final String chipsetModel;
  final bool usingExternalGnss;
  final String externalDeviceInfo;
  final List<dynamic> allSatellites;
  final String? message;
  final double? latitude;
  final double? longitude;
  final double? accuracy;
  final int timestamp;

  List<GnssSatellite> get gnssSatellites => _convertToGnssSatellites(allSatellites);
  int get totalSatellites => satelliteCount;

  const NavicDetectionResult({
    required this.isSupported,
    required this.isActive,
    required this.navicSatellites,
    required this.satelliteCount,
    required this.usedInFixCount,
    required this.detectionMethod,
    required this.hasL5Band,
    required this.hasL5BandActive,
    required this.chipsetType,
    required this.chipsetVendor,
    required this.chipsetModel,
    required this.usingExternalGnss,
    required this.externalDeviceInfo,
    required this.allSatellites,
    this.message,
    this.latitude,
    this.longitude,
    this.accuracy,
    this.timestamp = 0,
  });

  factory NavicDetectionResult.fromMap(Map<String, dynamic> map) {
    try {
      // Debug: Print all keys in the map
      print('📊 NavicDetectionResult keys: ${map.keys.toList()}');

      // Extract allSatellites list
      final allSatellites = _convertJavaList(map['allSatellites'] ?? []);

      return NavicDetectionResult(
        isSupported: _parseBool(map['isSupported'] ?? false),
        isActive: _parseBool(map['isActive'] ?? false),
        navicSatellites: _parseInt(map['navicSatellites'] ?? map['satelliteCount'] ?? 0),
        satelliteCount: _parseInt(map['satelliteCount'] ?? map['navicSatellites'] ?? 0),
        usedInFixCount: _parseInt(map['usedInFix'] ?? 0),
        detectionMethod: _parseString(map['detectionMethod'] ?? 'EXTERNAL_USB_GNSS'),
        hasL5Band: _parseBool(map['hasL5Band'] ?? false),
        hasL5BandActive: _parseBool(map['hasL5BandActive'] ?? false),
        chipsetType: _parseString(map['chipsetType'] ?? 'EXTERNAL_DEVICE'),
        chipsetVendor: _parseString(map['chipsetVendor'] ?? 'UNKNOWN'),
        chipsetModel: _parseString(map['chipsetModel'] ?? map['externalDeviceInfo'] ?? 'UNKNOWN'),
        usingExternalGnss: _parseBool(map['usingExternalGnss'] ?? false),
        externalDeviceInfo: _parseString(map['externalDeviceInfo'] ?? map['externalGnssInfo'] ?? 'NONE'),
        allSatellites: allSatellites,
        message: _parseString(map['message']),
        latitude: map['latitude'] as double?,
        longitude: map['longitude'] as double?,
        accuracy: map['accuracy'] as double?,
        timestamp: _parseInt(map['timestamp'] ?? DateTime.now().millisecondsSinceEpoch),
      );
    } catch (e) {
      print('❌ Error creating NavicDetectionResult: $e');
      return NavicDetectionResult(
        isSupported: false,
        isActive: false,
        navicSatellites: 0,
        satelliteCount: 0,
        usedInFixCount: 0,
        detectionMethod: 'ERROR',
        hasL5Band: false,
        hasL5BandActive: false,
        chipsetType: 'ERROR',
        chipsetVendor: 'ERROR',
        chipsetModel: 'ERROR',
        usingExternalGnss: false,
        externalDeviceInfo: 'ERROR',
        allSatellites: [],
        message: 'Error: $e',
      );
    }
  }

  Map<String, dynamic> toMap() {
    return {
      'isSupported': isSupported,
      'isActive': isActive,
      'navicSatellites': navicSatellites,
      'satelliteCount': satelliteCount,
      'usedInFixCount': usedInFixCount,
      'detectionMethod': detectionMethod,
      'hasL5Band': hasL5Band,
      'hasL5BandActive': hasL5BandActive,
      'chipsetType': chipsetType,
      'chipsetVendor': chipsetVendor,
      'chipsetModel': chipsetModel,
      'usingExternalGnss': usingExternalGnss,
      'externalDeviceInfo': externalDeviceInfo,
      'allSatellites': allSatellites,
      'message': message,
      'timestamp': timestamp,
    };
  }

  @override
  String toString() {
    return 'NavicDetectionResult('
        'isSupported: $isSupported, '
        'isActive: $isActive, '
        'navicSatellites: $navicSatellites, '
        'totalSatellites: $satelliteCount, '
        'hasL5Band: $hasL5Band, '
        'hasL5BandActive: $hasL5BandActive, '
        'chipset: $chipsetVendor $chipsetModel, '
        'external: $usingExternalGnss, '
        'device: $externalDeviceInfo)';
  }
}

// ============ NAVIC HARDWARE SERVICE ============

class NavicHardwareService {
  static const MethodChannel _channel = MethodChannel('navic_support');

  // Callback handlers
  static Function(Map<String, dynamic>)? _permissionResultCallback;
  static Function(Map<String, dynamic>)? _locationUpdateCallback;
  static Function(Map<String, dynamic>)? _externalGnssStatusCallback;

  static bool _isInitialized = false;
  static bool _isHandlingCall = false;

  static void initialize() {
    if (_isInitialized) {
      print('ℹ️ NavicHardwareService already initialized');
      return;
    }

    try {
      _channel.setMethodCallHandler(_handleMethodCall);
      _isInitialized = true;
      print('✅ NavicHardwareService initialized');
    } catch (e) {
      print('❌ Failed to initialize NavicHardwareService: $e');
      _isInitialized = false;
    }
  }

  static Future<dynamic> _handleMethodCall(MethodCall call) async {
    if (_isHandlingCall) {
      print('⚠️ Already handling method call: ${call.method}');
      return null;
    }

    _isHandlingCall = true;
    print('📱 MethodChannel received: ${call.method}');

    try {
      switch (call.method) {
        case 'onPermissionResult':
          if (call.arguments is Map) {
            final result = call.arguments as Map<String, dynamic>;
            print('🔑 Permission result received');
            _permissionResultCallback?.call(result);
          }
          break;
        case 'onLocationUpdate':
          if (call.arguments is Map) {
            final data = call.arguments as Map<String, dynamic>;
            print('📍 Location update received');
            _locationUpdateCallback?.call(data);
          }
          break;
        case 'onExternalGnssStatus':
          if (call.arguments is Map) {
            final data = call.arguments as Map<String, dynamic>;
            print('🔌 External GNSS status update received');
            _externalGnssStatusCallback?.call(data);
          }
          break;
        case 'onUsbPermissionResult':
          if (call.arguments is Map) {
            final data = call.arguments as Map<String, dynamic>;
            print('🔌 USB Permission result received');
            _externalGnssStatusCallback?.call(data);
          }
          break;
        default:
          print('⚠️ Unknown method call: ${call.method}');
      }
    } catch (e) {
      print('❌ Error handling method call ${call.method}: $e');
    } finally {
      _isHandlingCall = false;
    }
    return null;
  }

  // ============ MAIN NAVIC DETECTION ============

  /// Check NavIC hardware support - main method
  static Future<NavicDetectionResult> checkNavicHardware() async {
    try {
      print('🔍 Calling checkNavicHardware on Java side');
      final result = await _channel.invokeMethod('checkNavicHardware');
      print('✅ checkNavicHardware response received');

      if (result is Map) {
        final resultMap = Map<String, dynamic>.from(result);
        print('📊 Response data: $resultMap');
        return NavicDetectionResult.fromMap(resultMap);
      } else {
        print('❌ Unexpected response type from checkNavicHardware: ${result.runtimeType}');
        return _getErrorResult('Invalid response type: ${result.runtimeType}');
      }
    } on PlatformException catch (e) {
      print('❌ PlatformException in checkNavicHardware: ${e.message}');
      return _getErrorResult(e.message ?? 'PlatformException');
    } catch (e) {
      print('❌ Error in checkNavicHardware: $e');
      return _getErrorResult(e.toString());
    }
  }

  static NavicDetectionResult _getErrorResult(String errorMessage) {
    return NavicDetectionResult(
      isSupported: false,
      isActive: false,
      navicSatellites: 0,
      satelliteCount: 0,
      usedInFixCount: 0,
      detectionMethod: 'ERROR',
      hasL5Band: false,
      hasL5BandActive: false,
      chipsetType: 'ERROR',
      chipsetVendor: 'ERROR',
      chipsetModel: 'ERROR',
      usingExternalGnss: false,
      externalDeviceInfo: 'ERROR',
      allSatellites: [],
      message: 'Error: $errorMessage',
    );
  }

  // ============ USB GNSS METHODS ============

  /// Check for connected USB GNSS devices
  static Future<Map<String, dynamic>> checkUsbGnssDevices() async {
    try {
      print('🔌 Checking USB GNSS devices');
      final result = await _channel.invokeMethod('checkUsbGnssDevices');
      print('✅ USB GNSS check response: $result');

      if (result is Map) {
        final response = Map<String, dynamic>.from(result);

        // Convert devices to UsbGnssDevice objects
        final rawDevices = response['usbDevices'] as List? ?? [];
        final devices = _convertToUsbGnssDevices(rawDevices);

        return {
          'success': true,
          'usbDevices': devices.map((d) => d.toMap()).toList(),
          'availableDevices': devices,
          'deviceCount': devices.length,
          'connected': response['connected'] ?? false,
          'connectedDevice': response['connectedDevice'],
          'externalGnssInfo': response['deviceInfo'] ?? 'NONE',
          'timestamp': response['timestamp'] ?? DateTime.now().millisecondsSinceEpoch,
        };
      }
      return {
        'success': false,
        'usbDevices': [],
        'availableDevices': [],
        'deviceCount': 0,
        'message': 'Invalid response type'
      };
    } on PlatformException catch (e) {
      print('❌ Error checking USB GNSS devices: ${e.message}');
      return {
        'success': false,
        'usbDevices': [],
        'availableDevices': [],
        'deviceCount': 0,
        'message': e.message ?? 'Check failed'
      };
    } catch (e) {
      print('❌ Error checking USB GNSS devices: $e');
      return {
        'success': false,
        'usbDevices': [],
        'availableDevices': [],
        'deviceCount': 0,
        'message': e.toString()
      };
    }
  }

  /// Connect to USB GNSS device
  static Future<Map<String, dynamic>> connectToUsbGnss() async {
    try {
      print('🔌 Connecting to USB GNSS device');
      final result = await _channel.invokeMethod('connectToUsbGnss');
      print('✅ USB GNSS connect response: $result');

      if (result is Map) {
        final response = Map<String, dynamic>.from(result);
        return response;
      }
      return {
        'success': false,
        'message': 'Invalid response type'
      };
    } on PlatformException catch (e) {
      print('❌ Error connecting to USB GNSS: ${e.message}');
      return {
        'success': false,
        'message': e.message ?? 'Connection failed'
      };
    } catch (e) {
      print('❌ Error connecting to USB GNSS: $e');
      return {
        'success': false,
        'message': e.toString()
      };
    }
  }

  /// Disconnect from USB GNSS device
  static Future<Map<String, dynamic>> disconnectUsbGnss() async {
    try {
      print('🔌 Disconnecting from USB GNSS');
      final result = await _channel.invokeMethod('disconnectUsbGnss');
      print('✅ USB GNSS disconnect response: $result');

      if (result is Map) {
        final response = Map<String, dynamic>.from(result);
        return response;
      }
      return {
        'success': false,
        'message': 'Invalid response type'
      };
    } on PlatformException catch (e) {
      print('❌ Error disconnecting from USB GNSS: ${e.message}');
      return {
        'success': false,
        'message': e.message ?? 'Disconnect failed'
      };
    } catch (e) {
      print('❌ Error disconnecting from USB GNSS: $e');
      return {
        'success': false,
        'message': e.toString()
      };
    }
  }

  /// Get USB GNSS status
  static Future<Map<String, dynamic>> getUsbGnssStatus() async {
    try {
      print('🔌 Getting USB GNSS status');
      final result = await _channel.invokeMethod('getUsbGnssStatus');

      if (result is Map) {
        return Map<String, dynamic>.from(result);
      }
      return {
        'usingExternalGnss': false,
        'deviceInfo': 'NONE',
        'vendorId': 0,
        'productId': 0,
        'vendor': 'UNKNOWN',
        'hasL5Band': false,
        'hasL5BandActive': false,
        'connectionActive': false,
      };
    } on PlatformException catch (e) {
      print('❌ Error getting USB GNSS status: ${e.message}');
      return {
        'usingExternalGnss': false,
        'deviceInfo': 'ERROR',
        'message': e.message ?? 'Status check failed'
      };
    } catch (e) {
      print('❌ Error getting USB GNSS status: $e');
      return {
        'usingExternalGnss': false,
        'deviceInfo': 'ERROR',
        'message': e.toString()
      };
    }
  }

  /// Get USB GNSS hardware information
  static Future<Map<String, dynamic>> getUsbGnssHardwareInfo() async {
    try {
      print('🔧 Getting USB GNSS hardware info');
      final result = await _channel.invokeMethod('getUsbGnssHardwareInfo');

      if (result is Map) {
        return Map<String, dynamic>.from(result);
      }
      return {
        'error': 'NO_DEVICE_CONNECTED',
        'message': 'No USB GNSS device connected'
      };
    } on PlatformException catch (e) {
      print('❌ Error getting USB GNSS hardware info: ${e.message}');
      return {
        'error': 'ERROR',
        'message': e.message ?? 'Hardware info failed'
      };
    } catch (e) {
      print('❌ Error getting USB GNSS hardware info: $e');
      return {
        'error': 'ERROR',
        'message': e.toString()
      };
    }
  }

  /// Scan USB GNSS satellites
  static Future<Map<String, dynamic>> scanUsbGnssSatellites() async {
    try {
      print('📡 Scanning USB GNSS satellites');
      final result = await _channel.invokeMethod('scanUsbGnssSatellites');

      if (result is Map) {
        final response = Map<String, dynamic>.from(result);

        // Convert satellites if present
        if (response.containsKey('satellites') && response['satellites'] is List) {
          final satellites = response['satellites'] as List<dynamic>;
          response['gnssSatellites'] = _convertToGnssSatellites(satellites);
        }

        return response;
      }
      return {
        'error': 'SCAN_FAILED',
        'message': 'Invalid response type'
      };
    } on PlatformException catch (e) {
      print('❌ Error scanning USB GNSS satellites: ${e.message}');
      return {
        'error': 'SCAN_FAILED',
        'message': e.message ?? 'Scan failed'
      };
    } catch (e) {
      print('❌ Error scanning USB GNSS satellites: $e');
      return {
        'error': 'SCAN_FAILED',
        'message': e.toString()
      };
    }
  }

  /// Get USB GNSS band information
  static Future<Map<String, dynamic>> getUsbGnssBandInfo() async {
    try {
      print('📶 Getting USB GNSS band info');
      final result = await _channel.invokeMethod('getUsbGnssBandInfo');

      if (result is Map) {
        return Map<String, dynamic>.from(result);
      }
      return {
        'error': 'NO_DEVICE_CONNECTED',
        'message': 'No USB GNSS device connected'
      };
    } on PlatformException catch (e) {
      print('❌ Error getting USB GNSS band info: ${e.message}');
      return {
        'error': 'ERROR',
        'message': e.message ?? 'Band info failed'
      };
    } catch (e) {
      print('❌ Error getting USB GNSS band info: $e');
      return {
        'error': 'ERROR',
        'message': e.toString()
      };
    }
  }

  // ============ PERMISSION METHODS ============

  /// Check location permissions
  static Future<Map<String, dynamic>> checkLocationPermissions() async {
    try {
      print('🔑 Checking location permissions');
      final result = await _channel.invokeMethod('checkLocationPermissions');

      if (result is Map) {
        return Map<String, dynamic>.from(result);
      }
      return {
        'hasFineLocation': false,
        'hasCoarseLocation': false,
        'hasBackgroundLocation': false,
        'allPermissionsGranted': false,
      };
    } on PlatformException catch (e) {
      print('❌ Error checking permissions: ${e.message}');
      return {
        'error': 'PERMISSION_ERROR',
        'message': e.message ?? 'Permission check failed'
      };
    } catch (e) {
      print('❌ Error checking permissions: $e');
      return {
        'error': 'PERMISSION_ERROR',
        'message': e.toString()
      };
    }
  }

  /// Request location permissions
  static Future<Map<String, dynamic>> requestLocationPermissions() async {
    try {
      print('🔑 Requesting location permissions');
      final result = await _channel.invokeMethod('requestLocationPermissions');

      if (result is Map) {
        return Map<String, dynamic>.from(result);
      }
      return {
        'requested': false,
        'message': 'Invalid response type'
      };
    } on PlatformException catch (e) {
      print('❌ Error requesting permissions: ${e.message}');
      return {
        'error': 'PERMISSION_ERROR',
        'message': e.message ?? 'Permission request failed'
      };
    } catch (e) {
      print('❌ Error requesting permissions: $e');
      return {
        'error': 'PERMISSION_ERROR',
        'message': e.toString()
      };
    }
  }

  /// Check if location is enabled
  static Future<Map<String, dynamic>> isLocationEnabled() async {
    try {
      print('📍 Checking if location is enabled');
      final result = await _channel.invokeMethod('isLocationEnabled');

      if (result is Map) {
        return Map<String, dynamic>.from(result);
      }
      return {
        'gpsEnabled': false,
        'networkEnabled': false,
        'fusedEnabled': false,
        'anyEnabled': false,
      };
    } on PlatformException catch (e) {
      print('❌ Error checking location status: ${e.message}');
      return {
        'error': 'LOCATION_ERROR',
        'message': e.message ?? 'Location status check failed'
      };
    } catch (e) {
      print('❌ Error checking location status: $e');
      return {
        'error': 'LOCATION_ERROR',
        'message': e.toString()
      };
    }
  }

  // ============ LOCATION METHODS ============

  /// Start location updates
  static Future<Map<String, dynamic>> startLocationUpdates() async {
    try {
      print('📍 Starting location updates');
      final result = await _channel.invokeMethod('startLocationUpdates');

      if (result is Map) {
        return Map<String, dynamic>.from(result);
      }
      return {
        'success': false,
        'message': 'Invalid response type'
      };
    } on PlatformException catch (e) {
      print('❌ Error starting location updates: ${e.message}');
      return {
        'success': false,
        'message': e.message ?? 'Failed to start location updates'
      };
    } catch (e) {
      print('❌ Error starting location updates: $e');
      return {
        'success': false,
        'message': e.toString()
      };
    }
  }

  /// Stop location updates
  static Future<Map<String, dynamic>> stopLocationUpdates() async {
    try {
      print('📍 Stopping location updates');
      final result = await _channel.invokeMethod('stopLocationUpdates');

      if (result is Map) {
        return Map<String, dynamic>.from(result);
      }
      return {
        'success': false,
        'message': 'Invalid response type'
      };
    } on PlatformException catch (e) {
      print('❌ Error stopping location updates: ${e.message}');
      return {
        'success': false,
        'message': e.message ?? 'Failed to stop location updates'
      };
    } catch (e) {
      print('❌ Error stopping location updates: $e');
      return {
        'success': false,
        'message': e.toString()
      };
    }
  }

  // ============ SATELLITE METHODS ============

  /// Get all satellites
  static Future<Map<String, dynamic>> getAllSatellites() async {
    try {
      print('🛰️ Getting all satellites');
      final result = await _channel.invokeMethod('getAllSatellites');

      if (result is Map) {
        final response = Map<String, dynamic>.from(result);

        // Convert satellites if present
        if (response.containsKey('satellites') && response['satellites'] is List) {
          final satellites = response['satellites'] as List<dynamic>;
          response['gnssSatellites'] = _convertToGnssSatellites(satellites);
        }

        return response;
      }
      return {
        'error': 'NO_SATELLITES',
        'message': 'Invalid response type'
      };
    } on PlatformException catch (e) {
      print('❌ Error getting all satellites: ${e.message}');
      return {
        'error': 'SATELLITE_ERROR',
        'message': e.message ?? 'Failed to get satellites'
      };
    } catch (e) {
      print('❌ Error getting all satellites: $e');
      return {
        'error': 'SATELLITE_ERROR',
        'message': e.toString()
      };
    }
  }

  /// Get all satellites in range
  static Future<Map<String, dynamic>> getAllSatellitesInRange() async {
    try {
      print('🛰️ Getting all satellites in range');
      final result = await _channel.invokeMethod('getAllSatellitesInRange');

      if (result is Map) {
        final response = Map<String, dynamic>.from(result);

        // Convert satellites if present
        if (response.containsKey('satellites') && response['satellites'] is List) {
          final satellites = response['satellites'] as List<dynamic>;
          response['gnssSatellites'] = _convertToGnssSatellites(satellites);
        }

        return response;
      }
      return {
        'error': 'NO_SATELLITES',
        'message': 'Invalid response type'
      };
    } on PlatformException catch (e) {
      print('❌ Error getting satellites in range: ${e.message}');
      return {
        'error': 'SATELLITE_ERROR',
        'message': e.message ?? 'Failed to get satellites in range'
      };
    } catch (e) {
      print('❌ Error getting satellites in range: $e');
      return {
        'error': 'SATELLITE_ERROR',
        'message': e.toString()
      };
    }
  }

  /// Get GNSS range statistics
  static Future<Map<String, dynamic>> getGnssRangeStatistics() async {
    try {
      print('📊 Getting GNSS range statistics');
      final result = await _channel.invokeMethod('getGnssRangeStatistics');

      if (result is Map) {
        return Map<String, dynamic>.from(result);
      }
      return {
        'error': 'NO_STATISTICS',
        'message': 'Invalid response type'
      };
    } on PlatformException catch (e) {
      print('❌ Error getting GNSS range statistics: ${e.message}');
      return {
        'error': 'STATISTICS_ERROR',
        'message': e.message ?? 'Failed to get statistics'
      };
    } catch (e) {
      print('❌ Error getting GNSS range statistics: $e');
      return {
        'error': 'STATISTICS_ERROR',
        'message': e.toString()
      };
    }
  }

  // ============ CALLBACK SETTERS ============

  static void setPermissionResultCallback(Function(Map<String, dynamic>) callback) {
    _permissionResultCallback = callback;
  }

  static void removePermissionResultCallback() {
    _permissionResultCallback = null;
  }

  static void setLocationUpdateCallback(Function(Map<String, dynamic>) callback) {
    _locationUpdateCallback = callback;
  }

  static void removeLocationUpdateCallback() {
    _locationUpdateCallback = null;
  }

  static void setExternalGnssStatusCallback(Function(Map<String, dynamic>) callback) {
    _externalGnssStatusCallback = callback;
  }

  static void removeExternalGnssStatusCallback() {
    _externalGnssStatusCallback = null;
  }

  // ============ CLEANUP ============

  static void dispose() {
    // Remove callbacks
    removePermissionResultCallback();
    removeLocationUpdateCallback();
    removeExternalGnssStatusCallback();

    _isInitialized = false;
    print('🧹 NavicHardwareService disposed');
  }
}