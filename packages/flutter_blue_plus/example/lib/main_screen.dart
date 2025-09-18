import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'home_screen.dart';

class MainScreen extends StatefulWidget {
  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  BluetoothDevice? _connectedDevice;
  List<BluetoothDevice> _discoveredDevices = [];
  String? _connectingDeviceId;
  // ...other state variables...

  Future<void> connectToDevice(BluetoothDevice device) async {
    setState(() {
      _connectingDeviceId = device.id.toString();
    });
    await device.connect();
    setState(() {
      _connectedDevice = device;
      _connectingDeviceId = null;
    });
  }

  Future<void> disconnectDevice() async {
    if (_connectedDevice != null) {
      await _connectedDevice!.disconnect();
      setState(() {
        _connectedDevice = null;
      });
    }
  }

  // ...other BLE logic, scan, etc...

  @override
  Widget build(BuildContext context) {
    return HomeScreen(
      // Pass all required props
      onTabChange: (int idx) {},
      isDarkMode: false,
      systemId: "System",
      temperature: "25.0",
      humidity: "60.0",
      rainStatus: "0.0",
      lastSynced: "Just now",
      isScanning: false,
      isActuallyScanning: false,
      discoveredDevices: _discoveredDevices,
      connectingDeviceId: _connectingDeviceId,
      scanCompleted: true,
      startScan: () {},
      stopScanOnly: () {},
      connectToDevice: connectToDevice,
      disconnectDevice: disconnectDevice,
      cancelScan: () {},
      toggleTheme: (bool v) {},
      connectedDevice: _connectedDevice, // <-- pass to HomeScreen
    );
  }
}