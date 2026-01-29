// lib/models/enhanced_position.dart
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
  final String? message;

  EnhancedPosition({
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
    this.message,
  });

  // Factory constructor for creating EnhancedPosition from map
  factory EnhancedPosition.create({
    required double latitude,
    required double longitude,
    double? accuracy,
    double? altitude,
    double? speed,
    double? bearing,
    int? timestamp,
    bool isNavicSupported = false,
    bool isNavicActive = false,
    bool isNavicEnhanced = false,
    double confidenceScore = 0.5,
    String locationSource = 'GPS',
    String detectionReason = 'Standard GPS positioning',
    int navicSatellites = 0,
    int totalSatellites = 0,
    int navicUsedInFix = 0,
    bool hasL5Band = false,
    bool hasL5BandActive = false,
    String positioningMethod = 'GPS_PRIMARY',
    Map<String, dynamic> systemStats = const {},
    String primarySystem = 'GPS',
    bool usingExternalGnss = false,
    String externalGnssInfo = 'NONE',
    String externalGnssVendor = 'UNKNOWN',
    bool usbConnectionActive = false,
    String? message,
  }) {
    return EnhancedPosition(
      latitude: latitude,
      longitude: longitude,
      accuracy: accuracy,
      altitude: altitude,
      speed: speed,
      bearing: bearing,
      timestamp: timestamp ?? DateTime.now().millisecondsSinceEpoch,
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

  // Create from JSON/map (for deserialization from Java)
  factory EnhancedPosition.fromMap(Map<String, dynamic> map) {
    return EnhancedPosition(
      latitude: (map['latitude'] as num).toDouble(),
      longitude: (map['longitude'] as num).toDouble(),
      accuracy: map['accuracy'] != null ? (map['accuracy'] as num).toDouble() : null,
      altitude: map['altitude'] != null ? (map['altitude'] as num).toDouble() : null,
      speed: map['speed'] != null ? (map['speed'] as num).toDouble() : null,
      bearing: map['bearing'] != null ? (map['bearing'] as num).toDouble() : null,
      timestamp: map['timestamp'] as int? ?? DateTime.now().millisecondsSinceEpoch,
      isNavicSupported: map['isNavicSupported'] as bool? ?? false,
      isNavicActive: map['isNavicActive'] as bool? ?? false,
      isNavicEnhanced: map['isNavicEnhanced'] as bool? ?? false,
      confidenceScore: (map['confidenceScore'] as num?)?.toDouble() ?? 0.5,
      locationSource: map['locationSource'] as String? ?? 'GPS',
      detectionReason: map['detectionReason'] as String? ?? 'Standard GPS positioning',
      navicSatellites: map['navicSatellites'] as int? ?? 0,
      totalSatellites: map['totalSatellites'] as int? ?? 0,
      navicUsedInFix: map['navicUsedInFix'] as int? ?? 0,
      hasL5Band: map['hasL5Band'] as bool? ?? false,
      hasL5BandActive: map['hasL5BandActive'] as bool? ?? false,
      positioningMethod: map['positioningMethod'] as String? ?? 'GPS_PRIMARY',
      systemStats: (map['systemStats'] as Map<String, dynamic>?) ?? {},
      primarySystem: map['primarySystem'] as String? ?? 'GPS',
      usingExternalGnss: map['usingExternalGnss'] as bool? ?? false,
      externalGnssInfo: map['externalGnssInfo'] as String? ?? 'NONE',
      externalGnssVendor: map['externalGnssVendor'] as String? ?? 'UNKNOWN',
      usbConnectionActive: map['usbConnectionActive'] as bool? ?? false,
      message: map['message'] as String?,
    );
  }

  // Convert to JSON/map (for serialization)
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

  // Get formatted coordinates string
  String get formattedCoordinates {
    return '${latitude.toStringAsFixed(6)}, ${longitude.toStringAsFixed(6)}';
  }

  // Get formatted accuracy string
  String get formattedAccuracy {
    if (accuracy == null) return 'N/A';
    return '${accuracy!.toStringAsFixed(1)} meters';
  }

  // Get formatted time string
  String get formattedTime {
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}:${date.second.toString().padLeft(2, '0')}';
  }

  // Check if position is valid
  bool get isValid {
    return latitude >= -90 && latitude <= 90 &&
        longitude >= -180 && longitude <= 180 &&
        accuracy != null && accuracy! > 0;
  }

  // Get quality level based on accuracy
  String get qualityLevel {
    if (accuracy == null) return 'Unknown';
    if (accuracy! < 1.0) return 'Excellent';
    if (accuracy! < 2.0) return 'High';
    if (accuracy! < 5.0) return 'Good';
    if (accuracy! < 10.0) return 'Basic';
    return 'Low';
  }

  // Get color based on quality
  String get qualityColor {
    if (accuracy == null) return 'grey';
    if (accuracy! < 1.0) return 'green';
    if (accuracy! < 2.0) return 'blue';
    if (accuracy! < 5.0) return 'orange';
    if (accuracy! < 10.0) return 'amber';
    return 'red';
  }

  @override
  String toString() {
    return 'EnhancedPosition(lat: $latitude, lng: $longitude, accuracy: $accuracy, source: $locationSource, navic: $isNavicActive)';
  }
}