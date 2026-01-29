// lib/models/usb_gnss_device.dart
import 'dart:convert';

class UsbGnssDevice {
  final String deviceName;
  final int vendorId;
  final int productId;
  final String vendorName;
  final int deviceClass;
  final int deviceSubclass;
  final int deviceProtocol;
  final int interfaceCount;
  final String? serialNumber;
  final String? productName;
  final String? manufacturer;
  final int? version;
  final String? usbPath;
  final bool isConnected;
  final bool hasPermission;

  UsbGnssDevice({
    required this.deviceName,
    required this.vendorId,
    required this.productId,
    required this.vendorName,
    required this.deviceClass,
    required this.deviceSubclass,
    required this.deviceProtocol,
    required this.interfaceCount,
    this.serialNumber,
    this.productName,
    this.manufacturer,
    this.version,
    this.usbPath,
    this.isConnected = false,
    this.hasPermission = false,
  });

  factory UsbGnssDevice.fromMap(Map<String, dynamic> map) {
    return UsbGnssDevice(
      deviceName: map['deviceName']?.toString() ?? 'Unknown',
      vendorId: _parseInt(map['vendorId']),
      productId: _parseInt(map['productId']),
      vendorName: map['vendorName']?.toString() ?? 'Unknown',
      deviceClass: _parseInt(map['deviceClass']),
      deviceSubclass: _parseInt(map['deviceSubclass']),
      deviceProtocol: _parseInt(map['deviceProtocol']),
      interfaceCount: _parseInt(map['interfaceCount']),
      serialNumber: map['serialNumber']?.toString(),
      productName: map['productName']?.toString(),
      manufacturer: map['manufacturer']?.toString(),
      version: _parseInt(map['version']),
      usbPath: map['usbPath']?.toString(),
      isConnected: map['isConnected'] as bool? ?? false,
      hasPermission: map['hasPermission'] as bool? ?? false,
    );
  }

  static int _parseInt(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) {
      if (value.startsWith('0x')) {
        return int.tryParse(value.substring(2), radix: 16) ?? 0;
      }
      return int.tryParse(value) ?? 0;
    }
    return 0;
  }

  bool get isPotentialGnssDevice {
    // Check if vendor ID is in known GNSS vendors
    const gnssVendors = {
      0x067B: 'Prolific',      // PL2303
      0x0403: 'FTDI',          // FT232/FT245
      0x10C4: 'Silicon Labs',  // CP210x
      0x1546: 'u-blox',
      0x0FCF: 'Garmin',
      0x05C6: 'Qualcomm',
      0x1199: 'Sierra Wireless',
      0x12D1: 'Huawei',
      0x2C7C: 'Quectel',
      0x1D6B: 'Linux Foundation', // USB Host
      0x0BDA: 'Realtek',
      0x0483: 'STMicroelectronics',
    };

    if (gnssVendors.containsKey(vendorId)) {
      return true;
    }

    // Check device class (0x02 = Communications, 0xEF = Miscellaneous)
    if (deviceClass == 0x02 || deviceClass == 0xEF) {
      return true;
    }

    // Check for GNSS in product name
    if (productName?.toLowerCase().contains('gnss') == true ||
        productName?.toLowerCase().contains('gps') == true ||
        productName?.toLowerCase().contains('navic') == true ||
        deviceName.toLowerCase().contains('gnss') == true ||
        deviceName.toLowerCase().contains('gps') == true ||
        deviceName.toLowerCase().contains('navic') == true) {
      return true;
    }

    return false;
  }

  String get vendorIdHex => '0x${vendorId.toRadixString(16).toUpperCase().padLeft(4, '0')}';
  String get productIdHex => '0x${productId.toRadixString(16).toUpperCase().padLeft(4, '0')}';

  String get displayName {
    if (productName != null && productName!.isNotEmpty) {
      return '$productName (${vendorIdHex}:${productIdHex})';
    }
    return '$deviceName (${vendorIdHex}:${productIdHex})';
  }

  Map<String, dynamic> toMap() {
    return {
      'deviceName': deviceName,
      'vendorId': vendorId,
      'productId': productId,
      'vendorIdHex': vendorIdHex,
      'productIdHex': productIdHex,
      'vendorName': vendorName,
      'productName': productName,
      'manufacturer': manufacturer,
      'deviceClass': deviceClass,
      'deviceSubclass': deviceSubclass,
      'deviceProtocol': deviceProtocol,
      'interfaceCount': interfaceCount,
      'serialNumber': serialNumber,
      'version': version,
      'usbPath': usbPath,
      'isConnected': isConnected,
      'hasPermission': hasPermission,
      'isPotentialGnss': isPotentialGnssDevice,
      'displayName': displayName,
    };
  }

  String toJson() => json.encode(toMap());
  factory UsbGnssDevice.fromJson(String jsonStr) =>
      UsbGnssDevice.fromMap(json.decode(jsonStr));

  @override
  String toString() {
    return 'UsbGnssDevice($displayName, VID: $vendorIdHex, PID: $productIdHex, Vendor: $vendorName, Connected: $isConnected)';
  }
}

class UsbGnssHardwareInfo {
  final int vendorId;
  final int productId;
  final String vendorName;
  final String deviceName;
  final String connectionStatus;
  final List<String> supportedBands;
  final List<String> supportedConstellations;
  final int maxChannels;
  final String updateRate;
  final String accuracy;
  final String chipsetType;
  final String firmwareVersion;
  final String protocol;
  final int baudRate;
  final bool hasL5Band;
  final bool hasL2Band;
  final bool hasMultiGNSS;
  final bool hasRTK;
  final int timestamp;
  final String portPath;
  final bool isStreaming;
  final double? latitude;
  final double? longitude;
  final double? altitude;
  final double? speed;
  final double? bearing;
  final double? hdop;
  final double? vdop;
  final double? pdop;
  final int satelliteCount;
  final int satellitesInView;

  UsbGnssHardwareInfo({
    required this.vendorId,
    required this.productId,
    required this.vendorName,
    required this.deviceName,
    required this.connectionStatus,
    required this.supportedBands,
    required this.supportedConstellations,
    required this.maxChannels,
    required this.updateRate,
    required this.accuracy,
    required this.chipsetType,
    required this.firmwareVersion,
    required this.protocol,
    required this.baudRate,
    required this.hasL5Band,
    required this.hasL2Band,
    required this.hasMultiGNSS,
    required this.hasRTK,
    required this.timestamp,
    required this.portPath,
    required this.isStreaming,
    this.latitude,
    this.longitude,
    this.altitude,
    this.speed,
    this.bearing,
    this.hdop,
    this.vdop,
    this.pdop,
    this.satelliteCount = 0,
    this.satellitesInView = 0,
  });

  factory UsbGnssHardwareInfo.fromMap(Map<String, dynamic> map) {
    return UsbGnssHardwareInfo(
      vendorId: map['vendorId'] as int? ?? 0,
      productId: map['productId'] as int? ?? 0,
      vendorName: map['vendorName']?.toString() ?? 'Unknown',
      deviceName: map['deviceName']?.toString() ?? 'Unknown',
      connectionStatus: map['connectionStatus']?.toString() ?? 'DISCONNECTED',
      supportedBands: List<String>.from(map['supportedBands'] ?? []),
      supportedConstellations: List<String>.from(map['supportedConstellations'] ?? []),
      maxChannels: map['maxChannels'] as int? ?? 0,
      updateRate: map['updateRate']?.toString() ?? 'Unknown',
      accuracy: map['accuracy']?.toString() ?? 'Unknown',
      chipsetType: map['chipsetType']?.toString() ?? 'Unknown',
      firmwareVersion: map['firmwareVersion']?.toString() ?? 'Unknown',
      protocol: map['protocol']?.toString() ?? 'NMEA',
      baudRate: map['baudRate'] as int? ?? 9600,
      hasL5Band: map['hasL5Band'] as bool? ?? false,
      hasL2Band: map['hasL2Band'] as bool? ?? false,
      hasMultiGNSS: map['hasMultiGNSS'] as bool? ?? false,
      hasRTK: map['hasRTK'] as bool? ?? false,
      timestamp: map['timestamp'] as int? ?? DateTime.now().millisecondsSinceEpoch,
      portPath: map['portPath']?.toString() ?? '/dev/ttyUSB0',
      isStreaming: map['isStreaming'] as bool? ?? false,
      latitude: map['latitude'] as double?,
      longitude: map['longitude'] as double?,
      altitude: map['altitude'] as double?,
      speed: map['speed'] as double?,
      bearing: map['bearing'] as double?,
      hdop: map['hdop'] as double?,
      vdop: map['vdop'] as double?,
      pdop: map['pdop'] as double?,
      satelliteCount: map['satelliteCount'] as int? ?? 0,
      satellitesInView: map['satellitesInView'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'vendorId': vendorId,
      'productId': productId,
      'vendorName': vendorName,
      'deviceName': deviceName,
      'connectionStatus': connectionStatus,
      'supportedBands': supportedBands,
      'supportedConstellations': supportedConstellations,
      'maxChannels': maxChannels,
      'updateRate': updateRate,
      'accuracy': accuracy,
      'chipsetType': chipsetType,
      'firmwareVersion': firmwareVersion,
      'protocol': protocol,
      'baudRate': baudRate,
      'hasL5Band': hasL5Band,
      'hasL2Band': hasL2Band,
      'hasMultiGNSS': hasMultiGNSS,
      'hasRTK': hasRTK,
      'timestamp': timestamp,
      'portPath': portPath,
      'isStreaming': isStreaming,
      'latitude': latitude,
      'longitude': longitude,
      'altitude': altitude,
      'speed': speed,
      'bearing': bearing,
      'hdop': hdop,
      'vdop': vdop,
      'pdop': pdop,
      'satelliteCount': satelliteCount,
      'satellitesInView': satellitesInView,
    };
  }

  String toJson() => json.encode(toMap());
  factory UsbGnssHardwareInfo.fromJson(String jsonStr) =>
      UsbGnssHardwareInfo.fromMap(json.decode(jsonStr));

  @override
  String toString() {
    return 'UsbGnssHardwareInfo($deviceName, Chipset: $chipsetType, Status: $connectionStatus, Streaming: $isStreaming)';
  }
}