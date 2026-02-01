// lib/utils/nmea_parser.dart
class NMEAParser {
  Map<String, dynamic> parse(String sentence) {
    if (!sentence.startsWith('\$') || !sentence.contains('*')) {
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
        if (parts.length >= 7) {
          result['latitude'] = _parseLatitude(parts[1], parts[2]);
          result['longitude'] = _parseLongitude(parts[3], parts[4]);
          result['time'] = parts[5];
          result['status'] = parts[6]; // A=Valid, V=Invalid
          result['hasFix'] = parts[6] == 'A';
        }
        break;

      case '\$GNGGA': // Global Positioning System Fix Data
        if (parts.length >= 15) {
          result['time'] = parts[1];
          result['latitude'] = _parseLatitude(parts[2], parts[3]);
          result['longitude'] = _parseLongitude(parts[4], parts[5]);
          result['quality'] = int.tryParse(parts[6]) ?? 0;
          result['satellites'] = int.tryParse(parts[7]) ?? 0;
          result['hdop'] = double.tryParse(parts[8]) ?? 0.0;
          result['altitude'] = double.tryParse(parts[9]) ?? 0.0;
          result['hasFix'] = result['quality'] > 0;
        }
        break;

      case '\$GNRMC': // Recommended Minimum Specific GNSS Data
        if (parts.length >= 12) {
          result['time'] = parts[1];
          result['status'] = parts[2]; // A=Valid, V=Invalid
          result['latitude'] = _parseLatitude(parts[3], parts[4]);
          result['longitude'] = _parseLongitude(parts[5], parts[6]);
          result['speed'] = double.tryParse(parts[7]) ?? 0.0;
          result['course'] = double.tryParse(parts[8]) ?? 0.0;
          result['date'] = parts[9];
          result['hasFix'] = parts[2] == 'A';
        }
        break;

      case '\$GPGSV': // GNSS Satellites in View
        if (parts.length >= 4) {
          result['totalMessages'] = int.tryParse(parts[1]) ?? 1;
          result['messageNumber'] = int.tryParse(parts[2]) ?? 1;
          result['satellitesInView'] = int.tryParse(parts[3]) ?? 0;

          // Parse satellite info (up to 4 satellites per message)
          List<Map<String, dynamic>> satellites = [];
          for (int i = 4; i + 3 < parts.length; i += 4) {
            if (parts[i].isNotEmpty) {
              satellites.add({
                'prn': int.tryParse(parts[i]) ?? 0,
                'elevation': int.tryParse(parts[i + 1]) ?? 0,
                'azimuth': int.tryParse(parts[i + 2]) ?? 0,
                'snr': int.tryParse(parts[i + 3]) ?? 0,
              });
            }
          }
          result['satellites'] = satellites;
        }
        break;
    }

    return result;
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
}
