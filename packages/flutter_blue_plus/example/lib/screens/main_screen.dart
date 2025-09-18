import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'home_screen.dart';
import 'terminal_screen.dart';
import 'rain_calibration_screen.dart';
import 'system_info_screen.dart';
import 'usb_copy_screen.dart';
import '../utils/ble_manager.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;
  int _selectedTab = 0;

  // BLE and theme state
  final FlutterBluePlus flutterBlue = FlutterBluePlus();
  bool isDarkMode = false;
  String systemId = "UTNT";
  String? temperature;
  String? humidity;
  String? rainStatus;
  String lastSynced = "";
  Timer? _timer;

  bool isScanning = false;
  bool isActuallyScanning = false;
  List<BluetoothDevice> discoveredDevices = [];
  BluetoothDevice? connectedDevice;
  String? connectingDeviceId;

  StreamSubscription<List<ScanResult>>? _scanSubscription;
  StreamSubscription<bool>? _isScanningSubscription;
  bool scanCompleted = false;

  bool _wasScanning = false;

  // ADD: GlobalKey for SystemInfoScreenState
  final GlobalKey<SystemInfoScreenState> _systemInfoKey = GlobalKey<SystemInfoScreenState>();

  final GlobalKey<TerminalScreenState> _terminalScreenKey = GlobalKey<TerminalScreenState>();

  bool _isReading = false; // Add this to your _MainScreenState

  @override
  void dispose() {
    _timer?.cancel();
    _scanSubscription?.cancel();
    _isScanningSubscription?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant MainScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    _checkScanSwitch();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _checkScanSwitch();
  }

  void _checkScanSwitch() {
    if (!_wasScanning && isScanning) {
      _onTabChange(0); // Switch to Home tab
    }
    _wasScanning = isScanning;
  }

   Future<Map<String, String?>?> readBleData(
  BluetoothDevice device, {
  String characteristicUuid = '5679',
  String characteristicName = 'ble Info',
  String serviceUuid = '180f',
}) async {
  debugPrint('Reading $characteristicName characteristic...');
  try {
    final decoded = await BleManager().readCharacteristic(
      device,
      serviceUuid: serviceUuid,
      characteristicUuid: characteristicUuid,
    );
    if (decoded != null) {
      final cleanString = decoded.replaceAll('\x00', '').trim();
      final parts = cleanString.split(',').map((e) => e.trim()).toList();
      final temperature = parts.isNotEmpty ? parts[0] : null;
      final humidity = parts.length > 1 ? parts[1] : null;
      final rain = parts.length > 2 ? parts[2] : null;
      debugPrint('$characteristicName Characteristic: $cleanString');
      debugPrint('Temperature: $temperature, Humidity: $humidity, Rain: $rain');
      return {
        'temperature': temperature,
        'humidity': humidity,
        'rain': rain,
      };
    } else {
      debugPrint('$characteristicName characteristic not found or not readable.');
      return null;
    }
  } catch (error) {
    debugPrint('Error reading $characteristicName characteristic: $error');
    return null;
  }
}

  // SCAN LOGIC
  void startScan() async {
    await _scanSubscription?.cancel();
    await _isScanningSubscription?.cancel();

    setState(() {
      isScanning = true;
      isActuallyScanning = true;
      discoveredDevices.clear();
      connectingDeviceId = null;
      connectedDevice = null;
      scanCompleted = false;
      temperature = null;
      humidity = null;
      rainStatus = null;
      lastSynced = "";
      // Always switch to Home tab when scan starts
      _selectedTab = 0;
      _selectedIndex = 0;
    });

    FlutterBluePlus.startScan(timeout: const Duration(seconds: 15));

    _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
      final uniqueDevices = <String, BluetoothDevice>{};
      for (final r in results) {
        uniqueDevices[r.device.id.toString()] = r.device;
      }
      setState(() {
        discoveredDevices = uniqueDevices.values.toList();
      });
    });

    _isScanningSubscription = FlutterBluePlus.isScanning.listen((scanning) {
      setState(() {
        isActuallyScanning = scanning;
        if (!scanning && isScanning && !scanCompleted) {
          scanCompleted = true;
        }
      });
    });
  }

  void cancelScan() async {
    await FlutterBluePlus.stopScan();
    await _scanSubscription?.cancel();
    await _isScanningSubscription?.cancel();
    setState(() {
      isScanning = false;
      discoveredDevices.clear();
      connectingDeviceId = null;
      scanCompleted = false;
    });
  }

  void stopScanOnly() async {
    await FlutterBluePlus.stopScan();
    await _scanSubscription?.cancel();
    await _isScanningSubscription?.cancel();
    setState(() {
      connectingDeviceId = null;
    });
  }

  Future<void> connectToDevice(BluetoothDevice device) async {
    await FlutterBluePlus.stopScan();
    await _scanSubscription?.cancel();
    await _isScanningSubscription?.cancel();
    setState(() {
      connectingDeviceId = device.id.toString();
    });

    try {
      final isConnected = await device.isConnected;
      if (!isConnected) {
        await device.connect(timeout: const Duration(seconds: 15));
      }

      // Listen for disconnects
      device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected) {
          _handleDeviceDisconnected();
        }
      });

      // 👉 Cache characteristics after connection, before any BLE ops
      await BleManager().cacheCharacteristics(device);
    
      setState(() {
        connectedDevice = device;
        isScanning = false;
        discoveredDevices.clear();
        scanCompleted = false;
      });
      _timer?.cancel();
      // Only start timer if connected
      if (await device.isConnected) {
        _timer = Timer.periodic(const Duration(seconds: 1), (_) async {
          if (_isReading) return;
          if (!await device.isConnected) return;
          _isReading = true;
          try {
            final result = await readBleData(device);
            if (result != null) {
              setState(() {
                temperature = result['temperature'];
                humidity = result['humidity'];
                rainStatus = result['rain'];
                lastSynced = DateTime.now().toLocal().toString();
              });
            }
          } finally {
            _isReading = false;
          }
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to connect: $e')),
      );
    } finally {
      setState(() {
        connectingDeviceId = null;
      });
    }
  }

  Future<void> disconnectDevice() async {
    if (connectedDevice != null) {
      await connectedDevice!.disconnect();
      _timer?.cancel();
      setState(() {
        connectedDevice = null;
        //temperature = null;
        //humidity = null;
        //rainStatus = null;
        //lastSynced = "";
      });
    }
  }

  void toggleTheme(bool value) {
    setState(() {
      isDarkMode = value;
    });
  }

  void _handleDeviceDisconnected() {
    _timer?.cancel();
    setState(() {
      connectedDevice = null;
      //temperature = null;
      //humidity = null;
      //rainStatus = null;
      //lastSynced = "";
    });
  }

  // Tab change handler for child screens
  void _onTabChange(int index) {
    setState(() {
      _selectedTab = index;
      _selectedIndex = index;
    });

    // Start periodic read only on Home tab (index 0)
    if (index == 0 && connectedDevice != null) {
      // Start timer if not already running
      if (_timer == null || !_timer!.isActive) {
        _timer = Timer.periodic(const Duration(seconds: 1), (_) async {
          if (_isReading) return;
          if (!await connectedDevice!.isConnected) return;
          _isReading = true;
          try {
            final result = await readBleData(connectedDevice!);
            if (result != null) {
              setState(() {
                temperature = result['temperature'];
                humidity = result['humidity'];
                rainStatus = result['rain'];
                lastSynced = DateTime.now().toLocal().toString();
              });
            }
          } finally {
            _isReading = false;
          }
        });
      }
    } else {
      // Cancel timer when leaving Home tab
      _timer?.cancel();
      _timer = null;
    }

    // Trigger System Info fetch when Sys Info tab is selected (index 3)
    if (index == 3) {
      _systemInfoKey.currentState?.fetchSystemInfo();
    }

    // Subscribe to terminal updates if Terminal tab is selected
    if (index == 1) {
      //_terminalScreenKey.currentState?.subscribeIfFocused();
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> _screens = <Widget>[
      HomeScreen(
        onTabChange: _onTabChange,
        isDarkMode: isDarkMode,
        systemId: systemId,
        temperature: temperature,
        humidity: humidity,
        rainStatus: rainStatus,
        lastSynced: lastSynced,
        isScanning: isScanning,
        isActuallyScanning: isActuallyScanning,
        discoveredDevices: discoveredDevices,
        connectedDevice: connectedDevice,
        connectingDeviceId: connectingDeviceId,
        scanCompleted: scanCompleted,
        startScan: startScan,
        stopScanOnly: stopScanOnly,
        connectToDevice: connectToDevice,
        disconnectDevice: disconnectDevice,
        cancelScan: cancelScan,
        toggleTheme: toggleTheme,
      ),
      TerminalScreen(
        key: _terminalScreenKey,
        connectedDevice: connectedDevice,
      ),
      RainCalibrationScreen(connectedDevice: connectedDevice),
      SystemInfoScreen(
        key: _systemInfoKey, // <-- ADD the key here
        connectedDevice: connectedDevice,
      ),
      UsbCopyScreen(connectedDevice: connectedDevice),
    ];

    return Scaffold(
      backgroundColor: const Color(0xFFF0F1F5),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.home, color: Colors.blue, size: 28),
          tooltip: 'Home',
          onPressed: () {
            setState(() {
              _selectedTab = 0;
              _selectedIndex = 0;
            });
          },
        ),
        title: null, // Remove the UTNT/systemId text
        actions: [
          if (connectedDevice == null)
            TextButton.icon(
              icon: const Icon(
                Icons.qr_code_scanner,
                color: Colors.blue,
                size: 22, // Scan BT icon size
              ),
              label: Text(
                isActuallyScanning ? "Scanning..." : "Scan BT",
                style: const TextStyle(
                  color: Colors.blue,
                  fontSize: 16, // Scan BT font size
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
              onPressed: isScanning && isActuallyScanning ? null : startScan,
            )
          else
            TextButton.icon(
              icon: const Icon(
                Icons.link_off,
                color: Colors.red,
                size: 22, // Match Scan BT icon size
              ),
              label: const Text(
                "Disconnect",
                style: TextStyle(
                  color: Colors.red,
                  fontSize: 16, // Match Scan BT font size
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
              onPressed: disconnectDevice,
            ),
        ],
      ),
      body: SafeArea(
        child: IndexedStack(
          index: _selectedTab,
          children: _screens,
        ),
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black12,
              blurRadius: 8,
              offset: Offset(0, -2),
            ),
          ],
        ),
        child: BottomNavigationBar(
          type: BottomNavigationBarType.fixed,
          backgroundColor: Colors.white,
          currentIndex: _selectedIndex,
          onTap: _onTabChange, // <-- USE YOUR HANDLER
          selectedItemColor: const Color(0xFF4a90e2),
          unselectedItemColor: const Color(0xFF350F9C),
          selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          unselectedLabelStyle: const TextStyle(fontSize: 12),
          iconSize: 28,
          items: const [
            BottomNavigationBarItem(
              icon: Text('☁️', style: TextStyle(fontSize: 24)),
              label: 'WMS',
            ),
            BottomNavigationBarItem(
              icon: Text('💻', style: TextStyle(fontSize: 24)),
              label: 'Terminal',
            ),
            BottomNavigationBarItem(
              icon: Text('⚙️', style: TextStyle(fontSize: 24)),
              label: 'Calibration',
            ),
            BottomNavigationBarItem(
              icon: Text('ℹ️', style: TextStyle(fontSize: 24)),
              label: 'Sys Info',
            ),
            BottomNavigationBarItem(
              icon: Text('🔌', style: TextStyle(fontSize: 24)),
              label: 'USB Copy',
            ),
          ],
        ),
      ),
    );
  }
}