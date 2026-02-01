class GnssSatellite {
  final int svid;
  final String system;
  final double cn0DbHz;
  final double elevation;
  final double azimuth;
  final bool usedInFix;
  final int constellationType;
  final int carrierFrequencyHz;

  GnssSatellite({
    required this.svid,
    required this.system,
    required this.cn0DbHz,
    required this.elevation,
    required this.azimuth,
    required this.usedInFix,
    required this.constellationType,
    required this.carrierFrequencyHz,
  });
}
