import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../utils/ble_manager.dart';

class SystemInfoScreen extends StatefulWidget {
  final BluetoothDevice? connectedDevice;

  const SystemInfoScreen({super.key, this.connectedDevice});

  @override
  State<SystemInfoScreen> createState() => SystemInfoScreenState();
}

class SystemInfoScreenState extends State<SystemInfoScreen> {
  Map<String, String> systemData = {
    'devID': 'No Data',
    'fwVer': 'No Data',
    'log': 'No Data',
    'tempOffset': 'No Data',
    'rhOffset': 'No Data',
    'bmpOffset': 'No Data',
    'signalStrength': 'No Data',
    'simSlot': 'No Data',
  };

  Future<void> fetchSystemInfo() async {
    try {
      
      final isConnected = await widget.connectedDevice?.isConnected;
     
      if (isConnected != true) {
        _showError('Device not connected');
        return;
      }
      
      const command = '0x5676:c01';
      await BleManager().writeDataToDevice(
        widget.connectedDevice!,
        command,
        serviceUuid: '180f',
        characteristicUuid: '2a19',
      );
      
      final sysInfo = await BleManager().readCharacteristic(
        widget.connectedDevice!,
        serviceUuid: '180f',
        characteristicUuid: '5676',
      );

      if (sysInfo != null) {
        final lines = sysInfo.split('\n');
        setState(() {
          systemData = {
            'devID': lines.length > 0 ? lines[0].trim() : 'No Data',
            'fwVer': lines.length > 1 ? lines[1].trim() : 'No Data',
            'log': lines.length > 3 ? lines[3].trim() : 'No Data',
            'tempOffset': lines.length > 4 ? lines[4].trim() : 'No Data',
            'rhOffset': lines.length > 5 ? lines[5].trim() : 'No Data',
            'bmpOffset': lines.length > 6 ? lines[6].trim() : 'No Data',
            'signalStrength': lines.length > 7 ? lines[7].trim() : 'No Data',
            'simSlot': lines.length > 8 ? lines[8].trim() : 'No Data',
          };
        });
      } else {
        _showError('Invalid data received from Bluetooth device.');
      }
    } catch (e) {
      _showError('Failed to fetch system info. Please try again.');
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _showInfo(String message) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Info'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Widget renderCard(String label, String value, IconData icon, Color color) {
    return Card(
      elevation: 3,
      margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 0),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 24),
        child: Row(
          children: [
            Container(
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.all(10),
              child: Icon(icon, color: color, size: 32),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 18,
                      color: Color(0xFF2c3e50),
                      fontWeight: FontWeight.w600,
                      fontFamily: 'San Francisco',
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF1F2020),
                      fontFamily: 'San Francisco',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final width = media.size.width;
    final isTablet = width > 600;

    return Scaffold(
      backgroundColor: const Color(0xFFF0F0F5),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(
              horizontal: isTablet ? width * 0.18 : 16,
              vertical: isTablet ? 48 : 24,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const SizedBox(height: 32),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    Icon(Icons.info_outline, color: Color(0xFF007AFF), size: 32),
                    SizedBox(width: 10),
                    Text(
                      'System Info',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF2c3e50),
                        fontFamily: 'San Francisco',
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 32),
                renderCard('Device ID', systemData['devID'] ?? 'No Data', Icons.confirmation_number, Colors.blue),
                renderCard('Firmware Version', systemData['fwVer'] ?? 'No Data', Icons.memory, Colors.teal),
                renderCard('Log', systemData['log'] ?? 'No Data', Icons.receipt_long, Colors.deepPurple),
                renderCard('Temp Offset', systemData['tempOffset'] ?? 'No Data', Icons.thermostat, Colors.orange),
                renderCard('RH Offset', systemData['rhOffset'] ?? 'No Data', Icons.water_drop, Colors.indigo),
                renderCard('BMP Offset', systemData['bmpOffset'] ?? 'No Data', Icons.speed, Colors.green),
                renderCard('Signal Strength', systemData['signalStrength'] ?? 'No Data', Icons.network_cell, Colors.redAccent),
                renderCard('SIM Slot', systemData['simSlot'] ?? 'No Data', Icons.sim_card, Colors.purple),
                SizedBox(height: isTablet ? 40 : 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}