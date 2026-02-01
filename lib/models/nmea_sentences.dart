class NMEAParser {
  Map<String, dynamic> parse(String sentence) {
    if (!sentence.startsWith('\$') || !sentence.contains('*')) {
      return {};
    }

    // Validate checksum
    if (!_validateChecksum(sentence)) {
      return {};
    }

    // Remove checksum
    String data = sentence.split('*')[0];
    List<String> parts = data.split(',');

    if (parts.isEmpty) return {};

    String sentenceType = parts[0];
    Map<String, dynamic> result = {'type': sentenceType};

    switch (sentenceType) {
      case '\$GNGLL': // Geographic Position - Latitude/Longitude
      case '\$GPGLL':
        if (parts.length >= 7) {
          result['latitude'] = _parseLatitude(parts[1], parts[2]);
          result['longitude'] = _parseLongitude(parts[3], parts[4]);
          result['time'] = parts[5];
          result['status'] = parts[6]; // A=Valid, V=Invalid
          result['hasFix'] = parts[6] == 'A';
          result['system'] = sentenceType.startsWith('\$GN') ? 'Multi-GNSS' : 'GPS';
        }
        break;

      case '\$GNGGA': // Global Positioning System Fix Data
      case '\$GPGGA':
        if (parts.length >= 15) {
          result['time'] = parts[1];
          result['latitude'] = _parseLatitude(parts[2], parts[3]);
          result['longitude'] = _parseLongitude(parts[4], parts[5]);
          result['quality'] = int.tryParse(parts[6]) ?? 0;
          result['satellites'] = int.tryParse(parts[7]) ?? 0;
          result['hdop'] = double.tryParse(parts[8]) ?? 0.0;
          result['altitude'] = double.tryParse(parts[9]) ?? 0.0;
          result['hasFix'] = result['quality'] > 0;
          result['system'] = sentenceType.startsWith('\$GN') ? 'Multi-GNSS' : 'GPS';

          // Parse geoidal separation if available
          if (parts.length > 11) {
            result['geoidalSeparation'] = double.tryParse(parts[11]) ?? 0.0;
          }
        }
        break;

      case '\$GNRMC': // Recommended Minimum Specific GNSS Data
      case '\$GPRMC':
        if (parts.length >= 12) {
          result['time'] = parts[1];
          result['status'] = parts[2]; // A=Valid, V=Invalid
          result['latitude'] = _parseLatitude(parts[3], parts[4]);
          result['longitude'] = _parseLongitude(parts[5], parts[6]);
          result['speed'] = double.tryParse(parts[7]) ?? 0.0;
          result['course'] = double.tryParse(parts[8]) ?? 0.0;
          result['date'] = parts[9];
          result['hasFix'] = parts[2] == 'A';
          result['system'] = sentenceType.startsWith('\$GN') ? 'Multi-GNSS' : 'GPS';

          // Parse magnetic variation if available
          if (parts.length > 10) {
            result['magneticVariation'] = parts[10];
            if (parts.length > 11) {
              result['magneticVariationDirection'] = parts[11];
            }
          }
        }
        break;

      case '\$GPGSV': // GPS Satellites in View
      case '\$GLGSV': // GLONASS Satellites in View
      case '\$GAGSV': // Galileo Satellites in View
      case '\$GBGSV': // BeiDou Satellites in View
      case '\$GIGSV': // IRNSS Satellites in View
      case '\$GQGSV': // QZSS Satellites in View
      case '\$GNGSV': // Multi-GNSS Satellites in View
        if (parts.length >= 4) {
          result['totalMessages'] = int.tryParse(parts[1]) ?? 1;
          result['messageNumber'] = int.tryParse(parts[2]) ?? 1;
          result['satellitesInView'] = int.tryParse(parts[3]) ?? 0;

          // Determine system
          result['system'] = _getSystemFromSentenceType(sentenceType);
          result['constellation'] = _getConstellationFromSentenceType(sentenceType);

          // Parse satellite info (up to 4 satellites per message)
          List<Map<String, dynamic>> satellites = [];
          for (int i = 4; i + 3 < parts.length; i += 4) {
            if (parts[i].isNotEmpty) {
              int prn = int.tryParse(parts[i]) ?? 0;
              int elevation = int.tryParse(parts[i + 1]) ?? 0;
              int azimuth = int.tryParse(parts[i + 2]) ?? 0;
              int snr = int.tryParse(parts[i + 3]) ?? 0;

              // Adjust PRN for system
              int adjustedPrn = _adjustPrnForSystem(prn, sentenceType);

              satellites.add({
                'prn': adjustedPrn,
                'originalPrn': prn,
                'elevation': elevation,
                'azimuth': azimuth,
                'snr': snr,
                'system': result['system'],
                'constellation': result['constellation'],
              });
            }
          }
          result['satellites'] = satellites;
        }
        break;

      case '\$GPGSA': // GPS DOP and Active Satellites
      case '\$GNGSA': // Multi-GNSS DOP and Active Satellites
      case '\$GLGSA': // GLONASS DOP and Active Satellites
      case '\$GAGSA': // Galileo DOP and Active Satellites
        if (parts.length >= 18) {
          result['mode'] = parts[1]; // M=Manual, A=Automatic
          result['fixType'] = int.tryParse(parts[2]) ?? 1; // 1=No fix, 2=2D, 3=3D
          result['hasFix'] = result['fixType'] > 1;

          // Parse used satellite PRNs
          List<int> usedSatellites = [];
          for (int i = 3; i <= 14; i++) {
            if (parts[i].isNotEmpty) {
              int? prn = int.tryParse(parts[i]);
              if (prn != null && prn > 0) {
                usedSatellites.add(prn);
              }
            }
          }
          result['usedSatellites'] = usedSatellites;

          // Parse DOP values
          result['pdop'] = double.tryParse(parts[15]) ?? 0.0;
          result['hdop'] = double.tryParse(parts[16]) ?? 0.0;
          result['vdop'] = double.tryParse(parts[17]) ?? 0.0;

          result['system'] = _getSystemFromSentenceType(sentenceType);
        }
        break;

      case '\$GPVTG': // Course Over Ground and Ground Speed
      case '\$GNVTG':
        if (parts.length >= 9) {
          result['trueCourse'] = double.tryParse(parts[1]) ?? 0.0;
          result['magneticCourse'] = double.tryParse(parts[3]) ?? 0.0;
          result['speedKnots'] = double.tryParse(parts[5]) ?? 0.0;
          result['speedKmh'] = double.tryParse(parts[7]) ?? 0.0;
          result['system'] = sentenceType.startsWith('\$GN') ? 'Multi-GNSS' : 'GPS';
        }
        break;
    }

    return result;
  }

  bool _validateChecksum(String sentence) {
    try {
      if (!sentence.contains('*')) return true;

      String data = sentence.split('*')[0];
      String checksumStr = sentence.split('*')[1];
      int expectedChecksum = int.tryParse(checksumStr, radix: 16) ?? 0;

      int checksum = 0;
      for (int i = 1; i < data.length; i++) {
        checksum ^= data.codeUnitAt(i);
      }

      return checksum == expectedChecksum;
    } catch (e) {
      return false;
    }
  }

  String _getSystemFromSentenceType(String type) {
    if (type.startsWith('\$GP')) return 'GPS';
    if (type.startsWith('\$GL')) return 'GLONASS';
    if (type.startsWith('\$GA')) return 'Galileo';
    if (type.startsWith('\$GB')) return 'BeiDou';
    if (type.startsWith('\$GI')) return 'IRNSS';
    if (type.startsWith('\$GQ')) return 'QZSS';
    if (type.startsWith('\$GN')) return 'Multi-GNSS';
    return 'Unknown';
  }

  String _getConstellationFromSentenceType(String type) {
    if (type.startsWith('\$GP')) return 'GPS (USA)';
    if (type.startsWith('\$GL')) return 'GLONASS (Russia)';
    if (type.startsWith('\$GA')) return 'Galileo (EU)';
    if (type.startsWith('\$GB')) return 'BeiDou (China)';
    if (type.startsWith('\$GI')) return 'IRNSS/NavIC (India)';
    if (type.startsWith('\$GQ')) return 'QZSS (Japan)';
    if (type.startsWith('\$GN')) return 'Multi-GNSS';
    return 'Unknown';
  }

  int _adjustPrnForSystem(int prn, String sentenceType) {
    if (sentenceType.startsWith('\$GL')) {
      // GLONASS: 65-96
      return prn + 64;
    } else if (sentenceType.startsWith('\$GA')) {
      // Galileo: 301-336
      return prn + 300;
    } else if (sentenceType.startsWith('\$GB')) {
      // BeiDou: 201-235
      return prn + 200;
    } else if (sentenceType.startsWith('\$GI')) {
      // IRNSS: 120-158
      return prn + 119;
    } else if (sentenceType.startsWith('\$GQ')) {
      // QZSS: 193-202
      return prn + 192;
    }
    return prn; // GPS: 1-32
  }

  double? _parseLatitude(String value, String direction) {
    if (value.isEmpty || value.length < 4) return null;

    try {
      double degrees = double.parse(value.substring(0, 2));
      double minutes = double.parse(value.substring(2));
      double decimal = degrees + (minutes / 60.0);

      return (direction == 'S') ? -decimal : decimal;
    } catch (e) {
      return null;
    }
  }

  double? _parseLongitude(String value, String direction) {
    if (value.isEmpty || value.length < 5) return null;

    try {
      double degrees = double.parse(value.substring(0, 3));
      double minutes = double.parse(value.substring(3));
      double decimal = degrees + (minutes / 60.0);

      return (direction == 'W') ? -decimal : decimal;
    } catch (e) {
      return null;
    }
  }

  // Helper method to detect if sentence contains IRNSS data
  bool containsIrnssData(String sentence) {
    return sentence.contains('\$GI') ||
           sentence.contains('IRNSS') ||
           sentence.contains('NavIC') ||
           _containsIrnssPrn(sentence);
  }

  bool _containsIrnssPrn(String sentence) {
    if (!sentence.contains('\$GNGSV') && !sentence.contains('\$GN')) {
      return false;
    }

    // Check for IRNSS PRN range in multi-GNSS messages
    List<String> parts = sentence.split(',');
    for (String part in parts) {
      int? prn = int.tryParse(part);
      if (prn != null && prn >= 120 && prn <= 158) {
        return true;
      }
    }
    return false;
  }
}