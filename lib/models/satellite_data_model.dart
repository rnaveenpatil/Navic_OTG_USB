// lib/models/satellite_data_model.dart
import 'package:geolocator/geolocator.dart';

class SatelliteData {
  final int svid;
  final String system;
  final String constellation;
  final String countryFlag;
  final double cn0DbHz;
  final bool usedInFix;
  final double elevation;
  final double azimuth;
  final bool hasEphemeris;
  final bool hasAlmanac;
  final String frequencyBand;
  final double? carrierFrequencyHz;
  final int detectionTime;
  final int detectionCount;
  final String signalStrength;
  final int timestamp;
  final bool externalGnss;

  SatelliteData({
    required this.svid,
    required this.system,
    required this.constellation,
    required this.countryFlag,
    required this.cn0DbHz,
    required this.usedInFix,
    required this.elevation,
    required this.azimuth,
    required this.hasEphemeris,
    required this.hasAlmanac,
    required this.frequencyBand,
    this.carrierFrequencyHz,
    required this.detectionTime,
    required this.detectionCount,
    required this.signalStrength,
    required this.timestamp,
    this.externalGnss = false,
  });

  factory SatelliteData.fromMap(Map<String, dynamic> map) {
    return SatelliteData(
      svid: map['svid'] is int ? map['svid'] : (map['svid'] is num ? map['svid'].toInt() : 0),
      system: map['system'] as String? ?? 'UNKNOWN',
      constellation: map['constellation'] is int ?
      _getConstellationName(map['constellation'] as int) :
      (map['constellation'] as String? ?? 'UNKNOWN'),
      countryFlag: map['countryFlag'] as String? ?? '🌐',
      cn0DbHz: map['cn0DbHz'] is double ? map['cn0DbHz'] :
      (map['cn0DbHz'] is num ? map['cn0DbHz'].toDouble() : 0.0),
      usedInFix: map['usedInFix'] as bool? ?? false,
      elevation: map['elevation'] is double ? map['elevation'] :
      (map['elevation'] is num ? map['elevation'].toDouble() : 0.0),
      azimuth: map['azimuth'] is double ? map['azimuth'] :
      (map['azimuth'] is num ? map['azimuth'].toDouble() : 0.0),
      hasEphemeris: map['hasEphemeris'] as bool? ?? false,
      hasAlmanac: map['hasAlmanac'] as bool? ?? false,
      frequencyBand: map['frequencyBand'] as String? ?? 'UNKNOWN',
      carrierFrequencyHz: map['carrierFrequencyHz'] is double ? map['carrierFrequencyHz'] :
      (map['carrierFrequencyHz'] is num ? map['carrierFrequencyHz'].toDouble() : null),
      detectionTime: map['detectionTime'] is int ? map['detectionTime'] :
      (map['detectionTime'] is num ? map['detectionTime'].toInt() : 0),
      detectionCount: map['detectionCount'] is int ? map['detectionCount'] :
      (map['detectionCount'] is num ? map['detectionCount'].toInt() : 1),
      signalStrength: map['signalStrength'] as String? ?? 'UNKNOWN',
      timestamp: map['timestamp'] is int ? map['timestamp'] :
      (map['timestamp'] is num ? map['timestamp'].toInt() : DateTime.now().millisecondsSinceEpoch),
      externalGnss: map['externalGnss'] as bool? ?? false,
    );
  }

  static String _getConstellationName(int constellation) {
    switch (constellation) {
      case 1: return 'GPS';
      case 2: return 'SBAS';
      case 3: return 'GLONASS';
      case 4: return 'QZSS';
      case 5: return 'BEIDOU';
      case 6: return 'GALILEO';
      case 7: return 'IRNSS';
      default: return 'UNKNOWN';
    }
  }

  Map<String, dynamic> toMap() {
    return {
      'svid': svid,
      'system': system,
      'constellation': constellation,
      'countryFlag': countryFlag,
      'cn0DbHz': cn0DbHz,
      'usedInFix': usedInFix,
      'elevation': elevation,
      'azimuth': azimuth,
      'hasEphemeris': hasEphemeris,
      'hasAlmanac': hasAlmanac,
      'frequencyBand': frequencyBand,
      'carrierFrequencyHz': carrierFrequencyHz,
      'detectionTime': detectionTime,
      'detectionCount': detectionCount,
      'signalStrength': signalStrength,
      'timestamp': timestamp,
      'externalGnss': externalGnss,
    };
  }
}

class EnhancedPosition {
  final double latitude;
  final double longitude;
  final double? accuracy;
  final double? altitude;
  final double? speed;
  final double? bearing;
  final DateTime timestamp;

  // NavIC and GNSS status
  final bool isNavicSupported;
  final bool isNavicActive;
  final bool isNavicEnhanced;
  final double confidenceScore;
  final String locationSource;
  final String detectionReason;

  // Satellite counts
  final int navicSatellites;
  final int totalSatellites;
  final int navicUsedInFix;

  // Satellite data
  final List<Map<String, dynamic>> satelliteInfo;

  // L5 Band status
  final bool hasL5Band;
  final bool hasL5BandActive;

  // Positioning info
  final String positioningMethod;
  final Map<String, dynamic> systemStats;
  final String primarySystem;

  // Chipset info (from Java, but not actual detection)
  final String chipsetType;
  final String chipsetVendor;
  final String chipsetModel;

  final String? message;
  final List<dynamic> verificationMethods;
  final double acquisitionTimeMs;
  final List<dynamic> satelliteDetails;

  // USB GNSS fields (from Java code)
  final bool usingExternalGnss;
  final String externalGnssInfo;
  final String externalGnssVendor;
  final bool usbConnectionActive;

  EnhancedPosition({
    required this.latitude,
    required this.longitude,
    this.accuracy,
    this.altitude,
    this.speed,
    this.bearing,
    required this.timestamp,

    // NavIC and GNSS status
    required this.isNavicSupported,
    required this.isNavicActive,
    required this.isNavicEnhanced,
    required this.confidenceScore,
    required this.locationSource,
    required this.detectionReason,

    // Satellite counts
    required this.navicSatellites,
    required this.totalSatellites,
    required this.navicUsedInFix,

    // Satellite data
    required this.satelliteInfo,

    // L5 Band status
    required this.hasL5Band,
    required this.hasL5BandActive,

    // Positioning info
    required this.positioningMethod,
    required this.systemStats,
    required this.primarySystem,

    // Chipset info (kept for compatibility but not actual detection)
    required this.chipsetType,
    required this.chipsetVendor,
    required this.chipsetModel,

    this.message,
    required this.verificationMethods,
    required this.acquisitionTimeMs,
    required this.satelliteDetails,

    // USB GNSS fields
    required this.usingExternalGnss,
    required this.externalGnssInfo,
    required this.externalGnssVendor,
    required this.usbConnectionActive,
  });

  // Simplified factory constructor
  factory EnhancedPosition.create({
    required double latitude,
    required double longitude,
    double? accuracy,
    double? altitude,
    double? speed,
    double? bearing,
    required DateTime timestamp,

    // NavIC and GNSS status
    required bool isNavicSupported,
    required bool isNavicActive,
    required bool isNavicEnhanced,
    required double confidenceScore,
    required String locationSource,
    required String detectionReason,

    // Satellite counts
    required int navicSatellites,
    required int totalSatellites,
    required int navicUsedInFix,

    // L5 Band status
    required bool hasL5Band,
    required bool hasL5BandActive,

    // Positioning info
    required String positioningMethod,
    required Map<String, dynamic> systemStats,
    required String primarySystem,

    // USB GNSS info
    required bool usingExternalGnss,
    required String externalGnssInfo,
    required String externalGnssVendor,
    required bool usbConnectionActive,

    String? message,
  }) {
    return EnhancedPosition(
      latitude: latitude,
      longitude: longitude,
      accuracy: accuracy,
      altitude: altitude,
      speed: speed,
      bearing: bearing,
      timestamp: timestamp,
      isNavicSupported: isNavicSupported,
      isNavicActive: isNavicActive,
      isNavicEnhanced: isNavicEnhanced,
      confidenceScore: confidenceScore,
      locationSource: locationSource,
      detectionReason: detectionReason,
      navicSatellites: navicSatellites,
      totalSatellites: totalSatellites,
      navicUsedInFix: navicUsedInFix,
      satelliteInfo: [],
      hasL5Band: hasL5Band,
      hasL5BandActive: hasL5BandActive,
      positioningMethod: positioningMethod,
      systemStats: systemStats,
      primarySystem: primarySystem,
      chipsetType: usingExternalGnss ? "EXTERNAL_DEVICE" : "INTERNAL_GNSS",
      chipsetVendor: usingExternalGnss ? externalGnssVendor : "UNKNOWN",
      chipsetModel: usingExternalGnss ? externalGnssInfo : "UNKNOWN",
      message: message,
      verificationMethods: [],
      acquisitionTimeMs: 0.0,
      satelliteDetails: [],
      usingExternalGnss: usingExternalGnss,
      externalGnssInfo: externalGnssInfo,
      externalGnssVendor: externalGnssVendor,
      usbConnectionActive: usbConnectionActive,
    );
  }

  Map<String, dynamic> toJson() => {
    'latitude': latitude,
    'longitude': longitude,
    'accuracy': accuracy,
    'altitude': altitude,
    'speed': speed,
    'bearing': bearing,
    'timestamp': timestamp.toIso8601String(),
    'isNavicSupported': isNavicSupported,
    'isNavicActive': isNavicActive,
    'isNavicEnhanced': isNavicEnhanced,
    'confidenceScore': confidenceScore,
    'locationSource': locationSource,
    'detectionReason': detectionReason,
    'navicSatellites': navicSatellites,
    'totalSatellites': totalSatellites,
    'navicUsedInFix': navicUsedInFix,
    'hasL5Band': hasL5Band,
    'hasL5BandActive': hasL5BandActive,
    'positioningMethod': positioningMethod,
    'systemStats': systemStats,
    'primarySystem': primarySystem,
    'chipsetType': chipsetType,
    'chipsetVendor': chipsetVendor,
    'chipsetModel': chipsetModel,
    'message': message,
    'usingExternalGnss': usingExternalGnss,
    'externalGnssInfo': externalGnssInfo,
    'externalGnssVendor': externalGnssVendor,
    'usbConnectionActive': usbConnectionActive,
  };

  @override
  String toString() {
    return 'EnhancedPosition(lat: ${latitude.toStringAsFixed(6)}, lng: ${longitude.toStringAsFixed(6)}, '
        'acc: ${accuracy?.toStringAsFixed(2)}m, '
        'NavIC: ${isNavicEnhanced ? "Yes" : "No"} (Supported: $isNavicSupported, Active: $isNavicActive), '
        'Satellites: $totalSatellites total, $navicSatellites NavIC, '
        'L5: ${hasL5Band ? "Yes" : "No"} (${hasL5BandActive ? "Active" : "Inactive"}), '
        'Method: $positioningMethod, '
        'External GNSS: ${usingExternalGnss ? "Yes - $externalGnssInfo" : "No"})';
  }
}