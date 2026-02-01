import 'dart:math';
import 'package:flutter/material.dart';
import '../providers/gnss_provider.dart';

// Alias SatelliteInfo to Satellite to match provider if needed,
// but better to just update usage.
typedef SatelliteInfo = Satellite;

class SatelliteView extends StatelessWidget {
  final GNSSData data;

  const SatelliteView({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Sky plot
        Expanded(
          child: Center(
            child: CustomPaint(
              size: const Size(300, 300),
              painter: SkyPlotPainter(satellites: data.satellites),
            ),
          ),
        ),

        // Satellite list
        Expanded(
          child: ListView.builder(
            itemCount: data.satellites.length,
            itemBuilder: (context, index) {
              var sat = data.satellites[index];
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: _getSignalColor(sat.snr),
                  child: Text('${sat.prn}'),
                ),
                title: Text('PRN ${sat.prn}'),
                subtitle: Text('El: ${sat.elevation}° Az: ${sat.azimuth}°'),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('${sat.snr} dB'),
                    Icon(
                        sat.inUse
                            ? Icons.check_circle
                            : Icons.radio_button_unchecked,
                        color: sat.inUse ? Colors.green : Colors.grey,
                        size: 16),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Color _getSignalColor(int snr) {
    if (snr > 40) return Colors.green;
    if (snr > 30) return Colors.lightGreen;
    if (snr > 20) return Colors.yellow;
    if (snr > 10) return Colors.orange;
    return Colors.red;
  }
}

class SkyPlotPainter extends CustomPainter {
  final List<SatelliteInfo> satellites;

  SkyPlotPainter({required this.satellites});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 20;

    // Draw concentric circles
    final paint = Paint()
      ..color = Colors.blue.withValues(alpha: 0.1)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    for (int i = 0; i <= 90; i += 30) {
      double circleRadius = radius * (1 - i / 90);
      canvas.drawCircle(center, circleRadius, paint);

      // Draw elevation labels
      TextPainter(
        text: TextSpan(text: '$i°', style: const TextStyle(fontSize: 10)),
        textDirection: TextDirection.ltr,
      )
        ..layout()
        ..paint(canvas, Offset(center.dx + circleRadius + 5, center.dy - 6));
    }

    // Draw azimuth lines
    for (int azimuth = 0; azimuth < 360; azimuth += 45) {
      double radians = azimuth * 3.14159 / 180;
      Offset end = Offset(
        center.dx + radius * sin(radians),
        center.dy - radius * cos(radians),
      );
      canvas.drawLine(center, end, paint);
    }

    // Draw satellites
    for (var sat in satellites) {
      double distance = radius * (1 - sat.elevation / 90);
      double radians = sat.azimuth * 3.14159 / 180;

      Offset position = Offset(
        center.dx + distance * sin(radians),
        center.dy - distance * cos(radians),
      );

      final satPaint = Paint()
        ..color = _getSignalColor(sat.snr)
        ..style = PaintingStyle.fill;

      canvas.drawCircle(position, 8, satPaint);

      // Draw PRN number
      TextPainter(
        text: TextSpan(
          text: '${sat.prn}',
          style: const TextStyle(
              fontSize: 8, color: Colors.white, fontWeight: FontWeight.bold),
        ),
        textDirection: TextDirection.ltr,
      )
        ..layout()
        ..paint(canvas, Offset(position.dx - 4, position.dy - 4));
    }
  }

  Color _getSignalColor(int snr) {
    if (snr > 40) return Colors.green;
    if (snr > 30) return Colors.lightGreen;
    if (snr > 20) return Colors.yellow;
    if (snr > 10) return Colors.orange;
    return Colors.red;
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
