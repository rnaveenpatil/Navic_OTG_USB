import 'dart:convert';

class GnssSatellite {
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
  final String? frequencyBand;
  final double carrierFrequencyHz;
  final int detectionTime;
  final String signalStrength;
  final bool isL5Band;
  final int timestamp;
  final bool externalGnss;

  const GnssSatellite({
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
    required this.carrierFrequencyHz,
    required this.detectionTime,
    required this.signalStrength,
    required this.isL5Band,
    required this.timestamp,
    required this.externalGnss,
  });

  factory GnssSatellite.fromMap(Map<String, dynamic> map) {
    return GnssSatellite(
      svid: _parseInt(map['svid']),
      system: map['system']?.toString() ?? 'UNKNOWN',
      constellation: map['constellation']?.toString() ?? '0',
      countryFlag: map['countryFlag']?.toString() ?? '🌐',
      cn0DbHz: _parseDouble(map['cn0DbHz']),
      usedInFix: _parseBool(map['usedInFix']),
      elevation: _parseDouble(map['elevation']),
      azimuth: _parseDouble(map['azimuth']),
      hasEphemeris: _parseBool(map['hasEphemeris']),
      hasAlmanac: _parseBool(map['hasAlmanac']),
      frequencyBand: map['frequencyBand']?.toString(),
      carrierFrequencyHz: _parseDouble(map['carrierFrequencyHz']),
      detectionTime: _parseInt(map['detectionTime']),
      signalStrength: map['signalStrength']?.toString() ?? 'UNKNOWN',
      isL5Band: _parseBool(map['isL5Band']),
      timestamp: _parseInt(map['timestamp']),
      externalGnss: _parseBool(map['externalGnss']),
    );
  }

  static int _parseInt(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  static double _parseDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is double) return value;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
  }

  static bool _parseBool(dynamic value) {
    if (value == null) return false;
    if (value is bool) return value;
    if (value is String) {
      return value.toLowerCase() == 'true' || value == '1';
    }
    if (value is num) return value != 0;
    return false;
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
      'signalStrength': signalStrength,
      'isL5Band': isL5Band,
      'timestamp': timestamp,
      'externalGnss': externalGnss,
    };
  }

  String toJson() => json.encode(toMap());

  factory GnssSatellite.fromJson(String jsonStr) =>
      GnssSatellite.fromMap(json.decode(jsonStr));

  @override
  String toString() {
    return 'GnssSatellite($system-$svid, SNR: ${cn0DbHz.toStringAsFixed(1)} dB, Used: $usedInFix)';
  }
}