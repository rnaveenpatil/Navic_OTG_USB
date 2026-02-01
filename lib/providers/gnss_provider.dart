import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:usb_serial/usb_serial.dart';
import '../utils/nmea_parser.dart';

class Satellite {
  final int prn;
  final int elevation;
  final int azimuth;
  final int snr;
  bool inUse;
  final String system;
  final String constellation;

  Satellite({
    required this.prn,
    required this.elevation,
    required this.azimuth,
    required this.snr,
    this.inUse = false,
    required this.system,
    required this.constellation,
  });
}

class GNSSData {
  double? latitude;
  double? longitude;
  double? altitude;
  double? speed;
  double? course;
  double? hdop;
  double? pdop;
  double? vdop;
  int? satellitesInView;
  int? satellitesInUse;
  bool hasFix = false;
  String status = "No Data";
  DateTime? timestamp;
  List<Satellite> satellites = [];
  String rawNMEA = "";
  Map<String, int> systemCounts = {};
  Map<String, List<Satellite>> satellitesBySystem = {};
  bool isMultiGnss = false;
  bool hasIrnss = false;
  bool hasGalileo = false;
  bool hasGlonass = false;
  bool hasBeidou = false;
  int bytesReceived = 0;
  int nmeaSentences = 0;

  void clear() {
    latitude = null;
    longitude = null;
    altitude = null;
    speed = null;
    course = null;
    hdop = null;
    pdop = null;
    vdop = null;
    satellitesInView = null;
    satellitesInUse = null;
    hasFix = false;
    status = "No Data";
    timestamp = null;
    satellites.clear();
    bytesReceived = 0;
    nmeaSentences = 0;
    rawNMEA = "";
    systemCounts.clear();
    satellitesBySystem.clear();
    isMultiGnss = false;
    hasIrnss = false;
    hasGalileo = false;
    hasGlonass = false;
    hasBeidou = false;
  }

  void updateSystemCounts() {
    systemCounts.clear();
    satellitesBySystem.clear();

    for (var sat in satellites) {
      systemCounts.update(sat.system, (value) => value + 1, ifAbsent: () => 1);

      if (!satellitesBySystem.containsKey(sat.system)) {
        satellitesBySystem[sat.system] = [];
      }
      satellitesBySystem[sat.system]!.add(sat);
    }

    hasIrnss = systemCounts.keys.any((sys) => sys.contains('IRNSS') || sys.contains('NavIC'));
    hasGalileo = systemCounts.keys.any((sys) => sys.contains('Galileo'));
    hasGlonass = systemCounts.keys.any((sys) => sys.contains('GLONASS'));
    hasBeidou = systemCounts.keys.any((sys) => sys.contains('BeiDou'));
    isMultiGnss = systemCounts.keys.length > 1 || hasIrnss || hasGalileo || hasGlonass || hasBeidou;
  }
}

class GNSSProvider with ChangeNotifier {
  bool _isConnected = false;
  bool _isConnecting = false;
  String _connectionStatus = "Disconnected";
  String _deviceName = "";
  String _errorMessage = "";
  bool _hasError = false;
  int _baudRate = 9600;
  bool _connectionStable = true;
  DateTime? _lastDataReceived;

  static const List<int> baudRates = [4800, 9600, 19200, 38400, 57600, 115200, 230400, 460800];

  // Statistics
  int _bytesReceived = 0;
  int _nmeaSentencesCount = 0;
  DateTime? _connectionStartTime;
  int _connectionRetries = 0;
  int _maxRetries = 3;

  // Data
  final GNSSData _data = GNSSData();
  final List<String> _rawBuffer = [];
  final NMEAParser _parser = NMEAParser();

  // USB
  UsbPort? _port;
  StreamSubscription<Uint8List>? _subscription;
  String _buffer = "";

  // Connection monitoring
  Timer? _connectionMonitorTimer;
  Timer? _keepAliveTimer;
  final _connectionTimeout = const Duration(seconds: 10);
  final _keepAliveInterval = const Duration(seconds: 5);

  // Getters
  bool get isConnected => _isConnected;
  bool get isConnecting => _isConnecting;
  String get connectionStatus => _connectionStatus;
  String get deviceName => _deviceName;
  String get errorMessage => _errorMessage;
  bool get hasError => _hasError;
  int get baudRate => _baudRate;
  bool get connectionStable => _connectionStable;

  int get bytesReceived => _bytesReceived;
  int get nmeaSentences => _nmeaSentencesCount;
  Duration? get connectionDuration => _connectionStartTime != null ? DateTime.now().difference(_connectionStartTime!) : null;

  GNSSData get data => _data;
  List<String> get rawBuffer => _rawBuffer;

  void changeBaudRate(int rate) {
    _baudRate = rate;
    if (_isConnected && _port != null) {
      _reconfigurePort();
    }
    notifyListeners();
  }

  Future<void> connectToDevice() async {
    if (_isConnected) return;

    _isConnecting = true;
    _hasError = false;
    _errorMessage = "";
    _connectionStatus = "Scanning devices...";
    notifyListeners();

    try {
      List<UsbDevice> devices = await UsbSerial.listDevices();

      if (devices.isEmpty) {
        _setError("No USB devices found");
        return;
      }

      // Find GNSS devices
      UsbDevice? gnssDevice;
      for (var device in devices) {
        final productName = device.productName?.toLowerCase() ?? '';
        if (productName.contains('gps') || productName.contains('gnss')) {
          gnssDevice = device;
          break;
        }
      }

      final device = gnssDevice ?? devices.first;
      _deviceName = device.productName ?? "Unknown Device";
      _connectionStatus = "Connecting to $_deviceName...";
      notifyListeners();

      _port = await device.create();
      if (_port == null) {
        _setError("Failed to create port");
        return;
      }

      bool openResult = await _port!.open();
      if (!openResult) {
        _setError("Failed to open port");
        return;
      }

      await _configurePort();

      _isConnected = true;
      _isConnecting = false;
      _connectionStatus = "Connected";
      _connectionStartTime = DateTime.now();
      _lastDataReceived = DateTime.now();
      _connectionRetries = 0;

      // Start listening
      _subscription = _port!.inputStream!.listen(_onDataReceived, onError: (e) {
        _handleConnectionError("Read error: $e");
      }, onDone: () {
        _handleConnectionError("Stream closed");
      });

      _startConnectionMonitoring();
      notifyListeners();
    } catch (e) {
      _setError("Connection failed: $e");
    }
  }

  Future<void> _configurePort() async {
    if (_port == null) return;

    try {
      await _port!.setDTR(true);
      await _port!.setRTS(true);
      await _port!.setPortParameters(_baudRate, UsbPort.DATABITS_8,
          UsbPort.STOPBITS_1, UsbPort.PARITY_NONE);

      // Send GNSS configuration
      await _sendGnssConfiguration();
      _connectionStable = true;
    } catch (e) {
      print("Port configuration error: $e");
    }
  }

  Future<void> _sendGnssConfiguration() async {
    if (_port == null) return;

    try {
      // Common NMEA configuration commands
      final commands = [
        "\$PMTK314,1,1,1,1,1,5,0,0,0,0,0,0,0,0,0,0,0,0,0*29\r\n", // Enable all messages
        "\$PMTK220,100*2F\r\n", // Set update rate to 10Hz
      ];

      for (var cmd in commands) {
        await _port!.write(Uint8List.fromList(cmd.codeUnits));
        await Future.delayed(const Duration(milliseconds: 100));
      }
    } catch (e) {
      print("Configuration error: $e");
    }
  }

  void _startConnectionMonitoring() {
    _connectionMonitorTimer?.cancel();
    _keepAliveTimer?.cancel();

    _connectionMonitorTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      if (_isConnected && _lastDataReceived != null) {
        final timeSinceLastData = DateTime.now().difference(_lastDataReceived!);
        if (timeSinceLastData > _connectionTimeout) {
          _handleConnectionError("No data for ${timeSinceLastData.inSeconds}s");
        }
      }
    });

    _keepAliveTimer = Timer.periodic(_keepAliveInterval, (timer) async {
      if (_isConnected && _port != null) {
        try {
          await _port!.write(Uint8List.fromList("\$PMTK605*31\r\n".codeUnits));
        } catch (e) {
          // Ignore keep-alive errors
        }
      }
    });
  }

  void _handleConnectionError(String error) {
    if (!_isConnected) return;

    print("Connection error: $error");

    if (_connectionRetries < _maxRetries) {
      _connectionRetries++;
      _connectionStatus = "Reconnecting... ($_connectionRetries/$_maxRetries)";
      _connectionStable = false;
      notifyListeners();

      Future.delayed(const Duration(seconds: 2), () async {
        try {
          await disconnect();
          await connectToDevice();
        } catch (e) {
          _setError("Reconnection failed: $e");
        }
      });
    } else {
      _setError("Connection lost: $error");
    }
  }

  Future<void> disconnect() async {
    _cleanup();
    _isConnected = false;
    _connectionStatus = "Disconnected";
    _deviceName = "";
    _connectionStable = true;
    _connectionRetries = 0;
    notifyListeners();
  }

  void _cleanup() {
    _connectionMonitorTimer?.cancel();
    _keepAliveTimer?.cancel();
    _connectionMonitorTimer = null;
    _keepAliveTimer = null;

    _subscription?.cancel();
    _subscription = null;
    _port?.close();
    _port = null;
    _connectionStartTime = null;
    _lastDataReceived = null;
    _data.clear();
    _isConnecting = false;
  }

  void _setError(String msg) {
    _errorMessage = msg;
    _hasError = true;
    _isConnecting = false;
    _cleanup();
    _connectionStatus = "Error";
    _connectionStable = false;
    notifyListeners();
  }

  void _onDataReceived(Uint8List rawData) {
    _bytesReceived += rawData.length;
    _data.bytesReceived = _bytesReceived;
    _lastDataReceived = DateTime.now();
    _connectionStable = true;

    try {
      String chunk = utf8.decode(rawData, allowMalformed: true);
      _buffer += chunk;

      while (_buffer.contains('\n')) {
        int index = _buffer.indexOf('\n');
        String sentence = _buffer.substring(0, index).trim();
        _buffer = _buffer.substring(index + 1);

        if (sentence.isNotEmpty) {
          _processSentence(sentence);
        }
      }
    } catch (e) {
      print("Error processing data: $e");
    }
    notifyListeners();
  }

  void _processSentence(String sentence) {
    _nmeaSentencesCount++;
    _data.nmeaSentences = _nmeaSentencesCount;
    if (_rawBuffer.length > 100) _rawBuffer.removeAt(0);
    _rawBuffer.add(sentence);
    _data.rawNMEA = sentence;

    Map<String, dynamic> parsed = _parser.parse(sentence);
    if (parsed.isNotEmpty) {
      _updateData(parsed);
    }

    _parseGnssSpecificData(sentence);
  }

  void _parseGnssSpecificData(String sentence) {
    if (sentence.startsWith('\$GNGSA') || sentence.startsWith('\$GPGSA')) {
      List<String> parts = sentence.split(',');
      if (parts.length >= 18) {
        List<int> usedSatellites = [];
        for (int i = 3; i <= 14; i++) {
          if (parts[i].isNotEmpty) {
            int? prn = int.tryParse(parts[i]);
            if (prn != null && prn > 0) usedSatellites.add(prn);
          }
        }

        for (var sat in _data.satellites) {
          sat.inUse = usedSatellites.contains(sat.prn);
        }
      }
    }

    if (sentence.startsWith('\$GPGSV') ||
        sentence.startsWith('\$GLGSV') ||
        sentence.startsWith('\$GAGSV') ||
        sentence.startsWith('\$GBGSV') ||
        sentence.startsWith('\$GIGSV') ||
        sentence.startsWith('\$GQGSV') ||
        sentence.startsWith('\$GNGSV')) {
      _parseGSVMessage(sentence);
    }
  }

  void _parseGSVMessage(String sentence) {
    List<String> parts = sentence.split(',');
    if (parts.length < 4) return;

    String system = 'GPS';
    if (sentence.startsWith('\$GL')) system = 'GLONASS';
    if (sentence.startsWith('\$GA')) system = 'Galileo';
    if (sentence.startsWith('\$GB')) system = 'BeiDou';
    if (sentence.startsWith('\$GI')) system = 'IRNSS';
    if (sentence.startsWith('\$GQ')) system = 'QZSS';

    int totalSats = int.tryParse(parts[3]) ?? 0;
    _data.satellitesInView = totalSats;

    List<Satellite> newSats = [];
    for (int i = 4; i + 3 < parts.length && i < 20; i += 4) {
      if (parts[i].isNotEmpty) {
        int prn = int.tryParse(parts[i]) ?? 0;
        int elevation = int.tryParse(parts[i + 1]) ?? 0;
        int azimuth = int.tryParse(parts[i + 2]) ?? 0;
        int snr = int.tryParse(parts[i + 3]) ?? 0;

        String constellation = _getConstellationFromPrn(prn, system);

        newSats.add(Satellite(
          prn: prn,
          elevation: elevation,
          azimuth: azimuth,
          snr: snr,
          inUse: false,
          system: system,
          constellation: constellation,
        ));
      }
    }

    _mergeSatellites(newSats);
    _data.updateSystemCounts();
  }

  String _getConstellationFromPrn(int prn, String system) {
    switch (system) {
      case 'GPS': return 'GPS (USA)';
      case 'GLONASS': return 'GLONASS (Russia)';
      case 'Galileo': return 'Galileo (EU)';
      case 'BeiDou': return 'BeiDou (China)';
      case 'IRNSS': return 'IRNSS/NavIC (India)';
      case 'QZSS': return 'QZSS (Japan)';
      default:
        if (prn >= 120 && prn <= 158) return 'IRNSS/NavIC (India)';
        if (prn >= 201 && prn <= 235) return 'BeiDou (China)';
        if (prn >= 301 && prn <= 336) return 'Galileo (EU)';
        if (prn >= 65 && prn <= 96) return 'GLONASS (Russia)';
        if (prn >= 193 && prn <= 202) return 'QZSS (Japan)';
        return 'GPS (USA)';
    }
  }

  void _mergeSatellites(List<Satellite> newSats) {
    if (newSats.isNotEmpty) {
      String system = newSats.first.system;
      _data.satellites.removeWhere((sat) => sat.system == system);
    }

    _data.satellites.addAll(newSats);
    _data.satellites.sort((a, b) {
      int systemCompare = a.system.compareTo(b.system);
      if (systemCompare != 0) return systemCompare;
      return a.prn.compareTo(b.prn);
    });

    if (_data.satellites.length > 50) {
      _data.satellites = _data.satellites.sublist(0, 50);
    }
  }

  void _updateData(Map<String, dynamic> parsed) {
    String type = parsed['type'];

    if (parsed.containsKey('latitude')) _data.latitude = parsed['latitude'];
    if (parsed.containsKey('longitude')) _data.longitude = parsed['longitude'];
    if (parsed.containsKey('hasFix')) _data.hasFix = parsed['hasFix'] ?? false;
    if (parsed.containsKey('status')) _data.status = parsed['status'];

    if (type == '\$GPGGA' || type == '\$GNGGA') {
      if (parsed.containsKey('altitude')) _data.altitude = parsed['altitude'];
      if (parsed.containsKey('hdop')) _data.hdop = parsed['hdop'];
      if (parsed.containsKey('satellites')) {
        _data.satellitesInUse = parsed['satellites'];
      }
      _data.timestamp = DateTime.now();
    } else if (type == '\$GPRMC' || type == '\$GNRMC') {
      if (parsed.containsKey('speed')) _data.speed = parsed['speed'];
      if (parsed.containsKey('course')) _data.course = parsed['course'];
    } else if (type == '\$GPGSA' || type == '\$GNGSA') {
      if (parsed.containsKey('pdop')) _data.pdop = parsed['pdop'];
      if (parsed.containsKey('hdop')) _data.hdop = parsed['hdop'];
      if (parsed.containsKey('vdop')) _data.vdop = parsed['vdop'];
    }
  }

  Future<void> _reconfigurePort() async {
    if (_port == null || !_isConnected) return;
    try {
      await _port!.setPortParameters(_baudRate, UsbPort.DATABITS_8,
          UsbPort.STOPBITS_1, UsbPort.PARITY_NONE);
    } catch (e) {
      print("Port reconfiguration error: $e");
    }
  }

  @override
  void dispose() {
    _cleanup();
    super.dispose();
  }
}