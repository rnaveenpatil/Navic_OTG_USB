import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:usb_connect_gnss/providers/gnss_provider.dart';

class ConnectionScreen extends StatelessWidget {
  const ConnectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<GNSSProvider>(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Status Card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  ListTile(
                    leading: Icon(
                      provider.isConnected ? Icons.check_circle : Icons.error,
                      color: provider.isConnected ? Colors.green : Colors.red,
                    ),
                    title: Text(
                      provider.connectionStatus,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      provider.deviceName.isNotEmpty
                          ? 'Device: ${provider.deviceName}'
                          : 'No device connected',
                    ),
                  ),
                  if (provider.hasError)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        provider.errorMessage,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Connection Controls
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Connection Controls',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),

                  // Baud Rate Selector
                  const Text('Baud Rate:'),
                  DropdownButton<int>(
                    value: provider.baudRate,
                    onChanged: provider.isConnected
                        ? null
                        : (value) {
                            if (value != null) {
                              provider.changeBaudRate(value);
                            }
                          },
                    items: GNSSProvider.baudRates.map((rate) {
                      return DropdownMenuItem<int>(
                        value: rate,
                        child: Text('$rate'),
                      );
                    }).toList(),
                  ),

                  const SizedBox(height: 16),

                  // Connect/Disconnect Button
                  ElevatedButton.icon(
                    onPressed: provider.isConnecting
                        ? null
                        : () {
                            if (provider.isConnected) {
                              provider.disconnect();
                            } else {
                              provider.connectToDevice();
                            }
                          },
                    icon: Icon(
                      provider.isConnected ? Icons.stop : Icons.play_arrow,
                    ),
                    label: Text(
                      provider.isConnecting
                          ? 'Connecting...'
                          : provider.isConnected
                              ? 'Disconnect'
                              : 'Connect',
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          provider.isConnected ? Colors.red : Colors.green,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Statistics
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Statistics',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text('Bytes Received: ${provider.bytesReceived}'),
                  Text('NMEA Sentences: ${provider.nmeaSentences}'),
                  if (provider.connectionDuration != null)
                    Text(
                        'Connection Time: ${provider.connectionDuration!.inMinutes} min'),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Raw Data (Collapsible)
          Card(
            child: ExpansionTile(
              title: const Text('Raw Data Buffer'),
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  color: Colors.black,
                  height: 200,
                  child: ListView.builder(
                    itemCount: provider.rawBuffer.length,
                    itemBuilder: (context, index) {
                      return Text(
                        provider.rawBuffer[index],
                        style: const TextStyle(
                          color: Colors.green,
                          fontFamily: 'Monospace',
                          fontSize: 12,
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
