// lib/models/gnss_satellite.dart
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
  final String frequencyBand;
  final double? carrierFrequencyHz;
  final int detectionTime;
  final int detectionCount;
  final String signalStrength;
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
    required this.frequencyBand,
    this.carrierFrequencyHz,
    required this.detectionTime,
    required this.detectionCount,
    required this.signalStrength,
    required this.timestamp,
  });

  factory GnssSatellite.fromMap(Map<String, dynamic> map) {
    // Handle Java Object types
    final svid = map['svid'];
    final cn0DbHz = map['cn0DbHz'];
    final elevation = map['elevation'];
    final azimuth = map['azimuth'];
    final carrierFreq = map['carrierFrequencyHz'];
    final detectionTime = map['detectionTime'];
    final detectionCount = map['detectionCount'];
    final timestamp = map['timestamp'];
    final constellation = map['constellation'];

    return GnssSatellite(
      svid: svid is int ? svid : (svid is num ? svid.toInt() : 0),
      system: map['system'] as String? ?? 'UNKNOWN',
      constellation: constellation is int ? 
        _getConstellationName(constellation as int) : 
        (constellation is String ? constellation as String : 'UNKNOWN'),
      countryFlag: map['countryFlag'] as String? ?? '🌐',
      cn0DbHz: cn0DbHz is double ? cn0DbHz : 
               (cn0DbHz is num ? cn0DbHz.toDouble() : 0.0),
      usedInFix: map['usedInFix'] as bool? ?? false,
      elevation: elevation is double ? elevation : 
                (elevation is num ? elevation.toDouble() : 0.0),
      azimuth: azimuth is double ? azimuth : 
              (azimuth is num ? azimuth.toDouble() : 0.0),
      hasEphemeris: map['hasEphemeris'] as bool? ?? false,
      hasAlmanac: map['hasAlmanac'] as bool? ?? false,
      frequencyBand: map['frequencyBand'] as String? ?? 'UNKNOWN',
      carrierFrequencyHz: carrierFreq is double ? carrierFreq : 
                        (carrierFreq is num ? carrierFreq.toDouble() : null),
      detectionTime: detectionTime is int ? detectionTime : 
                    (detectionTime is num ? detectionTime.toInt() : 0),
      detectionCount: detectionCount is int ? detectionCount : 
                     (detectionCount is num ? detectionCount.toInt() : 1),
      signalStrength: map['signalStrength'] as String? ?? 'UNKNOWN',
      timestamp: timestamp is int ? timestamp : 
                (timestamp is num ? timestamp.toInt() : DateTime.now().millisecondsSinceEpoch),
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

  @override
  String toString() {
    return 'GnssSatellite(svid: $svid, system: $system, cn0DbHz: $cn0DbHz, usedInFix: $usedInFix)';
  }
}

class GnssSystemStats {
  final String name;
  final String flag;
  final int total;
  final int used;
  final int available;
  final double averageSignal;
  final double utilization;
  final int signalCount;

  GnssSystemStats({
    required this.name,
    required this.flag,
    required this.total,
    required this.used,
    required this.available,
    required this.averageSignal,
    required this.utilization,
    required this.signalCount,
  });

  factory GnssSystemStats.fromMap(Map<String, dynamic> map) {
    // Handle Java Object types
    final total = map['total'];
    final used = map['used'];
    final available = map['available'];
    final averageSignal = map['averageSignal'];
    final utilization = map['utilization'];
    final signalCount = map['signalCount'];

    return GnssSystemStats(
      name: map['name'] as String? ?? 'UNKNOWN',
      flag: map['flag'] as String? ?? '🌐',
      total: total is int ? total : (total is num ? total.toInt() : 0),
      used: used is int ? used : (used is num ? used.toInt() : 0),
      available: available is int ? available : (available is num ? available.toInt() : 0),
      averageSignal: averageSignal is double ? averageSignal : 
                    (averageSignal is num ? averageSignal.toDouble() : 0.0),
      utilization: utilization is double ? utilization : 
                  (utilization is num ? utilization.toDouble() : 0.0),
      signalCount: signalCount is int ? signalCount : (signalCount is num ? signalCount.toInt() : 0),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'flag': flag,
      'total': total,
      'used': used,
      'available': available,
      'averageSignal': averageSignal,
      'utilization': utilization,
      'signalCount': signalCount,
    };
  }

  @override
  String toString() {
    return 'GnssSystemStats(name: $name, total: $total, used: $used, signal: ${averageSignal.toStringAsFixed(1)}dB)';
  }
}