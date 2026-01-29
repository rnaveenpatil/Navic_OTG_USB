// lib/screens/home_screen.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:navic_ss/models/enhanced_position.dart';
import 'package:navic_ss/services/location_service.dart';
import 'package:navic_ss/models/gnss_satellite.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final EnhancedLocationService _locationService = EnhancedLocationService();
  final MapController _mapController = MapController();
  final ScrollController _scrollController = ScrollController();

  EnhancedPosition? _currentPosition;
  String _locationQuality = " Location...";
  String _locationSource = "GPS";
  bool _isLoading = true;
  bool _isHardwareChecked = false;
  bool _isNavicSupported = false;
  bool _isNavicActive = false;
  bool _hasL5Band = false;
  bool _hasL5BandActive = false;
  String _hardwareMessage = "Checking hardware...";
  String _hardwareStatus = "Checking...";
  bool _showLayerSelection = false;
  bool _showSatelliteList = false;
  bool _showBandPanel = false;
  bool _locationAcquired = false;
  LatLng? _lastValidMapCenter;
  double _confidenceLevel = 0.0;
  int _navicSatelliteCount = 0;
  int _totalSatelliteCount = 0;
  int _navicUsedInFix = 0;
  String _positioningMethod = "GPS";
  String _primarySystem = "GPS";
  String _detectionMethod = "UNKNOWN";
  List<GnssSatellite> _allSatellites = [];
  Map<String, dynamic> _systemStats = {};

  // USB Connection state
  bool _usingExternalGnss = false;
  String _externalDeviceInfo = "No USB device";
  String _chipsetVendor = "Unknown";
  String _chipsetModel = "Unknown";
  String _usbConnectionStatus = "DISCONNECTED";

  // New state for bottom panel visibility
  bool _isBottomPanelVisible = true;

  // Permission handling state
  bool _isCheckingPermission = false;
  bool _permissionGranted = false;
  bool _hasRequestedPermission = false;

  // New state for location acquisition type
  bool _isUsingNavic = false;
  String _acquisitionFlow = "GPS";

  Map<String, bool> _selectedLayers = {
    'OpenStreetMap Standard': true,
    'ESRI Satellite View': false,
  };

  final Map<String, TileLayer> _tileLayers = {
    'OpenStreetMap Standard': TileLayer(
      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
      userAgentPackageName: 'com.example.navic',
    ),
    'ESRI Satellite View': TileLayer(
      urlTemplate:
      'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
      userAgentPackageName: 'com.example.navic',
    ),
  };

  // Stream subscriptions
  late StreamSubscription<bool> _detectingSubscription;
  late StreamSubscription<Map<String, dynamic>> _hardwareStateSubscription;
  late StreamSubscription<List<GnssSatellite>> _satellitesSubscription;
  late StreamSubscription<EnhancedPosition?> _positionSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeApp();
    });
  }

  Future<void> _initializeApp() async {
    try {
      print("🚀 Initializing app...");

      // Initialize service first
      await _locationService.initializeService();

      // Setup stream listeners
      _setupStreamListeners();

      // Check and request permission only once
      _permissionGranted = await _checkAndRequestPermissionOnce();

      if (_permissionGranted) {
        // Get initial hardware status
        final status = _locationService.getHardwareStatus();
        _updateFromHardwareStatus(status);

        // Check USB connection first before trying to get location
        await _checkUsbDevices();

        if (_usingExternalGnss) {
          // Use the location service workflow with USB GNSS
          await _acquireInitialLocationWithNavICFlow();
        } else {
          // Show USB connection required message
          setState(() {
            _hardwareMessage = "Connect USB GNSS device to begin";
            _hardwareStatus = "USB Required";
          });
        }
      } else {
        print("⚠️ No location permission granted");
        _showPermissionDeniedDialog();
      }
    } catch (e) {
      print("Initialization error: $e");
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _setupStreamListeners() {
    // Listening for detecting state changes
    _detectingSubscription =
        _locationService.isDetectingStream.listen((isDetecting) {
          if (mounted) {
            setState(() {
              _isLoading = isDetecting;
            });
          }
        });

    // Listening for hardware state updates
    _hardwareStateSubscription =
        _locationService.hardwareStateStream.listen((state) {
          if (mounted) {
            _updateFromHardwareStatus(state);
          }
        });

    // Listening for satellite updates
    _satellitesSubscription =
        _locationService.satellitesStream.listen((satellites) {
          if (mounted) {
            setState(() {
              _allSatellites = satellites;
            });
          }
        });

    // Listening for position updates
    _positionSubscription = _locationService.positionStream.listen((position) {
      if (mounted && position != null) {
        setState(() {
          _currentPosition = position;
          _updateLocationState(position);
          _centerMapOnPosition(position);
          _logLocationDetails(position);
        });
      }
    });
  }

  Future<void> _acquireInitialLocationWithNavICFlow() async {
    try {
      print("\n🎯 ========= STARTING NAVIC FLOW FROM HOME SCREEN ==========");

      if (!_permissionGranted) {
        print("❌ No location permission, skipping acquisition");
        return;
      }

      // Check if USB GNSS is connected
      if (!_usingExternalGnss) {
        print("❌ External USB GNSS not connected");
        _showUsbRequiredDialog();
        return;
      }

      // Use the location service method
      final position = await _locationService.getLocationWithNavICFlow();

      if (position != null &&
          _isValidCoordinate(position.latitude, position.longitude)) {
        print("✅ Location acquired successfully using NavIC flow");

        // Update state from the position
        _isUsingNavic = position.isNavicEnhanced;
        _acquisitionFlow = _isUsingNavic ? "NAVIC" : "GPS";

        _updateLocationState(position);
        _centerMapOnPosition(position);
        _logLocationDetails(position);

        // Update hardware info from service
        final status = _locationService.getHardwareStatus();
        _updateFromHardwareStatus(status);
      } else {
        print("❌ Location acquisition failed");
        _showUsbRequiredDialog();
      }
    } on TimeoutException catch (e) {
      print("⏰ Location acquisition timeout: $e");
      _showUsbRequiredDialog();
    } catch (e) {
      print("❌ Error in location acquisition: $e");

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Failed to get location: ${e.toString()}"),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _refreshLocation() async {
    if (_isLoading) return;

    setState(() => _isLoading = true);

    try {
      // Check permission quickly first
      if (!_permissionGranted) {
        _permissionGranted = await _checkAndRequestPermissionOnce();
        if (!_permissionGranted) {
          print("❌ No location permission for refresh");
          return;
        }
      }

      // Check if USB GNSS is connected
      if (!_usingExternalGnss) {
        print("❌ External USB GNSS not connected");
        _showUsbRequiredDialog();
        setState(() => _isLoading = false);
        return;
      }

      // Use the NavIC flow
      final position = await _locationService.getLocationWithNavICFlow();

      if (position != null &&
          _isValidCoordinate(position.latitude, position.longitude)) {
        // Update state from position
        _isUsingNavic = position.isNavicEnhanced;
        _acquisitionFlow = _isUsingNavic ? "NAVIC" : "GPS";

        _updateLocationState(position);
        _centerMapOnPosition(position);
        _logLocationDetails(position);

        // Update hardware info
        final status = _locationService.getHardwareStatus();
        _updateFromHardwareStatus(status);

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_isUsingNavic
                ? "Location refreshed using NavIC"
                : "Location refreshed using ${position.locationSource}"),
            backgroundColor: _isUsingNavic ? Colors.green : Colors.blue,
            duration: const Duration(seconds: 2),
          ),
        );
      } else {
        _showUsbRequiredDialog();
      }
    } catch (e) {
      print("❌ Error refreshing location: $e");
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Refresh failed: ${e.toString()}"),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 2),
        ),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _updateFromHardwareStatus(Map<String, dynamic> status) {
    setState(() {
      _isNavicSupported = status['isNavicSupported'] ?? false;
      _isNavicActive = status['isNavicActive'] ?? false;
      _hasL5Band = status['hasL5Band'] ?? false;
      _hasL5BandActive = status['hasL5BandActive'] ?? false;
      _usingExternalGnss = status['usingExternalGnss'] ?? false;
      _externalDeviceInfo = status['externalDeviceInfo']?.toString() ?? "NONE";
      _usbConnectionStatus =
          status['usbConnectionStatus']?.toString() ?? "DISCONNECTED";
      _navicSatelliteCount = status['navicSatelliteCount'] ?? 0;
      _totalSatelliteCount = status['totalSatelliteCount'] ?? 0;
      _navicUsedInFix = status['navicUsedInFix'] ?? 0;
      _primarySystem = status['primarySystem']?.toString() ?? "GPS";
      _systemStats = status['systemStats'] ?? {};

      if (status['statusMessage'] != null) {
        _hardwareMessage = status['statusMessage'].toString();
      }

      // Update detection method and positioning method
      _detectionMethod = status['detectionMethod']?.toString() ?? "UNKNOWN";

      // Determine positioning method based on current state
      if (_usingExternalGnss) {
        _positioningMethod =
        _hasL5BandActive ? "EXTERNAL_GNSS_L5" : "EXTERNAL_GNSS";
      } else if (_isNavicActive && _navicUsedInFix >= 4) {
        _positioningMethod =
        _hasL5BandActive ? "NAVIC_PRIMARY_L5" : "NAVIC_PRIMARY";
      } else if (_isNavicActive && _navicUsedInFix >= 2) {
        _positioningMethod = "NAVIC_HYBRID";
      } else if (_isNavicActive && _navicUsedInFix >= 1) {
        _positioningMethod = "NAVIC_ASSISTED";
      } else {
        _positioningMethod = "GPS_PRIMARY";
      }

      // Update chipset info
      if (_usingExternalGnss) {
        _chipsetVendor = status['externalGnssVendor']?.toString() ?? "Unknown";
        _chipsetModel = _externalDeviceInfo;
      } else {
        _chipsetVendor = "Internal";
        _chipsetModel = "GNSS Chipset";
      }

      _isHardwareChecked = true;
      _updateHardwareMessage();
    });
  }

  Future<bool> _checkAndRequestPermissionOnce() async {
    if (_isCheckingPermission || _hasRequestedPermission) {
      print("ℹ️ Permission check already in progress or completed");
      return _permissionGranted;
    }

    setState(() {
      _isCheckingPermission = true;
    });

    try {
      print("📍 Starting permission check...");

      // Check if location services are enabled
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        print("⚠️ Location services disabled");

        WidgetsBinding.instance.addPostFrameCallback((_) {
          _showEnableLocationDialog();
        });
        return false;
      }

      // Check current permission status
      LocationPermission permission = await Geolocator.checkPermission();
      print("📍 Current permission status: $permission");

      switch (permission) {
        case LocationPermission.whileInUse:
        case LocationPermission.always:
          print("✅ Permission already granted");
          _hasRequestedPermission = true;
          return true;

        case LocationPermission.denied:
          print("📍 Permission denied, requesting...");
          permission = await Geolocator.requestPermission();
          _hasRequestedPermission = true;

          print("📍 Permission request result: $permission");

          if (permission == LocationPermission.whileInUse ||
              permission == LocationPermission.always) {
            print("✅ Permission granted after request");
            return true;
          } else {
            print("❌ Permission not granted after request: $permission");
            return false;
          }

        case LocationPermission.deniedForever:
          print("❌ Permission denied forever");
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _showPermissionDeniedForeverDialog();
          });
          _hasRequestedPermission = true;
          return false;

        case LocationPermission.unableToDetermine:
          print("⚠️ Unable to determine permission");
          return false;
      }
    } catch (e) {
      print("❌ Permission error: $e");
      return false;
    } finally {
      setState(() {
        _isCheckingPermission = false;
      });
    }
  }

  Future<void> _showUsbRequiredDialog() async {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Text('USB GNSS Required'),
            content: const Text(
              'External USB GNSS device is required for this app to work properly. '
                  'Please connect a USB GNSS device and try again.',
            ),
            actions: <Widget>[
              TextButton(
                child: const Text('Cancel'),
                onPressed: () {
                  Navigator.of(context).pop();
                },
              ),
              TextButton(
                child: const Text('Check USB Devices'),
                onPressed: () {
                  Navigator.of(context).pop();
                  _checkUsbDevices();
                },
              ),
              TextButton(
                child: const Text('Connect USB'),
                onPressed: () {
                  Navigator.of(context).pop();
                  _connectToUsbGnss();
                },
              ),
            ],
          );
        },
      );
    });
  }

  Future<void> _showEnableLocationDialog() async {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Location Services Disabled'),
          content: const Text(
            'Location services are required for this app to work properly. '
                'Please enable location services in your device settings.',
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: const Text('Enable'),
              onPressed: () {
                Navigator.of(context).pop();
                Geolocator.openLocationSettings();
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _showPermissionDeniedForeverDialog() async {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Location Permission Required'),
          content: const Text(
            'Location permission is required for this app to work. '
                'Please enable it in the app settings. '
                'On Android 13+, you can grant permission directly from this app.',
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: const Text('Grant Permission'),
              onPressed: () async {
                Navigator.of(context).pop();
                final permission = await Geolocator.requestPermission();
                if (permission == LocationPermission.whileInUse ||
                    permission == LocationPermission.always) {
                  setState(() {
                    _permissionGranted = true;
                  });
                  await _acquireInitialLocationWithNavICFlow();
                } else {
                  Geolocator.openAppSettings();
                }
              },
            ),
          ],
        );
      },
    );
  }

  void _showPermissionDeniedDialog() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Text('Permission Required'),
            content: const Text(
              'Location permission is required to use this app. '
                  'Please grant location permission.',
            ),
            actions: <Widget>[
              TextButton(
                child: const Text('Cancel'),
                onPressed: () {
                  Navigator.of(context).pop();
                },
              ),
              TextButton(
                child: const Text('Grant Permission'),
                onPressed: () async {
                  Navigator.of(context).pop();
                  final permission = await Geolocator.requestPermission();
                  if (permission == LocationPermission.whileInUse ||
                      permission == LocationPermission.always) {
                    setState(() {
                      _permissionGranted = true;
                    });
                    await _acquireInitialLocationWithNavICFlow();
                  }
                },
              ),
            ],
          );
        },
      );
    });
  }

  void _updateHardwareMessage() {
    final bool hasNavicBands = _hasL5Band && _hasL5BandActive;

    if (_usingExternalGnss) {
      _hardwareMessage =
      "Using external USB GNSS device. ${_chipsetVendor} $_chipsetModel";
      _hardwareStatus = "USB GNSS";
    } else if (!_isNavicSupported && !hasNavicBands) {
      _hardwareMessage = "Connect USB GNSS device to begin";
      _hardwareStatus = "USB Required";
    } else if (_isNavicSupported && _isNavicActive && hasNavicBands) {
      _hardwareMessage = "NavIC positioning active with L5 band!";
      _hardwareStatus = "NavIC Active";
    } else if (_hasL5Band && _hasL5BandActive) {
      _hardwareMessage = "L5 band active. Enhanced positioning available.";
      _hardwareStatus = "L5 Active";
    } else if (_hasL5Band) {
      _hardwareMessage =
      "L5 band supported. $_primarySystem positioning available.";
      _hardwareStatus = "$_primarySystem with L5";
    } else {
      _hardwareMessage = "Connect USB GNSS device";
      _hardwareStatus = "USB Required";
    }
  }

  void _updateLocationState(EnhancedPosition position) {
    setState(() {
      _currentPosition = position;

      _primarySystem = position.primarySystem;
      if (_primarySystem.isEmpty || _primarySystem == "Unknown") {
        _primarySystem = _determinePrimarySystem();
      }

      _updateLocationSource();
      _updateLocationQuality(position);
      _locationAcquired = true;
      _lastValidMapCenter = LatLng(position.latitude, position.longitude);

      _navicSatelliteCount = position.navicSatellites;
      _totalSatelliteCount = position.totalSatellites;
      _navicUsedInFix = position.navicUsedInFix;
      _hasL5Band = position.hasL5Band;
      _hasL5BandActive = position.hasL5BandActive;
      _positioningMethod = position.positioningMethod;

      if (_primarySystem.isEmpty || _primarySystem == "Unknown") {
        _primarySystem = _determinePrimarySystem();
      }

      _isUsingNavic = position.isNavicEnhanced;
      _acquisitionFlow = _isUsingNavic ? "NAVIC" : _primarySystem;

      _systemStats = position.systemStats;
    });
  }

  void _centerMapOnPosition(EnhancedPosition position) {
    _mapController.move(
      LatLng(position.latitude, position.longitude),
      18.0,
    );
  }

  void _logLocationDetails(EnhancedPosition position) {
    print("\n📍 === LOCATION DETAILS ===");
    print("📍 Coordinates: ${position.latitude}, ${position.longitude}");
    print("🎯 Accuracy: ${position.accuracy?.toStringAsFixed(2)} meters");
    print("🛰️ Source: ${position.locationSource}");
    print("🎯 Primary System: $_primarySystem");
    print(
        "💪 Confidence: ${(position.confidenceScore * 100).toStringAsFixed(1)}%");
    print("🔌 Using External GNSS: $_usingExternalGnss");
    print("🏭 Chipset: $_chipsetVendor $_chipsetModel");
    print(
        "📡 NavIC Satellites: $_navicSatelliteCount ($_navicUsedInFix in fix)");
    print("📶 L5 Band: ${_hasL5Band ? 'Available' : 'Not Available'}");
    print("🎯 Positioning Method: $_positioningMethod");
    print("🛰️ Total Satellites: $_totalSatelliteCount");
    print("📊 Visible Satellites: ${_allSatellites.length}");
    print("📱 Using NavIC: $_isUsingNavic");
    print("📱 Acquisition Flow: $_acquisitionFlow");
    print("===========================\n");
  }

  void _updateLocationSource() {
    if (_isUsingNavic && _isNavicSupported && _isNavicActive) {
      _locationSource = "NAVIC";
    } else if (_usingExternalGnss) {
      _locationSource = "USB GNSS";
    } else {
      _locationSource = _primarySystem;
    }

    print(
        "📍 Location Source Updated: $_locationSource (Using NavIC: $_isUsingNavic, USB: $_usingExternalGnss)");
  }

  void _updateLocationQuality(EnhancedPosition pos) {
    final isUsingNavic = _isUsingNavic && _isNavicSupported && _isNavicActive;
    final isUsingL5 = _hasL5BandActive;

    String bandInfo = isUsingL5 ? "L5 " : "";

    final String systemName = _locationSource;

    if (pos.accuracy != null && pos.accuracy! < 1.0) {
      _locationQuality = isUsingNavic
          ? "${bandInfo}NavIC Excellent"
          : "${bandInfo}$systemName Excellent";
    } else if (pos.accuracy != null && pos.accuracy! < 2.0) {
      _locationQuality = isUsingNavic
          ? "${bandInfo}NavIC High"
          : "${bandInfo}$systemName High";
    } else if (pos.accuracy != null && pos.accuracy! < 5.0) {
      _locationQuality = isUsingNavic
          ? "${bandInfo}NavIC Good"
          : "${bandInfo}$systemName Good";
    } else if (pos.accuracy != null && pos.accuracy! < 10.0) {
      _locationQuality = isUsingNavic
          ? "${bandInfo}NavIC Basic"
          : "${bandInfo}$systemName Basic";
    } else {
      _locationQuality =
      isUsingNavic ? "${bandInfo}NavIC Low" : "${bandInfo}$systemName Low";
    }
  }

  String _determinePrimarySystem() {
    if (_primarySystem.isNotEmpty && _primarySystem != "Unknown") {
      return _primarySystem;
    }

    if (_systemStats.isNotEmpty) {
      try {
        String maxSystem = "GPS";
        int maxCount = 0;

        for (final entry in _systemStats.entries) {
          final system = entry.key;
          final stats = entry.value;

          if (stats is Map<String, dynamic>) {
            final total = stats['total'] as int? ?? 0;
            if (total > maxCount) {
              maxCount = total;
              maxSystem = system;
            }
          }
        }

        return _mapSystemToDisplayName(maxSystem);
      } catch (e) {
        print("⚠️ Error determining primary system: $e");
      }
    }

    if (_positioningMethod.contains("NAVIC")) return "NavIC";
    if (_positioningMethod.contains("GLONASS")) return "GLONASS";
    if (_positioningMethod.contains("GALILEO")) return "Galileo";
    if (_positioningMethod.contains("BEIDOU")) return "BeiDou";
    if (_positioningMethod.contains("QZSS")) return "QZSS";
    if (_positioningMethod.contains("SBAS")) return "SBAS";
    if (_positioningMethod.contains("MULTI")) return "Multi-GNSS";

    return "GPS";
  }

  String _mapSystemToDisplayName(String system) {
    switch (system.toUpperCase()) {
      case 'IRNSS':
      case 'NAVIC':
        return "NavIC";
      case 'GPS':
        return "GPS";
      case 'GLO':
      case 'GLONASS':
        return "GLONASS";
      case 'GAL':
      case 'GALILEO':
        return "Galileo";
      case 'BDS':
      case 'BEIDOU':
        return "BeiDou";
      case 'QZS':
      case 'QZSS':
        return "QZSS";
      case 'SBS':
      case 'SBAS':
        return "SBAS";
      default:
        return system;
    }
  }

  Future<void> _checkUsbDevices() async {
    try {
      setState(() {
        _hardwareMessage = "Scanning for USB devices...";
      });

      final result = await _locationService.checkUsbGnssDevices();

      setState(() {
        if (result['success'] == true) {
          _usbConnectionStatus = result['status']?.toString() ?? "SCANNED";
          final deviceCount = result['availableDevices']?.length ?? 0;
          _hardwareMessage = "Found $deviceCount USB device(s)";

          if (deviceCount > 0) {
            // Show dialog to connect to available devices
            _showUsbDeviceSelectionDialog(result['availableDevices']);
          }
        } else {
          _hardwareMessage = "USB scan failed: ${result['message']}";
        }
      });
    } catch (e) {
      print("❌ Error checking USB devices: $e");
      setState(() {
        _hardwareMessage = "USB scan failed: $e";
      });
    }
  }

  void _showUsbDeviceSelectionDialog(List<dynamic> devices) {
    showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Available USB Devices'),
          content: SizedBox(
            width: double.maxFinite,
            height: 200,
            child: ListView.builder(
              itemCount: devices.length,
              itemBuilder: (context, index) {
                final device = devices[index];
                return ListTile(
                  leading: const Icon(Icons.usb),
                  title: Text(
                      device['deviceName']?.toString() ?? 'Unknown Device'),
                  subtitle: Text(
                      'Vendor: ${device['vendorId']}, Product: ${device['productId']}'),
                  onTap: () {
                    Navigator.of(context).pop();
                    _connectToUsbGnss();
                  },
                );
              },
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: const Text('Connect'),
              onPressed: () {
                Navigator.of(context).pop();
                _connectToUsbGnss();
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _connectToUsbGnss() async {
    try {
      setState(() {
        _hardwareMessage = "Connecting to USB GNSS...";
      });

      final result = await _locationService.connectToUsbGnss();

      setState(() {
        if (result['success'] == true) {
          _hardwareMessage = "Connected to ${result['deviceInfo']}";
          _usingExternalGnss = true;
          _externalDeviceInfo = result['deviceInfo']?.toString() ?? "CONNECTED";

          // Try to get location after successful connection
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _acquireInitialLocationWithNavICFlow();
          });
        } else {
          _hardwareMessage = "Connection failed: ${result['message']}";
        }
      });
    } catch (e) {
      print("❌ Error connecting to USB GNSS: $e");
      setState(() {
        _hardwareMessage = "USB connection error: $e";
      });
    }
  }

  Future<void> _disconnectUsbGnss() async {
    try {
      final result = await _locationService.disconnectUsbGnss();

      setState(() {
        if (result['success'] == true) {
          _hardwareMessage = "USB GNSS disconnected";
          _usingExternalGnss = false;
          _externalDeviceInfo = "NONE";
          _currentPosition = null;
          _locationAcquired = false;
        } else {
          _hardwareMessage = "Disconnect failed: ${result['message']}";
        }
      });
    } catch (e) {
      print("❌ Error disconnecting USB GNSS: $e");
    }
  }

  void _toggleLayerSelection() =>
      setState(() => _showLayerSelection = !_showLayerSelection);
  void _toggleSatelliteList() =>
      setState(() => _showSatelliteList = !_showSatelliteList);
  void _toggleBandPanel() => setState(() => _showBandPanel = !_showBandPanel);
  void _toggleLayer(String layerName) =>
      setState(() => _selectedLayers[layerName] = !_selectedLayers[layerName]!);
  void _toggleBottomPanel() =>
      setState(() => _isBottomPanelVisible = !_isBottomPanelVisible);

  Color _getQualityColor() {
    if (_locationQuality.contains("Excellent")) return Colors.green;
    if (_locationQuality.contains("High")) return Colors.blue;
    if (_locationQuality.contains("Good")) return Colors.orange;
    if (_locationQuality.contains("Basic")) return Colors.amber;
    return Colors.red;
  }

  bool _isValidCoordinate(double lat, double lng) {
    return lat >= -90 && lat <= 90 && lng >= -180 && lng <= 180;
  }

  LatLng _getMapCenter() {
    if (_currentPosition != null &&
        _isValidCoordinate(
            _currentPosition!.latitude, _currentPosition!.longitude)) {
      return LatLng(_currentPosition!.latitude, _currentPosition!.longitude);
    } else if (_lastValidMapCenter != null) {
      return _lastValidMapCenter!;
    } else {
      return const LatLng(28.6139, 77.2090); // Delhi, India
    }
  }

  Widget _buildMap() {
    final selectedTileLayers = _selectedLayers.entries
        .where((e) => e.value)
        .map((e) => _tileLayers[e.key]!)
        .toList();

    final mapCenter = _getMapCenter();

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        center: mapCenter,
        zoom: _locationAcquired ? 18.0 : 5.0,
        maxZoom: 20.0,
        minZoom: 3.0,
        interactiveFlags: InteractiveFlag.all,
        keepAlive: true,
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.example.navic',
          subdomains: const ['a', 'b', 'c'],
          maxNativeZoom: 19,
        ),
        ...selectedTileLayers,
        if (_currentPosition != null && _locationAcquired)
          MarkerLayer(
            markers: [
              Marker(
                point: mapCenter,
                width: 80,
                height: 80,
                builder: (ctx) => _buildLocationMarker(),
              ),
            ],
          ),
      ],
    );
  }

  Widget _buildLocationMarker() {
    final isNavic = _isUsingNavic && _isNavicSupported && _isNavicActive;
    final isL5 = _hasL5BandActive;
    final isUsb = _usingExternalGnss;
    final accuracy = _currentPosition?.accuracy ?? 10.0;

    Color primaryColor;
    if (isL5)
      primaryColor = Colors.green;
    else if (isUsb)
      primaryColor = Colors.teal;
    else
      primaryColor = isNavic ? Colors.green : _getSystemColor(_primarySystem);

    return Stack(
      alignment: Alignment.center,
      children: [
        Container(
          width: (accuracy * 3.0).clamp(40.0, 250.0),
          height: (accuracy * 3.0).clamp(40.0, 250.0),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: primaryColor.withValues(alpha: 0.15),
            border: Border.all(
              color: primaryColor.withValues(alpha: 0.4),
              width: isL5 ? 2.0 : 1.5,
            ),
          ),
        ),
        Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: primaryColor.withValues(alpha: 0.25),
            border: Border.all(
              color: primaryColor.withValues(alpha: 0.6),
              width: isL5 ? 2.5 : 2.0,
            ),
          ),
        ),
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: primaryColor.withValues(alpha: 0.4),
            border: Border.all(
              color: primaryColor.withValues(alpha: 0.8),
              width: isL5 ? 3.0 : 2.0,
            ),
          ),
        ),
        Stack(
          alignment: Alignment.center,
          children: [
            Icon(
              Icons.location_pin,
              color: primaryColor,
              size: 28,
            ),
            if (isL5)
              Positioned(
                top: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.speed,
                    color: Colors.green,
                    size: 12,
                  ),
                ),
              ),
            if (isNavic)
              Positioned(
                bottom: 0,
                left: 0,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.satellite_alt,
                    color: Colors.green,
                    size: 10,
                  ),
                ),
              ),
            if (isUsb)
              Positioned(
                top: 0,
                left: 0,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.usb,
                    color: Colors.teal,
                    size: 10,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildSatelliteListPanel() {
    final satelliteSummary = _locationService.getSatelliteSummary();
    final satelliteList =
        _allSatellites; // Use the actual satellite list from stream

    return Container(
      width: MediaQuery.of(context).size.width * 0.9,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
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
                    "SATELLITE VIEW",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade700,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  Text(
                    "${satelliteList.length} sats",
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade600,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: _toggleSatelliteList,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (satelliteList.isNotEmpty)
            SizedBox(
              height: 300,
              child: ListView.builder(
                shrinkWrap: true,
                physics: const BouncingScrollPhysics(),
                itemCount: satelliteList.length,
                itemBuilder: (context, index) {
                  final sat = satelliteList[index];
                  return _buildSatelliteListItem(sat);
                },
              ),
            )
          else
            _buildNoSatellitesView(),
          const SizedBox(height: 12),
          if (_primarySystem.isNotEmpty) _buildPrimarySystemInfo(),
        ],
      ),
    );
  }

  Widget _buildSatelliteListItem(GnssSatellite sat) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: sat.usedInFix ? Colors.green.shade50 : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color:
            sat.usedInFix ? Colors.green.shade200 : Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Icon(
            sat.system == 'IRNSS' || sat.system == 'NAVIC'
                ? Icons.satellite_alt
                : Icons.satellite,
            color: _getSystemColor(sat.system),
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "${sat.system} ${sat.svid}",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade800,
                  ),
                ),
                Text(
                  "SNR: ${sat.cn0DbHz.toStringAsFixed(1)} dB",
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: sat.usedInFix
                  ? Colors.green.withValues(alpha: 0.2)
                  : Colors.grey.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              sat.usedInFix ? "In Use" : "Available",
              style: TextStyle(
                fontSize: 10,
                color: sat.usedInFix ? Colors.green : Colors.grey,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBandPanel() {
    return Container(
      width: MediaQuery.of(context).size.width * 0.9,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
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
                    "BAND INFORMATION",
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
                onPressed: _toggleBandPanel,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          const SizedBox(height: 12),
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
                const SizedBox(height: 8),
                Row(
                  children: [
                    _buildBandStatusChip("L5", _hasL5Band, _hasL5BandActive),
                    const SizedBox(width: 8),
                    _buildBandStatusChip("USB", true, _usingExternalGnss),
                  ],
                ),
                if (_usingExternalGnss) ...[
                  const SizedBox(height: 12),
                  Text(
                    _externalDeviceInfo,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.green.shade700,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBandStatusChip(String band, bool supported, bool active) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: supported
            ? (active ? Colors.green.shade100 : Colors.blue.shade100)
            : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: supported
                ? (active ? Colors.green.shade300 : Colors.blue.shade300)
                : Colors.grey.shade300),
      ),
      child: Row(
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
            "$band ${active ? '(Active)' : supported ? '(Available)' : '(Unavailable)'}",
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: supported
                  ? (active ? Colors.green.shade800 : Colors.blue.shade800)
                  : Colors.grey.shade800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoSatellitesView() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Icon(Icons.satellite, size: 48, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          Text(
            _usingExternalGnss
                ? "No satellites detected"
                : "Connect USB GNSS device",
            style: TextStyle(
              color: Colors.grey.shade600,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _usingExternalGnss
                ? "Make sure you're outdoors with clear sky view"
                : "Connect a USB GNSS device to begin satellite tracking",
            style: TextStyle(
              color: Colors.grey.shade500,
              fontSize: 12,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: _usingExternalGnss ? _refreshLocation : _checkUsbDevices,
            icon: Icon(_usingExternalGnss ? Icons.refresh : Icons.usb),
            label: Text(_usingExternalGnss ? "Refresh" : "Check USB Devices"),
          ),
        ],
      ),
    );
  }

  Widget _buildPrimarySystemInfo() {
    Color primaryColor = _getSystemColor(_primarySystem);
    bool isNavicPrimary = _primarySystem.contains("NavIC");

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: primaryColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: primaryColor.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isNavicPrimary
                    ? Icons.satellite_alt
                    : _getSystemIcon(_primarySystem),
                color: primaryColor,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "PRIMARY POSITIONING SYSTEM",
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.grey.shade600,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      _primarySystem,
                      style: TextStyle(
                        fontSize: 14,
                        color: primaryColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              if (_hasL5Band && _hasL5BandActive)
                Container(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.speed, size: 12, color: Colors.green),
                      const SizedBox(width: 4),
                      Text(
                        "L5 Active",
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.green,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (_chipsetVendor != "Unknown" && _chipsetModel != "Unknown")
            Row(
              children: [
                Icon(Icons.memory, size: 14, color: Colors.grey.shade600),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    "$_chipsetVendor $_chipsetModel",
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade700,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          if (_usingExternalGnss)
            Row(
              children: [
                Icon(Icons.usb, size: 14, color: Colors.green.shade600),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _externalDeviceInfo,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.green.shade700,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    "CONNECTED",
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.green,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  IconData _getSystemIcon(String system) {
    switch (system.toUpperCase()) {
      case 'NAVIC':
      case 'IRNSS':
        return Icons.satellite_alt;
      case 'GPS':
        return Icons.gps_fixed;
      case 'GLONASS':
        return Icons.satellite;
      case 'GALILEO':
        return Icons.satellite;
      case 'BEIDOU':
      case 'BDS':
        return Icons.satellite;
      case 'QZSS':
        return Icons.satellite;
      case 'SBAS':
        return Icons.satellite;
      default:
        return Icons.gps_fixed;
    }
  }

  Color _getSystemColor(String system) {
    switch (system.toUpperCase()) {
      case 'IRNSS':
      case 'NAVIC':
        return Colors.green;
      case 'GPS':
        return Colors.blue;
      case 'GLONASS':
        return Colors.red;
      case 'GALILEO':
        return Colors.purple;
      case 'BEIDOU':
        return Colors.orange;
      case 'QZSS':
        return Colors.pink;
      case 'SBAS':
        return Colors.teal;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    String appBarSubtitle = "";

    // Add USB status
    if (_usingExternalGnss) {
      appBarSubtitle = "USB GNSS Connected";
      if (_chipsetVendor != "Unknown") {
        appBarSubtitle += " • $_chipsetVendor $_chipsetModel";
      }
    } else {
      appBarSubtitle = "Connect USB GNSS Device";
    }

    // Add current location source if available
    if (_currentPosition != null) {
      final displaySystem = _isUsingNavic ? 'NavIC' : _primarySystem;
      appBarSubtitle += " • Using $displaySystem";
    }

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'NAVIC',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
            if (appBarSubtitle.isNotEmpty)
              Container(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width - 120,
                ),
                child: Text(
                  appBarSubtitle,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
        ),
        backgroundColor: _isUsingNavic
            ? Colors.green.shade700
            : _getSystemColor(_primarySystem).withValues(alpha: 0.8),
        elevation: 2,
        actions: [
          IconButton(
            icon: Icon(_isLoading ? Icons.refresh : Icons.refresh_outlined),
            onPressed: _isLoading ? null : _refreshLocation,
            tooltip: 'Refresh Location',
          ),
          IconButton(
            icon: const Icon(Icons.layers),
            onPressed: _toggleLayerSelection,
            tooltip: 'Map Layers',
          ),
          IconButton(
            icon: const Icon(Icons.satellite_alt),
            onPressed: _toggleSatelliteList,
            tooltip: 'Satellites',
          ),
          IconButton(
            icon: const Icon(Icons.settings_input_antenna),
            onPressed: _toggleBandPanel,
            tooltip: 'Band Information',
          ),
          IconButton(
            icon: Icon(_isBottomPanelVisible
                ? Icons.visibility_off
                : Icons.visibility),
            onPressed: _toggleBottomPanel,
            tooltip: _isBottomPanelVisible ? 'Hide Panel' : 'Show Panel',
          ),
          IconButton(
            icon: Icon(
              _usingExternalGnss ? Icons.usb : Icons.usb_off,
              color: _usingExternalGnss ? Colors.green : Colors.grey,
            ),
            onPressed: _checkUsbDevices,
            tooltip: _usingExternalGnss ? 'USB Connected' : 'Check USB',
          ),
        ],
      ),
      body: Stack(
        children: [
          _buildMap(),
          if (_isLoading) _buildLoadingOverlay(),
          if (_isBottomPanelVisible)
            Positioned(bottom: 0, left: 0, right: 0, child: _buildInfoPanel()),
          if (_showLayerSelection)
            Positioned(top: 80, right: 16, child: _buildLayerSelectionPanel()),
          if (_showSatelliteList)
            Positioned(
                top: 80,
                left: 16,
                right: 16,
                child: _buildSatelliteListPanel()),
          if (_showBandPanel)
            Positioned(top: 80, left: 16, right: 16, child: _buildBandPanel()),
          if (_isHardwareChecked && !_isLoading)
            Positioned(
                top: 16,
                left: 16,
                right: 16,
                child: _buildHardwareSupportBanner()),
        ],
      ),
      floatingActionButton: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton.small(
            onPressed: _toggleSatelliteList,
            backgroundColor: Colors.purple,
            child: Icon(
              _showSatelliteList ? Icons.close : Icons.satellite_alt,
              color: Colors.white,
            ),
            tooltip: 'Satellites',
          ),
          const SizedBox(width: 8),
          FloatingActionButton.small(
            onPressed: _toggleBandPanel,
            backgroundColor: Colors.green,
            child: Icon(
              _showBandPanel ? Icons.close : Icons.settings_input_antenna,
              color: Colors.white,
            ),
            tooltip: 'Bands',
          ),
          const SizedBox(width: 8),
          FloatingActionButton.small(
            onPressed: _toggleBottomPanel,
            backgroundColor: Colors.blue,
            child: Icon(
              _isBottomPanelVisible
                  ? Icons.keyboard_arrow_down
                  : Icons.keyboard_arrow_up,
              color: Colors.white,
            ),
            tooltip: _isBottomPanelVisible ? 'Hide Panel' : 'Show Panel',
          ),
          const SizedBox(width: 8),
          if (_usingExternalGnss && _currentPosition != null)
            FloatingActionButton(
              onPressed: _refreshLocation,
              backgroundColor: _isUsingNavic
                  ? Colors.green
                  : _getSystemColor(_primarySystem),
              child: Icon(
                _isUsingNavic
                    ? Icons.satellite_alt
                    : _getSystemIcon(_primarySystem),
                color: Colors.white,
              ),
              tooltip:
              _isUsingNavic ? 'NavIC Location' : '$_primarySystem Location',
            ),
          if (!_usingExternalGnss)
            FloatingActionButton(
              onPressed: _checkUsbDevices,
              backgroundColor: Colors.orange,
              child: const Icon(Icons.usb, color: Colors.white),
              tooltip: 'Connect USB GNSS',
            ),
          if (_usingExternalGnss)
            FloatingActionButton.small(
              onPressed: _disconnectUsbGnss,
              backgroundColor: Colors.red,
              child: const Icon(Icons.usb_off, color: Colors.white),
              tooltip: 'Disconnect USB',
            ),
        ],
      ),
    );
  }

  Widget _buildLoadingOverlay() {
    final displaySystem = _isUsingNavic ? 'NavIC' : _primarySystem;

    return Container(
      color: Colors.black.withValues(alpha: 0.4),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(_isUsingNavic
                  ? Colors.green
                  : _getSystemColor(_primarySystem)),
              strokeWidth: 3,
            ),
            const SizedBox(height: 20),
            Text(
              _usingExternalGnss
                  ? "Acquiring Location..."
                  : "Connecting to USB GNSS...",
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _isUsingNavic
                  ? "Using NavIC positioning"
                  : _usingExternalGnss
                  ? "Using $_primarySystem positioning"
                  : "Please wait...",
              style: TextStyle(
                color: Colors.white70,
                fontSize: 14,
              ),
            ),
          ],
        ),
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
            color: Colors.black.withValues(alpha: 0.2),
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
                onTap: () => _toggleLayer(name),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Row(
                    children: [
                      Checkbox(
                        value: _selectedLayers[name],
                        onChanged: (_) => _toggleLayer(name),
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

  Widget _buildInfoPanel() {
    if (_currentPosition == null) {
      return _buildLocationAcquiringPanel();
    }

    return Container(
      height: 450,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: SingleChildScrollView(
              controller: _scrollController,
              physics: const BouncingScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSystemStatusHeader(),
                  const SizedBox(height: 16),
                  _buildCoordinatesSection(),
                  const SizedBox(height: 16),
                  _buildAccuracyMetricsSection(),
                  const SizedBox(height: 16),
                  _buildHardwareInfoSection(),
                  const SizedBox(height: 16),
                  _buildSatelliteSummaryCard(),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLocationAcquiringPanel() {
    return Container(
      height: 160,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            _usingExternalGnss
                ? (_isUsingNavic
                ? Icons.satellite_alt
                : _getSystemIcon(_primarySystem))
                : Icons.usb,
            color: _usingExternalGnss
                ? (_isUsingNavic
                ? Colors.green.shade400
                : _getSystemColor(_primarySystem).withValues(alpha: 0.7))
                : Colors.orange.shade400,
            size: 48,
          ),
          const SizedBox(height: 12),
          Text(
            _usingExternalGnss
                ? (_isUsingNavic
                ? "Getting NavIC Location"
                : "Getting $_primarySystem Location")
                : "Connect USB GNSS Device",
            style: TextStyle(
              color: Colors.grey.shade600,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _usingExternalGnss
                ? (_isUsingNavic
                ? "Using NavIC with ${_hasL5BandActive ? 'L5 band active' : 'enhanced positioning'}"
                : "Using $_primarySystem for positioning")
                : "External USB GNSS required for location",
            style: TextStyle(
              color: Colors.grey.shade500,
              fontSize: 14,
            ),
          ),
          if (!_usingExternalGnss) const SizedBox(height: 12),
          if (!_usingExternalGnss)
            ElevatedButton.icon(
              onPressed: _checkUsbDevices,
              icon: const Icon(Icons.usb),
              label: const Text("Check USB Devices"),
            ),
        ],
      ),
    );
  }

  Widget _buildSystemStatusHeader() {
    final pos = _currentPosition!;
    final isNavic = _isUsingNavic && _isNavicSupported && _isNavicActive;
    final isUsb = _usingExternalGnss;

    Color backgroundColor;
    Color iconColor;
    String systemText;

    if (isUsb) {
      backgroundColor = Colors.teal.withValues(alpha: 0.15);
      iconColor = Colors.teal;
      systemText = "USB GNSS POSITIONING";
    } else if (isNavic) {
      backgroundColor = Colors.green.withValues(alpha: 0.15);
      iconColor = Colors.green;
      systemText = "NAVIC POSITIONING";
    } else {
      backgroundColor = _getSystemColor(_primarySystem).withValues(alpha: 0.15);
      iconColor = _getSystemColor(_primarySystem);
      systemText = "$_primarySystem POSITIONING";
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: iconColor.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: iconColor,
              shape: BoxShape.circle,
            ),
            child: Icon(
              isUsb
                  ? Icons.usb
                  : (isNavic
                  ? Icons.satellite_alt
                  : _getSystemIcon(_primarySystem)),
              color: Colors.white,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      systemText,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 10,
                        color: iconColor.withValues(alpha: 0.9),
                      ),
                    ),
                    if (_hasL5BandActive) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.green.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          "L5 Active",
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.green,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  _locationQuality,
                  style: TextStyle(
                    fontSize: 12,
                    color: iconColor.withValues(alpha: 0.8),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (_chipsetVendor != "Unknown" &&
                    _chipsetModel != "Unknown") ...[
                  const SizedBox(height: 2),
                  Text(
                    "$_chipsetVendor $_chipsetModel",
                    style: TextStyle(
                      fontSize: 10,
                      color: iconColor.withValues(alpha: 0.7),
                    ),
                  ),
                ],
                if (isUsb && _externalDeviceInfo.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    _externalDeviceInfo,
                    style: TextStyle(
                      fontSize: 10,
                      color: iconColor.withValues(alpha: 0.7),
                    ),
                  ),
                ],
                if (isNavic && _hasL5BandActive) ...[
                  const SizedBox(height: 2),
                  Text(
                    "L5 Band Active",
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.green.shade600,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: _getQualityColor().withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              "${(pos.confidenceScore * 100).toStringAsFixed(0)}%",
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: _getQualityColor(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCoordinatesSection() {
    final pos = _currentPosition!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "COORDINATES",
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Colors.grey.shade500,
            letterSpacing: 1.0,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildInfoCard(
                icon: Icons.explore,
                title: "LATITUDE",
                value: pos.latitude.toStringAsFixed(6),
                color: _isUsingNavic
                    ? Colors.green.shade50
                    : _getSystemColor(_primarySystem).withValues(alpha: 0.1),
                iconColor: _isUsingNavic
                    ? Colors.green.shade700
                    : _getSystemColor(_primarySystem),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildInfoCard(
                icon: Icons.explore_outlined,
                title: "LONGITUDE",
                value: pos.longitude.toStringAsFixed(6),
                color: _isUsingNavic
                    ? Colors.green.shade50
                    : _getSystemColor(_primarySystem).withValues(alpha: 0.1),
                iconColor: _isUsingNavic
                    ? Colors.green.shade700
                    : _getSystemColor(_primarySystem),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildAccuracyMetricsSection() {
    final pos = _currentPosition!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "ACCURACY METRICS",
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Colors.grey.shade500,
            letterSpacing: 1.0,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildInfoCard(
                icon: Icons.location_on_sharp,
                title: "ACCURACY",
                value: "${pos.accuracy?.toStringAsFixed(1) ?? 'N/A'} meters",
                color: _isUsingNavic
                    ? Colors.green.shade50
                    : Colors.orange.shade50,
                iconColor: _isUsingNavic
                    ? Colors.green.shade700
                    : Colors.orange.shade700,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildHardwareInfoSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "HARDWARE INFO",
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Colors.grey.shade500,
            letterSpacing: 1.0,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildInfoCard(
                icon: Icons.settings_input_antenna,
                title: "ACTIVE BAND",
                value: _hasL5BandActive ? "L5" : "L1",
                color: _hasL5BandActive
                    ? Colors.green.withValues(alpha: 0.1)
                    : Colors.orange.withValues(alpha: 0.1),
                iconColor: _hasL5BandActive ? Colors.green : Colors.orange,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildInfoCard(
                icon: Icons.usb,
                title: "USB STATUS",
                value: _usingExternalGnss ? "Connected" : "Disconnected",
                color: _usingExternalGnss
                    ? Colors.green.shade50
                    : Colors.grey.shade50,
                iconColor: _usingExternalGnss
                    ? Colors.green.shade700
                    : Colors.grey.shade700,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSatelliteSummaryCard() {
    final satelliteSummary = _locationService.getSatelliteSummary();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.satellite,
                      color: Colors.purple.shade600, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    "GNSS RANGE",
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ],
              ),
              if (_isUsingNavic)
                Container(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.satellite_alt, size: 12, color: Colors.green),
                      const SizedBox(width: 4),
                      Text(
                        "NavIC Active",
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.green,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              if (_usingExternalGnss)
                Container(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.teal.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.usb, size: 12, color: Colors.teal),
                      const SizedBox(width: 4),
                      Text(
                        "USB",
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.teal,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _buildSatelliteStat("Total Sats",
                  "${satelliteSummary['total'] ?? 0}", Colors.blue),
              const SizedBox(width: 12),
              _buildSatelliteStat(
                  "NavIC", "${satelliteSummary['navic'] ?? 0}", Colors.green),
              const SizedBox(width: 12),
              _buildSatelliteStat(
                  "GPS", "${satelliteSummary['gps'] ?? 0}", Colors.blue),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _isUsingNavic
                  ? Colors.green.withValues(alpha: 0.1)
                  : _getSystemColor(_primarySystem).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: _isUsingNavic
                    ? Colors.green.withValues(alpha: 0.3)
                    : _getSystemColor(_primarySystem).withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  _isUsingNavic
                      ? Icons.satellite_alt
                      : _getSystemIcon(_primarySystem),
                  size: 16,
                  color: _isUsingNavic
                      ? Colors.green
                      : _getSystemColor(_primarySystem),
                ),
                const SizedBox(width: 8),
                Text(
                  _isUsingNavic
                      ? "Using NavIC Positioning"
                      : "Using $_primarySystem Positioning",
                  style: TextStyle(
                    fontSize: 12,
                    color: _isUsingNavic
                        ? Colors.green
                        : _getSystemColor(_primarySystem),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                if (_isNavicSupported && !_isUsingNavic)
                  Text(
                    "NavIC Available",
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.green,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard(
      {required IconData icon,
        required String title,
        required String value,
        required Color color,
        required Color iconColor}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Colors.grey.shade800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSatelliteStat(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: color,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHardwareSupportBanner() {
    Color bannerColor;
    Color bannerIconColor;
    IconData bannerIcon;
    String bannerStatus;

    if (_usingExternalGnss) {
      bannerColor = Colors.teal.shade50;
      bannerIconColor = Colors.teal;
      bannerIcon = Icons.usb;
      bannerStatus = "USB GNSS Connected";
    } else if (_isUsingNavic && _isNavicActive && _hasL5BandActive) {
      bannerColor = Colors.green.shade50;
      bannerIconColor = Colors.green;
      bannerIcon = Icons.satellite_alt;
      bannerStatus = "NavIC Active";
    } else if (_isNavicSupported && _hasL5Band) {
      bannerColor = Colors.green.shade50;
      bannerIconColor = Colors.green;
      bannerIcon = Icons.satellite_alt;
      bannerStatus = "NavIC Ready";
    } else if (_hasL5BandActive) {
      bannerColor = Colors.blue.shade50;
      bannerIconColor = Colors.blue;
      bannerIcon = Icons.speed;
      bannerStatus = "L5 $_primarySystem Active";
    } else if (_hasL5Band) {
      bannerColor = Colors.blue.shade50;
      bannerIconColor = Colors.blue;
      bannerIcon = Icons.speed;
      bannerStatus = "L5 Available";
    } else {
      bannerColor = Colors.orange.shade50;
      bannerIconColor = Colors.orange;
      bannerIcon = Icons.usb;
      bannerStatus = "USB GNSS Required";
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: bannerColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: bannerIconColor.withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(bannerIcon, color: bannerIconColor, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  bannerStatus,
                  style: TextStyle(
                    color: bannerIconColor,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  _hardwareMessage,
                  style: TextStyle(
                    color: bannerIconColor,
                    fontSize: 11,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: bannerIconColor.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              _hasL5BandActive
                  ? "L5 Active"
                  : _usingExternalGnss
                  ? "USB"
                  : "Connect",
              style: TextStyle(
                color: bannerIconColor,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          if (_isUsingNavic)
            Container(
              margin: const EdgeInsets.only(left: 8),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                "NAVIC",
                style: TextStyle(
                  color: Colors.green,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          if (_usingExternalGnss)
            Container(
              margin: const EdgeInsets.only(left: 8),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.teal.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.usb, size: 10, color: Colors.teal),
                  const SizedBox(width: 2),
                  Text(
                    "USB",
                    style: TextStyle(
                      color: Colors.teal,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _detectingSubscription.cancel();
    _hardwareStateSubscription.cancel();
    _satellitesSubscription.cancel();
    _positionSubscription.cancel();
    _scrollController.dispose();
    _locationService.dispose();
    super.dispose();
  }
}