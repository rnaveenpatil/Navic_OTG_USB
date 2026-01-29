class GnssSatellite {
  final int svid;
  final String system;
  final int constellation;
  final String countryFlag;
  final double cn0DbHz;
  final bool usedInFix;
  final double elevation;
  final double azimuth;
  final bool hasEphemeris;
  final bool hasAlmanac;
  final String? frequencyBand;
  final double? carrierFrequencyHz;
  final int detectionTime;
  final int detectionCount;
  final bool isL5Band;
  final bool externalGnss;
  final int timestamp;

  GnssSatellite({
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
    this.frequencyBand,
    this.carrierFrequencyHz,
    required this.detectionTime,
    required this.detectionCount,
    required this.isL5Band,
    required this.externalGnss,
    required this.timestamp,
  });

  factory GnssSatellite.fromMap(Map<String, dynamic> map) {
    return GnssSatellite(
      svid: (map['svid'] as num?)?.toInt() ?? 0,
      system: (map['system'] as String?) ?? 'UNKNOWN',
      constellation: (map['constellation'] as num?)?.toInt() ?? 0,
      countryFlag: (map['countryFlag'] as String?) ?? '🌐',
      cn0DbHz: (map['cn0DbHz'] as num?)?.toDouble() ?? 0.0,
      usedInFix: (map['usedInFix'] as bool?) ?? false,
      elevation: (map['elevation'] as num?)?.toDouble() ?? 0.0,
      azimuth: (map['azimuth'] as num?)?.toDouble() ?? 0.0,
      hasEphemeris: (map['hasEphemeris'] as bool?) ?? false,
      hasAlmanac: (map['hasAlmanac'] as bool?) ?? false,
      frequencyBand: map['frequencyBand'] as String?,
      carrierFrequencyHz: (map['carrierFrequencyHz'] as num?)?.toDouble(),
      detectionTime: (map['detectionTime'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch,
      detectionCount: (map['detectionCount'] as num?)?.toInt() ?? 1,
      isL5Band: (map['isL5Band'] as bool?) ?? false,
      externalGnss: (map['externalGnss'] as bool?) ?? false,
      timestamp: (map['timestamp'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch,
    );
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
      'isL5Band': isL5Band,
      'externalGnss': externalGnss,
      'timestamp': timestamp,
    };
  }

  @override
  String toString() {
    return 'GnssSatellite($system-$svid, CN0: ${cn0DbHz.toStringAsFixed(1)} dB-Hz, Used: $usedInFix)';
  }
}