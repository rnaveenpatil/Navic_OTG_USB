import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_gauges/gauges.dart';
import '../providers/gnss_provider.dart';

class StatusView extends StatelessWidget {
  final GNSSData data;

  const StatusView({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // DOP Gauges
        SizedBox(
          height: 150,
          child: Row(
            children: [
              Expanded(
                child: _buildDOPGauge('HDOP', data.hdop ?? 0, 5),
              ),
              Expanded(
                child: _buildDOPGauge('VDOP', data.vdop ?? 0, 5),
              ),
              Expanded(
                child: _buildDOPGauge('PDOP', data.pdop ?? 0, 5),
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),

        // Position Info
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Position Information',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                _buildInfoRow(
                    'Latitude', data.latitude?.toStringAsFixed(6) ?? 'N/A'),
                _buildInfoRow(
                    'Longitude', data.longitude?.toStringAsFixed(6) ?? 'N/A'),
                _buildInfoRow(
                    'Altitude',
                    data.altitude != null
                        ? '${data.altitude!.toStringAsFixed(1)} m'
                        : 'N/A'),
                _buildInfoRow(
                    'Speed',
                    data.speed != null
                        ? '${data.speed!.toStringAsFixed(1)} km/h'
                        : 'N/A'),
                _buildInfoRow(
                    'Course',
                    data.course != null
                        ? '${data.course!.toStringAsFixed(1)}°'
                        : 'N/A'),
              ],
            ),
          ),
        ),

        const SizedBox(height: 20),

        // Satellite Info
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Satellite Information',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                _buildInfoRow('Satellites in View',
                    data.satellitesInView?.toString() ?? 'N/A'),
                _buildInfoRow('Satellites in Use',
                    data.satellitesInUse?.toString() ?? 'N/A'),
                _buildInfoRow('Fix Status', data.hasFix ? '3D Fix' : 'No Fix'),
              ],
            ),
          ),
        ),

        const SizedBox(height: 20),

        // Raw NMEA Data
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Raw NMEA Data',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(8),
                  color: Colors.black,
                  child: Text(
                    data.rawNMEA.isNotEmpty ? data.rawNMEA : 'No data received',
                    style: const TextStyle(
                        color: Colors.green,
                        fontFamily: 'Monospace',
                        fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDOPGauge(String title, double value, double maxValue) {
    return Column(
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
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
        Text(value.toStringAsFixed(2),
            style: TextStyle(
              color: _getDOPColor(value),
              fontWeight: FontWeight.bold,
            )),
      ],
    );
  }

  Color _getDOPColor(double value) {
    if (value <= 1) return Colors.green;
    if (value <= 2) return Colors.yellow;
    return Colors.red;
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
