import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:navic_ss/services/location_service.dart';
import 'package:navic_ss/screens/emergency.dart';
import 'package:navic_ss/models/satellite_data_model.dart';
import 'package:navic_ss/models/gnss_satellite.dart';
import 'package:geolocator/geolocator.dart';

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
  bool _hasL1Band = false;
  bool _hasL2Band = false;
  bool _hasSBand = false;
  double _l5Confidence = 0.0;
  String _hardwareMessage = "Checking hardware...";
  String _hardwareStatus = "Checking...";
  bool _showLayerSelection = false;
  bool _showSatelliteList = false;
  bool _showBandPanel = false;
  bool _locationAcquired = false;
  LatLng? _lastValidMapCenter;
  String _chipsetType = "Unknown";
  String _chipsetVendor = "Unknown";
  String _chipsetModel = "Unknown";
  double _chipsetConfidence = 0.0;
  double _confidenceLevel = 0.0;
  double _signalStrength = 0.0;
  int _navicSatelliteCount = 0;
  int _totalSatelliteCount = 0;
  int _navicUsedInFix = 0;
  String _positioningMethod = "GPS";
  String _primarySystem = "GPS";
  Map<String, dynamic> _l5BandInfo = {};
  List<GnssSatellite> _allSatellites = [];
  List<GnssSatellite> _visibleSystems = [];
  List<GnssSatellite> _satelliteDetails = [];
  Map<String, dynamic> _systemStats = {};
  
  // Band information from hardware service
  Map<String, dynamic> _availableBands = {};
  Map<String, List<String>> _systemBands = {};
  List<String> _activeBands = [];
  List<String> _supportedBands = [];
  Map<String, int> _bandSatelliteCounts = {};
  Map<String, double> _bandAverageSignals = {};

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
      urlTemplate: 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
      userAgentPackageName: 'com.example.navic',
    ),
  };

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
      
      // Check and request permission only once
      _permissionGranted = await _checkAndRequestPermissionOnce();
      
      if (_permissionGranted) {
        // Use the new location service workflow:
        // 1. Gets GPS location first
        // 2. Checks hardware capabilities
        // 3. If hardware supports NavIC, tries to get NavIC-enhanced location
        // 4. Falls back to GPS if NavIC fails
        await _acquireInitialLocationWithNavICFlow();
        
        // Start monitoring in background
        _startRealTimeMonitoring();
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

  /// NEW: Uses the proper flow from location_service.dart
  Future<void> _acquireInitialLocationWithNavICFlow() async {
    try {
      print("\n🎯 ========= STARTING NAVIC FLOW FROM HOME SCREEN ==========");
      
      if (!_permissionGranted) {
        print("❌ No location permission, skipping acquisition");
        return;
      }

      // Use the new location service method that implements the proper flow
      final position = await _locationService.getLocationWithNavICFlow();
      
      if (position != null && _isValidCoordinate(position.latitude, position.longitude)) {
        print("✅ Location acquired successfully using NavIC flow");
        
        // Update state from the position returned by location service
        _isUsingNavic = position.isNavicEnhanced;
        _isHardwareChecked = _locationService.hasHardwareBeenChecked;
        _acquisitionFlow = _isUsingNavic ? "NAVIC" : "GPS";
        
        _updateLocationState(position);
        _centerMapOnPosition(position);
        _logLocationDetails(position);
        
        // Now update hardware info from location service
        await _updateHardwareInfoFromService();
      } else {
        print("❌ Location acquisition failed");
        await _tryFallbackLocationAcquisition();
      }
    } on TimeoutException catch (e) {
      print("⏰ Location acquisition timeout: $e");
      await _tryFallbackLocationAcquisition();
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

  /// Refresh location - follows same workflow
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

      // Use the new NavIC flow
      final position = await _locationService.getLocationWithNavICFlow();
      
      if (position != null && _isValidCoordinate(position.latitude, position.longitude)) {
        // Update state from position
        _isUsingNavic = position.isNavicEnhanced;
        _acquisitionFlow = _isUsingNavic ? "NAVIC" : "GPS";
        
        _updateLocationState(position);
        _centerMapOnPosition(position);
        _logLocationDetails(position);
        
        // Update hardware info
        await _updateHardwareInfoFromService();
        
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_isUsingNavic ? 
              "Location refreshed using NavIC" : 
              "Location refreshed using ${position.locationSource}"),
            backgroundColor: _isUsingNavic ? Colors.green : Colors.blue,
            duration: const Duration(seconds: 2),
          ),
        );
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

  /// Update hardware info from location service
  Future<void> _updateHardwareInfoFromService() async {
    try {
      print("🔄 Updating hardware info from location service...");
      
      setState(() {
        _isNavicSupported = _locationService.isNavicSupported;
        _isNavicActive = _locationService.isNavicActive;
        _hasL5Band = _locationService.hasL5Band;
        _hasL1Band = _locationService.hasL1Band;
        _hasL2Band = _locationService.hasL2Band;
        _hasSBand = _locationService.hasSBand;
        _l5Confidence = _locationService.l5Confidence;
        _chipsetType = _locationService.chipsetType;
        _chipsetVendor = _locationService.chipsetVendor;
        _chipsetModel = _locationService.chipsetModel;
        _chipsetConfidence = _locationService.chipsetConfidence;
        _confidenceLevel = _locationService.confidenceLevel;
        _signalStrength = _locationService.averageSignalStrength;
        _navicSatelliteCount = _locationService.navicSatelliteCount;
        _totalSatelliteCount = _locationService.totalSatelliteCount;
        _navicUsedInFix = _locationService.navicUsedInFix;
        _positioningMethod = _locationService.positioningMethod;
        _primarySystem = _locationService.primarySystem;
        _l5BandInfo = _locationService.l5BandInfo;
        
        _allSatellites = _locationService.allSatellites;
        _satelliteDetails = _locationService.satelliteDetails;
        _visibleSystems = _locationService.visibleSystems;
        _systemStats = _locationService.systemStats;
        
        // Get band information
        _availableBands = _locationService.availableBands;
        _systemBands = _locationService.systemBands;
        _activeBands = _locationService.activeBands;
        _supportedBands = _locationService.supportedBands;
        _bandSatelliteCounts = _locationService.bandSatelliteCounts;
        _bandAverageSignals = _locationService.bandAverageSignals;

        _updateHardwareMessage();
        _isHardwareChecked = _locationService.hasHardwareBeenChecked;
      });

      print("✅ Hardware info updated from service");
      print("  ✅ Using NavIC: $_isUsingNavic");
      print("  ✅ Acquisition Flow: $_acquisitionFlow");
      print("  ✅ NavIC Supported: $_isNavicSupported");
      print("  ✅ NavIC Active: $_isNavicActive");
      print("  ✅ L5 Band: $_hasL5Band (${(_l5Confidence * 100).toStringAsFixed(1)}%)");
      print("  ✅ S Band: $_hasSBand");
      print("  ✅ Should Use NavIC: ${_locationService.shouldUseNavic}");
      print("  ✅ Primary System: $_primarySystem");

    } catch (e) {
      print("❌ Error updating hardware info: $e");
    }
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
        
        // Show dialog but don't wait for it to complete
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _showEnableLocationDialog();
        });
        return false;
      }

      // Check current permission status
      LocationPermission permission = await Geolocator.checkPermission();
      print("📍 Current permission status: $permission");

      // Handle different permission states
      switch (permission) {
        case LocationPermission.whileInUse:
        case LocationPermission.always:
          print("✅ Permission already granted");
          _hasRequestedPermission = true;
          return true;
          
        case LocationPermission.denied:
          print("📍 Permission denied, requesting...");
          // Request permission using the new Android 13+ in-app dialog
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
          // For Android 13+, show explanation dialog first
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
                // Try requesting permission again
                final permission = await Geolocator.requestPermission();
                if (permission == LocationPermission.whileInUse || 
                    permission == LocationPermission.always) {
                  setState(() {
                    _permissionGranted = true;
                  });
                  // Retry location acquisition
                  await _acquireInitialLocationWithNavICFlow();
                } else {
                  // Fallback to app settings
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
                  // Request permission directly
                  final permission = await Geolocator.requestPermission();
                  if (permission == LocationPermission.whileInUse || 
                      permission == LocationPermission.always) {
                    setState(() {
                      _permissionGranted = true;
                    });
                    // Retry location acquisition
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

  Future<void> _tryFallbackLocationAcquisition() async {
    try {
      print("🔄 Trying fallback location acquisition...");
      
      // Quick check if location services are enabled
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        print("❌ Location services are disabled");
        return;
      }
      
      // Try with lower accuracy and shorter timeout
      print("📍 Trying with lower accuracy...");
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
        timeLimit: const Duration(seconds: 10),
      ).timeout(const Duration(seconds: 10));
      
      if (_isValidCoordinate(position.latitude, position.longitude)) {
        print("✅ Fallback location acquired");
        final enhancedPosition = EnhancedPosition(
          latitude: position.latitude,
          longitude: position.longitude,
          accuracy: position.accuracy,
          altitude: position.altitude,
          speed: position.speed,
          heading: position.heading,
          timestamp: position.timestamp,
          isNavicEnhanced: false,
          confidenceScore: 0.7,
          locationSource: "GPS",
          detectionReason: "Fallback GPS positioning",
          navicSatellites: 0,
          totalSatellites: 0,
          navicUsedInFix: 0,
          hasL5Band: false,
          positioningMethod: "GPS_FALLBACK",
          satelliteInfo: [],
          systemStats: {},
          primarySystem: "GPS",
          chipsetType: "Unknown",
          chipsetVendor: "Unknown",
          chipsetModel: "Unknown",
          chipsetConfidence: 0.0,
          l5Confidence: 0.0,
          verificationMethods: [],
          acquisitionTimeMs: 0.0,
          satelliteDetails: [],
        );
        
        _updateLocationState(enhancedPosition);
        _centerMapOnPosition(enhancedPosition);
        
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Using GPS for positioning"),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 3),
          ),
        );
      }
    } on TimeoutException {
      print("⏰ Fallback location acquisition timeout");
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Location acquisition timed out"),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 3),
        ),
      );
    } catch (e) {
      print("❌ Fallback location acquisition failed: $e");
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Location unavailable: ${e.toString()}"),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  /// FIXED: Properly determine primary system
  String _determinePrimarySystem() {
    // First use what's already determined by location service
    if (_primarySystem.isNotEmpty && _primarySystem != "Unknown") {
      return _primarySystem;
    }
    
    // Then check system stats
    if (_systemStats.isNotEmpty) {
      try {
        // Find the system with the most satellites used in fix
        String maxSystem = "GPS";
        int maxUsed = 0;
        
        for (final entry in _systemStats.entries) {
          final system = entry.key;
          final stats = entry.value;
          
          if (stats is Map<String, dynamic>) {
            final usedCount = stats['used'] as int? ?? 0;
            if (usedCount > maxUsed) {
              maxUsed = usedCount;
              maxSystem = system;
            }
          }
        }
        
        // Map to proper display names
        return _mapSystemToDisplayName(maxSystem);
      } catch (e) {
        print("⚠️ Error determining primary system: $e");
      }
    }
    
    // Fallback based on positioning method
    if (_positioningMethod.contains("NAVIC")) return "NavIC";
    if (_positioningMethod.contains("GLONASS")) return "GLONASS";
    if (_positioningMethod.contains("GALILEO")) return "Galileo";
    if (_positioningMethod.contains("BEIDOU")) return "BeiDou";
    if (_positioningMethod.contains("QZSS")) return "QZSS";
    if (_positioningMethod.contains("SBAS")) return "SBAS";
    if (_positioningMethod.contains("MULTI")) return "Multi-GNSS";
    
    return "GPS";
  }

  /// Map system codes to display names
  String _mapSystemToDisplayName(String system) {
    switch (system.toUpperCase()) {
      case 'IRNSS':
      case 'NAVIC': return "NavIC";
      case 'GPS': return "GPS";
      case 'GLO':
      case 'GLONASS': return "GLONASS";
      case 'GAL':
      case 'GALILEO': return "Galileo";
      case 'BDS':
      case 'BEIDOU': return "BeiDou";
      case 'QZS':
      case 'QZSS': return "QZSS";
      case 'SBS':
      case 'SBAS': return "SBAS";
      default: return system;
    }
  }

  Future<void> _updateSatelliteData() async {
    try {
      print("🛰️ Updating satellite data...");
      await _locationService.updateSatelliteData();
      
      setState(() {
        _allSatellites = _locationService.allSatellites;
        _satelliteDetails = _locationService.satelliteDetails;
        _visibleSystems = _locationService.visibleSystems;
        _systemStats = _locationService.systemStats;
        _navicSatelliteCount = _locationService.navicSatelliteCount;
        _totalSatelliteCount = _locationService.totalSatelliteCount;
        _navicUsedInFix = _locationService.navicUsedInFix;
        _hasL5Band = _locationService.hasL5Band;
        _hasL1Band = _locationService.hasL1Band;
        _hasL2Band = _locationService.hasL2Band;
        _hasSBand = _locationService.hasSBand;
        _l5Confidence = _locationService.l5Confidence;
        _positioningMethod = _locationService.positioningMethod;
        _primarySystem = _locationService.primarySystem; // Get from service
        
        // Update band information
        _activeBands = _locationService.activeBands;
        _bandSatelliteCounts = _locationService.bandSatelliteCounts;
        _bandAverageSignals = _locationService.bandAverageSignals;
      });
      
      print("✅ Satellite data updated: $_totalSatelliteCount total, $_navicSatelliteCount NavIC ($_navicUsedInFix in fix)");
      print("🎯 Primary System: $_primarySystem");
      print("🎯 Positioning Method: $_positioningMethod");
    } catch (e) {
      print("❌ Error updating satellite data: $e");
    }
  }

  void _updateHardwareMessage() {
    final bands = <String>[];
    if (_hasL1Band) bands.add('L1');
    if (_hasL2Band) bands.add('L2');
    if (_hasL5Band) bands.add('L5');
    if (_hasSBand) bands.add('S');
    
    final bandsStr = bands.isNotEmpty ? 'Available bands: ${bands.join(', ')}. ' : '';
    
    // Check if both L5 and S bands are present for NavIC support
    final bool hasNavicBands = _hasL5Band && _hasSBand;
    
    if (!_isNavicSupported && !hasNavicBands) {
      _hardwareMessage = "$bandsStr Device does not have both L5 and S bands required for NavIC. Using $_primarySystem.";
      _hardwareStatus = "Limited Hardware";
    } else if (_isNavicSupported && hasNavicBands) {
      _hardwareMessage = "$bandsStr Device has L5 and S bands. NavIC positioning ready!";
      _hardwareStatus = "NavIC Ready";
    } else if (_hasL5Band && _hasSBand) {
      _hardwareMessage = "$bandsStr Device has L5 and S bands but NavIC not fully supported.";
      _hardwareStatus = "Partial NavIC";
    } else if (_hasL5Band) {
      _hardwareMessage = "$bandsStr Device has L5 band support. $_primarySystem positioning available.";
      _hardwareStatus = "$_primarySystem with L5";
    } else {
      _hardwareMessage = "$bandsStr Using $_primarySystem positioning.";
      _hardwareStatus = "$_primarySystem Only";
    }

    _updateLocationSource();
  }

  void _setHardwareErrorState() {
    setState(() {
      _isHardwareChecked = true;
      _isNavicSupported = false;
      _isNavicActive = false;
      _hasL5Band = false;
      _hasL1Band = false;
      _hasL2Band = false;
      _hasSBand = false;
      _l5Confidence = 0.0;
      _hardwareMessage = "Hardware detection failed";
      _hardwareStatus = "Error";
      _locationSource = "GPS";
      _chipsetType = "Unknown";
      _chipsetVendor = "Unknown";
      _chipsetModel = "Unknown";
      _chipsetConfidence = 0.0;
      _confidenceLevel = 0.0;
      _signalStrength = 0.0;
      _navicSatelliteCount = 0;
      _totalSatelliteCount = 0;
      _navicUsedInFix = 0;
      _positioningMethod = "GPS";
      _primarySystem = "GPS";
      _l5BandInfo = {};
      _allSatellites = [];
      _visibleSystems = [];
      _satelliteDetails = [];
      _systemStats = {};
      _availableBands = {};
      _systemBands = {};
      _activeBands = [];
      _supportedBands = [];
      _bandSatelliteCounts = {};
      _bandAverageSignals = {};
      _isUsingNavic = false;
      _acquisitionFlow = "GPS";
    });
  }

  void _updateLocationState(EnhancedPosition position) {
    setState(() {
      _currentPosition = position;
      
      // Trust the location service for primary system
      _primarySystem = position.primarySystem;
      if (_primarySystem.isEmpty || _primarySystem == "Unknown") {
        _primarySystem = _determinePrimarySystem();
      }
      
      _updateLocationSource();
      _updateLocationQuality(position);
      _locationAcquired = true;
      _lastValidMapCenter = LatLng(position.latitude, position.longitude);

      // Update from location service
      _navicSatelliteCount = _locationService.navicSatelliteCount;
      _totalSatelliteCount = _locationService.totalSatelliteCount;
      _navicUsedInFix = _locationService.navicUsedInFix;
      _hasL5Band = _locationService.hasL5Band;
      _hasL1Band = _locationService.hasL1Band;
      _hasL2Band = _locationService.hasL2Band;
      _hasSBand = _locationService.hasSBand;
      _l5Confidence = _locationService.l5Confidence;
      _positioningMethod = _locationService.positioningMethod;
      
      // Ensure primary system is correct
      if (_primarySystem.isEmpty || _primarySystem == "Unknown") {
        _primarySystem = _determinePrimarySystem();
      }
      
      _chipsetType = _locationService.chipsetType;
      _chipsetVendor = _locationService.chipsetVendor;
      _chipsetModel = _locationService.chipsetModel;
      _chipsetConfidence = _locationService.chipsetConfidence;
      _isUsingNavic = position.isNavicEnhanced;
      _acquisitionFlow = _isUsingNavic ? "NAVIC" : _primarySystem;
      
      _allSatellites = _locationService.allSatellites;
      _satelliteDetails = _locationService.satelliteDetails;
      _systemStats = _locationService.systemStats;
      
      // Update band information
      _activeBands = _locationService.activeBands;
      _bandSatelliteCounts = _locationService.bandSatelliteCounts;
      _bandAverageSignals = _locationService.bandAverageSignals;
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
    print("💪 Confidence: ${(position.confidenceScore * 100).toStringAsFixed(1)}%");
    print("🏭 Vendor: $_chipsetVendor");
    print("📋 Model: $_chipsetModel");
    print("🎯 Chipset Confidence: ${(_chipsetConfidence * 100).toStringAsFixed(1)}%");
    print("📊 Hardware Confidence: ${(_confidenceLevel * 100).toStringAsFixed(1)}%");
    print("📡 NavIC Satellites: $_navicSatelliteCount ($_navicUsedInFix in fix)");
    print("📶 L1 Band: ${_hasL1Band ? 'Available' : 'Not Available'}");
    print("📶 L2 Band: ${_hasL2Band ? 'Available' : 'Not Available'}");
    print("📶 L5 Band: ${_hasL5Band ? 'Available' : 'Not Available'}");
    print("📶 S Band: ${_hasSBand ? 'Available' : 'Not Available'}");
    print("🔍 L5 Confidence: ${(_l5Confidence * 100).toStringAsFixed(1)}%");
    print("🎯 Positioning Method: $_positioningMethod");
    print("🛰️ Total Satellites: $_totalSatelliteCount");
    print("📊 Visible Satellites: ${_satelliteDetails.length}");
    print("📡 Active Bands: ${_activeBands.join(', ')}");
    print("📱 Using NavIC: $_isUsingNavic");
    print("📱 Acquisition Flow: $_acquisitionFlow");
    print("===========================\n");
  }

  Future<void> _startRealTimeMonitoring() async {
    try {
      await _locationService.startRealTimeMonitoring();
      await _updateSatelliteData();
      print("✅ Real-time monitoring started");
    } catch (e) {
      print("❌ Real-time monitoring failed: $e");
    }
  }

  /// Show actual system being used
  void _updateLocationSource() {
    if (_isUsingNavic && _isNavicSupported && _isNavicActive) {
      _locationSource = "NAVIC";
    } else {
      // Use the primary system determined from satellite data
      _locationSource = _primarySystem;
    }
    
    print("📍 Location Source Updated: $_locationSource (Using NavIC: $_isUsingNavic)");
  }

  void _updateLocationQuality(EnhancedPosition pos) {
    final isUsingNavic = _isUsingNavic && _isNavicSupported && _isNavicActive;
    final isUsingL5 = _activeBands.contains('L5');
    final isUsingL1 = _activeBands.contains('L1');
    final isUsingL2 = _activeBands.contains('L2');
    final isUsingS = _activeBands.contains('S');

    String bandInfo = "";
    if (isUsingL5) bandInfo = "L5 ";
    else if (isUsingL2) bandInfo = "L2 ";
    else if (isUsingL1) bandInfo = "L1 ";
    else if (isUsingS) bandInfo = "S ";

    // Use the actual location source
    final String systemName = _locationSource;
    
    if (pos.accuracy != null && pos.accuracy! < 1.0) {
      _locationQuality = isUsingNavic ? 
        "${bandInfo}NavIC Excellent" : 
        "${bandInfo}$systemName Excellent";
    } else if (pos.accuracy != null && pos.accuracy! < 2.0) {
      _locationQuality = isUsingNavic ? 
        "${bandInfo}NavIC High" : 
        "${bandInfo}$systemName High";
    } else if (pos.accuracy != null && pos.accuracy! < 5.0) {
      _locationQuality = isUsingNavic ? 
        "${bandInfo}NavIC Good" : 
        "${bandInfo}$systemName Good";
    } else if (pos.accuracy != null && pos.accuracy! < 10.0) {
      _locationQuality = isUsingNavic ? 
        "${bandInfo}NavIC Basic" : 
        "${bandInfo}$systemName Basic";
    } else {
      _locationQuality = isUsingNavic ? 
        "${bandInfo}NavIC Low" : 
        "${bandInfo}$systemName Low";
    }
  }

  void _toggleLayerSelection() => setState(() => _showLayerSelection = !_showLayerSelection);
  void _toggleSatelliteList() => setState(() => _showSatelliteList = !_showSatelliteList);
  void _toggleBandPanel() => setState(() => _showBandPanel = !_showBandPanel);
  void _toggleLayer(String layerName) => setState(() => _selectedLayers[layerName] = !_selectedLayers[layerName]!);
  void _toggleBottomPanel() => setState(() => _isBottomPanelVisible = !_isBottomPanelVisible);

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
        _isValidCoordinate(_currentPosition!.latitude, _currentPosition!.longitude)) {
      return LatLng(_currentPosition!.latitude, _currentPosition!.longitude);
    } else if (_lastValidMapCenter != null) {
      return _lastValidMapCenter!;
    } else {
      return const LatLng(28.6139, 77.2090); // Default to New Delhi
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
    final isL5 = _activeBands.contains('L5');
    final isL1 = _activeBands.contains('L1');
    final isL2 = _activeBands.contains('L2');
    final isS = _activeBands.contains('S');
    final accuracy = _currentPosition?.accuracy ?? 10.0;

    Color primaryColor;
    if (isL5) primaryColor = Colors.green;
    else if (isL2) primaryColor = Colors.blue;
    else if (isL1) primaryColor = Colors.orange;
    else if (isS) primaryColor = Colors.purple;
    else primaryColor = isNavic ? Colors.green : _getSystemColor(_primarySystem);

    return Stack(
      alignment: Alignment.center,
      children: [
        Container(
          width: (accuracy * 3.0).clamp(40.0, 250.0),
          height: (accuracy * 3.0).clamp(40.0, 250.0),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: primaryColor.withOpacity(0.15),
            border: Border.all(
              color: primaryColor.withOpacity(0.4),
              width: isL5 ? 2.0 : 1.5,
            ),
          ),
        ),
        Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: primaryColor.withOpacity(0.25),
            border: Border.all(
              color: primaryColor.withOpacity(0.6),
              width: isL5 ? 2.5 : 2.0,
            ),
          ),
        ),
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: primaryColor.withOpacity(0.4),
            border: Border.all(
              color: primaryColor.withOpacity(0.8),
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
          ],
        ),
      ],
    );
  }

  Widget _buildSatelliteListPanel() {
    return Container(
      width: MediaQuery.of(context).size.width * 0.9,
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
                  Icon(Icons.satellite_alt, color: Colors.purple.shade700, size: 20),
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
                    "${_satelliteDetails.length} sats",
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
          
          if (_satelliteDetails.isNotEmpty)
            SizedBox(
              height: 300,
              child: ListView.builder(
                shrinkWrap: true,
                physics: const BouncingScrollPhysics(),
                itemCount: _satelliteDetails.length,
                itemBuilder: (context, index) {
                  final sat = _satelliteDetails[index];
                  return _buildSatelliteListItem(sat);
                },
              ),
            )
          else
            _buildNoSatellitesView(),
          
          const SizedBox(height: 12),
          
          if (_primarySystem.isNotEmpty)
            _buildPrimarySystemInfo(),
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
                  Icon(Icons.settings_input_antenna, color: Colors.green.shade700, size: 20),
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
          
          // Current Active Band
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
                    Icon(Icons.wifi_tethering, color: Colors.green.shade700, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      "CURRENT ACTIVE BAND",
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.green.shade700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (_activeBands.isNotEmpty)
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _activeBands.map((band) {
                      // Get band frequency information
                      String bandDisplay = band;
                      if (_availableBands.containsKey(band)) {
                        final bandInfo = _availableBands[band];
                        if (bandInfo is Map && bandInfo.containsKey('frequencyHz')) {
                          final freq = bandInfo['frequencyHz'];
                          if (freq != null && freq > 0) {
                            bandDisplay = '$band (${(freq / 1e6).toStringAsFixed(2)} MHz)';
                          }
                        }
                      }
                      
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.green.shade100,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.green.shade300),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.circle,
                              size: 10,
                              color: Colors.green.shade700,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              bandDisplay,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.green.shade800,
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  )
                else
                  Text(
                    "No active bands detected",
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: 14,
                    ),
                  ),
              ],
            ),
          ),
          
          const SizedBox(height: 12),
          
          // Band Statistics
          if (_bandSatelliteCounts.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.purple.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.purple.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.analytics, color: Colors.purple.shade700, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        "BAND STATISTICS",
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.purple.shade700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: _bandSatelliteCounts.entries.map((entry) {
                      final band = entry.key;
                      final count = entry.value;
                      final avgSignal = _bandAverageSignals[band] ?? 0.0;
                      final isActive = _activeBands.contains(band);
                      
                      // Get frequency for display
                      String bandDisplay = band;
                      if (_availableBands.containsKey(band)) {
                        final bandInfo = _availableBands[band];
                        if (bandInfo is Map && bandInfo.containsKey('frequencyHz')) {
                          final freq = bandInfo['frequencyHz'];
                          if (freq != null && freq > 0) {
                            bandDisplay = '$band\n(${(freq / 1e6).toStringAsFixed(2)} MHz)';
                          }
                        }
                      }
                      
                      return Container(
                        width: 100,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: isActive ? Colors.purple.shade100 : Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isActive ? Colors.purple.shade300 : Colors.grey.shade300,
                          ),
                        ),
                        child: Column(
                          children: [
                            Text(
                              bandDisplay,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: isActive ? Colors.purple.shade800 : Colors.grey.shade700,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              "$count sats",
                              style: TextStyle(
                                fontSize: 12,
                                color: isActive ? Colors.purple.shade600 : Colors.grey.shade600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              "${avgSignal.toStringAsFixed(1)} dB-Hz",
                              style: TextStyle(
                                fontSize: 11,
                                color: isActive ? Colors.purple.shade600 : Colors.grey.shade600,
                              ),
                            ),
                            if (isActive)
                              Container(
                                margin: const EdgeInsets.only(top: 4),
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.green.shade100,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  "ACTIVE",
                                  style: TextStyle(
                                    fontSize: 9,
                                    color: Colors.green.shade800,
                                    fontWeight: FontWeight.bold,
                                  ),
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
      ),
    );
  }

  Widget _buildSatelliteListItem(GnssSatellite satellite) {
    final system = satellite.system;
    final svid = satellite.svid;
    final cn0 = satellite.cn0DbHz ?? 0.0;
    final used = satellite.usedInFix ?? false;
    final elevation = satellite.elevation ?? 0.0;
    final azimuth = satellite.azimuth ?? 0.0;
    final carrierFrequency = satellite.carrierFrequencyHz;
    final signalStrength = _getSignalStrengthString(cn0);
    final systemColor = _getSystemColor(system);
    final signalColor = _getSignalColor(cn0);
    final countryFlag = _getCountryFlag(system);
    final systemFullName = _getSystemFullName(system);
    final systemCountry = _getSystemCountry(system);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: systemColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  countryFlag,
                  style: const TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 4),
                Text(
                  _getConstellationAbbreviation(system),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: systemColor,
                  ),
                ),
              ],
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
                      "PRN-$svid",
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey.shade800,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: signalColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: signalColor),
                      ),
                      child: Text(
                        signalStrength,
                        style: TextStyle(
                          fontSize: 10,
                          color: signalColor,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    if (used)
                      Container(
                        margin: const EdgeInsets.only(left: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.green.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: Colors.green),
                        ),
                        child: const Text(
                          "IN FIX",
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.green,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                  ],
                ),

                const SizedBox(height: 6),

                Row(
                  children: [
                    Icon(Icons.signal_cellular_alt, size: 14, color: signalColor),
                    const SizedBox(width: 4),
                    Text(
                      "${cn0.toStringAsFixed(1)} dB-Hz",
                      style: TextStyle(
                        fontSize: 12,
                        color: signalColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 4),

                Row(
                  children: [
                    Icon(Icons.vertical_align_top, size: 14, color: Colors.orange.shade600),
                    const SizedBox(width: 4),
                    Text(
                      "${elevation.toStringAsFixed(0)}°",
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.orange.shade600,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Icon(Icons.compass_calibration, size: 14, color: Colors.purple.shade600),
                    const SizedBox(width: 4),
                    Text(
                      "${azimuth.toStringAsFixed(0)}°",
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.purple.shade600,
                      ),
                    ),

                    if (carrierFrequency != null && carrierFrequency > 0)
                      Row(
                        children: [
                          const SizedBox(width: 12),
                          Icon(Icons.waves, size: 14, color: Colors.blue.shade600),
                          const SizedBox(width: 4),
                          Text(
                            "${(carrierFrequency / 1e6).toStringAsFixed(1)} MHz",
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.blue.shade600,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),

                const SizedBox(height: 4),
                Text(
                  "$systemFullName • $systemCountry",
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),

          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: used ? Colors.green.withOpacity(0.2) : Colors.grey.withOpacity(0.2),
            ),
            child: Icon(
              used ? Icons.check_circle : Icons.radio_button_unchecked,
              size: 20,
              color: used ? Colors.green : Colors.grey,
            ),
          ),
        ],
      ),
    );
  }

  String _getSignalStrengthString(double cn0) {
    if (cn0 >= 35) return "EXCELLENT";
    if (cn0 >= 25) return "STRONG";
    if (cn0 >= 18) return "GOOD";
    if (cn0 >= 10) return "WEAK";
    return "VERY WEAK";
  }

  String _getConstellationAbbreviation(String system) {
    switch (system.toUpperCase()) {
      case 'IRNSS':
      case 'NAVIC': return 'IRN';
      case 'GPS': return 'GPS';
      case 'GLONASS': return 'GLO';
      case 'GALILEO': return 'GAL';
      case 'BEIDOU': return 'BDS';
      case 'QZSS': return 'QZS';
      case 'SBAS': return 'SBS';
      default: return system.length > 3 ? system.substring(0, 3) : system;
    }
  }

  String _getCountryFlag(String system) {
    switch (system.toUpperCase()) {
      case 'IRNSS':
      case 'NAVIC': return '🇮🇳';
      case 'GPS': return '🇺🇸';
      case 'GLONASS': return '🇷🇺';
      case 'GALILEO': return '🇪🇺';
      case 'BEIDOU':
      case 'BDS': return '🇨🇳';
      case 'QZSS': return '🇯🇵';
      case 'SBAS': return '🌐';
      default: return '🛰️';
    }
  }

  String _getSystemFullName(String system) {
    switch (system.toUpperCase()) {
      case 'IRNSS':
      case 'NAVIC': return 'Indian Regional Navigation Satellite System';
      case 'GPS': return 'Global Positioning System';
      case 'GLONASS': return 'Global Navigation Satellite System';
      case 'GALILEO': return 'Galileo Satellite Navigation';
      case 'BEIDOU':
      case 'BDS': return 'BeiDou Navigation Satellite System';
      case 'QZSS': return 'Quasi-Zenith Satellite System';
      case 'SBAS': return 'Satellite Based Augmentation System';
      default: return system;
    }
  }

  String _getSystemCountry(String system) {
    switch (system.toUpperCase()) {
      case 'IRNSS':
      case 'NAVIC': return 'India';
      case 'GPS': return 'United States';
      case 'GLONASS': return 'Russia';
      case 'GALILEO': return 'European Union';
      case 'BEIDOU':
      case 'BDS': return 'China';
      case 'QZSS': return 'Japan';
      case 'SBAS': return 'Multiple Countries';
      default: return 'International';
    }
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
            "No satellites detected",
            style: TextStyle(
              color: Colors.grey.shade600,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            "Make sure you're outdoors with clear sky view",
            style: TextStyle(
              color: Colors.grey.shade500,
              fontSize: 12,
            ),
            textAlign: TextAlign.center,
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
        color: primaryColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: primaryColor.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isNavicPrimary ? Icons.satellite_alt : _getSystemIcon(_primarySystem),
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
              if (_hasL5Band && _hasSBand)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.satellite_alt, size: 12, color: Colors.green),
                      const SizedBox(width: 4),
                      Text(
                        "NavIC",
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.green,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              if (_hasL5Band)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.speed, size: 12, color: Colors.green),
                      const SizedBox(width: 4),
                      Text(
                        "L5 ${(_l5Confidence * 100).toStringAsFixed(0)}%",
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
          
          if (_chipsetVendor != "Unknown")
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
                if (_chipsetConfidence > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      "${(_chipsetConfidence * 100).toStringAsFixed(0)}%",
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.blue,
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
      case 'IRNSS': return Icons.satellite_alt;
      case 'GPS': return Icons.gps_fixed;
      case 'GLONASS': return Icons.satellite;
      case 'GALILEO': return Icons.satellite;
      case 'BEIDOU':
      case 'BDS': return Icons.satellite;
      case 'QZSS': return Icons.satellite;
      case 'SBAS': return Icons.satellite;
      default: return Icons.gps_fixed;
    }
  }

  Color _getSignalColor(double cn0) {
    if (cn0 >= 35) return Colors.green;
    if (cn0 >= 25) return Colors.blue;
    if (cn0 >= 18) return Colors.orange;
    if (cn0 >= 10) return Colors.amber;
    return Colors.red;
  }

  Color _getSystemColor(String system) {
    switch (system.toUpperCase()) {
      case 'IRNSS':
      case 'NAVIC': return Colors.green;
      case 'GPS': return Colors.blue;
      case 'GLONASS': return Colors.red;
      case 'GALILEO': return Colors.purple;
      case 'BEIDOU': return Colors.orange;
      case 'QZSS': return Colors.pink;
      case 'SBAS': return Colors.teal;
      default: return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Create a string for the AppBar subtitle
    String appBarSubtitle = "";
    
    if (_chipsetVendor != "Unknown") {
      appBarSubtitle = "$_chipsetVendor $_chipsetModel";
      
      // Add NavIC support status
      final hasNavicBands = _hasL5Band && _hasSBand;
      if (_isNavicSupported && hasNavicBands) {
        appBarSubtitle += " • NavIC Supported";
      } else if (hasNavicBands) {
        appBarSubtitle += " • Has L5+S Bands";
      }
      
      // Add L5 band info
      if (_hasL5Band) {
        appBarSubtitle += " • L5 Band";
      }
      
      // Add S band info
      if (_hasSBand) {
        appBarSubtitle += " • S Band";
      }
      
      // Add current location source - Show actual system being used
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
        backgroundColor: _isUsingNavic ? Colors.green.shade700 : _getSystemColor(_primarySystem).withOpacity(0.8),
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
            onPressed: _updateSatelliteData,
            tooltip: 'Update Satellites',
          ),
          IconButton(
            icon: const Icon(Icons.settings_input_antenna),
            onPressed: _toggleBandPanel,
            tooltip: 'Band Information',
          ),
          IconButton(
            icon: Icon(_isBottomPanelVisible ? Icons.visibility_off : Icons.visibility),
            onPressed: _toggleBottomPanel,
            tooltip: _isBottomPanelVisible ? 'Hide Panel' : 'Show Panel',
          ),
          if (_currentPosition != null)
            IconButton(
              icon: const Icon(Icons.emergency_share_sharp),
              iconSize: 24,
              onPressed: () => Navigator.push(
                context, 
                MaterialPageRoute(builder: (context) => const EmergencyPage()),
              ),
            ),
        ],
      ),
      body: Stack(
        children: [
          _buildMap(),
          if (_isLoading) _buildLoadingOverlay(),
          if (_isBottomPanelVisible)
            Positioned(bottom: 0, left: 0, right: 0, child: _buildInfoPanel()),
          if (_showLayerSelection) Positioned(top: 80, right: 16, child: _buildLayerSelectionPanel()),
          if (_showSatelliteList) Positioned(top: 80, left: 16, right: 16, child: _buildSatelliteListPanel()),
          if (_showBandPanel) Positioned(top: 80, left: 16, right: 16, child: _buildBandPanel()),
          if (_isHardwareChecked && !_isLoading)
            Positioned(top: 16, left: 16, right: 16, child: _buildHardwareSupportBanner()),
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
              _isBottomPanelVisible ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_up,
              color: Colors.white,
            ),
            tooltip: _isBottomPanelVisible ? 'Hide Panel' : 'Show Panel',
          ),
          const SizedBox(width: 8),
          if (_currentPosition != null)
            FloatingActionButton(
              onPressed: _refreshLocation,
              backgroundColor: _isUsingNavic ? Colors.green : _getSystemColor(_primarySystem),
              child: Icon(
                _isUsingNavic ? Icons.satellite_alt : _getSystemIcon(_primarySystem), 
                color: Colors.white
              ),
              tooltip: _isUsingNavic ? 'NavIC Location' : '$_primarySystem Location',
            ),
        ],
      ),
    );
  }

  Widget _buildLoadingOverlay() {
    // Determine display system name
    final displaySystem = _isUsingNavic ? 'NavIC' : _primarySystem;
    
    return Container(
      color: Colors.black.withOpacity(0.4),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(
                _isUsingNavic ? Colors.green : _getSystemColor(_primarySystem)
              ),
              strokeWidth: 3,
            ),
            const SizedBox(height: 20),
            Text(
              "Acquiring Location...",
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _isUsingNavic ? 
                "Using NavIC positioning" : 
                "Using $_primarySystem positioning",
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
          ..._selectedLayers.keys.map((name) => Padding(
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
          )).toList(),
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
            color: Colors.black.withOpacity(0.15),
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
            color: Colors.black.withOpacity(0.15),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            _isUsingNavic ? Icons.satellite_alt : _getSystemIcon(_primarySystem), 
            color: _isUsingNavic ? Colors.green.shade400 : _getSystemColor(_primarySystem).withOpacity(0.7), 
            size: 48
          ),
          const SizedBox(height: 12),
          Text(
            _isUsingNavic ? "Getting NavIC Location" : "Getting $_primarySystem Location",
            style: TextStyle(
              color: Colors.grey.shade600,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _isUsingNavic ? 
              "Using NavIC with ${_hasL5Band && _hasSBand ? 'L5 & S bands' : 'enhanced positioning'}" : 
              "Using $_primarySystem for positioning",
            style: TextStyle(
              color: Colors.grey.shade500,
              fontSize: 14,
            ),
          ),
          if (_activeBands.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              "Active Bands: ${_activeBands.join(', ')}",
              style: TextStyle(
                color: Colors.grey.shade500,
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSystemStatusHeader() {
    final pos = _currentPosition!;
    final isNavic = _isUsingNavic && _isNavicSupported && _isNavicActive;
    final activeBand = _activeBands.isNotEmpty ? _activeBands.first : "L1";

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isNavic
            ? Colors.green.withOpacity(0.15)
            : _getSystemColor(_primarySystem).withOpacity(0.15),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isNavic
              ? Colors.green.withOpacity(0.3)
              : _getSystemColor(_primarySystem).withOpacity(0.3),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isNavic ? Colors.green : _getSystemColor(_primarySystem),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isNavic ? Icons.satellite_alt : _getSystemIcon(_primarySystem),
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
                      isNavic ? "NAVIC POSITIONING" : "$_primarySystem POSITIONING",
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 10,
                        color: isNavic ? Colors.green.shade800 : _getSystemColor(_primarySystem).withOpacity(0.9),
                      ),
                    ),
                    if (_activeBands.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: _getBandColor(activeBand).withOpacity(0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          activeBand,
                          style: TextStyle(
                            fontSize: 10,
                            color: _getBandColor(activeBand),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                    if (isNavic)
                      Container(
                        margin: const EdgeInsets.only(left: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.green.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          "NAVIC",
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.green,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  _locationQuality,
                  style: TextStyle(
                    fontSize: 12,
                    color: isNavic ? Colors.green.shade600 : _getSystemColor(_primarySystem).withOpacity(0.8),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (_chipsetVendor != "Unknown") ...[
                  const SizedBox(height: 2),
                  Text(
                    "$_chipsetVendor $_chipsetModel",
                    style: TextStyle(
                      fontSize: 10,
                      color: isNavic ? Colors.green.shade500 : _getSystemColor(_primarySystem).withOpacity(0.7),
                    ),
                  ),
                ],
                if (isNavic && _hasL5Band && _hasSBand) ...[
                  const SizedBox(height: 2),
                  Text(
                    "L5 + S Bands Active",
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
              color: _getQualityColor().withOpacity(0.2),
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

  Color _getBandColor(String band) {
    switch (band.toUpperCase()) {
      case 'L5': return Colors.green;
      case 'L2': return Colors.blue;
      case 'L1': return Colors.orange;
      case 'S': return Colors.purple;
      case 'G1':
      case 'G2':
      case 'G3': return Colors.red; // GLONASS bands
      case 'E1':
      case 'E5':
      case 'E5A': return Colors.purple; // Galileo bands
      case 'B1':
      case 'B2':
      case 'B2A': return Colors.orange; // BeiDou bands
      default: return Colors.grey;
    }
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
                color: _isUsingNavic ? Colors.green.shade50 : _getSystemColor(_primarySystem).withOpacity(0.1),
                iconColor: _isUsingNavic ? Colors.green.shade700 : _getSystemColor(_primarySystem),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildInfoCard(
                icon: Icons.explore_outlined,
                title: "LONGITUDE",
                value: pos.longitude.toStringAsFixed(6),
                color: _isUsingNavic ? Colors.green.shade50 : _getSystemColor(_primarySystem).withOpacity(0.1),
                iconColor: _isUsingNavic ? Colors.green.shade700 : _getSystemColor(_primarySystem),
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
                color: _isUsingNavic ? Colors.green.shade50 : Colors.orange.shade50,
                iconColor: _isUsingNavic ? Colors.green.shade700 : Colors.orange.shade700,
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
                icon: Icons.memory,
                title: "CHIPSET",
                value: "$_chipsetVendor $_chipsetModel",
                color: Colors.purple.shade50,
                iconColor: Colors.purple.shade700,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildInfoCard(
                icon: Icons.settings_input_antenna,
                title: "ACTIVE BAND",
                value: _activeBands.isNotEmpty ? _activeBands.join(', ') : "None",
                color: _activeBands.isNotEmpty ? _getBandColor(_activeBands.first).withOpacity(0.1) : Colors.grey.shade50,
                iconColor: _activeBands.isNotEmpty ? _getBandColor(_activeBands.first) : Colors.grey.shade700,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSatelliteSummaryCard() {
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
                  Icon(Icons.satellite, color: Colors.purple.shade600, size: 18),
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
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.1),
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
            ],
          ),
          const SizedBox(height: 12),

          Row(
            children: [
              _buildSatelliteStat("Total Sats", "$_totalSatelliteCount", Colors.blue),
              const SizedBox(width: 12),
              _buildSatelliteStat("NavIC", "$_navicSatelliteCount", Colors.green),
              const SizedBox(width: 12),
            ],
          ),
          const SizedBox(height: 8),
          
          // Location source indicator
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _isUsingNavic ? Colors.green.withOpacity(0.1) : _getSystemColor(_primarySystem).withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: _isUsingNavic ? Colors.green.withOpacity(0.3) : _getSystemColor(_primarySystem).withOpacity(0.3),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  _isUsingNavic ? Icons.satellite_alt : _getSystemIcon(_primarySystem),
                  size: 16,
                  color: _isUsingNavic ? Colors.green : _getSystemColor(_primarySystem),
                ),
                const SizedBox(width: 8),
                Text(
                  _isUsingNavic ? "Using NavIC Positioning" : "Using $_primarySystem Positioning",
                  style: TextStyle(
                    fontSize: 12,
                    color: _isUsingNavic ? Colors.green : _getSystemColor(_primarySystem),
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

  Widget _buildInfoCard({required IconData icon, required String title, required String value, required Color color, required Color iconColor}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
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
              color: iconColor.withOpacity(0.1),
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
          color: color.withOpacity(0.1),
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

    // Check for NavIC support (requires both L5 and S bands)
    final bool hasNavicBands = _hasL5Band && _hasSBand;
    
    if (_isUsingNavic && _isNavicActive && hasNavicBands) {
      bannerColor = Colors.green.shade50;
      bannerIconColor = Colors.green;
      bannerIcon = Icons.satellite_alt;
      bannerStatus = "NavIC Active";
    } else if (_isNavicSupported && hasNavicBands) {
      bannerColor = Colors.green.shade50;
      bannerIconColor = Colors.green;
      bannerIcon = Icons.satellite_alt;
      bannerStatus = "NavIC Ready";
    } else if (hasNavicBands) {
      bannerColor = Colors.blue.shade50;
      bannerIconColor = Colors.blue;
      bannerIcon = Icons.check_circle;
      bannerStatus = "L5 + S Bands";
    } else if (_hasL5Band && _activeBands.contains('L5')) {
      bannerColor = Colors.blue.shade50;
      bannerIconColor = Colors.blue;
      bannerIcon = Icons.speed;
      bannerStatus = "L5 $_primarySystem Active";
    } else if (_hasL5Band) {
      bannerColor = Colors.blue.shade50;
      bannerIconColor = Colors.blue;
      bannerIcon = Icons.speed;
      bannerStatus = "L5 Available";
    } else if (_hasSBand) {
      bannerColor = Colors.purple.shade50;
      bannerIconColor = Colors.purple;
      bannerIcon = Icons.settings_input_antenna;
      bannerStatus = "S-Band Available";
    } else {
      bannerColor = Colors.orange.shade50;
      bannerIconColor = Colors.orange;
      bannerIcon = Icons.warning;
      bannerStatus = "$_primarySystem Only";
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: bannerColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: bannerIconColor.withOpacity(0.3)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
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
          if (_activeBands.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: bannerIconColor.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _activeBands.join(', '),
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
                color: Colors.green.withOpacity(0.2),
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
        ],
      ),
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _locationService.dispose();
    super.dispose();
  }
}