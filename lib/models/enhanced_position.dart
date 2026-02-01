class EnhancedPosition {
  final double latitude;
  final double longitude;
  final double accuracy;
  final double altitude;
  final double speed;
  final double heading;
  final DateTime timestamp;
  final String locationSource;
  final bool hasL5Band;
  final bool hasL5BandActive;
  final bool isNavicEnhanced;
  final int navicSatellites;
  final int totalSatellites;
  final int navicUsedInFix;
  final String primarySystem;
  final String positioningMethod;
  final double confidenceScore;
  final Map<String, Map<String, int>> systemStats;

  EnhancedPosition({
    required this.latitude,
    required this.longitude,
    required this.accuracy,
    required this.altitude,
    required this.speed,
    required this.heading,
    required this.timestamp,
    required this.locationSource,
    required this.hasL5Band,
    required this.hasL5BandActive,
    required this.isNavicEnhanced,
    required this.navicSatellites,
    required this.totalSatellites,
    required this.navicUsedInFix,
    required this.primarySystem,
    required this.positioningMethod,
    required this.confidenceScore,
    required this.systemStats,
  });
}
