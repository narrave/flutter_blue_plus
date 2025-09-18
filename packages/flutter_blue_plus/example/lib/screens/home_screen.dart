import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class HomeScreen extends StatefulWidget {
  final void Function(int) onTabChange;
  final bool isDarkMode;
  final String systemId;
  final String? temperature;
  final String? humidity;
  final String? rainStatus;
  final String lastSynced;
  final bool isScanning;
  final bool isActuallyScanning;
  final List<BluetoothDevice> discoveredDevices;
  final String? connectingDeviceId;
  final bool scanCompleted;
  final VoidCallback startScan;
  final VoidCallback stopScanOnly;
  final Future<void> Function(BluetoothDevice) connectToDevice;
  final Future<void> Function() disconnectDevice;
  final VoidCallback cancelScan;
  final void Function(bool) toggleTheme;
  final BluetoothDevice? connectedDevice; // <-- Add this to constructor and props

  const HomeScreen({
    super.key,
    required this.onTabChange,
    required this.isDarkMode,
    required this.systemId,
    required this.temperature,
    required this.humidity,
    required this.rainStatus,
    required this.lastSynced,
    required this.isScanning,
    required this.isActuallyScanning,
    required this.discoveredDevices,
    required this.connectingDeviceId,
    required this.scanCompleted,
    required this.startScan,
    required this.stopScanOnly,
    required this.connectToDevice,
    required this.disconnectDevice,
    required this.cancelScan,
    required this.toggleTheme,
    required this.connectedDevice, // <-- Add this line
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Key _homeScreenKey = UniqueKey();
  int _selectedTab = 0;

  void _onTabChange(int index) {
    setState(() {
      _selectedTab = index;
      if (index == 0) {
        _homeScreenKey = UniqueKey(); // This will force HomeScreen to rebuild
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final List<Color> gradientColors = widget.isDarkMode
        ? [const Color(0xFF16163A), const Color(0xFF16163A)]
        : [const Color(0xFFF7F7F7), const Color(0xFF0B8BF5)];

    final Color cardColor = Colors.white;
    final Color textColor = widget.isDarkMode ? Colors.white : Colors.black87;

    bool isNoData(String? value) {
      if (value == null) return true;
      // Matches 0, 0.0, 00.00, 000.0, 000.000, etc. or -99
      final zeroPattern = RegExp(r'^0+(\.0+)?$');
      return zeroPattern.hasMatch(value) || value == '-99';
    }

    final List<Map<String, dynamic>> data = [
      {
        'id': '1',
        'title': 'Temperature',
        'value': (!isNoData(widget.temperature)) ? '${widget.temperature} °C' : 'No Data',
        'icon': '🌡️'
      },
      {
        'id': '2',
        'title': 'Humidity',
        'value': (!isNoData(widget.humidity)) ? '${widget.humidity} %' : 'No Data',
        'icon': '💧'
      },
      {
        'id': '3',
        'title': 'Rain',
        'value': widget.rainStatus != null ? '${widget.rainStatus} mm' : 'No Data',
        'icon': '🌧️'
      },
      {
        'id': '4',
        'title': 'System Info',
        'icon': '🖥️',
        'tabIndex': 3,
      },
      {
        'id': '5',
        'title': 'Rain Calibration',
        'icon': '⚙️',
        'tabIndex': 2,
      },
      {
        'id': '6',
        'title': 'USB Copy',
        'icon': '🔌',
        'tabIndex': 4,
      },
    ];

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: gradientColors,
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 18.0, horizontal: 12),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(widget.isDarkMode ? 'Dark Mode' : 'Light Mode',
                          style: TextStyle(fontSize: 16, color: textColor)),
                      Switch(
                        value: widget.isDarkMode,
                        onChanged: widget.toggleTheme,
                        activeColor: Colors.amber,
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Good Day, ${widget.systemId}',
                    style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w500,
                        color: textColor),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Last synced: ${widget.lastSynced.isNotEmpty ? widget.lastSynced : "No Data"}',
                    style: TextStyle(
                        fontSize: 16,
                        color: widget.isDarkMode ? Colors.grey[400] : Colors.grey[700],
                        fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            // Main content
            Expanded(
              child: widget.isScanning
                  ? Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(18),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black12,
                              blurRadius: 8,
                              offset: Offset(0, 2),
                            ),
                          ],
                        ),
                        padding: const EdgeInsets.all(18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Text(
                                  "Discovered Devices:",
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                ),
                                const Spacer(),
                                TextButton.icon(
                                  icon: const Icon(Icons.stop, color: Colors.red),
                                  label: const Text(
                                    "Stop Scan",
                                    style: TextStyle(
                                      color: Colors.red,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                    ),
                                  ),
                                  onPressed: widget.stopScanOnly,
                                  style: TextButton.styleFrom(
                                    foregroundColor: Colors.red,
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                                    minimumSize: Size.zero,
                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Expanded(
                              child: widget.discoveredDevices.isEmpty
                                  ? const Center(
                                      child: Text(
                                        "No devices found yet...",
                                        style: TextStyle(color: Colors.grey),
                                      ),
                                    )
                                  : ListView.builder(
                                      itemCount: widget.discoveredDevices.length,
                                      itemBuilder: (context, idx) {
                                        final d = widget.discoveredDevices[idx];
                                        final isConnecting = widget.connectingDeviceId == d.id.toString();
                                        final isConnected = widget.connectedDevice?.id == d.id; // <-- Use widget.connectedDevice

                                        return ListTile(
                                          title: Text(d.name.isNotEmpty ? d.name : d.id.toString()),
                                          subtitle: Text(d.id.toString()),
                                          trailing: isConnecting
                                              ? const SizedBox(
                                                  width: 28,
                                                  height: 28,
                                                  child: CircularProgressIndicator(strokeWidth: 3),
                                                )
                                              : isConnected
                                                  ? ElevatedButton(
                                                      style: ElevatedButton.styleFrom(
                                                        backgroundColor: Colors.red,
                                                        foregroundColor: Colors.white,
                                                      ),
                                                      child: const Text("Disconnect"),
                                                      onPressed: () async {
                                                        await widget.disconnectDevice();
                                                      },
                                                    )
                                                  : ElevatedButton(
                                                      child: const Text("Connect"),
                                                      onPressed: () async {
                                                        await widget.connectToDevice(d);
                                                      },
                                                    ),
                                        );
                                      },
                                    ),
                            ),
                            TextButton.icon(
                              icon: const Icon(Icons.close, color: Colors.grey),
                              label: const Text(
                                "Close",
                                style: TextStyle(
                                  color: Colors.grey,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                              ),
                              onPressed: widget.cancelScan,
                              style: TextButton.styleFrom(
                                foregroundColor: Colors.grey,
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                            ),
                            if (widget.scanCompleted && !widget.isActuallyScanning)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8.0),
                                child: Text(
                                  "Scan complete. You can still connect to a device or press Close.",
                                  style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
                                ),
                              ),
                          ],
                        ),
                      ),
                    )
                  : ListView.builder(
                      key: _homeScreenKey,
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                      itemCount: data.length,
                      itemBuilder: (context, idx) {
                        final item = data[idx];
                        return GestureDetector(
                          onTap: () {
                            if (item.containsKey('tabIndex')) {
                              widget.onTabChange(item['tabIndex']);
                            }
                          },
                          child: Card(
                            color: cardColor,
                            elevation: 10,
                            margin: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(15)),
                            child: Padding(
                              padding: const EdgeInsets.all(20),
                              child: Row(
                                children: [
                                  Text(item['icon'],
                                      style: TextStyle(
                                          fontSize: 30,
                                          color: widget.isDarkMode
                                              ? const Color(0xFF141414)
                                              : const Color(0xFF3B3B3B))),
                                  const SizedBox(width: 18),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(item['title'],
                                            style: TextStyle(
                                                fontSize: 20,
                                                fontWeight: FontWeight.w500,
                                                color: widget.isDarkMode
                                                    ? const Color(0xFF0F0F0F)
                                                    : const Color(0xFF3B3B3B))),
                                        if (item['value'] != null)
                                          Padding(
                                            padding: const EdgeInsets.only(top: 6.0),
                                            child: Text(
                                              item['value'],
                                              style: TextStyle(
                                                  fontSize: 20,
                                                  fontWeight: FontWeight.bold,
                                                  color: widget.isDarkMode
                                                      ? const Color(0xFF1F1D1D)
                                                      : const Color(0xFF555555)),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
