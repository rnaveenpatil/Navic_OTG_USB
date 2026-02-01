import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:syncfusion_flutter_gauges/gauges.dart';
import 'package:flutter/services.dart' show MethodChannel, PlatformException;
import '../providers/gnss_provider.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late TabController _tabController;
  final MapController _mapController = MapController();
  final ScrollController _scrollController = ScrollController();

  // Method channel
  static const MethodChannel _channel =
  MethodChannel('com.example.usb_connect_gnss/usb');

  // USB Connection State
  String _usbDeviceName = "";
  String _usbConnectionStatus = "DISCONNECTED";
  String _chipsetVendor = "Unknown";
  String _chipsetModel = "Unknown";
  bool _usingUsbGnss = false;
  bool _isLoading = false;
  bool _showUsbDevicesDialog = false;
  List<Map<String, dynamic>> _availableUsbDevices = [];
  bool _connectionStable = true;
  int _connectionAttempts = 0;
  int _connectionRetries = 0;
  DateTime? _lastDataTime;
  Timer? _connectionMonitorTimer;
  Timer? _keepAliveTimer;

  // GNSS Data State
  double? _latitude;
  double? _longitude;
  double? _altitude;
  double? _speed;
  double? _course;
  double? _hdop;
  double? _pdop;
  double? _vdop;
  int? _satellitesInView;
  int? _satellitesInUse;
  bool _hasFix = false;
  String _status = "No Data";
  String _rawNMEA = "";
  List<Map<String, dynamic>> _satellites = [];

  // UI State
  bool _showLayerSelection = false;
  bool _showSatelliteList = false;
  bool _showBandPanel = false;
  bool _isBottomPanelVisible = true;
  bool _locationAcquired = false;
  LatLng? _lastValidMapCenter;
  bool _mapZoomed = false;

  // GNSS System Data
  Map<String, List<Map<String, dynamic>>> _satellitesBySystem = {};
  Map<String, Map<String, dynamic>> _systemDetails = {};
  List<String> _availableSystems = [];

  // Map layers
  Map<String, bool> _selectedLayers = {
    'OpenStreetMap Standard': true,
    'ESRI Satellite View': false,
  };

  // Statistics
  int _bytesReceived = 0;
  int _nmeaSentences = 0;
  DateTime? _connectionStartTime;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _tabController = TabController(length: 4, vsync: this);
    _setupMethodChannel();
    _scanUsbDevices();
    _startConnectionMonitoring();

    // Initialize with last known position if available
    _initializeWithLastPosition();
  }

  void _initializeWithLastPosition() async {
    // Try to get last known position from provider or local storage
    final provider = Provider.of<GNSSProvider>(context, listen: false);
    if (provider.data.latitude != null && provider.data.longitude != null) {
      setState(() {
        _latitude = provider.data.latitude;
        _longitude = provider.data.longitude;
        _locationAcquired = true;
        _lastValidMapCenter = LatLng(_latitude!, _longitude!);
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      _checkConnectionStability();
      _scanUsbDevices();
    }
  }

  void _startConnectionMonitoring() {
    _connectionMonitorTimer =
        Timer.periodic(const Duration(seconds: 2), (timer) {
          if (_usingUsbGnss) {
            _checkConnectionStability();
          }
        });

    _keepAliveTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
      if (_usingUsbGnss && _usbDeviceName.isNotEmpty) {
        await _sendKeepAlivePing();
      }
    });
  }

  Future<void> _sendKeepAlivePing() async {
    try {
      await _channel.invokeMethod('keepAlivePing', {
        'vendorId': _getCurrentVendorId(),
        'productId': _getCurrentProductId(),
      });
    } catch (e) {
      // Silent fail
    }
  }

  void _checkConnectionStability() async {
    if (!_usingUsbGnss) return;

    try {
      final isConnected = await _channel.invokeMethod(
        'isUsbDeviceConnected',
        {
          'vendorId': _getCurrentVendorId(),
          'productId': _getCurrentProductId(),
        },
      );

      if (isConnected != true && _connectionRetries < 3) {
        _connectionRetries++;
        setState(() {
          _connectionStable = false;
          _usbConnectionStatus = "RECONNECTING ($_connectionRetries/3)...";
        });

        Future.delayed(const Duration(seconds: 1), () {
          _reconnectDevice();
        });
      } else if (isConnected == true) {
        setState(() {
          _connectionStable = true;
          _connectionRetries = 0;
          _usbConnectionStatus = "CONNECTED";
        });
      }
    } catch (e) {
      // Connection check failed
    }
  }

  void _reconnectDevice() async {
    try {
      final device = _availableUsbDevices.firstWhere(
            (d) => d['deviceName'] == _usbDeviceName,
        orElse: () => {},
      );

      if (device.isNotEmpty) {
        await _channel.invokeMethod('resetConnection', {
          'vendorId': device['vendorId'],
          'productId': device['productId'],
        });

        await Future.delayed(const Duration(seconds: 1));

        final connectionInfo = await _channel.invokeMethod(
          'openUsbDevice',
          {
            'deviceName': _usbDeviceName,
            'vendorId': device['vendorId'],
            'productId': device['productId'],
          },
        );

        if (connectionInfo != null) {
          setState(() {
            _connectionStable = true;
            _connectionRetries = 0;
            _usbConnectionStatus = "RECONNECTED";
          });

          // Reinitialize GNSS data stream
          final provider = Provider.of<GNSSProvider>(context, listen: false);
          if (provider.isConnected) {
            await provider.startDataStream();
          }
        }
      }
    } catch (e) {
      // Reconnect failed
    }
  }

  int? _getCurrentVendorId() {
    if (_availableUsbDevices.isEmpty || _usbDeviceName.isEmpty) return null;
    final device = _availableUsbDevices.firstWhere(
          (d) => d['deviceName'] == _usbDeviceName,
      orElse: () =>
      _availableUsbDevices.isNotEmpty ? _availableUsbDevices[0] : {},
    );
    return device['vendorId'] as int?;
  }

  int? _getCurrentProductId() {
    if (_availableUsbDevices.isEmpty || _usbDeviceName.isEmpty) return null;
    final device = _availableUsbDevices.firstWhere(
          (d) => d['deviceName'] == _usbDeviceName,
      orElse: () =>
      _availableUsbDevices.isNotEmpty ? _availableUsbDevices[0] : {},
    );
    return device['productId'] as int?;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _connectionMonitorTimer?.cancel();
    _keepAliveTimer?.cancel();
    _tabController.dispose();
    _scrollController.dispose();
    _mapController.dispose();
    super.dispose();
  }

  void _setupMethodChannel() {
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'usbDeviceAttached':
          _handleUsbDeviceAttached(call.arguments);
          break;
        case 'usbDeviceDetached':
          _handleUsbDeviceDetached(call.arguments);
          break;
        case 'usbPermissionResult':
          _handleUsbPermissionResult(call.arguments);
          break;
        case 'usbConnectionLost':
          _handleUsbConnectionLost(call.arguments);
          break;
      }
      return null;
    });
  }

  void _handleUsbConnectionLost(Map<dynamic, dynamic> arguments) {
    final connectionKey = arguments['connectionKey'] as String?;
    final reason = arguments['reason'] as String?;

    if (connectionKey != null && _usingUsbGnss) {
      setState(() {
        _connectionStable = false;
        _usbConnectionStatus = "LOST: ${reason ?? 'Unknown'}";
      });

      if (_connectionRetries < 3) {
        _connectionRetries++;
        Future.delayed(const Duration(seconds: 2), () {
          _reconnectDevice();
        });
      }
    }
  }

  Future<void> _scanUsbDevices() async {
    if (_isLoading) return;

    try {
      setState(() {
        _isLoading = true;
        _usbConnectionStatus = "SCANNING...";
      });

      await Future.delayed(const Duration(milliseconds: 500));

      final result = await _channel.invokeMethod('getUsbDevices');
      if (result != null) {
        final Map<String, dynamic> devicesMap =
        Map<String, dynamic>.from(result);

        setState(() {
          _availableUsbDevices = devicesMap.entries.map((entry) {
            final deviceInfo = Map<String, dynamic>.from(entry.value);
            final isRealHardware =
                deviceInfo['isRealHardware'] as bool? ?? false;

            return {
              'deviceName': entry.key,
              'productName': deviceInfo['productName'] ?? 'Unknown Device',
              'vendorId': deviceInfo['vendorId'],
              'productId': deviceInfo['productId'],
              'hasPermission': deviceInfo['hasPermission'] ?? false,
              'isRealHardware': isRealHardware,
              'isGnssDevice': deviceInfo['isGnssDevice'] ?? false,
              'gnssType': deviceInfo['gnssType'] ?? 'Unknown',
              'supportsIrnss': deviceInfo['supportsIrnss'] ?? false,
              'supportsMultiGnss': deviceInfo['supportsMultiGnss'] ?? false,
              'vendorHex':
              '0x${(deviceInfo['vendorId'] as int).toRadixString(16).padLeft(4, '0').toUpperCase()}',
              'productHex':
              '0x${(deviceInfo['productId'] as int).toRadixString(16).padLeft(4, '0').toUpperCase()}',
            };
          }).toList();

          // Sort by connection status
          _availableUsbDevices.sort((a, b) {
            final aHasPermission = a['hasPermission'] as bool;
            final bHasPermission = b['hasPermission'] as bool;
            if (aHasPermission && !bHasPermission) return -1;
            if (!aHasPermission && bHasPermission) return 1;
            return 0;
          });

          _isLoading = false;
          _usbConnectionStatus = "READY";
        });
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _usbConnectionStatus = "SCAN FAILED";
      });
    }
  }

  void _handleUsbDeviceAttached(Map<dynamic, dynamic> arguments) {
    final deviceName = arguments['deviceName'] as String?;
    final isRealHardware = arguments['isRealHardware'] as bool? ?? false;

    if (deviceName != null && isRealHardware) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('USB device connected: $deviceName'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 3),
        ),
      );

      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scanUsbDevices();
      });
    }
  }

  void _handleUsbDeviceDetached(Map<dynamic, dynamic> arguments) {
    final deviceName = arguments['deviceName'] as String?;

    if (deviceName != null && deviceName == _usbDeviceName) {
      _handleDeviceDisconnection();
    }
  }

  void _handleUsbPermissionResult(Map<dynamic, dynamic> arguments) {
    final deviceName = arguments['deviceName'] as String?;
    final permissionGranted = arguments['permissionGranted'] as bool? ?? false;
    final isRealHardware = arguments['isRealHardware'] as bool? ?? false;

    if (deviceName != null && deviceName == _usbDeviceName) {
      if (permissionGranted && isRealHardware) {
        _openAndConfigureUsbDevice();
      } else {
        setState(() {
          _isLoading = false;
          _usbConnectionStatus = "PERMISSION DENIED";
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                isRealHardware ? 'Permission denied' : 'Non-hardware device'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  void _handleDeviceDisconnection() {
    if (!_usingUsbGnss) return;

    setState(() {
      _usingUsbGnss = false;
      _usbDeviceName = "";
      _usbConnectionStatus = "DISCONNECTED";
      _chipsetVendor = "Unknown";
      _chipsetModel = "Unknown";
      _connectionStable = false;
      _connectionRetries = 0;
      _mapZoomed = false;
    });

    final provider = Provider.of<GNSSProvider>(context, listen: false);
    if (provider.isConnected) {
      provider.disconnect();
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('USB device disconnected'),
        backgroundColor: Colors.orange,
      ),
    );
  }

  Future<void> _connectToUsbDevice(Map<String, dynamic> device) async {
    if (_connectionAttempts > 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Too many connection attempts'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    try {
      setState(() {
        _isLoading = true;
        _usbConnectionStatus = "REQUESTING PERMISSION...";
        _connectionAttempts++;
      });

      final hasPermission = await _channel.invokeMethod(
        'checkUsbPermission',
        {
          'deviceName': device['deviceName'],
          'vendorId': device['vendorId'],
          'productId': device['productId'],
        },
      );

      if (hasPermission == true) {
        setState(() {
          _usbDeviceName = device['deviceName'];
        });
        await _openAndConfigureUsbDevice();
      } else {
        await _channel.invokeMethod(
          'requestUsbPermission',
          {
            'deviceName': device['deviceName'],
            'vendorId': device['vendorId'],
            'productId': device['productId'],
          },
        );

        setState(() {
          _usbDeviceName = device['deviceName'];
        });
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _usbConnectionStatus = "CONNECTION FAILED";
      });
    }
  }

  Future<void> _openAndConfigureUsbDevice() async {
    try {
      setState(() {
        _usbConnectionStatus = "OPENING DEVICE...";
      });

      final device = _availableUsbDevices.firstWhere(
            (d) => d['deviceName'] == _usbDeviceName,
        orElse: () =>
        _availableUsbDevices.isNotEmpty ? _availableUsbDevices[0] : {},
      );

      final connectionInfo = await _channel.invokeMethod(
        'openUsbDevice',
        {
          'deviceName': _usbDeviceName,
          'vendorId': device['vendorId'] ?? 0,
          'productId': device['productId'] ?? 0,
        },
      );

      if (connectionInfo != null) {
        setState(() {
          _usingUsbGnss = true;
          _usbDeviceName = device['deviceName'] ?? _usbDeviceName;
          _usbConnectionStatus = "CONNECTED";
          _chipsetVendor = "USB GNSS";
          _chipsetModel = device['productName'] ?? 'Unknown Device';
          _isLoading = false;
          _showUsbDevicesDialog = false;
          _connectionStable = true;
          _connectionAttempts = 0;
          _connectionRetries = 0;
          _lastDataTime = DateTime.now();
          _connectionStartTime = DateTime.now();
          _mapZoomed = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Connected to ${device['productName']}'),
            backgroundColor: Colors.green,
          ),
        );

        // FIX: Initialize GNSS provider with proper connection
        final provider = Provider.of<GNSSProvider>(context, listen: false);

        // Check if provider needs to be initialized
        if (!provider.isConnected) {
          // Initialize the GNSS provider with USB connection
          await provider.connectToDevice();
        }

        // Start data streaming immediately
        await provider.startDataStream();

        // Force an initial data update
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _updateFromGNSSData(provider.data);
            _updateUsbStatus(provider);
          }
        });
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _usbConnectionStatus = "OPEN FAILED";
      });
      print('Error opening USB device: $e');
    }
  }

  Future<void> _disconnectUsbDevice() async {
    try {
      setState(() {
        _isLoading = true;
        _usbConnectionStatus = "DISCONNECTING...";
      });

      final provider = Provider.of<GNSSProvider>(context, listen: false);
      if (provider.isConnected) {
        await provider.disconnect();
      }

      if (_usbDeviceName.isNotEmpty) {
        final device = _availableUsbDevices.firstWhere(
              (d) => d['deviceName'] == _usbDeviceName,
          orElse: () => {},
        );

        if (device.isNotEmpty) {
          await _channel.invokeMethod('closeUsbDevice', {
            'vendorId': device['vendorId'] ?? 0,
            'productId': device['productId'] ?? 0,
          });
        }
      }

      setState(() {
        _usingUsbGnss = false;
        _usbDeviceName = "";
        _usbConnectionStatus = "DISCONNECTED";
        _isLoading = false;
        _connectionStable = true;
        _connectionAttempts = 0;
        _connectionRetries = 0;
        _connectionStartTime = null;
        _mapZoomed = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Widget _buildUsbDevicesDialog() {
    return AlertDialog(
      title: const Text('Available USB Devices'),
      content: SizedBox(
        width: double.maxFinite,
        height: 500,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _availableUsbDevices.isEmpty
            ? const Center(child: Text('No USB devices found'))
            : Column(
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  const Icon(Icons.usb, size: 16, color: Colors.blue),
                  const SizedBox(width: 8),
                  Text(
                    '${_availableUsbDevices.length} devices',
                    style: const TextStyle(fontSize: 12),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.refresh),
                    onPressed: _scanUsbDevices,
                    iconSize: 20,
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: _availableUsbDevices.length,
                itemBuilder: (context, index) {
                  final device = _availableUsbDevices[index];
                  final hasPermission =
                  device['hasPermission'] as bool;
                  final isRealHardware =
                  device['isRealHardware'] as bool;

                  return Card(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    color: hasPermission
                        ? Colors.green.shade50
                        : Colors.grey.shade50,
                    child: ListTile(
                      leading: Icon(
                        hasPermission
                            ? Icons.check_circle
                            : Icons.lock_outline,
                        color: hasPermission
                            ? Colors.green
                            : Colors.orange,
                      ),
                      title: Text(
                          device['productName'] ?? 'Unknown Device'),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'VID: ${device['vendorHex']} PID: ${device['productHex']}',
                            style: const TextStyle(fontSize: 11),
                          ),
                          if (device['gnssType'] != 'Unknown') ...[
                            const SizedBox(height: 4),
                            Text(
                              device['gnssType'] as String,
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.blue,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ],
                      ),
                      trailing: !isRealHardware
                          ? const Icon(Icons.warning,
                          color: Colors.red, size: 16)
                          : null,
                      onTap: () => _connectToUsbDevice(device),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => setState(() => _showUsbDevicesDialog = false),
          child: const Text('Cancel'),
        ),
      ],
    );
  }

  void _processSatelliteData(List<dynamic> satellites) {
    _satellitesBySystem.clear();
    _systemDetails.clear();
    _availableSystems.clear();
    _satellites.clear();

    for (var sat in satellites) {
      final satMap = {
        'prn': sat.prn,
        'elevation': sat.elevation,
        'azimuth': sat.azimuth,
        'snr': sat.snr,
        'inUse': sat.inUse,
        'system': sat.system,
        'constellation': sat.constellation,
      };
      _satellites.add(satMap);

      final system = sat.constellation;
      if (!_satellitesBySystem.containsKey(system)) {
        _satellitesBySystem[system] = [];
      }
      _satellitesBySystem[system]!.add(satMap);
    }

    for (var system in _satellitesBySystem.keys) {
      final sats = _satellitesBySystem[system]!;
      var totalSNR = 0.0;
      var inUseCount = 0;

      for (var sat in sats) {
        totalSNR += (sat['snr'] as int?)?.toDouble() ?? 0.0;
        if ((sat['inUse'] as bool?) == true) inUseCount++;
      }

      final avgSNR = sats.isNotEmpty ? totalSNR / sats.length : 0.0;

      _systemDetails[system] = {
        'total': sats.length,
        'inUse': inUseCount,
        'avgSNR': avgSNR,
        'health': _calculateSystemHealth(avgSNR, inUseCount, sats.length),
      };
    }

    _availableSystems = _satellitesBySystem.keys.toList();
  }

  String _calculateSystemHealth(double avgSNR, int inUseCount, int totalCount) {
    if (totalCount == 0) return 'OFFLINE';
    if (inUseCount >= 4 && avgSNR > 30) return 'EXCELLENT';
    if (inUseCount >= 3 && avgSNR > 25) return 'GOOD';
    if (inUseCount >= 2 && avgSNR > 20) return 'FAIR';
    if (inUseCount >= 1 && avgSNR > 15) return 'POOR';
    return 'WEAK';
  }

  void _updateFromGNSSData(GNSSData data) {
    _lastDataTime = DateTime.now();
    _bytesReceived = data.bytesReceived;
    _nmeaSentences = data.nmeaSentences;

    setState(() {
      _latitude = data.latitude;
      _longitude = data.longitude;
      _altitude = data.altitude;
      _speed = data.speed;
      _course = data.course;
      _hdop = data.hdop;
      _pdop = data.pdop;
      _vdop = data.vdop;
      _satellitesInView = data.satellitesInView;
      _satellitesInUse = data.satellitesInUse;
      _hasFix = data.hasFix;
      _status = data.status;
      _rawNMEA = data.rawNMEA;

      if (data.satellites.isNotEmpty) {
        _processSatelliteData(data.satellites);
      }

      if (_latitude != null && _longitude != null) {
        _locationAcquired = true;
        _lastValidMapCenter = LatLng(_latitude!, _longitude!);
      }
    });
  }

  void _zoomToCurrentLocation() {
    if (_latitude != null && _longitude != null && _locationAcquired) {
      _mapController.move(LatLng(_latitude!, _longitude!), 18.0);
      setState(() {
        _mapZoomed = true;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Zoomed to current location'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No location data available'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  void _updateUsbStatus(GNSSProvider provider) {
    setState(() {
      _usingUsbGnss = provider.isConnected;
      _usbConnectionStatus = provider.connectionStatus;
      _usbDeviceName = provider.deviceName;
      _connectionStable = provider.connectionStable;
    });
  }

  Widget _buildMap() {
    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: _getMapCenter(),
            initialZoom: _locationAcquired ? 18.0 : 5.0,
            maxZoom: 20.0,
            minZoom: 3.0,
            keepAlive: true,
            onPositionChanged: (position, hasGesture) {
              if (hasGesture) {
                setState(() {
                  _mapZoomed = true;
                });
              }
            },
          ),
          children: [
            // OpenStreetMap Standard Layer
            if (_selectedLayers['OpenStreetMap Standard'] == true)
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.usb_connect_gnss',
                subdomains: const ['a', 'b', 'c'],
              ),

            // ESRI Satellite Imagery Layer
            if (_selectedLayers['ESRI Satellite View'] == true)
              TileLayer(
                urlTemplate:
                'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
                userAgentPackageName: 'com.example.usb_connect_gnss',
              ),

            // Location marker
            if (_latitude != null && _longitude != null && _locationAcquired)
              MarkerLayer(
                markers: [
                  Marker(
                    point: LatLng(_latitude!, _longitude!),
                    width: 80.0,
                    height: 80.0,
                    child: _buildLocationMarker(),
                  ),
                ],
              ),
          ],
        ),

        // Current Location Button
        Positioned(
          bottom: 100,
          right: 16,
          child: FloatingActionButton(
            onPressed: _zoomToCurrentLocation,
            backgroundColor: Colors.white,
            foregroundColor: Colors.blue,
            elevation: 4,
            child: const Icon(Icons.my_location),
            tooltip: 'Go to current location',
          ),
        ),
      ],
    );
  }

  Widget _buildLocationMarker() {
    return Stack(
      alignment: Alignment.center,
      children: [
        // Outer ring
        Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _usingUsbGnss
                ? Colors.teal.withOpacity(0.1)
                : Colors.green.withOpacity(0.1),
            border: Border.all(
              color: _usingUsbGnss
                  ? Colors.teal.withOpacity(0.3)
                  : Colors.green.withOpacity(0.3),
              width: 2.0,
            ),
          ),
        ),

        // Inner circle
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _usingUsbGnss ? Colors.teal : Colors.green,
            boxShadow: [
              BoxShadow(
                color: (_usingUsbGnss ? Colors.teal : Colors.green)
                    .withOpacity(0.5),
                blurRadius: 8,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Icon(
            _usingUsbGnss ? Icons.usb : Icons.gps_fixed,
            color: Colors.white,
            size: 14,
          ),
        ),

        // Fix status indicator
        if (_hasFix)
          Positioned(
            top: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 4,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: const Icon(
                Icons.check_circle,
                color: Colors.green,
                size: 12,
              ),
            ),
          ),
      ],
    );
  }

  LatLng _getMapCenter() {
    if (_latitude != null && _longitude != null) {
      return LatLng(_latitude!, _longitude!);
    } else if (_lastValidMapCenter != null) {
      return _lastValidMapCenter!;
    } else {
      return const LatLng(28.6139, 77.2090); // Default to New Delhi
    }
  }

  Widget _buildBandPanel() {
    // Calculate actual band status based on detected systems and signal quality
    final hasGPS = _availableSystems.any((s) => s.contains('GPS'));
    final hasGalileo = _availableSystems.any((s) => s.contains('Galileo'));
    final hasBeiDou = _availableSystems.any((s) => s.contains('BeiDou'));
    final hasGLONASS = _availableSystems.any((s) => s.contains('GLONASS'));
    final hasIRNSS = _availableSystems.any((s) =>
    s.contains('IRNSS') || s.contains('NavIC'));

    // Determine if bands are active based on actual data
    final isL1Active = hasGPS || hasGalileo || hasBeiDou;
    final isL2Active = _satellitesInUse != null && _satellitesInUse! > 8; // High satellite count suggests L2
    final isL5Active = hasIRNSS && _satellitesInUse != null && _satellitesInUse! > 6;
    final isSActive = hasIRNSS;
    final isE1Active = hasGalileo;
    final isB1Active = hasBeiDou;
    final isG1Active = hasGLONASS;

    return Container(
      width: MediaQuery.of(context).size.width * 0.95,
      height: 500,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.settings_input_antenna,
                      color: Colors.green.shade700, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    "GNSS BAND INFORMATION",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade700,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 20),
                onPressed: () => setState(() => _showBandPanel = false),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Band Status - FIXED LOGIC
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.green.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.wifi_tethering,
                        color: Colors.green.shade700, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      "BAND STATUS",
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.green.shade700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    // L1 Band - Active if GPS/Galileo/BeiDou detected with good signal
                    _buildBandStatusChip(
                        "L1",
                        true, // L1 is always supported
                        isL1Active && _hasFix,
                        "1575.42 MHz"),

                    // L2 Band - Active if device supports and we have good satellite count
                    _buildBandStatusChip(
                        "L2",
                        _usingUsbGnss, // L2 supported if using USB GNSS
                        isL2Active,
                        "1227.60 MHz"),

                    // L5 Band - Active if IRNSS is detected with good signal
                    _buildBandStatusChip(
                        "L5",
                        hasIRNSS || _usingUsbGnss, // Available if IRNSS capable or USB device
                        isL5Active,
                        "1176.45 MHz"),

                    // S Band - ONLY active if IRNSS is actually detected
                    _buildBandStatusChip(
                        "S",
                        hasIRNSS, // Only available if IRNSS
                        isSActive,
                        "2492.028 MHz"),

                    // E1 Band - Only if Galileo detected
                    _buildBandStatusChip(
                        "E1",
                        hasGalileo || _usingUsbGnss,
                        isE1Active,
                        "1575.42 MHz"),

                    // B1 Band - Only if BeiDou detected
                    _buildBandStatusChip(
                        "B1",
                        hasBeiDou || _usingUsbGnss,
                        isB1Active,
                        "1561.098 MHz"),

                    // G1 Band - Only if GLONASS detected
                    _buildBandStatusChip(
                        "G1",
                        hasGLONASS || _usingUsbGnss,
                        isG1Active,
                        "1602 MHz"),
                  ],
                ),
              ],
            ),
          ),

          // System Statistics
          if (_availableSystems.isNotEmpty) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.analytics,
                          color: Colors.blue.shade700, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        "DETECTED GNSS SYSTEMS",
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue.shade700,
                        ),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          "${_availableSystems.length} systems",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.blue.shade700,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _availableSystems.map((system) {
                      final details = _systemDetails[system];
                      final total = details?['total'] as int? ?? 0;
                      final inUse = details?['inUse'] as int? ?? 0;

                      return Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: _getSystemColor(system).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: _getSystemColor(system).withOpacity(0.3)),
                        ),
                        child: Column(
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(_getSystemIcon(system),
                                    size: 14, color: _getSystemColor(system)),
                                const SizedBox(width: 6),
                                Text(
                                  system.split(' ').first,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: _getSystemColor(system),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '$inUse/$total',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              details?['health'] ?? 'UNKNOWN',
                              style: TextStyle(
                                fontSize: 10,
                                color:
                                _getHealthColor(details?['health'] ?? ''),
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ],

          // Connection Info
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.orange.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.usb, color: Colors.orange.shade700, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      "CONNECTION INFO",
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.orange.shade700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _buildStatCard(
                          "Uptime", _getUptime(), Icons.timer, Colors.blue),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildStatCard(
                          "Satellites",
                          "${_satellitesInView ?? 0}",
                          Icons.satellite,
                          Colors.green),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildStatCard("Fix", _hasFix ? "3D" : "No",
                          Icons.gps_fixed, _hasFix ? Colors.green : Colors.red),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBandStatusChip(
      String band, bool supported, bool active, String frequency) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: supported
            ? (active ? Colors.green.shade100 : Colors.blue.shade100)
            : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: supported
              ? (active ? Colors.green.shade300 : Colors.blue.shade300)
              : Colors.grey.shade300,
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.circle,
                size: 10,
                color: supported
                    ? (active ? Colors.green.shade700 : Colors.blue.shade700)
                    : Colors.grey.shade700,
              ),
              const SizedBox(width: 6),
              Text(
                band,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: supported
                      ? (active ? Colors.green.shade800 : Colors.blue.shade800)
                      : Colors.grey.shade800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            frequency,
            style: TextStyle(
              fontSize: 10,
              color: Colors.grey.shade600,
            ),
          ),
          Text(
            active
                ? 'ACTIVE'
                : supported
                ? 'AVAILABLE'
                : 'UNAVAILABLE',
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.bold,
              color: active
                  ? Colors.green
                  : (supported ? Colors.blue : Colors.grey),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(
      String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            title,
            style: TextStyle(
              fontSize: 10,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLayerSelectionPanel() {
    return Container(
      width: 220,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "MAP LAYERS",
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade700,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 12),
          ..._selectedLayers.keys
              .map((name) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => setState(() =>
                _selectedLayers[name] = !_selectedLayers[name]!),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Row(
                    children: [
                      Checkbox(
                        value: _selectedLayers[name],
                        onChanged: (_) => setState(() =>
                        _selectedLayers[name] =
                        !_selectedLayers[name]!),
                        activeColor: Colors.green,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          name,
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey.shade800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ))
              .toList(),
        ],
      ),
    );
  }

  String _getUptime() {
    if (_connectionStartTime == null) return "0s";
    final duration = DateTime.now().difference(_connectionStartTime!);
    if (duration.inHours > 0) return "${duration.inHours}h";
    if (duration.inMinutes > 0) return "${duration.inMinutes}m";
    return "${duration.inSeconds}s";
  }

  Color _getSystemColor(String system) {
    if (system.contains('NavIC') || system.contains('IRNSS'))
      return Colors.green;
    if (system.contains('GPS')) return Colors.blue;
    if (system.contains('GLONASS')) return Colors.red;
    if (system.contains('Galileo')) return Colors.purple;
    if (system.contains('BeiDou')) return Colors.orange;
    if (system.contains('QZSS')) return Colors.pink;
    return Colors.grey;
  }

  Color _getHealthColor(String health) {
    switch (health) {
      case 'EXCELLENT':
        return Colors.green;
      case 'GOOD':
        return Colors.lightGreen;
      case 'FAIR':
        return Colors.yellow;
      case 'POOR':
        return Colors.orange;
      case 'WEAK':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  IconData _getSystemIcon(String system) {
    if (system.contains('NavIC') || system.contains('IRNSS'))
      return Icons.satellite_alt;
    if (system.contains('GPS')) return Icons.gps_fixed;
    return Icons.satellite;
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<GNSSProvider>(context);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _updateFromGNSSData(provider.data);
        _updateUsbStatus(provider);

        // Auto-zoom to location if we have a fix and haven't zoomed yet
        if (_hasFix && !_mapZoomed && _latitude != null && _longitude != null) {
          _mapController.move(LatLng(_latitude!, _longitude!), 18.0);
          setState(() {
            _mapZoomed = true;
          });
        }
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'GNSS MONITOR',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            if (_usbDeviceName.isNotEmpty)
              Container(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width - 120,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _usingUsbGnss
                            ? "Connected: $_usbDeviceName"
                            : "Disconnected",
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (_usingUsbGnss && !_connectionStable)
                      Container(
                        margin: const EdgeInsets.only(left: 8),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade100,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'UNSTABLE',
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.orange,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
        backgroundColor: _usingUsbGnss
            ? Colors.teal.shade700
            : (_hasFix ? Colors.green.shade700 : Colors.orange.shade700),
        elevation: 2,
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.map), text: 'Map'),
            Tab(icon: Icon(Icons.satellite), text: 'Satellites'),
            Tab(icon: Icon(Icons.analytics), text: 'Analytics'),
            Tab(icon: Icon(Icons.info), text: 'Status'),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(_usingUsbGnss ? Icons.usb : Icons.usb_off),
            onPressed: _usingUsbGnss
                ? _disconnectUsbDevice
                : () => setState(() => _showUsbDevicesDialog = true),
            tooltip: _usingUsbGnss ? 'Disconnect' : 'Connect USB',
          ),
          IconButton(
            icon: const Icon(Icons.layers),
            onPressed: () =>
                setState(() => _showLayerSelection = !_showLayerSelection),
            tooltip: 'Map Layers',
          ),
          IconButton(
            icon: const Icon(Icons.satellite_alt),
            onPressed: () =>
                setState(() => _showSatelliteList = !_showSatelliteList),
            tooltip: 'Satellites',
          ),
          IconButton(
            icon: const Icon(Icons.settings_input_antenna),
            onPressed: () => setState(() => _showBandPanel = !_showBandPanel),
            tooltip: 'Band Information',
          ),
        ],
      ),
      body: Stack(
        children: [
          TabBarView(
            controller: _tabController,
            children: [
              // Map View
              _buildMap(),

              // Satellite View
              _buildSatelliteView(),

              // Analytics View - WITH LATITUDE/LONGITUDE
              _buildAnalyticsView(),

              // Status View
              _buildStatusView(),
            ],
          ),
          if (_showLayerSelection)
            Positioned(top: 80, right: 16, child: _buildLayerSelectionPanel()),
          if (_showSatelliteList)
            Positioned(
              top: 80,
              left: 16,
              right: 16,
              child: _buildSatelliteListPanel(),
            ),
          if (_showBandPanel)
            Positioned(top: 80, left: 16, right: 16, child: _buildBandPanel()),
          if (_showUsbDevicesDialog) Dialog(child: _buildUsbDevicesDialog()),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => setState(() => _showBandPanel = !_showBandPanel),
        backgroundColor: Colors.purple,
        child: const Icon(Icons.radar, color: Colors.white),
        tooltip: 'GNSS Bands',
      ),
    );
  }

  Widget _buildSatelliteView() {
    return Column(
      children: [
        // Sky Plot
        Expanded(
          child: Center(
            child: CustomPaint(
              size: const Size(300, 300),
              painter: SkyPlotPainter(satellites: _satellites),
            ),
          ),
        ),
        // Satellite List
        Expanded(
          child: _satellites.isNotEmpty
              ? ListView.builder(
            itemCount: _satellites.length,
            itemBuilder: (context, index) {
              final sat = _satellites[index];
              return _buildSatelliteListItem(sat);
            },
          )
              : const Center(child: Text('No satellites detected')),
        ),
      ],
    );
  }

  Widget _buildSatelliteListItem(Map<String, dynamic> sat) {
    final system = sat['system'] as String;
    final snr = sat['snr'] as int? ?? 0;
    final inUse = sat['inUse'] as bool? ?? false;

    return ListTile(
      leading: Icon(
        Icons.satellite,
        color: _getSystemColor(system),
      ),
      title: Text('${system} ${sat['prn']}'),
      subtitle: Text(
          'SNR: ${snr}dB | Elev: ${sat['elevation']}° | Azim: ${sat['azimuth']}°'),
      trailing: inUse
          ? const Icon(Icons.check_circle, color: Colors.green)
          : const Icon(Icons.radio_button_unchecked, color: Colors.grey),
    );
  }

  Widget _buildAnalyticsView() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Position Information Card - WITH LATITUDE/LONGITUDE
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Position Information',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),

                // Latitude/Longitude Row
                Row(
                  children: [
                    Expanded(
                      child: _buildCoordinateCard(
                        'Latitude',
                        _latitude?.toStringAsFixed(6) ?? 'N/A',
                        Icons.explore,
                        Colors.blue,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildCoordinateCard(
                        'Longitude',
                        _longitude?.toStringAsFixed(6) ?? 'N/A',
                        Icons.explore_outlined,
                        Colors.green,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Other position data
                _buildInfoRow(
                    'Altitude',
                    _altitude != null
                        ? '${_altitude!.toStringAsFixed(1)} m'
                        : 'N/A'),
                _buildInfoRow(
                    'Speed',
                    _speed != null
                        ? '${_speed!.toStringAsFixed(1)} km/h'
                        : 'N/A'),
                _buildInfoRow(
                    'Course',
                    _course != null
                        ? '${_course!.toStringAsFixed(1)}°'
                        : 'N/A'),
                _buildInfoRow('Fix Status', _hasFix ? '3D Fix' : 'No Fix'),
                _buildInfoRow('Satellites',
                    '${_satellitesInUse ?? 0} in use / ${_satellitesInView ?? 0} in view'),
              ],
            ),
          ),
        ),

        const SizedBox(height: 16),

        // DOP Information
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Dilution of Precision',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 100,
                  child: Row(
                    children: [
                      Expanded(
                        child: _buildDOPGauge('HDOP', _hdop ?? 0, 5),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildDOPGauge('VDOP', _vdop ?? 0, 5),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildDOPGauge('PDOP', _pdop ?? 0, 5),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 16),

        // GNSS Systems
        if (_availableSystems.isNotEmpty) ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'GNSS Systems',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _availableSystems.map((system) {
                      final details = _systemDetails[system];
                      return Chip(
                        backgroundColor:
                        _getSystemColor(system).withOpacity(0.1),
                        label: Text(
                          '$system (${details?['inUse'] ?? 0}/${details?['total'] ?? 0})',
                          style: TextStyle(color: _getSystemColor(system)),
                        ),
                        avatar: Icon(
                          _getSystemIcon(system),
                          color: _getSystemColor(system),
                          size: 16,
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],

        // Connection Statistics
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Connection Statistics',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                _buildInfoRow('Status', _usbConnectionStatus),
                _buildInfoRow('Device',
                    _usbDeviceName.isNotEmpty ? _usbDeviceName : 'None'),
                _buildInfoRow('Uptime', _getUptime()),
                _buildInfoRow('Bytes Received', '$_bytesReceived'),
                _buildInfoRow('NMEA Sentences', '$_nmeaSentences'),
                _buildInfoRow(
                    'Connection', _connectionStable ? 'Stable' : 'Unstable'),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCoordinateCard(
      String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, size: 24, color: color),
          const SizedBox(height: 8),
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              color: color,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildDOPGauge(String title, double value, double maxValue) {
    return Column(
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Expanded(
          child: SfLinearGauge(
            minimum: 0,
            maximum: maxValue,
            interval: 1,
            minorTicksPerInterval: 0,
            axisLabelStyle: const TextStyle(fontSize: 10),
            axisTrackStyle: const LinearAxisTrackStyle(
              thickness: 10,
              color: Colors.grey,
            ),
            markerPointers: [
              LinearShapePointer(
                value: value,
                height: 15,
                width: 15,
                color: _getDOPColor(value),
              ),
            ],
            ranges: [
              const LinearGaugeRange(
                startValue: 0,
                endValue: 1,
                color: Colors.green,
              ),
              const LinearGaugeRange(
                startValue: 1,
                endValue: 2,
                color: Colors.yellow,
              ),
              LinearGaugeRange(
                startValue: 2,
                endValue: maxValue,
                color: Colors.red,
              ),
            ],
          ),
        ),
        Text(
          value.toStringAsFixed(2),
          style: TextStyle(
            color: _getDOPColor(value),
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Color _getDOPColor(double value) {
    if (value <= 1) return Colors.green;
    if (value <= 2) return Colors.yellow;
    return Colors.red;
  }

  Widget _buildStatusView() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Device Information
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Device Information',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                _buildInfoRow(
                    'Device Name',
                    _usbDeviceName.isNotEmpty
                        ? _usbDeviceName
                        : 'Not Connected'),
                _buildInfoRow('Chipset', '$_chipsetVendor $_chipsetModel'),
                _buildInfoRow('Connection Status', _usbConnectionStatus),
                _buildInfoRow(
                    'Stability', _connectionStable ? 'Stable' : 'Unstable'),
                _buildInfoRow('Retry Count', '$_connectionRetries'),
              ],
            ),
          ),
        ),

        const SizedBox(height: 16),

        // Data Statistics
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Data Statistics',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                _buildInfoRow('Bytes Received', '$_bytesReceived'),
                _buildInfoRow('NMEA Sentences', '$_nmeaSentences'),
                _buildInfoRow(
                    'Last Data',
                    _lastDataTime != null
                        ? '${DateTime.now().difference(_lastDataTime!).inSeconds}s ago'
                        : 'Never'),
                _buildInfoRow('Satellites Detected', '${_satellites.length}'),
                _buildInfoRow('GNSS Systems', '${_availableSystems.length}'),
              ],
            ),
          ),
        ),

        const SizedBox(height: 16),

        // Raw NMEA Data
        if (_rawNMEA.isNotEmpty) ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Last NMEA Sentence',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: SelectableText(
                      _rawNMEA,
                      style: const TextStyle(
                        color: Colors.green,
                        fontFamily: 'Monospace',
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],

        // Control Buttons
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _usingUsbGnss
                    ? _disconnectUsbDevice
                    : () => setState(() => _showUsbDevicesDialog = true),
                icon: Icon(_usingUsbGnss ? Icons.usb_off : Icons.usb),
                label: Text(_usingUsbGnss ? 'Disconnect' : 'Connect USB'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _usingUsbGnss ? Colors.red : Colors.green,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
            const SizedBox(width: 10),
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _scanUsbDevices,
              tooltip: 'Rescan USB Devices',
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSatelliteListPanel() {
    return Container(
      width: MediaQuery.of(context).size.width * 0.95,
      height: 400,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.satellite_alt,
                      color: Colors.purple.shade700, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    "SATELLITE MONITOR",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade700,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 20),
                onPressed: () => setState(() => _showSatelliteList = false),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _satellites.isNotEmpty
                ? ListView.builder(
              itemCount: _satellites.length,
              itemBuilder: (context, index) {
                final sat = _satellites[index];
                return _buildSatelliteListItem(sat);
              },
            )
                : const Center(
              child: Text(
                "No satellites detected",
                style: TextStyle(color: Colors.grey),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('$label:', style: const TextStyle(fontWeight: FontWeight.w500)),
          Text(value, style: const TextStyle(fontFamily: 'Monospace')),
        ],
      ),
    );
  }
}

class SkyPlotPainter extends CustomPainter {
  final List<Map<String, dynamic>> satellites;

  SkyPlotPainter({required this.satellites});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 20;

    // Draw sky plot background
    final paint = Paint()
      ..color = Colors.blue.withOpacity(0.1)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    // Draw elevation circles
    for (int i = 0; i <= 90; i += 30) {
      double circleRadius = radius * (1 - i / 90);
      canvas.drawCircle(center, circleRadius, paint);
    }

    // Draw satellites
    for (var sat in satellites) {
      double elevation = (sat['elevation'] as int?)?.toDouble() ?? 0.0;
      double azimuth = (sat['azimuth'] as int?)?.toDouble() ?? 0.0;
      double distance = radius * (1 - elevation / 90);
      double radians = azimuth * pi / 180;

      Offset position = Offset(
        center.dx + distance * sin(radians),
        center.dy - distance * cos(radians),
      );

      final satPaint = Paint()
        ..color = _getSignalColor(sat['snr'] ?? 0)
        ..style = PaintingStyle.fill;

      canvas.drawCircle(position, 8, satPaint);

      // Draw PRN
      TextPainter(
        text: TextSpan(
          text: '${sat['prn']}',
          style: const TextStyle(
              fontSize: 8, color: Colors.white, fontWeight: FontWeight.bold),
        ),
        textDirection: TextDirection.ltr,
      )
        ..layout()
        ..paint(canvas, Offset(position.dx - 4, position.dy - 4));
    }
  }

  Color _getSignalColor(dynamic snr) {
    final value = snr is int
        ? snr
        : snr is double
        ? snr
        : 0;
    if (value > 40) return Colors.green;
    if (value > 30) return Colors.lightGreen;
    if (value > 20) return Colors.yellow;
    if (value > 10) return Colors.orange;
    return Colors.red;
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}