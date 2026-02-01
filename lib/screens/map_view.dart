import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../providers/gnss_provider.dart';

class MapView extends StatelessWidget {
  final GNSSData data;

  const MapView({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    return FlutterMap(
      options: MapOptions(
        initialCenter: data.latitude != null && data.longitude != null
            ? LatLng(data.latitude!, data.longitude!)
            : const LatLng(0, 0),
        initialZoom: data.hasFix ? 15.0 : 3.0,
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
          subdomains: const ['a', 'b', 'c'],
        ),
        if (data.hasFix)
          MarkerLayer(
            markers: [
              Marker(
                width: 40,
                height: 40,
                point: LatLng(data.latitude!, data.longitude!),
                child: const Icon(
                  Icons.location_on,
                  color: Colors.red,
                  size: 40,
                ),
              ),
            ],
          ),
      ],
    );
  }
}
