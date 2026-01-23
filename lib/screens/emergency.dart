import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:async';
import '../services/location_service.dart';
import 'package:geolocator/geolocator.dart';

class EmergencyPage extends StatefulWidget {
  const EmergencyPage({super.key});

  @override
  State<EmergencyPage> createState() => _EmergencyPageState();
}

class _EmergencyPageState extends State<EmergencyPage> {
  final EnhancedLocationService _locationService = EnhancedLocationService();
  bool _isLoading = false;
  String _currentStatus = "Ready";
  bool _isLiveTracking = false;
  Timer? _locationUpdateTimer;
  dynamic _lastPosition;
  String _locationSource = "GPS";
  bool _hasL5Band = false;
  String _chipsetVendor = "Unknown";
  String _chipsetModel = "Unknown";
  double _l5Confidence = 0.0;
  double _confidenceLevel = 0.0;
  double _signalStrength = 0.0;
  int _navicSatelliteCount = 0;
  int _totalSatelliteCount = 0;
  int _navicUsedInFix = 0;
  String _positioningMethod = "GPS";
  String _primarySystem = "GPS";
  
  // Emergency numbers
  final Map<String, String> _emergencyNumbers = {
    "Police": "100",
    "Ambulance": "102",
    "Fire": "101",
    "Women Helpline": "1091",
    "Child Helpline": "1098",
    "Disaster Management": "108",
    "Emergency (India)": "112",
    "Road Accident": "1073",
  };
  
  String _customEmergencyNumber = "";
  String _selectedEmergencyType = "Emergency (India)";

  @override
  void initState() {
    super.initState();
    _initializeLocationService();
  }

  void _initializeLocationService() async {
    try {
      await _locationService.initializeService();
      await _locationService.startRealTimeMonitoring();
      
      _updateServiceStats();
    } catch (e) {
      print("❌ Error initializing location service: $e");
    }
  }

  Future<void> _updateServiceStats() async {
    try {
      final serviceStats = await _locationService.getServiceStats();
      
      setState(() {
        _hasL5Band = serviceStats['hasL5Band'] as bool? ?? false;
        _chipsetVendor = serviceStats['chipsetVendor'] as String? ?? "Unknown";
        _chipsetModel = serviceStats['chipsetModel'] as String? ?? "Unknown";
        _l5Confidence = (serviceStats['l5Confidence'] as num?)?.toDouble() ?? 0.0;
        _confidenceLevel = (serviceStats['confidenceLevel'] as num?)?.toDouble() ?? 0.0;
        _signalStrength = (serviceStats['signalStrength'] as num?)?.toDouble() ?? 0.0;
        _navicSatelliteCount = serviceStats['navicSatellites'] as int? ?? 0;
        _totalSatelliteCount = serviceStats['totalSatellites'] as int? ?? 0;
        _navicUsedInFix = serviceStats['navicUsedInFix'] as int? ?? 0;
        _positioningMethod = serviceStats['positioningMethod'] as String? ?? "GPS";
        _primarySystem = serviceStats['primarySystem'] as String? ?? "GPS";
      });
    } catch (e) {
      print("❌ Error updating service stats: $e");
    }
  }

  Future<bool> _checkAndRequestLocationPermission() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _showError("Location services are disabled. Please enable location services.");
        return false;
      }

      LocationPermission permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.deniedForever) {
        _showError("Location permission denied forever. Please enable in app settings.");
        return false;
      }

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();

        if (permission == LocationPermission.denied ||
            permission == LocationPermission.deniedForever) {
          _showError("Location permission denied. Emergency features require location access.");
          return false;
        }
      }

      return permission == LocationPermission.always ||
          permission == LocationPermission.whileInUse;
    } catch (e) {
      _showError("Permission error: $e");
      return false;
    }
  }

  Future<dynamic> _getEnhancedLocation() async {
    final hasPermission = await _checkAndRequestLocationPermission();
    if (!hasPermission) {
      return null;
    }

    setState(() {
      _isLoading = true;
      _currentStatus = "Acquiring Location...";
    });

    try {
      final enhancedPos = await _locationService.getCurrentLocation();

      if (enhancedPos == null) {
        _showError("Unable to fetch current location!");
        return null;
      }

      await _updateServiceStats();
      
      setState(() {
        _currentStatus = "Location Acquired";
        _lastPosition = enhancedPos;
        _locationSource = _getLocationSource(enhancedPos);
      });

      return enhancedPos;
    } catch (e) {
      _showError("Location error: $e");
      return null;
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  String _getLocationSource(dynamic position) {
    try {
      // Try to access isNavicEnhanced property
      final isNavicEnhanced = position.isNavicEnhanced as bool? ?? false;
      final primarySystem = position.primarySystem as String? ?? "GPS";
      
      return isNavicEnhanced ? "NAVIC" : primarySystem;
    } catch (e) {
      return "GPS";
    }
  }

  bool _getIsNavicEnhanced(dynamic position) {
    try {
      return position.isNavicEnhanced as bool? ?? false;
    } catch (e) {
      return false;
    }
  }

  double _getLatitude(dynamic position) {
    try {
      return position.latitude as double? ?? 0.0;
    } catch (e) {
      return 0.0;
    }
  }

  double _getLongitude(dynamic position) {
    try {
      return position.longitude as double? ?? 0.0;
    } catch (e) {
      return 0.0;
    }
  }

  double _getAccuracy(dynamic position) {
    try {
      return position.accuracy as double? ?? 10.0;
    } catch (e) {
      return 10.0;
    }
  }

  double _getConfidenceScore(dynamic position) {
    try {
      return position.confidenceScore as double? ?? 0.0;
    } catch (e) {
      return 0.0;
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 3),
      ),
    );
    setState(() {
      _currentStatus = "Error: ${message.length > 30 ? message.substring(0, 30) + '...' : message}";
    });
  }

  void _showSuccess(String message) {
    if (!mounted) return;
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // FIXED: Emergency call function with multiple options
  Future<void> _showEmergencyCallDialog() async {
    // Get current location first
    final enhancedPos = await _getEnhancedLocation();
    if (enhancedPos == null) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.emergency, color: Colors.red),
            SizedBox(width: 10),
            Text("Emergency Call"),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                "Select emergency service to call:",
                style: TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 20),
              
              // Emergency number list
              ..._emergencyNumbers.entries.map((entry) {
                return ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.red.shade100,
                      shape: BoxShape.circle,
                    ),
                    child: _getEmergencyIcon(entry.key),
                  ),
                  title: Text(
                    entry.key,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text("Number: ${entry.value}"),
                  trailing: const Icon(Icons.call, color: Colors.red),
                  onTap: () {
                    Navigator.pop(context);
                    _callEmergencyNumber(entry.value, entry.key);
                  },
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  tileColor: Colors.red.withOpacity(0.05),
                );
              }).toList(),
              
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 16),
              
              // Custom number input
              TextField(
                decoration: InputDecoration(
                  labelText: "Custom Emergency Number",
                  hintText: "Enter phone number",
                  prefixIcon: const Icon(Icons.phone),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                keyboardType: TextInputType.phone,
                onChanged: (value) {
                  setState(() {
                    _customEmergencyNumber = value.trim();
                  });
                },
              ),
              
              const SizedBox(height: 16),
              
              if (_customEmergencyNumber.isNotEmpty)
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      _callEmergencyNumber(_customEmergencyNumber, "Custom Number");
                    },
                    icon: const Icon(Icons.call),
                    label: const Text("Call Custom Number"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                    ),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
        ],
      ),
    );
  }

  Icon _getEmergencyIcon(String service) {
    switch (service) {
      case "Police":
        return const Icon(Icons.local_police, color: Colors.blue, size: 18);
      case "Ambulance":
        return const Icon(Icons.local_hospital, color: Colors.red, size: 18);
      case "Fire":
        return const Icon(Icons.fire_truck, color: Colors.orange, size: 18);
      case "Women Helpline":
        return const Icon(Icons.female, color: Colors.purple, size: 18);
      case "Child Helpline":
        return const Icon(Icons.child_care, color: Colors.pink, size: 18);
      case "Disaster Management":
        return const Icon(Icons.warning, color: Colors.amber, size: 18);
      default:
        return const Icon(Icons.emergency, color: Colors.red, size: 18);
    }
  }

  Future<void> _callEmergencyNumber(String number, String serviceName) async {
    // Format number for dialing
    String formattedNumber = number;
    if (!formattedNumber.startsWith("tel:")) {
      formattedNumber = "tel:$formattedNumber";
    }

    try {
      if (await canLaunchUrl(Uri.parse(formattedNumber))) {
        await launchUrl(Uri.parse(formattedNumber));
        _showSuccess("Calling $serviceName...");
      } else {
        _showError("Cannot make call to $serviceName");
      }
    } catch (e) {
      _showError("Call error: $e");
    }
  }

  Future<void> shareLocation() async {
    final enhancedPos = await _getEnhancedLocation();
    if (enhancedPos == null) return;

    _shareLocationMessage(enhancedPos, "CURRENT LOCATION");
    _showSuccess("Location shared successfully!");
  }

  Future<void> startLiveLocationSharing() async {
    if (_isLiveTracking) {
      _stopLiveTracking();
      setState(() {
        _currentStatus = "Live Tracking Stopped";
      });
      _showSuccess("Live tracking stopped");
      return;
    }

    final hasPermission = await _checkAndRequestLocationPermission();
    if (!hasPermission) return;

    setState(() {
      _isLoading = true;
      _currentStatus = "Starting Live Location Sharing...";
    });

    try {
      final initialPos = await _locationService.getCurrentLocation();
      if (initialPos == null) return;

      _lastPosition = initialPos;

      await _locationService.startRealTimeMonitoring();

      _startPeriodicLocationUpdates();

      await _updateServiceStats();
      
      setState(() {
        _isLiveTracking = true;
        _isLoading = false;
        _currentStatus = "Live Sharing Active - Share the link!";
        _locationSource = _getLocationSource(initialPos);
      });

      String liveShareMessage = _createLiveShareMessage(initialPos);
      Share.share(liveShareMessage);

      _showSuccess("Live tracking started!");

    } catch (e) {
      setState(() {
        _isLoading = false;
        _currentStatus = "Failed to start live tracking";
      });
      _showError("Live tracking error: $e");
    }
  }

  void _startPeriodicLocationUpdates() {
    _locationUpdateTimer = Timer.periodic(const Duration(seconds: 30), (timer) async {
      if (!_isLiveTracking) {
        timer.cancel();
        return;
      }

      try {
        final newPos = await _locationService.getCurrentLocation();
        if (newPos != null) {
          await _updateServiceStats();
          
          setState(() {
            _lastPosition = newPos;
            _currentStatus = "Live Tracking - ${DateTime.now().toString().split('.').first}";
            _locationSource = _getLocationSource(newPos);
          });
        }
      } catch (e) {
        print("Periodic update error: $e");
      }
    });
  }

  void _stopLiveTracking() {
    _locationUpdateTimer?.cancel();
    _locationService.stopRealTimeMonitoring();
    setState(() {
      _isLiveTracking = false;
    });
  }

  Future<void> sendLocationUpdate() async {
    if (_lastPosition == null) {
      final currentPos = await _getEnhancedLocation();
      if (currentPos == null) return;
      _lastPosition = currentPos;
    }

    _shareLocationMessage(_lastPosition!, "LOCATION UPDATE");

    setState(() {
      _currentStatus = "Location Update Sent - ${DateTime.now().toString().split('.').first}";
    });

    _showSuccess("Location update sent!");
  }

 // FIXED: Emergency SMS function - Optimized for screen
Future<void> _showEmergencySMSDialog() async {
  // Get location first
  final enhancedPos = await _getEnhancedLocation();
  if (enhancedPos == null) return;

  final screenHeight = MediaQuery.of(context).size.height;
  final isSmallScreen = screenHeight < 600;
  final isMediumScreen = screenHeight < 800;

  String? selectedService = await showDialog<String>(
    context: context,
    builder: (context) => Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: screenHeight * 0.8, // Dynamic height based on screen
          maxWidth: 400, // Maximum width for larger screens
        ),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(9),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade100,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.sms, color: Colors.blue, size: 24),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        "Send Emergency SMS",
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue,
                        ),
                      ),
                    ),
                  ],
                ),
                
                const SizedBox(height: 20),
                
                // Instruction
                Text(
                  "Select emergency service:",
                  style: TextStyle(
                    fontSize: isSmallScreen ? 12 : 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                
                const SizedBox(height: 16),
                
                // Emergency service selection - Better for small screens
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _selectedEmergencyType,
                      isExpanded: true,
                      icon: const Icon(Icons.arrow_drop_down, color: Colors.blue),
                      iconSize: 28,
                      style: TextStyle(
                        fontSize: isSmallScreen ? 14 : 16,
                        color: Colors.black87,
                      ),
                      items: _emergencyNumbers.entries.map((entry) {
                        return DropdownMenuItem<String>(
                          value: entry.key,
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Row(
                              children: [
                                _getEmergencyIcon(entry.key),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        entry.key,
                                        style: const TextStyle(fontWeight: FontWeight.w500),
                                      ),
                                      Text(
                                        entry.value,
                                        style: TextStyle(
                                          fontSize: isSmallScreen ? 11 : 12,
                                          color: Colors.grey.shade600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                      onChanged: (String? newValue) {
                        if (newValue != null) {
                          setState(() {
                            _selectedEmergencyType = newValue;
                          });
                        }
                      },
                    ),
                  ),
                ),
                
                const SizedBox(height: 20),
                
                // Preview section
                Text(
                  "Message Preview:",
                  style: TextStyle(
                    fontSize: isSmallScreen ? 13 : 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade700,
                  ),
                ),
                
                const SizedBox(height: 8),
                
                // Scrollable preview container
                Container(
                  height: isSmallScreen ? 120 : 150,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: SingleChildScrollView(
                    child: Text(
                      _createEmergencyMessage(enhancedPos, _selectedEmergencyType),
                      style: TextStyle(
                        fontSize: isSmallScreen ? 11 : 12,
                        height: 1.4,
                      ),
                    ),
                  ),
                ),
                
                const SizedBox(height: 8),
                
                // Character count warning
                Text(
                  "Message will be sent to your default SMS app",
                  style: TextStyle(
                    fontSize: isSmallScreen ? 10 : 11,
                    color: Colors.grey.shade600,
                    fontStyle: FontStyle.italic,
                  ),
                ),
                
                const SizedBox(height: 24),
                
                // Action buttons
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.pop(context),
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.symmetric(vertical: isSmallScreen ? 12 : 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          "CANCEL",
                          style: TextStyle(
                            fontSize: isSmallScreen ? 14 : 15,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ),
                    ),
                    
                    const SizedBox(width: 12),
                    
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => Navigator.pop(context, _selectedEmergencyType),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                          padding: EdgeInsets.symmetric(vertical: isSmallScreen ? 12 : 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 2,
                        ),
                        icon: Icon(
                          Icons.send,
                          size: isSmallScreen ? 18 : 20,
                        ),
                        label: Text(
                          "SEND SMS",
                          style: TextStyle(
                            fontSize: isSmallScreen ? 14 : 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  if (selectedService != null && mounted) {
    await sendEmergencySMS(selectedService);
  }
}

  Future<void> sendEmergencySMS([String? serviceName]) async {
    final enhancedPos = await _getEnhancedLocation();
    if (enhancedPos == null) return;

    String actualService = serviceName ?? _selectedEmergencyType;
    String message = _createEmergencyMessage(enhancedPos, actualService);
    
    // FIXED: Proper SMS URL encoding
    String smsUrl = "sms:?body=${Uri.encodeComponent(message)}";

    try {
      if (await canLaunchUrl(Uri.parse(smsUrl))) {
        await launchUrl(Uri.parse(smsUrl));
        _showSuccess("Opening SMS app...");
      } else {
        // Fallback: Share via other apps
        await Share.share(message);
        _showSuccess("Shared via available apps");
      }
    } catch (e) {
      _showError("SMS error: $e");
      // Final fallback
      await Share.share(message);
    }
  }

  void _shareLocationMessage(dynamic position, String type) {
    String message = _createLocationMessage(position, type);
    Share.share(message);
  }

  String _createLocationMessage(dynamic position, String type) {
    final lat = _getLatitude(position);
    final lng = _getLongitude(position);
    
    String googleMaps = "https://www.google.com/maps?q=$lat,$lng";
    String openStreetMap = "https://www.openstreetmap.org/?mlat=$lat&mlon=$lng#map=18/$lat/$lng";

    final isNavicEnhanced = _getIsNavicEnhanced(position);
    String positioningInfo = isNavicEnhanced
        ? "🛰️ **NAVIC POSITIONING**\n"
        : "📍 **GPS POSITIONING**\n";

    String l5Info = _hasL5Band && _l5Confidence > 0.5
        ? "• L5 Band: Available (${(_l5Confidence * 100).toInt()}% confidence)\n"
        : "• L5 Band: Not available\n";

    String chipsetInfo = _chipsetVendor != "Unknown" 
        ? "• Chipset: $_chipsetVendor $_chipsetModel\n"
        : "";

    String satelliteInfo = _totalSatelliteCount > 0
        ? "• Satellites: $_totalSatelliteCount total, $_navicSatelliteCount NavIC\n"
        : "";

    return """🚨 $type 🚨

$positioningInfo
📡 Source: $_locationSource
🎯 Accuracy: ${_getAccuracy(position).toStringAsFixed(1)} meters
🕒 Timestamp: ${DateTime.now().toString().split('.').first}
$l5Info$chipsetInfo$satelliteInfo
📍 Coordinates:
   • Latitude: ${lat.toStringAsFixed(6)}
   • Longitude: ${lng.toStringAsFixed(6)}

🔗 **Google Maps:**
$googleMaps

🗺️ **OpenStreetMap:**
$openStreetMap

${type == "LIVE LOCATION TRACKING" ? "🔄 Live tracking active - location updates every 30 seconds\n" : ""}
⚠️ This is an emergency location share""";
  }

  String _createLiveShareMessage(dynamic position) {
    return _createLocationMessage(position, "LIVE LOCATION TRACKING");
  }

  String _createEmergencyMessage(dynamic position, String serviceType) {
    final lat = _getLatitude(position);
    final lng = _getLongitude(position);
    
    String googleMaps = "https://www.google.com/maps?q=$lat,$lng";
    String openStreetMap = "https://www.openstreetmap.org/?mlat=$lat&mlon=$lng#map=18/$lat/$lng";

    String l5Info = _hasL5Band && _l5Confidence > 0.5
        ? "• L5 Band: Available\n"
        : "";

    String satelliteInfo = _totalSatelliteCount > 0
        ? "• Satellites: $_totalSatelliteCount total, $_navicSatelliteCount NavIC\n"
        : "";

    String emergencyNumber = _emergencyNumbers[serviceType] ?? "112";

    return """🚨 EMERGENCY: $serviceType 🚨
📞 Emergency Number: $emergencyNumber

🆘  NEED IMMEDIATE ASSISTANCE!

📍 **My Current Location:**
• Latitude: ${lat.toStringAsFixed(6)}
• Longitude: ${lng.toStringAsFixed(6)}
• Accuracy: ${_getAccuracy(position).toStringAsFixed(1)} meters
• Positioning: $_locationSource
$l5Info$satelliteInfo

🗺️ **Quick Links:**
• Google Maps: $googleMaps
• OpenStreetMap: $openStreetMap

📱 **Device Info:**
$_chipsetVendor $_chipsetModel

⏰ Timestamp: ${DateTime.now().toString().split('.').first}

This is an automated emergency message sent via NavIC  App.

Please dispatch help immediately!""";
  }

  Color _getStatusColor() {
    if (_isLoading) return Colors.orange;
    if (_isLiveTracking) return Colors.green;
    if (_currentStatus.contains("Error") || _currentStatus.contains("Failed")) {
      return Colors.red;
    }
    return Colors.blue;
  }

  @override
  Widget build(BuildContext context) {
    final bool isNavic = _locationSource == "NAVIC";
    final bool isNavicActive = _lastPosition != null ? _getIsNavicEnhanced(_lastPosition!) : false;
    final bool isL5 = _hasL5Band;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Emergency Assistance',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        backgroundColor: Colors.red.shade700,
        elevation: 2,
        foregroundColor: Colors.white,
        actions: [
          // Quick emergency call button in app bar
          IconButton(
            icon: const Icon(Icons.emergency, color: Colors.white),
            onPressed: _showEmergencyCallDialog,
            tooltip: 'Emergency Call',
          ),
          IconButton(
            icon: Icon(_isLoading ? Icons.refresh : Icons.refresh_outlined),
            onPressed: _isLoading ? null : () async {
              setState(() => _isLoading = true);
              await _getEnhancedLocation();
              setState(() => _isLoading = false);
            },
            tooltip: 'Refresh Location',
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.red.shade50,
              Colors.red.shade100,
            ],
          ),
        ),
        child: Column(
          children: [
            // Hardware Status Banner
            if (_hasL5Band || isNavic)
              _buildHardwareSupportBanner(),

            const SizedBox(height: 16),

            // Status Indicator
            _buildStatusIndicator(),

            const SizedBox(height: 16),

            // System Status Card (only when position is available)
            if (_lastPosition != null)
              _buildSystemStatusHeader(),

            const SizedBox(height: 24),

            // Emergency Buttons Section
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                physics: const BouncingScrollPhysics(),
                child: Column(
                  children: [
                    // 1️⃣ Call Emergency Number (Now with dialog)
                    _buildEmergencyButton(
                      icon: Icons.emergency,
                      title: "CALL EMERGENCY SERVICES",
                      subtitle: "Police, Ambulance, Fire, and more",
                      color: Colors.red.shade700,
                      iconColor: Colors.white,
                      onPressed: _showEmergencyCallDialog,
                    ),

                    const SizedBox(height: 16),

                    // 2️⃣ Share Current Location
                    _buildEmergencyButton(
                      icon: Icons.share_location,
                      title: "SHARE CURRENT LOCATION",
                      subtitle: "Share your precise location instantly",
                      color: Colors.blue.shade700,
                      iconColor: Colors.white,
                      onPressed: shareLocation,
                    ),

                    const SizedBox(height: 16),

                    // 3️⃣ Live Location Tracking
                    _buildEmergencyButton(
                      icon: _isLiveTracking ? Icons.location_off : Icons.location_searching,
                      title: _isLiveTracking ? "STOP LIVE TRACKING" : "START LIVE TRACKING",
                      subtitle: _isLiveTracking ? "Stop sharing live location" : "Share live location updates",
                      color: _isLiveTracking ? Colors.orange.shade700 : Colors.green.shade700,
                      iconColor: Colors.white,
                      onPressed: startLiveLocationSharing,
                    ),

                    const SizedBox(height: 16),

                    // 4️⃣ Send Location Update (only when live tracking)
                    if (_isLiveTracking)
                      Column(
                        children: [
                          _buildEmergencyButton(
                            icon: Icons.update,
                            title: "SEND LOCATION UPDATE",
                            subtitle: "Send immediate location update",
                            color: Colors.purple.shade700,
                            iconColor: Colors.white,
                            onPressed: sendLocationUpdate,
                          ),
                          const SizedBox(height: 16),
                        ],
                      ),

                    // 5️⃣ Send Emergency SMS (Now with dialog)
                    _buildEmergencyButton(
                      icon: Icons.sms,
                      title: "SEND EMERGENCY SMS",
                      subtitle: "Send location via SMS to contacts",
                      color: Colors.orange.shade700,
                      iconColor: Colors.white,
                      onPressed: _showEmergencySMSDialog,
                    ),

                    // 6️⃣ Quick Emergency Info
                    Container(
                      margin: const EdgeInsets.only(top: 24, bottom: 32),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.8),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.red.shade200),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.info, color: Colors.red, size: 18),
                              SizedBox(width: 8),
                              Text(
                                "Emergency Numbers (India):",
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.red,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: _emergencyNumbers.entries.map((entry) {
                              return Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Colors.red.shade50,
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: Colors.red.shade200),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    _getEmergencyIcon(entry.key),
                                    const SizedBox(width: 6),
                                    Text(
                                      "${entry.key}: ",
                                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                                    ),
                                    Text(
                                      entry.value,
                                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
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
    String bannerMessage;

    final bool isNavic = _locationSource == "NAVIC";
    final bool isNavicActive = _lastPosition != null ? _getIsNavicEnhanced(_lastPosition!) : false;

    if (isNavicActive && _hasL5Band) {
      bannerColor = Colors.green.shade50;
      bannerIconColor = Colors.green;
      bannerIcon = Icons.satellite_alt;
      bannerStatus = "NavIC + L5";
      bannerMessage = "Using NavIC with L5 for precise positioning";
    } else if (isNavicActive) {
      bannerColor = Colors.green.shade50;
      bannerIconColor = Colors.green;
      bannerIcon = Icons.satellite_alt;
      bannerStatus = "NavIC Active";
      bannerMessage = "Using NavIC for positioning";
    } else if (_hasL5Band) {
      bannerColor = Colors.blue.shade50;
      bannerIconColor = Colors.blue;
      bannerIcon = Icons.speed;
      bannerStatus = "L5 GPS";
      bannerMessage = "Using GPS with L5 band";
    } else {
      bannerColor = Colors.orange.shade50;
      bannerIconColor = Colors.orange;
      bannerIcon = Icons.gps_fixed;
      bannerStatus = "GPS Only";
      bannerMessage = "Using standard GPS positioning";
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
                  bannerMessage,
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
          if (_confidenceLevel > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: bannerIconColor.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                "${(_confidenceLevel * 100).toStringAsFixed(0)}%",
                style: TextStyle(
                  color: bannerIconColor,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStatusIndicator() {
    final Color statusColor = _getStatusColor();
    
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: statusColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: statusColor.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (_isLoading)
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(statusColor),
              ),
            )
          else if (_isLiveTracking)
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: statusColor,
                shape: BoxShape.circle,
              ),
            )
          else
            Icon(
              Icons.info,
              color: statusColor,
              size: 20,
            ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _currentStatus,
              style: TextStyle(
                color: statusColor,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSystemStatusHeader() {
    if (_lastPosition == null) return Container();

    final bool isNavic = _locationSource == "NAVIC";
    final bool isL5 = _hasL5Band;
    final double confidenceScore = _getConfidenceScore(_lastPosition!);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isNavic
            ? (isL5 ? Colors.green.withOpacity(0.15) : Colors.green.withOpacity(0.1))
            : (isL5 ? Colors.blue.withOpacity(0.15) : Colors.blue.withOpacity(0.1)),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isNavic
              ? (isL5 ? Colors.green : Colors.green.withOpacity(0.3))
              : (isL5 ? Colors.blue : Colors.blue.withOpacity(0.3)),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isNavic ? Colors.green : Colors.blue,
              shape: BoxShape.circle,
            ),
            child: Icon(
              isNavic ? Icons.satellite_alt : Icons.gps_fixed,
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
                      isNavic ? "NAVIC POSITIONING" : "GPS POSITIONING",
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: isNavic ? Colors.green.shade800 : Colors.blue.shade800,
                      ),
                    ),
                    if (isL5) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.green.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          "L5",
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.green.shade800,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  "${_getAccuracy(_lastPosition!).toStringAsFixed(1)} meters accuracy",
                  style: TextStyle(
                    fontSize: 12,
                    color: isNavic ? Colors.green.shade600 : Colors.blue.shade600,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (_chipsetVendor != "Unknown") ...[
                  const SizedBox(height: 2),
                  Text(
                    "$_chipsetVendor $_chipsetModel",
                    style: TextStyle(
                      fontSize: 10,
                      color: isNavic ? Colors.green.shade500 : Colors.blue.shade500,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: (confidenceScore > 0.8 ? Colors.green : Colors.orange).withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              "${(confidenceScore * 100).toStringAsFixed(0)}%",
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: confidenceScore > 0.8 ? Colors.green : Colors.orange,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmergencyButton({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required Color iconColor,
    required VoidCallback onPressed,
  }) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.2),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.all(20),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: 0,
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 24, color: iconColor),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withOpacity(0.9),
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 24, color: Colors.white.withOpacity(0.8)),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _stopLiveTracking();
    _locationUpdateTimer?.cancel();
    super.dispose();
  }


  
}