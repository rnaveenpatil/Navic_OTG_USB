class EnhancedPosition {
  final double latitude;
  final double longitude;
  final double? accuracy;
  final double? altitude;
  final double? speed;
  final double? bearing;
  final int timestamp;
  final bool isNavicSupported;
  final bool isNavicActive;
  final bool isNavicEnhanced;
  final double confidenceScore;
  final String locationSource;
  final String detectionReason;
  final int navicSatellites;
  final int totalSatellites;
  final int navicUsedInFix;
  final bool hasL5Band;
  final bool hasL5BandActive;
  final String positioningMethod;
  final Map<String, dynamic> systemStats;
  final String primarySystem;
  final bool usingExternalGnss;
  final String externalGnssInfo;
  final String externalGnssVendor;
  final bool usbConnectionActive;
  final String message;

  const EnhancedPosition({
    required this.latitude,
    required this.longitude,
    this.accuracy,
    this.altitude,
    this.speed,
    this.bearing,
    required this.timestamp,
    required this.isNavicSupported,
    required this.isNavicActive,
    required this.isNavicEnhanced,
    required this.confidenceScore,
    required this.locationSource,
    required this.detectionReason,
    required this.navicSatellites,
    required this.totalSatellites,
    required this.navicUsedInFix,
    required this.hasL5Band,
    required this.hasL5BandActive,
    required this.positioningMethod,
    required this.systemStats,
    required this.primarySystem,
    required this.usingExternalGnss,
    required this.externalGnssInfo,
    required this.externalGnssVendor,
    required this.usbConnectionActive,
    required this.message,
  });

  factory EnhancedPosition.create({
    required double latitude,
    required double longitude,
    double? accuracy,
    double? altitude,
    double? speed,
    double? bearing,
    required int timestamp,
    required bool isNavicSupported,
    required bool isNavicActive,
    required bool isNavicEnhanced,
    required double confidenceScore,
    required String locationSource,
    required String detectionReason,
    required int navicSatellites,
    required int totalSatellites,
    required int navicUsedInFix,
    required bool hasL5Band,
    required bool hasL5BandActive,
    required String positioningMethod,
    required Map<String, dynamic> systemStats,
    required String primarySystem,
    required bool usingExternalGnss,
    required String externalGnssInfo,
    required String externalGnssVendor,
    required bool usbConnectionActive,
    required String message,
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
      hasL5Band: hasL5Band,
      hasL5BandActive: hasL5BandActive,
      positioningMethod: positioningMethod,
      systemStats: systemStats,
      primarySystem: primarySystem,
      usingExternalGnss: usingExternalGnss,
      externalGnssInfo: externalGnssInfo,
      externalGnssVendor: externalGnssVendor,
      usbConnectionActive: usbConnectionActive,
      message: message,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'latitude': latitude,
      'longitude': longitude,
      'accuracy': accuracy,
      'altitude': altitude,
      'speed': speed,
      'bearing': bearing,
      'timestamp': timestamp,
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
      'usingExternalGnss': usingExternalGnss,
      'externalGnssInfo': externalGnssInfo,
      'externalGnssVendor': externalGnssVendor,
      'usbConnectionActive': usbConnectionActive,
      'message': message,
    };
  }

  @override
  String toString() {
    return 'EnhancedPosition($latitude, $longitude, Accuracy: $accuracy, Source: $locationSource)';
  }
}