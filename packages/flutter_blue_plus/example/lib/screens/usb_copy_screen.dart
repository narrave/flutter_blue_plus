import 'dart:async'; // For StreamSubscription and Completer
import 'dart:io'; // <-- Add this line for File and FileMode
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:path_provider/path_provider.dart';
import '../utils/ble_manager.dart';

class UsbCopyScreen extends StatefulWidget {
  final BluetoothDevice? connectedDevice;
  const UsbCopyScreen({super.key, this.connectedDevice});

  @override
  State<UsbCopyScreen> createState() => _UsbCopyScreenState();
}

class _UsbCopyScreenState extends State<UsbCopyScreen> {
  DateTime startDate = DateTime.now();
  DateTime endDate = DateTime.now();
  bool isLoading = false;
  int progress = 0;
  String filePath = '';
  List<Map<String, dynamic>> directoryContent = [];
  bool modalVisible = false;
  String modalMessage = '';
  String modalTitle = '';
  String? systemId;
  String loadingType = ''; // 'copy' or 'list'
  bool showDirectoryContent = true;

  final String serviceUuid = '180f';
  final String charUuid = '5675'; // BLE file transfer characteristic

  StreamSubscription<List<int>>? _activeSubscription;

  @override
  void initState() {
    super.initState();
    fetchSystemId();
  }

  Future<void> fetchSystemId() async {
    if (widget.connectedDevice == null) return;
    try {
      final sysId = await BleManager().readCharacteristic(
        widget.connectedDevice!,
        serviceUuid: serviceUuid,
        characteristicUuid: '5678',
      );
      if (sysId != null) {
        setState(() => systemId = sysId.trim());
      }
    } catch (e) {
      // Optionally handle error
    }
  }

  Future<void> pickStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: startDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => startDate = picked);
  }

  Future<void> pickEndDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: endDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => endDate = picked);
  }

  List<DateTime> getDateRange(DateTime start, DateTime end) {
    final dates = <DateTime>[];
    var current = DateTime(start.year, start.month, start.day);
    while (!current.isAfter(end)) {
      dates.add(current);
      current = current.add(const Duration(days: 1));
    }
    return dates;
  }

  String formatToDDMMYY(DateTime date) {
    final dd = date.day.toString().padLeft(2, '0');
    final mm = date.month.toString().padLeft(2, '0');
    final yy = date.year.toString().substring(2);
    return '$dd$mm$yy';
  }

  Future<String> getDownloadPath(String filename) async {
    if (Platform.isAndroid) {
      // Android: Use Downloads directory
      return '/storage/emulated/0/Download/$filename';
    } else if (Platform.isIOS || Platform.isMacOS) {
      // iOS/macOS: Use app's Documents directory
      final dir = await getApplicationDocumentsDirectory();
      return '${dir.path}/$filename';
    } else {
      // Fallback for other platforms
      final dir = await getTemporaryDirectory();
      return '${dir.path}/$filename';
    }
  }

  // --- BLE file copy logic ---
  Future<String?> readFileContentFromBleDevice(String filename) async {
    if (!await _isDeviceConnected()) return null;
    final cleanFilename = filename.endsWith('.csv') ? filename.substring(0, filename.length - 4) : filename;
    final command = '0x5675:READ $cleanFilename';
    final updatedFilename = '${systemId ?? "SYSID"}_$filename';
    final savePath = await getDownloadPath(updatedFilename);

    // Send BLE command to start file transfer
    await BleManager().writeDataToDevice(
      widget.connectedDevice!,
      command,
      serviceUuid: serviceUuid,
      characteristicUuid: charUuid,
    );

    // Use BleManager to get the cached characteristic
    final characteristic = BleManager().getCharacteristic(
      widget.connectedDevice!,
      serviceUuid: serviceUuid,
      characteristicUuid: charUuid,
    );
    if (characteristic == null) return null;

    await characteristic.setNotifyValue(true);

    final file = File(savePath);
    if (file.existsSync()) file.writeAsStringSync('');
    final completer = Completer<String?>();
    StreamSubscription<List<int>>? sub;
    bool fileError = false;

    _activeSubscription?.cancel();
    _activeSubscription = characteristic.onValueReceived.listen((value) async {
      final decoded = String.fromCharCodes(value).replaceAll('\x00', '').trim();
      print('USB Copy BLE received: $decoded'); // Debug print
      if (decoded.contains('FILE DOES NOT EXISTS') || decoded.contains('FILE READ ERROR')) {
        if (await file.exists()) {
          await file.delete();
        }
        await _activeSubscription?.cancel();
        _activeSubscription = null;
        completer.completeError(decoded);
        return;
      }
      await file.writeAsString(decoded, mode: FileMode.append);
      if (decoded.contains('END OF FILE')) {
        await _activeSubscription?.cancel();
        _activeSubscription = null;
        completer.complete(savePath);
      }
    });

    // Timeout after 60 seconds
    Future.delayed(const Duration(seconds: 60), () async {
      if (!completer.isCompleted) {
        await _activeSubscription?.cancel();
        _activeSubscription = null;
        if (!fileError) completer.completeError('Timeout: No data received from BLE device.');
      }
    });

    return completer.future;
  }

  // --- BLE directory listing logic ---
  Future<List<Map<String, dynamic>>> fetchDirectoryContentFromBleDevice() async {
    if (!await _isDeviceConnected()) return [];
    // Send BLE command to list files
    await BleManager().writeDataToDevice(
      widget.connectedDevice!,
      '0x5676:c02',
      serviceUuid: serviceUuid,
      characteristicUuid: charUuid,
    );

    // Use BleManager to get the cached characteristic
    final characteristic = BleManager().getCharacteristic(
      widget.connectedDevice!,
      serviceUuid: serviceUuid,
      characteristicUuid: charUuid,
    );
    if (characteristic == null) return [];

    await characteristic.setNotifyValue(true);

    final List<Map<String, dynamic>> result = [];
    final completer = Completer<List<Map<String, dynamic>>>();
    List<String> dataBuffer = [];
    StreamSubscription<List<int>>? sub;

    _activeSubscription?.cancel();
    _activeSubscription = characteristic.onValueReceived.listen((value) async {
      print('Raw bytes: $value');
      final decoded = String.fromCharCodes(value).replaceAll('\x00', '').trim();
      print('USB Copy BLE received: "$decoded"');
      if (decoded == 'END_OF_CONTENT,NONE') {
        await _activeSubscription?.cancel();
        _activeSubscription = null;
        print('Completing directory result with ${dataBuffer.length} entries');
        for (final entry in dataBuffer) {
          print('Parsing entry: "$entry"');
          final parts = entry.split(',');
          final name = parts[0].trim();
          final type = parts.length > 1 ? parts[1].trim() : '';
          print('Parsed name: "$name", type: "$type"');
          result.add({
            'id': '${result.length + 1}',
            'name': name,
            'type': type == '8' ? 'file' : 'folder',
            'icon': type == '8' ? Icons.insert_drive_file : Icons.folder,
          });
        }
        print('Calling completer.complete(result)');
        completer.complete(result);
        return;
      }
      if (decoded.isNotEmpty) dataBuffer.add(decoded);
    });

    // Timeout after 60 seconds
    Future.delayed(const Duration(seconds: 60), () async {
      if (!completer.isCompleted) {
        await _activeSubscription?.cancel();
        _activeSubscription = null;
        completer.complete(result);
      }
    });

    return completer.future;
  }

  Future<void> handleDataCopy() async {
    if (widget.connectedDevice == null) {
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Error'),
          content: const Text('BLE device is not connected.'),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
        ),
      );
      return;
    }
    setState(() {
      isLoading = true;
      progress = 0;
      filePath = '';
      loadingType = 'copy';
    });
    try {
      final datesInRange = getDateRange(startDate, endDate);
      final totalFiles = datesInRange.length;
      if (totalFiles == 0) {
        setState(() => isLoading = false);
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Error'),
            content: const Text('No date range selected or invalid date range.'),
            actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
          ),
        );
        return;
      }
      int successCount = 0;
      List<String> failedFiles = [];
      for (int i = 0; i < totalFiles; i++) {
        final dateObj = datesInRange[i];
        final filename = '${formatToDDMMYY(dateObj)}.csv';
        try {
          final path = await readFileContentFromBleDevice(filename);
          if (path != null) {
            setState(() => filePath = path);
            successCount++;
          } else {
            failedFiles.add(filename);
          }
        } catch (fileError) {
          failedFiles.add('$filename - $fileError');
        }
        setState(() => progress = ((i + 1) / totalFiles * 100).round());
      }
      String message = 'Copied $successCount out of $totalFiles files to Download folder.';
      if (failedFiles.isNotEmpty) {
        message += '\n\nFailed Files:\n${failedFiles.join('\n')}';
      }
      setState(() {
        modalTitle = 'Data Copy Complete';
        modalMessage = message;
        modalVisible = true;
      });
    } catch (e) {
      setState(() => isLoading = false);
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Error'),
          content: Text(e.toString()),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
        ),
      );
    } finally {
      setState(() => isLoading = false);
    }
  }

  Future<void> handleListFiles() async {
    if (widget.connectedDevice == null) {
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Error'),
          content: const Text('BLE device is not connected.'),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
        ),
      );
      return;
    }
    setState(() {
      isLoading = true;
      loadingType = 'list';
    });
    final content = await fetchDirectoryContentFromBleDevice();
    if (!mounted) return;
    setState(() {
      directoryContent = content;
      isLoading = false;
      showDirectoryContent = true;
    });
    print('Directory content updated: ${directoryContent.length} items');
  }

  void showCopyCompleteDialog(BuildContext context, String title, String message) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: Colors.white,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_circle, color: Colors.teal, size: 56),
              const SizedBox(height: 16),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.teal,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                message,
                style: const TextStyle(fontSize: 16, color: Colors.black87),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                ),
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK', style: TextStyle(fontSize: 18)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<bool> _isDeviceConnected() async {
    return widget.connectedDevice != null &&
           await widget.connectedDevice!.isConnected;
  }

  @override
  void didUpdateWidget(covariant UsbCopyScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.connectedDevice != widget.connectedDevice) {
      _activeSubscription?.cancel();
      _activeSubscription = null;
      setState(() {
        isLoading = false;
        progress = 0;
        filePath = '';
        directoryContent = [];
        modalVisible = false;
        modalMessage = '';
        modalTitle = '';
        showDirectoryContent = true;
      });
    }
  }

  @override
  void dispose() {
    _activeSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final width = media.size.width;
    final isTablet = width > 600;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FB), // Soft off-white/blue
      body: Stack(
        children: [
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(
                  horizontal: isTablet ? width * 0.18 : 16,
                  vertical: isTablet ? 48 : 24,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 24),
                    Card(
                      elevation: 4,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 24),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Icon(Icons.usb_rounded, color: Colors.teal[700], size: 32),
                                const SizedBox(width: 12),
                                const Text(
                                  'USB Data Copy',
                                  style: TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF2c3e50),
                                    fontFamily: 'Roboto',
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 18),
                            Divider(color: Colors.grey[300]),
                            const SizedBox(height: 18),
                            if (widget.connectedDevice != null) ...[
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Flexible(
                                    child: OutlinedButton.icon(
                                      icon: const Icon(Icons.date_range),
                                      label: Text(
                                        'Start: ${startDate.toLocal().toString().split(' ')[0]}',
                                        style: const TextStyle(fontSize: 16),
                                      ),
                                      onPressed: pickStartDate,
                                      style: OutlinedButton.styleFrom(
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                        side: const BorderSide(color: Colors.teal, width: 1.5),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Flexible(
                                    child: OutlinedButton.icon(
                                      icon: const Icon(Icons.date_range),
                                      label: Text(
                                        'End: ${endDate.toLocal().toString().split(' ')[0]}',
                                        style: const TextStyle(fontSize: 16),
                                      ),
                                      onPressed: pickEndDate,
                                      style: OutlinedButton.styleFrom(
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                        side: const BorderSide(color: Colors.teal, width: 1.5),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 18),
                              LinearProgressIndicator(
                                value: progress / 100,
                                backgroundColor: Colors.grey[200],
                                color: const Color(0xFF1976D2),
                                minHeight: 10,
                              ),
                              if (isLoading)
                                Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Text(
                                    '$progress% completed',
                                    style: const TextStyle(fontSize: 15, color: Colors.teal, fontWeight: FontWeight.w600),
                                  ),
                                ),
                              const SizedBox(height: 18),
                              Row(
                                children: [
                                  Expanded(
                                    child: ElevatedButton.icon(
                                      icon: const Icon(Icons.copy_rounded, color: Colors.white),
                                      label: Text(isLoading ? 'Copying...' : 'Copy Data'),
                                      onPressed: isLoading ? null : handleDataCopy,
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(0xFF00BFAE), // Vibrant teal
                                        foregroundColor: Colors.white,
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                        padding: const EdgeInsets.symmetric(vertical: 18),
                                        textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 1.1),
                                        elevation: 4,
                                        shadowColor: const Color(0xFF00BFAE).withOpacity(0.3),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: ElevatedButton.icon(
                                      icon: const Icon(Icons.folder_open, color: Colors.white),
                                      label: const Text('List Files'),
                                      onPressed: isLoading ? null : handleListFiles,
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(0xFF1976D2), // Deep blue
                                        foregroundColor: Colors.white,
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                        padding: const EdgeInsets.symmetric(vertical: 18),
                                        textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 1.1),
                                        elevation: 4,
                                        shadowColor: const Color(0xFF1976D2).withOpacity(0.3),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              if (filePath.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 16),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.save_alt, color: Colors.teal, size: 20),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          'Last file saved to:\n$filePath',
                                          style: const TextStyle(fontSize: 14, color: Colors.black87),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ] else ...[
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 32),
                                child: Column(
                                  children: [
                                    Icon(Icons.usb_off, color: Colors.red[400], size: 48),
                                    const SizedBox(height: 16),
                                    const Text(
                                      'Please connect to a BLE device\nto begin copying data.',
                                      style: TextStyle(
                                        color: Color(0xFFFF9900),
                                        fontSize: 18,
                                        fontWeight: FontWeight.w600,
                                        height: 1.4,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                      const SizedBox(height: 32),
                      if (widget.connectedDevice != null && directoryContent.isNotEmpty && showDirectoryContent)
                        Card(
                          elevation: 2,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                          color: Colors.white,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Expanded(
                                      child: Text(
                                        'Directory Content',
                                        style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFF1976D2),
                                        ),
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.close, color: Color(0xFFD32F2F)), // Red color for X
                                      tooltip: 'Close',
                                      splashRadius: 22,
                                      onPressed: () => setState(() => showDirectoryContent = false),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                GridView.builder(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: isTablet ? 5 : 3,
                                    childAspectRatio: 1,
                                    crossAxisSpacing: 12,
                                    mainAxisSpacing: 12,
                                  ),
                                  itemCount: directoryContent.length,
                                  itemBuilder: (context, idx) {
                                    final item = directoryContent[idx];
                                    return Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(item['icon'], size: 40, color: item['type'] == 'file' ? Color(0xFF1976D2) : Color(0xFF43A047)),
                                        const SizedBox(height: 6),
                                        Text(item['name'], style: const TextStyle(fontSize: 12), textAlign: TextAlign.center),
                                      ],
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                        ),
                      if (modalVisible)
                        AlertDialog(
                          title: Text(modalTitle),
                          content: SingleChildScrollView(child: Text(modalMessage)),
                          actions: [
                            TextButton(
                              onPressed: () => setState(() => modalVisible = false),
                              child: const Text('Close'),
                            ),
                          ],
                        ),
                  ],
                ),
              ),
            ),
          ),
          // Modal barrier and loading dialog
          if (isLoading)
            ModalBarrier(
              dismissible: false,
              color: Colors.black.withOpacity(0.2),
            ),
          if (isLoading)
            Center(
              child: Card(
                elevation: 8,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 24),
                      LinearProgressIndicator(
                        value: progress / 100,
                        backgroundColor: Colors.grey[200],
                        color: const Color(0xFF1976D2),
                        minHeight: 10,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        loadingType == 'copy'
                            ? 'Copying data from device...\n\n'
                            : 'Listing files from device...\n\n'
                        '$progress% completed',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 16),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  } // <-- This closes the build method

} // <-- This closes the _UsbCopyScreenState class
