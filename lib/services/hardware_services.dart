// lib/services/hardware_services.dart
import 'dart:async';
//import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:navic_ss/models/gnss_satellite.dart';

// ============ HELPER FUNCTIONS ============

int _parseInt(dynamic value) {
  if (value == null) return 0;
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? 0;
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

List<Map<String, dynamic>> _convertJavaSatelliteList(List<dynamic> javaList) {
  final List<Map<String, dynamic>> converted = [];

  for (final item in javaList) {
    if (item is Map) {
      try {
        final Map<String, dynamic> sat = {};

        for (final entry in item.entries) {
          final key = entry.key.toString();
          final value = entry.value;

          // Convert Java types to Dart types
          if (value == null) {
            sat[key] = null;
          } else if (value is num) {
            sat[key] = value.toDouble();
          } else if (value is bool) {
            sat[key] = value;
          } else if (value is String) {
            sat[key] = value;
          } else if (value is List) {
            sat[key] = _convertJavaList(value);
          } else if (value is Map) {
            sat[key] = _convertJavaMap(value);
          } else {
            sat[key] = value.toString();
          }
        }

        converted.add(sat);
      } catch (e) {
        print('⚠️ Error converting satellite map: $e');
      }
    }
  }

  return converted;
}

// ============ DATA CLASSES ============

class NavicDetectionResult {
  final bool isSupported;
  final bool isActive;
  final int satelliteCount;
  final int totalSatellites;
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

  List<GnssSatellite> get gnssSatellites => _convertToGnssSatellites(allSatellites);

  const NavicDetectionResult({
    required this.isSupported,
    required this.isActive,
    required this.satelliteCount,
    required this.totalSatellites,
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
  });

  factory NavicDetectionResult.fromMap(Map<String, dynamic> map) {
    try {
      return NavicDetectionResult(
        isSupported: _parseBool(map['isSupported']),
        isActive: _parseBool(map['isActive']),
        satelliteCount: _parseInt(map['navicSatellites'] ?? map['satelliteCount'] ?? 0), // FIX: Changed field name
        totalSatellites: _parseInt(map['totalSatellites'] ?? map['satelliteCount'] ?? 0),
        usedInFixCount: _parseInt(map['navicUsedInFix'] ?? map['usedInFixCount'] ?? 0), // FIX: Changed field name
        detectionMethod: _parseString(map['detectionMethod']),
        hasL5Band: _parseBool(map['hasL5Band']),
        hasL5BandActive: _parseBool(map['hasL5BandActive'] ?? false),
        chipsetType: _parseString(map['chipsetType'] ?? 'UNKNOWN'),
        chipsetVendor: _parseString(map['chipsetVendor'] ?? 'UNKNOWN'),
        chipsetModel: _parseString(map['chipsetModel'] ?? 'UNKNOWN'),
        usingExternalGnss: _parseBool(map['usingExternalGnss'] ?? false),
        externalDeviceInfo: _parseString(map['externalDeviceInfo'] ?? map['externalGnssInfo'] ?? 'NONE'), // FIX: Field name
        allSatellites: _convertJavaList(map['allSatellites'] ?? []),
        message: map['message'] as String?,
      );
    } catch (e) {
      print('❌ Error creating NavicDetectionResult: $e');
      return NavicDetectionResult(
        isSupported: false,
        isActive: false,
        satelliteCount: 0,
        totalSatellites: 0,
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
      'satelliteCount': satelliteCount,
      'totalSatellites': totalSatellites,
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
    };
  }

  @override
  String toString() {
    return 'NavicDetectionResult('
        'isSupported: $isSupported, '
        'isActive: $isActive, '
        'satelliteCount: $satelliteCount, '
        'hasL5Band: $hasL5Band, '
        'hasL5BandActive: $hasL5BandActive, '
        'chipset: $chipsetVendor $chipsetModel, '
        'external: $usingExternalGnss)';
  }
}

class PermissionResult {
  final bool granted;
  final String message;
  final Map<String, bool>? permissions;

  const PermissionResult({
    required this.granted,
    required this.message,
    this.permissions,
  });

  factory PermissionResult.fromMap(Map<String, dynamic> map) {
    return PermissionResult(
      granted: _parseBool(map['granted']),
      message: _parseString(map['message']),
      permissions: map['permissions'] as Map<String, bool>?,
    );
  }

  @override
  String toString() {
    return 'PermissionResult(granted: $granted, message: $message)';
  }
}

// ============ NAVIC HARDWARE SERVICE ============

class NavicHardwareService {
  static const MethodChannel _channel = MethodChannel('navic_support');

  // Callback handlers
  static Function(Map<String, dynamic>)? _permissionResultCallback;
  static Function(Map<String, dynamic>)? _satelliteUpdateCallback;
  static Function(Map<String, dynamic>)? _locationUpdateCallback;
  static Function(Map<String, dynamic>)? _satelliteMonitorCallback;
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
        case 'onSatelliteUpdate':
          if (call.arguments is Map) {
            final data = call.arguments as Map<String, dynamic>;
            print('🛰️ Satellite update received');
            _satelliteUpdateCallback?.call(data);
          }
          break;
        case 'onLocationUpdate':
          if (call.arguments is Map) {
            final data = call.arguments as Map<String, dynamic>;
            print('📍 Location update received');
            _locationUpdateCallback?.call(data);
          }
          break;
        case 'onSatelliteMonitorUpdate':
          if (call.arguments is Map) {
            final data = call.arguments as Map<String, dynamic>;
            print('📡 Satellite monitor update received');
            _satelliteMonitorCallback?.call(data);
          }
          break;
        case 'onExternalGnssStatus':
          if (call.arguments is Map) {
            final data = call.arguments as Map<String, dynamic>;
            print('🔌 External GNSS status update received');
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
      satelliteCount: 0,
      totalSatellites: 0,
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
      final result = await _channel.invokeMethod('checkUsbGnssDevices');
      if (result is Map) {
        return Map<String, dynamic>.from(result);
      }
      return {
        'success': false,
        'usbDevices': [],
        'deviceCount': 0,
        'usingExternalGnss': false,
        'externalGnssInfo': 'NONE',
        'message': 'Invalid response type'
      };
    } on PlatformException catch (e) {
      print('Error checking USB GNSS devices: ${e.message}');
      return {
        'success': false,
        'usbDevices': [],
        'deviceCount': 0,
        'message': e.message
      };
    } catch (e) {
      print('Error checking USB GNSS devices: $e');
      return {
        'success': false,
        'usbDevices': [],
        'deviceCount': 0,
        'message': e.toString()
      };
    }
  }

  /// Connect to USB GNSS device
  static Future<Map<String, dynamic>> connectToUsbGnss() async {
    try {
      final result = await _channel.invokeMethod('connectToUsbGnss');
      if (result is Map) {
        return Map<String, dynamic>.from(result);
      }
      return {
        'success': false,
        'message': 'Invalid response type'
      };
    } on PlatformException catch (e) {
      print('Error connecting to USB GNSS: ${e.message}');
      return {
        'success': false,
        'message': e.message ?? 'Connection failed'
      };
    } catch (e) {
      print('Error connecting to USB GNSS: $e');
      return {
        'success': false,
        'message': e.toString()
      };
    }
  }

  /// Disconnect from USB GNSS device
  static Future<Map<String, dynamic>> disconnectUsbGnss() async {
    try {
      final result = await _channel.invokeMethod('disconnectUsbGnss');
      if (result is Map) {
        return Map<String, dynamic>.from(result);
      }
      return {
        'success': false,
        'message': 'Invalid response type'
      };
    } on PlatformException catch (e) {
      print('Error disconnecting from USB GNSS: ${e.message}');
      return {
        'success': false,
        'message': e.message ?? 'Disconnect failed'
      };
    } catch (e) {
      print('Error disconnecting from USB GNSS: $e');
      return {
        'success': false,
        'message': e.toString()
      };
    }
  }

  /// Get USB GNSS status
  static Future<Map<String, dynamic>> getUsbGnssStatus() async {
    try {
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
      print('Error getting USB GNSS status: ${e.message}');
      return {
        'usingExternalGnss': false,
        'deviceInfo': 'ERROR',
        'message': e.message
      };
    } catch (e) {
      print('Error getting USB GNSS status: $e');
      return {
        'usingExternalGnss': false,
        'deviceInfo': 'ERROR',
        'message': e.toString()
      };
    }
  }

  /// Force external GNSS mode (for testing)
  static Future<Map<String, dynamic>> forceExternalGnssMode(bool enable) async {
    try {
      final result = await _channel.invokeMethod('forceExternalGnssMode', enable);
      if (result is Map) {
        return Map<String, dynamic>.from(result);
      }
      return {
        'success': false,
        'message': 'Invalid response type'
      };
    } on PlatformException catch (e) {
      print('Error forcing external GNSS mode: ${e.message}');
      return {
        'success': false,
        'message': e.message ?? 'Failed to change mode'
      };
    } catch (e) {
      print('Error forcing external GNSS mode: $e');
      return {
        'success': false,
        'message': e.toString()
      };
    }
  }

  // ============ PERMISSION METHODS ============

  /// Check location permissions
  static Future<Map<String, dynamic>> checkLocationPermissions() async {
    try {
      final result = await _channel.invokeMethod('checkLocationPermissions');
      if (result is Map) {
        return Map<String, dynamic>.from(result);
      }
      return {
        'hasFineLocation': false,
        'hasCoarseLocation': false,
        'hasBackgroundLocation': false,
        'allPermissionsGranted': false
      };
    } on PlatformException catch (e) {
      print('Error checking permissions: ${e.message}');
      return {
        'hasFineLocation': false,
        'hasCoarseLocation': false,
        'hasBackgroundLocation': false,
        'allPermissionsGranted': false,
        'message': e.message
      };
    } catch (e) {
      print('Error checking permissions: $e');
      return {
        'hasFineLocation': false,
        'hasCoarseLocation': false,
        'hasBackgroundLocation': false,
        'allPermissionsGranted': false,
        'message': e.toString()
      };
    }
  }

  /// Request location permissions
  static Future<Map<String, dynamic>> requestLocationPermissions() async {
    try {
      final result = await _channel.invokeMethod('requestLocationPermissions');
      if (result is Map) {
        return Map<String, dynamic>.from(result);
      }
      return {'requested': false, 'message': 'Invalid response type'};
    } on PlatformException catch (e) {
      print('Error requesting permissions: ${e.message}');
      return {'requested': false, 'message': e.message ?? 'Request failed'};
    } catch (e) {
      print('Error requesting permissions: $e');
      return {'requested': false, 'message': 'Unknown error: $e'};
    }
  }

  // ============ REAL-TIME MONITORING ============

  /// Start real-time detection
  static Future<Map<String, dynamic>> startRealTimeDetection() async {
    try {
      final result = await _channel.invokeMethod('startRealTimeDetection');
      if (result is Map) {
        return Map<String, dynamic>.from(result);
      }
      return {'success': false, 'message': 'Invalid response type'};
    } on PlatformException catch (e) {
      print('Error starting real-time detection: ${e.message}');
      return {'success': false, 'message': 'Failed to start: ${e.message}'};
    } catch (e) {
      print('Error starting real-time detection: $e');
      return {'success': false, 'message': 'Failed to start: $e'};
    }
  }

  /// Stop real-time detection
  static Future<Map<String, dynamic>> stopRealTimeDetection() async {
    try {
      final result = await _channel.invokeMethod('stopRealTimeDetection');
      if (result is Map) {
        return Map<String, dynamic>.from(result);
      }
      return {'success': false, 'message': 'Invalid response type'};
    } on PlatformException catch (e) {
      print('Error stopping real-time detection: ${e.message}');
      return {'success': false, 'message': 'Failed to stop: ${e.message}'};
    } catch (e) {
      print('Error stopping real-time detection: $e');
      return {'success': false, 'message': 'Failed to stop: $e'};
    }
  }

  // ============ LOCATION UPDATES ============

  /// Start location updates
  static Future<Map<String, dynamic>> startLocationUpdates() async {
    try {
      final result = await _channel.invokeMethod('startLocationUpdates');
      if (result is Map) {
        return Map<String, dynamic>.from(result);
      }
      return {'success': false, 'message': 'Invalid response type'};
    } on PlatformException catch (e) {
      print('Error starting location updates: ${e.message}');
      return {'success': false, 'message': e.message ?? 'Failed to start updates'};
    } catch (e) {
      print('Error starting location updates: $e');
      return {'success': false, 'message': 'Failed to start updates: $e'};
    }
  }

  /// Stop location updates
  static Future<Map<String, dynamic>> stopLocationUpdates() async {
    try {
      final result = await _channel.invokeMethod('stopLocationUpdates');
      if (result is Map) {
        return Map<String, dynamic>.from(result);
      }
      return {'success': false, 'message': 'Invalid response type'};
    } on PlatformException catch (e) {
      print('Error stopping location updates: ${e.message}');
      return {'success': false, 'message': e.message ?? 'Failed to stop updates'};
    } catch (e) {
      print('Error stopping location updates: $e');
      return {'success': false, 'message': 'Failed to stop updates: $e'};
    }
  }

  // ============ SATELLITE MONITORING ============

  /// Start satellite monitoring
  static Future<Map<String, dynamic>> startSatelliteMonitoring() async {
    try {
      final result = await _channel.invokeMethod('startSatelliteMonitoring');
      if (result is Map) {
        return Map<String, dynamic>.from(result);
      }
      return {'success': false, 'message': 'Invalid response type'};
    } on PlatformException catch (e) {
      print('Error starting satellite monitoring: ${e.message}');
      return {'success': false, 'message': 'Failed to start: ${e.message}'};
    } catch (e) {
      print('Error starting satellite monitoring: $e');
      return {'success': false, 'message': 'Failed to start: $e'};
    }
  }

  /// Stop satellite monitoring
  static Future<Map<String, dynamic>> stopSatelliteMonitoring() async {
    try {
      final result = await _channel.invokeMethod('stopSatelliteMonitoring');
      if (result is Map) {
        return Map<String, dynamic>.from(result);
      }
      return {'success': false, 'message': 'Invalid response type'};
    } on PlatformException catch (e) {
      print('Error stopping satellite monitoring: ${e.message}');
      return {'success': false, 'message': 'Failed to stop: ${e.message}'};
    } catch (e) {
      print('Error stopping satellite monitoring: $e');
      return {'success': false, 'message': 'Failed to stop: $e'};
    }
  }

  // ============ SATELLITE DATA METHODS ============

  /// Get all satellites
  static Future<Map<String, dynamic>> getAllSatellites() async {
    try {
      final result = await _channel.invokeMethod('getAllSatellites');
      if (result is Map) {
        final data = Map<String, dynamic>.from(result);

        // Convert satellites to GnssSatellite objects
        if (data.containsKey('satellites') && data['satellites'] is List) {
          final satellites = data['satellites'] as List<dynamic>;
          final gnssSatellites = _convertToGnssSatellites(satellites);
          data['gnssSatellites'] = gnssSatellites;
        }

        return data;
      }
      return {'hasData': false, 'satellites': [], 'message': 'Invalid response type'};
    } on PlatformException catch (e) {
      print('Error getting all satellites: ${e.message}');
      return {'hasData': false, 'satellites': [], 'message': e.message};
    } catch (e) {
      print('Error getting all satellites: $e');
      return {'hasData': false, 'satellites': [], 'message': e.toString()};
    }
  }

  /// Get all satellites in range
  static Future<Map<String, dynamic>> getAllSatellitesInRange() async {
    try {
      final result = await _channel.invokeMethod('getAllSatellitesInRange');
      if (result is Map) {
        final data = Map<String, dynamic>.from(result);

        // Convert satellites list to proper format
        if (data.containsKey('satellites') && data['satellites'] is List) {
          final satellites = data['satellites'] as List<dynamic>;
          // Keep both formats for compatibility
          data['satellites'] = _convertJavaSatelliteList(satellites);
          data['gnssSatellites'] = _convertToGnssSatellites(satellites);
        }

        return data;
      }
      return {'hasData': false, 'satellites': [], 'message': 'Invalid response type'};
    } on PlatformException catch (e) {
      print('Error getting satellites in range: ${e.message}');
      return {'hasData': false, 'satellites': [], 'message': e.message};
    } catch (e) {
      print('Error getting satellites in range: $e');
      return {'hasData': false, 'satellites': [], 'message': e.toString()};
    }
  }

  // ============ GNSS CAPABILITIES ============

  /// Get GNSS capabilities
  static Future<Map<String, dynamic>> getGnssCapabilities() async {
    try {
      final result = await _channel.invokeMethod('getGnssCapabilities');
      if (result is Map) {
        return Map<String, dynamic>.from(result);
      }
      return {};
    } on PlatformException catch (e) {
      print('Error getting GNSS capabilities: ${e.message}');
      return {};
    } catch (e) {
      print('Error getting GNSS capabilities: $e');
      return {};
    }
  }

  // ============ SYSTEM INFORMATION ============

  /// Get device info
  static Future<Map<String, dynamic>> getDeviceInfo() async {
    try {
      final result = await _channel.invokeMethod('getDeviceInfo');
      if (result is Map) {
        return Map<String, dynamic>.from(result);
      }
      return {};
    } on PlatformException catch (e) {
      print('Error getting device info: ${e.message}');
      return {};
    } catch (e) {
      print('Error getting device info: $e');
      return {};
    }
  }

  /// Check if location is enabled
  static Future<Map<String, dynamic>> isLocationEnabled() async {
    try {
      final result = await _channel.invokeMethod('isLocationEnabled');
      if (result is Map) {
        return Map<String, dynamic>.from(result);
      }
      return {};
    } on PlatformException catch (e) {
      print('Error checking location status: ${e.message}');
      return {};
    } catch (e) {
      print('Error checking location status: $e');
      return {};
    }
  }

  // ============ SETTINGS ============

  /// Open location settings
  static Future<bool> openLocationSettings() async {
    try {
      final result = await _channel.invokeMethod('openLocationSettings');
      if (result is Map) {
        final data = Map<String, dynamic>.from(result);
        return data['success'] as bool? ?? false;
      }
      return false;
    } on PlatformException catch (e) {
      print('Error opening location settings: ${e.message}');
      return false;
    } catch (e) {
      print('Error opening location settings: $e');
      return false;
    }
  }

  // ============ CALLBACK SETUP METHODS ============

  /// Set permission result callback
  static void setPermissionResultCallback(Function(Map<String, dynamic>) callback) {
    print('🔑 Setting permission result callback');
    _permissionResultCallback = callback;
  }

  static void removePermissionResultCallback() {
    print('🔑 Removing permission result callback');
    _permissionResultCallback = null;
  }

  /// Set satellite update callback
  static void setSatelliteUpdateCallback(Function(Map<String, dynamic>) callback) {
    print('🛰️ Setting satellite update callback');
    _satelliteUpdateCallback = callback;
  }

  static void removeSatelliteUpdateCallback() {
    print('🛰️ Removing satellite update callback');
    _satelliteUpdateCallback = null;
  }

  /// Set location update callback
  static void setLocationUpdateCallback(Function(Map<String, dynamic>) callback) {
    print('📍 Setting location update callback');
    _locationUpdateCallback = callback;
  }

  static void removeLocationUpdateCallback() {
    print('📍 Removing location update callback');
    _locationUpdateCallback = null;
  }

  /// Set satellite monitor callback
  static void setSatelliteMonitorCallback(Function(Map<String, dynamic>) callback) {
    print('📡 Setting satellite monitor callback');
    _satelliteMonitorCallback = callback;
  }

  static void removeSatelliteMonitorCallback() {
    print('📡 Removing satellite monitor callback');
    _satelliteMonitorCallback = null;
  }

  /// Set external GNSS status callback
  static void setExternalGnssStatusCallback(Function(Map<String, dynamic>) callback) {
    print('🔌 Setting external GNSS status callback');
    _externalGnssStatusCallback = callback;
  }

  static void removeExternalGnssStatusCallback() {
    print('🔌 Removing external GNSS status callback');
    _externalGnssStatusCallback = null;
  }

  // ============ UTILITY METHODS ============

  /// Test method to verify channel communication
  static Future<bool> testChannelConnection() async {
    try {
      await _channel.invokeMethod('checkNavicHardware');
      print('✅ Channel connection test successful');
      return true;
    } catch (e) {
      print('❌ Channel connection test failed: $e');
      return false;
    }
  }

  /// Clean up all resources
  static void dispose() {
    removePermissionResultCallback();
    removeSatelliteUpdateCallback();
    removeLocationUpdateCallback();
    removeSatelliteMonitorCallback();
    removeExternalGnssStatusCallback();
    _isInitialized = false;
    print('🧹 NavicHardwareService disposed');
  }

  /// Get method channel name (for debugging)
  static String get channelName => 'navic_support';
}