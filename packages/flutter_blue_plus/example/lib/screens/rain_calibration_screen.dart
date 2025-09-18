import 'package:flutter/material.dart';
import 'dart:async';
import '../utils/ble_manager.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class RainCalibrationScreen extends StatefulWidget {
  final BluetoothDevice? connectedDevice;

  const RainCalibrationScreen({
    super.key,
    this.connectedDevice,
  });

  @override
  State<RainCalibrationScreen> createState() => _RainCalibrationScreenState();
}

class _RainCalibrationScreenState extends State<RainCalibrationScreen> {
  int vTicks = 0;
  double argCalRainCount = 0.0;
  int argCalMIN = 0;
  bool isRunning = false;
  bool isStartCalib = false;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _readRainCalibration() async {
    try {
      if (await _isDeviceConnected()) {
        final decodedData = await BleManager().readCharacteristic(
          widget.connectedDevice!,
          serviceUuid: '180f',
          characteristicUuid: '5677',
        );
        if (decodedData != null) {
          final parts = decodedData.split(',').map((e) => e.trim()).toList();
          setState(() {
            vTicks = parts.isNotEmpty ? int.tryParse(parts[0]) ?? 0 : 0;
            argCalRainCount = parts.length > 1 ? double.tryParse(parts[1]) ?? 0.0 : 0.0;
            argCalMIN = parts.length > 2 ? int.tryParse(parts[2]) ?? 0 : 0;
          });
        }
      } else {
        _stopPolling();
        setState(() {
          isRunning = false;
          isStartCalib = false;
        });
      }
    } catch (e) {
      _stopPolling();
      setState(() {
        isRunning = false;
        isStartCalib = false;
      });
      // Optionally show error
    }
  }

  void _startPolling() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _readRainCalibration());
  }

  void _stopPolling() {
    _timer?.cancel();
  }

  Future<void> _handleButtonPress() async {
    try {
      if (!isRunning) {
        // Start calibration
        if (await _isDeviceConnected()) {
          await BleManager().writeDataToDevice(
            widget.connectedDevice!,
            '0x5676:c03',
            serviceUuid: '180f',
            characteristicUuid: '2a19',
          );
        }
        setState(() {
          isStartCalib = true;
          isRunning = true;
        });
        _startPolling();
      } else {
        // Cancel calibration
        if (await _isDeviceConnected()) {
          await BleManager().writeDataToDevice(
            widget.connectedDevice!,
            '0x5676:c04',
            serviceUuid: '180f',
            characteristicUuid: '2a19',
          );
        }
        setState(() {
          isStartCalib = false;
          isRunning = false;
        });
        _stopPolling();
      }
    } catch (e) {
      // Optionally show error
      // print('Failed to send command: $e');
    }
  }

  Future<bool> _isDeviceConnected() async {
    return widget.connectedDevice != null &&
           await widget.connectedDevice!.isConnected;
  }

  Widget _buildStatCard({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
  }) {
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
  void didUpdateWidget(RainCalibrationScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.connectedDevice != widget.connectedDevice) {
      _stopPolling();
      setState(() {
        isRunning = false;
        isStartCalib = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final width = media.size.width;
    final isTablet = width > 600;

    return Scaffold(
      backgroundColor: const Color(0xFFF7F7FA),
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
                    Icon(Icons.water_drop, color: Color(0xFF007AFF), size: 32),
                    SizedBox(width: 10),
                    Text(
                      'Rain Calibration',
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
                _buildStatCard(
                  label: 'Rain Ticks',
                  value: '$vTicks',
                  icon: Icons.bubble_chart,
                  color: Colors.blue,
                ),
                _buildStatCard(
                  label: 'Rain (MM)',
                  value: argCalRainCount.toStringAsFixed(2),
                  icon: Icons.grain,
                  color: Colors.teal,
                ),
                _buildStatCard(
                  label: 'Elapsed Time',
                  value: '$argCalMIN Min',
                  icon: Icons.timer,
                  color: Colors.deepPurple,
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 24.0, bottom: 8.0),
                  child: SizedBox(
                    width: isTablet ? 220 : double.infinity,
                    child: ElevatedButton.icon(
                      icon: Icon(
                        isRunning ? Icons.stop_circle : Icons.play_circle_fill,
                        color: Colors.white,
                        size: 28,
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isRunning
                            ? const Color(0xFFFF3B30)
                            : (widget.connectedDevice != null
                                ? const Color(0xFF007AFF)
                                : const Color(0xFFCCCCCC)),
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: 5,
                        textStyle: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      onPressed: widget.connectedDevice == null ? null : _handleButtonPress,
                      label: Text(
                        isRunning ? 'Cancel Calibration' : 'Start Calibration',
                        style: TextStyle(
                          color: widget.connectedDevice != null ? Colors.white : const Color(0xFF999999),
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
                SizedBox(height: isTablet ? 40 : 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}