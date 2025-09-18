import 'dart:async';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class BleManager {
  static final BleManager _instance = BleManager._internal();
  factory BleManager() => _instance;
  BleManager._internal();

  Future<void> _lastOperation = Future.value();

  // Cache: deviceId -> Map<serviceUuid, Map<characteristicUuid, BluetoothCharacteristic>>
  final Map<String, Map<String, Map<String, BluetoothCharacteristic>>> _charCache = {};

  Future<T> runExclusive<T>(Future<T> Function() operation) {
    // Chain the operation and return the correct type
    final completer = Completer<T>();
    _lastOperation = _lastOperation.then((_) => operation()).then((result) {
      completer.complete(result);
    }).catchError((e, s) {
      completer.completeError(e, s);
    });
    return completer.future;
  }

  /// Call this ONCE after connecting, before any read/write
  Future<void> cacheCharacteristics(BluetoothDevice device) async {
    final services = await device.discoverServices();
    final deviceId = device.id.id;
    _charCache[deviceId] = {};
    for (final service in services) {
      final serviceUuid = service.uuid.toString().toLowerCase();
      _charCache[deviceId]![serviceUuid] = {};
      for (final char in service.characteristics) {
        final charUuid = char.uuid.toString().toLowerCase();
        _charCache[deviceId]![serviceUuid]![charUuid] = char;
      }
    }
  }

  BluetoothCharacteristic? getCharacteristic(
    BluetoothDevice device, {
    required String serviceUuid,
    required String characteristicUuid,
  }) {
    final deviceId = device.id.id;
    return _charCache[deviceId]?[serviceUuid.toLowerCase()]?[characteristicUuid.toLowerCase()];
  }

  // Use explicit type for write:
  Future<void> write(
    BluetoothCharacteristic char,
    List<int> data, {
    bool withoutResponse = false,
  }) {
    return runExclusive<void>(() => char.write(data, withoutResponse: withoutResponse));
  }

  // ✅ Use explicit generic type here!
  Future<List<int>> read(BluetoothCharacteristic char) {
    return runExclusive<List<int>>(() => char.read());
  }

  /// Optimized: Use cached characteristic for write
  Future<void> writeDataToDevice(
    BluetoothDevice device,
    String data, {
    required String serviceUuid,
    required String characteristicUuid,
  }) async {
    final char = getCharacteristic(device, serviceUuid: serviceUuid, characteristicUuid: characteristicUuid);
    if (char == null) throw Exception('Characteristic not cached/found.');
    final message = '$data\r\n';
    final bytes = message.codeUnits;
    const chunkSize = 20;
    for (int offset = 0; offset < bytes.length; offset += chunkSize) {
      final chunk = bytes.sublist(offset, (offset + chunkSize > bytes.length) ? bytes.length : offset + chunkSize);
      await write(char, chunk, withoutResponse: false);
      await Future.delayed(const Duration(milliseconds: 30)); // <-- Add a small delay
    }
  }

  /// Optimized: Use cached characteristic for read
  Future<String?> readCharacteristic(
    BluetoothDevice device, {
    required String serviceUuid,
    required String characteristicUuid,
  }) async {
    final char = getCharacteristic(device, serviceUuid: serviceUuid, characteristicUuid: characteristicUuid);
    if (char == null) throw Exception('Characteristic not cached/found.');
    final readData = await read(char);
    return String.fromCharCodes(readData).trim();
  }
}