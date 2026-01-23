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
    };
  }
}

class EnhancedPosition {
  final double latitude;
  final double longitude;
  final double? accuracy;
  final double? altitude;
  final double? speed;
  final double? heading;
  final DateTime timestamp;
  final bool isNavicEnhanced;
  final double confidenceScore;
  final String locationSource;
  final String detectionReason;
  final int navicSatellites;
  final int totalSatellites;
  final int navicUsedInFix;
  final List<Map<String, dynamic>> satelliteInfo;
  final bool hasL5Band;
  final String positioningMethod;
  final Map<String, dynamic> systemStats;
  final String primarySystem;
  final String chipsetType;
  final String chipsetVendor;
  final String chipsetModel;
  final double chipsetConfidence;
  final double l5Confidence;
  final String? message;
  final List<dynamic> verificationMethods;
  final double acquisitionTimeMs;
  final List<dynamic> satelliteDetails;

  EnhancedPosition({
    required this.latitude,
    required this.longitude,
    this.accuracy,
    this.altitude,
    this.speed,
    this.heading,
    required this.timestamp,
    required this.isNavicEnhanced,
    required this.confidenceScore,
    required this.locationSource,
    required this.detectionReason,
    required this.navicSatellites,
    required this.totalSatellites,
    required this.navicUsedInFix,
    required this.satelliteInfo,
    required this.hasL5Band,
    required this.positioningMethod,
    required this.systemStats,
    required this.primarySystem,
    required this.chipsetType,
    required this.chipsetVendor,
    required this.chipsetModel,
    required this.chipsetConfidence,
    required this.l5Confidence,
    this.message,
    required this.verificationMethods,
    required this.acquisitionTimeMs,
    required this.satelliteDetails,
  });

  // Factory constructor to create from Position object
  factory EnhancedPosition.fromPosition({
    required Position position,
    required bool isNavicEnhanced,
    required double confidenceScore,
    required String locationSource,
    required String detectionReason,
    required int navicSatellites,
    required int totalSatellites,
    required int navicUsedInFix,
    required List<Map<String, dynamic>> satelliteInfo,
    required bool hasL5Band,
    required String positioningMethod,
    required Map<String, dynamic> systemStats,
    required String primarySystem,
    required String chipsetType,
    required String chipsetVendor,
    required String chipsetModel,
    required double chipsetConfidence,
    required double l5Confidence,
    String? message,
    required List<dynamic> verificationMethods,
    required double acquisitionTimeMs,
    required List<dynamic> satelliteDetails,
  }) {
    return EnhancedPosition(
      latitude: position.latitude,
      longitude: position.longitude,
      accuracy: position.accuracy,
      altitude: position.altitude,
      speed: position.speed,
      heading: position.heading,
      timestamp: position.timestamp,
      isNavicEnhanced: isNavicEnhanced,
      confidenceScore: confidenceScore,
      locationSource: locationSource,
      detectionReason: detectionReason,
      navicSatellites: navicSatellites,
      totalSatellites: totalSatellites,
      navicUsedInFix: navicUsedInFix,
      satelliteInfo: satelliteInfo,
      hasL5Band: hasL5Band,
      positioningMethod: positioningMethod,
      systemStats: systemStats,
      primarySystem: primarySystem,
      chipsetType: chipsetType,
      chipsetVendor: chipsetVendor,
      chipsetModel: chipsetModel,
      chipsetConfidence: chipsetConfidence,
      l5Confidence: l5Confidence,
      message: message,
      verificationMethods: verificationMethods,
      acquisitionTimeMs: acquisitionTimeMs,
      satelliteDetails: satelliteDetails,
    );
  }

  Map<String, dynamic> toJson() => {
    'latitude': latitude,
    'longitude': longitude,
    'accuracy': accuracy,
    'altitude': altitude,
    'speed': speed,
    'heading': heading,
    'timestamp': timestamp.toIso8601String(),
    'isNavicEnhanced': isNavicEnhanced,
    'confidenceScore': confidenceScore,
    'locationSource': locationSource,
    'detectionReason': detectionReason,
    'navicSatellites': navicSatellites,
    'totalSatellites': totalSatellites,
    'navicUsedInFix': navicUsedInFix,
    'satelliteInfo': satelliteInfo,
    'hasL5Band': hasL5Band,
    'positioningMethod': positioningMethod,
    'systemStats': systemStats,
    'primarySystem': primarySystem,
    'chipsetType': chipsetType,
    'chipsetVendor': chipsetVendor,
    'chipsetModel': chipsetModel,
    'chipsetConfidence': chipsetConfidence,
    'l5Confidence': l5Confidence,
    'message': message,
    'verificationMethods': verificationMethods,
    'acquisitionTimeMs': acquisitionTimeMs,
    'satelliteDetails': satelliteDetails,
  };

  @override
  String toString() {
    return 'EnhancedPosition(lat: ${latitude.toStringAsFixed(6)}, lng: ${longitude.toStringAsFixed(6)}, '
        'acc: ${accuracy?.toStringAsFixed(2)}m, navic: $isNavicEnhanced, '
        'conf: ${(confidenceScore * 100).toStringAsFixed(1)}%, '
        'primary: $primarySystem, '
        'chipset: $chipsetVendor $chipsetModel, '
        'L5: ${hasL5Band ? "Yes" : "No"}, '
        'Method: $positioningMethod)';
  }
}