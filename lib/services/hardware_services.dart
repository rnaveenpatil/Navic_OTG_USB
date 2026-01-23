// lib/services/hardware_services.dart
import 'dart:async';
import 'dart:convert';
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

List<String> _convertJavaStringList(dynamic value) {
  if (value == null) return [];
  if (value is List) {
    try {
      return List<String>.from(value.whereType<String>());
    } catch (e) {
      print('⚠️ Error converting Java string list: $e');
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

// ============ BAND DETECTION DATA CLASSES ============

class GnssFrequencyInfo {
  final String bandName;
  final double frequencyHz;
  final double toleranceHz;
  final bool isAvailable;
  final bool isActive;
  final int satelliteCount;
  final double averageSignal;
  final List<String> supportedSystems;

  const GnssFrequencyInfo({
    required this.bandName,
    required this.frequencyHz,
    required this.toleranceHz,
    required this.isAvailable,
    required this.isActive,
    required this.satelliteCount,
    required this.averageSignal,
    required this.supportedSystems,
  });

  factory GnssFrequencyInfo.fromMap(Map<String, dynamic> map) {
    return GnssFrequencyInfo(
      bandName: _parseString(map['bandName']),
      frequencyHz: _parseDouble(map['frequencyHz']),
      toleranceHz: _parseDouble(map['toleranceHz']),
      isAvailable: _parseBool(map['isAvailable']),
      isActive: _parseBool(map['isActive']),
      satelliteCount: _parseInt(map['satelliteCount']),
      averageSignal: _parseDouble(map['averageSignal']),
      supportedSystems: _convertJavaStringList(map['supportedSystems']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'bandName': bandName,
      'frequencyHz': frequencyHz,
      'toleranceHz': toleranceHz,
      'isAvailable': isAvailable,
      'isActive': isActive,
      'satelliteCount': satelliteCount,
      'averageSignal': averageSignal,
      'supportedSystems': supportedSystems,
    };
  }
}

class BandDetectionResult {
  final Map<String, GnssFrequencyInfo> availableBands;
  final Map<String, List<String>> systemBands;
  final List<String> activeBands;
  final List<String> supportedBands;
  final Map<String, int> bandSatelliteCounts;
  final Map<String, double> bandAverageSignals;
  final bool hasL5Band;
  final bool hasL5BandActive;
  final bool hasL1Band;
  final bool hasL2Band;
  final bool hasSBand;
  final double l5Confidence;
  final List<String> detectionMethods;
  final List<String> verificationDetails;

  const BandDetectionResult({
    required this.availableBands,
    required this.systemBands,
    required this.activeBands,
    required this.supportedBands,
    required this.bandSatelliteCounts,
    required this.bandAverageSignals,
    required this.hasL5Band,
    required this.hasL5BandActive,
    required this.hasL1Band,
    required this.hasL2Band,
    required this.hasSBand,
    required this.l5Confidence,
    required this.detectionMethods,
    required this.verificationDetails,
  });

  factory BandDetectionResult.fromMap(Map<String, dynamic> map) {
    // Parse available bands
    final Map<String, GnssFrequencyInfo> availableBands = {};
    if (map['availableBands'] is Map) {
      final bandsMap = _convertJavaMap(map['availableBands']);
      for (final entry in bandsMap.entries) {
        if (entry.value is Map) {
          availableBands[entry.key] = GnssFrequencyInfo.fromMap(
            Map<String, dynamic>.from(entry.value),
          );
        }
      }
    }

    // Parse system bands
    final Map<String, List<String>> systemBands = {};
    if (map['systemBands'] is Map) {
      final systemMap = _convertJavaMap(map['systemBands']);
      for (final entry in systemMap.entries) {
        if (entry.value is List) {
          systemBands[entry.key] = _convertJavaStringList(entry.value);
        }
      }
    }

    return BandDetectionResult(
      availableBands: availableBands,
      systemBands: systemBands,
      activeBands: _convertJavaStringList(map['activeBands']),
      supportedBands: _convertJavaStringList(map['supportedBands']),
      bandSatelliteCounts: Map<String, int>.from(
        _convertJavaMap(map['bandSatelliteCounts']).map(
          (key, value) => MapEntry(key, _parseInt(value)),
        ),
      ),
      bandAverageSignals: Map<String, double>.from(
        _convertJavaMap(map['bandAverageSignals']).map(
          (key, value) => MapEntry(key, _parseDouble(value)),
        ),
      ),
      hasL5Band: _parseBool(map['hasL5Band']),
      hasL5BandActive: _parseBool(map['hasL5BandActive']),
      hasL1Band: _parseBool(map['hasL1Band']),
      hasL2Band: _parseBool(map['hasL2Band']),
      hasSBand: _parseBool(map['hasSBand']),
      l5Confidence: _parseDouble(map['l5Confidence']),
      detectionMethods: _convertJavaStringList(map['detectionMethods']),
      verificationDetails: _convertJavaStringList(map['verificationDetails']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'availableBands': availableBands.map((key, value) => MapEntry(key, value.toMap())),
      'systemBands': systemBands,
      'activeBands': activeBands,
      'supportedBands': supportedBands,
      'bandSatelliteCounts': bandSatelliteCounts,
      'bandAverageSignals': bandAverageSignals,
      'hasL5Band': hasL5Band,
      'hasL5BandActive': hasL5BandActive,
      'hasL1Band': hasL1Band,
      'hasL2Band': hasL2Band,
      'hasSBand': hasSBand,
      'l5Confidence': l5Confidence,
      'detectionMethods': detectionMethods,
      'verificationDetails': verificationDetails,
    };
  }
}

// ============ DATA CLASSES ============

class NavicDetectionResult {
  final bool isSupported;
  final bool isActive;
  final int satelliteCount;
  final int totalSatellites;
  final int usedInFixCount;
  final String detectionMethod;
  final double confidenceLevel;
  final double averageSignalStrength;
  final String chipsetType;
  final String chipsetVendor;
  final String chipsetModel;
  final bool hasL5Band;
  final bool hasL5BandActive;
  final bool hasL1Band;
  final bool hasL2Band;
  final bool hasSBand;
  final String positioningMethod;
  final String primarySystem;
  final Map<String, dynamic> l5BandInfo;
  final Map<String, dynamic> bandInfo;
  final BandDetectionResult bandDetectionResult;
  final List<dynamic> allSatellites;
  final String? message;
  final List<String> verificationMethods;
  final double acquisitionTimeMs;
  final List<dynamic> satelliteDetails;
  final double l5Confidence;
  final double chipsetConfidence;

  // NEW: Added GnssSatellite lists
  List<GnssSatellite> get gnssSatellites => _convertToGnssSatellites(allSatellites);
  List<GnssSatellite> get gnssSatelliteDetails => _convertToGnssSatellites(satelliteDetails);

  const NavicDetectionResult({
    required this.isSupported,
    required this.isActive,
    required this.satelliteCount,
    required this.totalSatellites,
    required this.usedInFixCount,
    required this.detectionMethod,
    required this.confidenceLevel,
    required this.averageSignalStrength,
    required this.chipsetType,
    required this.chipsetVendor,
    required this.chipsetModel,
    required this.hasL5Band,
    required this.hasL5BandActive,
    required this.hasL1Band,
    required this.hasL2Band,
    required this.hasSBand,
    required this.positioningMethod,
    required this.primarySystem,
    required this.l5BandInfo,
    required this.bandInfo,
    required this.bandDetectionResult,
    required this.allSatellites,
    this.message,
    this.verificationMethods = const [],
    this.acquisitionTimeMs = 0.0,
    this.satelliteDetails = const [],
    this.l5Confidence = 0.0,
    this.chipsetConfidence = 0.0,
  });

  factory NavicDetectionResult.fromMap(Map<String, dynamic> map) {
    try {
      // Extract band detection result
      final bandDetectionResult = map.containsKey('bandDetectionResult')
          ? BandDetectionResult.fromMap(
              Map<String, dynamic>.from(map['bandDetectionResult']),
            )
          : BandDetectionResult(
              availableBands: {},
              systemBands: {},
              activeBands: [],
              supportedBands: [],
              bandSatelliteCounts: {},
              bandAverageSignals: {},
              hasL5Band: false,
              hasL5BandActive: false,
              hasL1Band: false,
              hasL2Band: false,
              hasSBand: false,
              l5Confidence: 0.0,
              detectionMethods: [],
              verificationDetails: [],
            );

      // Handle Java Object types properly
      return NavicDetectionResult(
        isSupported: _parseBool(map['isSupported']),
        isActive: _parseBool(map['isActive']),
        satelliteCount: _parseInt(map['satelliteCount']),
        totalSatellites: _parseInt(map['totalSatellites']),
        usedInFixCount: _parseInt(map['usedInFixCount']),
        detectionMethod: _parseString(map['detectionMethod']),
        confidenceLevel: _parseDouble(map['confidenceLevel']),
        averageSignalStrength: _parseDouble(map['averageSignalStrength']),
        chipsetType: _parseString(map['chipsetType']),
        chipsetVendor: _parseString(map['chipsetVendor']),
        chipsetModel: _parseString(map['chipsetModel']),
        hasL5Band: _parseBool(map['hasL5Band']),
        hasL5BandActive: _parseBool(map['hasL5BandActive'] ?? false),
        hasL1Band: _parseBool(map['hasL1Band'] ?? bandDetectionResult.hasL1Band),
        hasL2Band: _parseBool(map['hasL2Band'] ?? bandDetectionResult.hasL2Band),
        hasSBand: _parseBool(map['hasSBand'] ?? bandDetectionResult.hasSBand),
        positioningMethod: _parseString(map['positioningMethod']),
        primarySystem: _parseString(map['primarySystem']),
        l5BandInfo: _convertJavaMap(map['l5BandInfo']),
        bandInfo: _convertJavaMap(map['bandInfo'] ?? {}),
        bandDetectionResult: bandDetectionResult,
        allSatellites: _convertJavaList(map['allSatellites']),
        message: map['message'] as String?,
        verificationMethods: _convertJavaStringList(map['verificationMethods']),
        acquisitionTimeMs: _parseDouble(map['acquisitionTimeMs']),
        satelliteDetails: _convertJavaList(map['satelliteDetails']),
        l5Confidence: _parseDouble(map['l5Confidence'] ?? 0.0),
        chipsetConfidence: _parseDouble(map['chipsetConfidence'] ?? 0.0),
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
        confidenceLevel: 0.0,
        averageSignalStrength: 0.0,
        chipsetType: 'ERROR',
        chipsetVendor: 'ERROR',
        chipsetModel: 'ERROR',
        hasL5Band: false,
        hasL5BandActive: false,
        hasL1Band: false,
        hasL2Band: false,
        hasSBand: false,
        positioningMethod: 'ERROR',
        primarySystem: 'GPS',
        l5BandInfo: {},
        bandInfo: {},
        bandDetectionResult: BandDetectionResult(
          availableBands: {},
          systemBands: {},
          activeBands: [],
          supportedBands: [],
          bandSatelliteCounts: {},
          bandAverageSignals: {},
          hasL5Band: false,
          hasL5BandActive: false,
          hasL1Band: false,
          hasL2Band: false,
          hasSBand: false,
          l5Confidence: 0.0,
          detectionMethods: [],
          verificationDetails: [],
        ),
        allSatellites: [],
        message: 'Error: $e',
        l5Confidence: 0.0,
        chipsetConfidence: 0.0,
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
      'confidenceLevel': confidenceLevel,
      'averageSignalStrength': averageSignalStrength,
      'chipsetType': chipsetType,
      'chipsetVendor': chipsetVendor,
      'chipsetModel': chipsetModel,
      'hasL5Band': hasL5Band,
      'hasL5BandActive': hasL5BandActive,
      'hasL1Band': hasL1Band,
      'hasL2Band': hasL2Band,
      'hasSBand': hasSBand,
      'positioningMethod': positioningMethod,
      'primarySystem': primarySystem,
      'l5BandInfo': l5BandInfo,
      'bandInfo': bandInfo,
      'bandDetectionResult': bandDetectionResult.toMap(),
      'allSatellites': allSatellites,
      'message': message,
      'verificationMethods': verificationMethods,
      'acquisitionTimeMs': acquisitionTimeMs,
      'satelliteDetails': satelliteDetails,
      'l5Confidence': l5Confidence,
      'chipsetConfidence': chipsetConfidence,
    };
  }

  @override
  String toString() {
    return 'NavicDetectionResult(isSupported: $isSupported, isActive: $isActive, '
        'satelliteCount: $satelliteCount, totalSatellites: $totalSatellites, '
        'hasL5Band: $hasL5Band, hasL5BandActive: $hasL5BandActive, '
        'hasL1Band: $hasL1Band, hasL2Band: $hasL2Band, hasSBand: $hasSBand, '
        'l5Confidence: $l5Confidence, positioningMethod: $positioningMethod)';
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
        
        // Ensure band detection result is included
        if (!resultMap.containsKey('bandDetectionResult')) {
          resultMap['bandDetectionResult'] = await _extractBandDetectionInfo(resultMap);
        }
        
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

  /// Extract band detection information from the result
  static Future<Map<String, dynamic>> _extractBandDetectionInfo(Map<String, dynamic> resultMap) async {
    try {
      // Try to get detailed band information from Java
      final capabilities = await getGnssCapabilities();
      final allSatellites = await getAllSatellitesInRange();
      
      final Map<String, dynamic> bandInfo = {
        'hasL5Band': resultMap['hasL5Band'] ?? false,
        'hasL5BandActive': resultMap['hasL5BandActive'] ?? false,
        'l5Confidence': resultMap['l5Confidence'] ?? 0.0,
      };
      
      // Extract band information from satellites
      final Map<String, dynamic> bandData = await _analyzeSatelliteBands(allSatellites);
      
      return {
        'availableBands': bandData['availableBands'] ?? {},
        'systemBands': bandData['systemBands'] ?? {},
        'activeBands': bandData['activeBands'] ?? [],
        'supportedBands': bandData['supportedBands'] ?? [],
        'bandSatelliteCounts': bandData['bandSatelliteCounts'] ?? {},
        'bandAverageSignals': bandData['bandAverageSignals'] ?? {},
        'hasL5Band': bandInfo['hasL5Band'],
        'hasL5BandActive': bandInfo['hasL5BandActive'],
        'hasL1Band': capabilities['hasL1'] ?? false,
        'hasL2Band': capabilities['hasL2'] ?? false,
        'hasSBand': bandData['hasSBand'] ?? false,
        'l5Confidence': bandInfo['l5Confidence'],
        'detectionMethods': resultMap['verificationMethods'] ?? [],
        'verificationDetails': [],
      };
    } catch (e) {
      print('⚠️ Error extracting band detection info: $e');
      return {};
    }
  }

  /// Analyze satellite bands from the satellite data
  static Future<Map<String, dynamic>> _analyzeSatelliteBands(Map<String, dynamic> satelliteData) async {
    final Map<String, dynamic> result = {
      'availableBands': {},
      'systemBands': {},
      'activeBands': [],
      'supportedBands': [],
      'bandSatelliteCounts': {},
      'bandAverageSignals': {},
      'hasSBand': false,
    };
    
    try {
      if (satelliteData.containsKey('satellites') && satelliteData['satellites'] is List) {
        final satellites = satelliteData['satellites'] as List<dynamic>;
        
        for (final sat in satellites) {
          if (sat is Map) {
            final satMap = Map<String, dynamic>.from(sat);
            final band = satMap['frequencyBand']?.toString() ?? '';
            final system = satMap['system']?.toString() ?? '';
            final cn0 = _parseDouble(satMap['cn0DbHz']);
            
            if (band.isNotEmpty && band != 'Unknown') {
              // Track band availability
              if (!result['availableBands'].containsKey(band)) {
                result['availableBands'][band] = {
                  'bandName': band,
                  'frequencyHz': _getFrequencyForBand(band),
                  'toleranceHz': 2.0e6,
                  'isAvailable': true,
                  'isActive': cn0 > 0,
                  'satelliteCount': 0,
                  'averageSignal': 0.0,
                  'supportedSystems': [],
                };
              }
              
              // Update band info
              final bandInfo = result['availableBands'][band];
              bandInfo['satelliteCount'] = bandInfo['satelliteCount'] + 1;
              
              // Update average signal
              final currentAvg = bandInfo['averageSignal'];
              final currentCount = bandInfo['satelliteCount'];
              bandInfo['averageSignal'] = ((currentAvg * (currentCount - 1)) + cn0) / currentCount;
              
              // Add system to supported systems
              if (!bandInfo['supportedSystems'].contains(system)) {
                bandInfo['supportedSystems'].add(system);
              }
              
              // Track active bands
              if (cn0 > 0 && !result['activeBands'].contains(band)) {
                result['activeBands'].add(band);
              }
              
              // Track system bands
              if (!result['systemBands'].containsKey(system)) {
                result['systemBands'][system] = [];
              }
              if (!result['systemBands'][system].contains(band)) {
                result['systemBands'][system].add(band);
              }
              
              // Update band counts
              result['bandSatelliteCounts'][band] = (result['bandSatelliteCounts'][band] ?? 0) + 1;
              
              // Check for S-band
              if (band == 'S' || band.contains('S-band')) {
                result['hasSBand'] = true;
              }
            }
          }
        }
        
        // Create supported bands list
        result['supportedBands'] = List<String>.from(result['availableBands'].keys);
        
        // Calculate band average signals
        for (final band in result['availableBands'].keys) {
          final bandInfo = result['availableBands'][band];
          result['bandAverageSignals'][band] = bandInfo['averageSignal'];
        }
      }
    } catch (e) {
      print('⚠️ Error analyzing satellite bands: $e');
    }
    
    return result;
  }

  /// Get frequency for band name - FIXED WITH ALL GNSS BANDS
  static double _getFrequencyForBand(String band) {
    switch (band.toUpperCase()) {
      // GPS Bands
      case 'L1': return 1575.42e6;
      case 'L2': return 1227.60e6;
      case 'L5': return 1176.45e6;
      
      // NavIC Bands
      case 'S': return 2492.028e6;
      
      // GLONASS Bands
      case 'G1': return 1602.00e6;
      case 'G2': return 1246.00e6;
      case 'G3': return 1202.025e6;
      
      // Galileo Bands
      case 'E1': return 1575.42e6;
      case 'E5': return 1207.14e6;
      case 'E5A': return 1176.45e6;
      
      // BeiDou Bands
      case 'B1': return 1561.098e6;
      case 'B2': return 1207.14e6;
      case 'B2A': return 1176.45e6;
      
      // QZSS Bands
      case 'L1C': return 1575.42e6;
      case 'L2C': return 1227.60e6;
      
      // SBAS Bands (same as GPS L1)
      case 'L1CA': return 1575.42e6;
      
      default: return 0.0;
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
      confidenceLevel: 0.0,
      averageSignalStrength: 0.0,
      chipsetType: 'ERROR',
      chipsetVendor: 'ERROR',
      chipsetModel: 'ERROR',
      hasL5Band: false,
      hasL5BandActive: false,
      hasL1Band: false,
      hasL2Band: false,
      hasSBand: false,
      positioningMethod: 'ERROR',
      primarySystem: 'GPS',
      l5BandInfo: {},
      bandInfo: {},
      bandDetectionResult: BandDetectionResult(
        availableBands: {},
        systemBands: {},
        activeBands: [],
        supportedBands: [],
        bandSatelliteCounts: {},
        bandAverageSignals: {},
        hasL5Band: false,
        hasL5BandActive: false,
        hasL1Band: false,
        hasL2Band: false,
        hasSBand: false,
        l5Confidence: 0.0,
        detectionMethods: [],
        verificationDetails: [],
      ),
      allSatellites: [],
      message: 'Error: $errorMessage',
      l5Confidence: 0.0,
      chipsetConfidence: 0.0,
    );
  }

  // ============ PERMISSION METHODS ============

  /// Check location permissions
  static Future<PermissionResult> checkLocationPermissions() async {
    try {
      final result = await _channel.invokeMethod('checkLocationPermissions');
      if (result is Map) {
        final resultMap = Map<String, dynamic>.from(result);
        return PermissionResult.fromMap(resultMap);
      }
      return PermissionResult(
        granted: false,
        message: 'Invalid response type',
      );
    } on PlatformException catch (e) {
      print('Error checking permissions: ${e.message}');
      return PermissionResult(
        granted: false,
        message: e.message ?? 'Permission check failed',
      );
    } catch (e) {
      print('Error checking permissions: $e');
      return PermissionResult(
        granted: false,
        message: 'Unknown error: $e',
      );
    }
  }

  /// Request location permissions
  static Future<PermissionResult> requestLocationPermissions() async {
    try {
      final result = await _channel.invokeMethod('requestLocationPermissions');
      if (result is Map) {
        final resultMap = Map<String, dynamic>.from(result);
        return PermissionResult.fromMap(resultMap);
      }
      return PermissionResult(
        granted: false,
        message: 'Invalid response type',
      );
    } on PlatformException catch (e) {
      print('Error requesting permissions: ${e.message}');
      return PermissionResult(
        granted: false,
        message: e.message ?? 'Permission request failed',
      );
    } catch (e) {
      print('Error requesting permissions: $e');
      return PermissionResult(
        granted: false,
        message: 'Unknown error: $e',
      );
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
  static Future<bool> startLocationUpdates() async {
    try {
      final result = await _channel.invokeMethod('startLocationUpdates');
      if (result is Map) {
        final data = Map<String, dynamic>.from(result);
        return data['success'] as bool? ?? false;
      }
      return false;
    } on PlatformException catch (e) {
      print('Error starting location updates: ${e.message}');
      return false;
    } catch (e) {
      print('Error starting location updates: $e');
      return false;
    }
  }

  /// Stop location updates
  static Future<bool> stopLocationUpdates() async {
    try {
      final result = await _channel.invokeMethod('stopLocationUpdates');
      if (result is Map) {
        final data = Map<String, dynamic>.from(result);
        return data['success'] as bool? ?? false;
      }
      return false;
    } on PlatformException catch (e) {
      print('Error stopping location updates: ${e.message}');
      return false;
    } catch (e) {
      print('Error stopping location updates: $e');
      return false;
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
        final data = Map<String, dynamic>.from(result);
        
        // Extract band capabilities
        if (data.containsKey('gnssCapabilities') && data['gnssCapabilities'] is Map) {
          final caps = Map<String, dynamic>.from(data['gnssCapabilities']);
          data['hasL1'] = caps['hasL1'] ?? false;
          data['hasL2'] = caps['hasL2'] ?? false;
          data['hasL5'] = caps['hasL5'] ?? false;
        }
        
        return data;
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

  // ============ ENHANCED SATELLITE METHODS ============

  /// Get GNSS range statistics
  static Future<Map<String, dynamic>> getGnssRangeStatistics() async {
    try {
      final result = await _channel.invokeMethod('getGnssRangeStatistics');
      if (result is Map) {
        return Map<String, dynamic>.from(result);
      }
      return {'hasData': false, 'message': 'Invalid response type'};
    } on PlatformException catch (e) {
      print('Error getting GNSS range statistics: ${e.message}');
      return {'hasData': false, 'message': e.message};
    } catch (e) {
      print('Error getting GNSS range statistics: $e');
      return {'hasData': false, 'message': e.toString()};
    }
  }

  /// Get detailed satellite info
  static Future<Map<String, dynamic>> getDetailedSatelliteInfo() async {
    try {
      final result = await _channel.invokeMethod('getDetailedSatelliteInfo');
      if (result is Map) {
        return Map<String, dynamic>.from(result);
      }
      return {'hasData': false, 'message': 'Invalid response type'};
    } on PlatformException catch (e) {
      print('Error getting detailed satellite info: ${e.message}');
      return {'hasData': false, 'message': e.message};
    } catch (e) {
      print('Error getting detailed satellite info: $e');
      return {'hasData': false, 'message': e.toString()};
    }
  }

  /// Get complete satellite summary
  static Future<Map<String, dynamic>> getCompleteSatelliteSummary() async {
    try {
      final result = await _channel.invokeMethod('getCompleteSatelliteSummary');
      if (result is Map) {
        return Map<String, dynamic>.from(result);
      }
      return {'hasData': false, 'message': 'Invalid response type'};
    } on PlatformException catch (e) {
      print('Error getting complete satellite summary: ${e.message}');
      return {'hasData': false, 'message': e.message};
    } catch (e) {
      print('Error getting complete satellite summary: $e');
      return {'hasData': false, 'message': e.toString()};
    }
  }

  /// Get satellite names
  static Future<Map<String, dynamic>> getSatelliteNames() async {
    try {
      final result = await _channel.invokeMethod('getSatelliteNames');
      if (result is Map) {
        return Map<String, dynamic>.from(result);
      }
      return {'hasData': false, 'message': 'Invalid response type'};
    } on PlatformException catch (e) {
      print('Error getting satellite names: ${e.message}');
      return {'hasData': false, 'message': e.message};
    } catch (e) {
      print('Error getting satellite names: $e');
      return {'hasData': false, 'message': e.toString()};
    }
  }

  /// Get constellation details
  static Future<Map<String, dynamic>> getConstellationDetails() async {
    try {
      final result = await _channel.invokeMethod('getConstellationDetails');
      if (result is Map) {
        return Map<String, dynamic>.from(result);
      }
      return {'hasData': false, 'message': 'Invalid response type'};
    } on PlatformException catch (e) {
      print('Error getting constellation details: ${e.message}');
      return {'hasData': false, 'message': e.message};
    } catch (e) {
      print('Error getting constellation details: $e');
      return {'hasData': false, 'message': e.toString()};
    }
  }

  /// Get signal strength analysis
  static Future<Map<String, dynamic>> getSignalStrengthAnalysis() async {
    try {
      final result = await _channel.invokeMethod('getSignalStrengthAnalysis');
      if (result is Map) {
        return Map<String, dynamic>.from(result);
      }
      return {'hasData': false, 'message': 'Invalid response type'};
    } on PlatformException catch (e) {
      print('Error getting signal strength analysis: ${e.message}');
      return {'hasData': false, 'message': e.message};
    } catch (e) {
      print('Error getting signal strength analysis: $e');
      return {'hasData': false, 'message': e.toString()};
    }
  }

  /// Get elevation azimuth data
  static Future<Map<String, dynamic>> getElevationAzimuthData() async {
    try {
      final result = await _channel.invokeMethod('getElevationAzimuthData');
      if (result is Map) {
        return Map<String, dynamic>.from(result);
      }
      return {'hasData': false, 'message': 'Invalid response type'};
    } on PlatformException catch (e) {
      print('Error getting elevation azimuth data: ${e.message}');
      return {'hasData': false, 'message': e.message};
    } catch (e) {
      print('Error getting elevation azimuth data: $e');
      return {'hasData': false, 'message': e.toString()};
    }
  }

  /// Get carrier frequency info
  static Future<Map<String, dynamic>> getCarrierFrequencyInfo() async {
    try {
      final result = await _channel.invokeMethod('getCarrierFrequencyInfo');
      if (result is Map) {
        return Map<String, dynamic>.from(result);
      }
      return {'hasData': false, 'message': 'Invalid response type'};
    } on PlatformException catch (e) {
      print('Error getting carrier frequency info: ${e.message}');
      return {'hasData': false, 'message': e.message};
    } catch (e) {
      print('Error getting carrier frequency info: $e');
      return {'hasData': false, 'message': e.toString()};
    }
  }

  /// Get ephemeris almanac status
  static Future<Map<String, dynamic>> getEphemerisAlmanacStatus() async {
    try {
      final result = await _channel.invokeMethod('getEphemerisAlmanacStatus');
      if (result is Map) {
        return Map<String, dynamic>.from(result);
      }
      return {'hasData': false, 'message': 'Invalid response type'};
    } on PlatformException catch (e) {
      print('Error getting ephemeris almanac status: ${e.message}');
      return {'hasData': false, 'message': e.message};
    } catch (e) {
      print('Error getting ephemeris almanac status: $e');
      return {'hasData': false, 'message': e.toString()};
    }
  }

  /// Get satellite detection history
  static Future<Map<String, dynamic>> getSatelliteDetectionHistory() async {
    try {
      final result = await _channel.invokeMethod('getSatelliteDetectionHistory');
      if (result is Map) {
        return Map<String, dynamic>.from(result);
      }
      return {'hasData': false, 'message': 'Invalid response type'};
    } on PlatformException catch (e) {
      print('Error getting satellite detection history: ${e.message}');
      return {'hasData': false, 'message': e.message};
    } catch (e) {
      print('Error getting satellite detection history: $e');
      return {'hasData': false, 'message': e.toString()};
    }
  }

  /// Get GNSS diversity report
  static Future<Map<String, dynamic>> getGnssDiversityReport() async {
    try {
      final result = await _channel.invokeMethod('getGnssDiversityReport');
      if (result is Map) {
        return Map<String, dynamic>.from(result);
      }
      return {'hasData': false, 'message': 'Invalid response type'};
    } on PlatformException catch (e) {
      print('Error getting GNSS diversity report: ${e.message}');
      return {'hasData': false, 'message': e.message};
    } catch (e) {
      print('Error getting GNSS diversity report: $e');
      return {'hasData': false, 'message': e.toString()};
    }
  }

  /// Get real-time satellite stream
  static Future<Map<String, dynamic>> getRealTimeSatelliteStream() async {
    try {
      final result = await _channel.invokeMethod('getRealTimeSatelliteStream');
      if (result is Map) {
        return Map<String, dynamic>.from(result);
      }
      return {'hasData': false, 'message': 'Invalid response type'};
    } on PlatformException catch (e) {
      print('Error getting real-time satellite stream: ${e.message}');
      return {'hasData': false, 'message': e.message};
    } catch (e) {
      print('Error getting real-time satellite stream: $e');
      return {'hasData': false, 'message': e.toString()};
    }
  }

  /// Get satellite signal quality
  static Future<Map<String, dynamic>> getSatelliteSignalQuality() async {
    try {
      final result = await _channel.invokeMethod('getSatelliteSignalQuality');
      if (result is Map) {
        return Map<String, dynamic>.from(result);
      }
      return {'hasData': false, 'message': 'Invalid response type'};
    } on PlatformException catch (e) {
      print('Error getting satellite signal quality: ${e.message}');
      return {'hasData': false, 'message': e.message};
    } catch (e) {
      print('Error getting satellite signal quality: $e');
      return {'hasData': false, 'message': e.toString()};
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
    _isInitialized = false;
    print('🧹 NavicHardwareService disposed');
  }

  /// Get method channel name (for debugging)
  static String get channelName => 'navic_support';
}