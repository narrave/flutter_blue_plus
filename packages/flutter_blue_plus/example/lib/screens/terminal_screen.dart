import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'dart:async';
import '../utils/ble_manager.dart';

class TerminalScreen extends StatefulWidget {
  final BluetoothDevice? connectedDevice;
  const TerminalScreen({super.key, this.connectedDevice});

  @override
  State<TerminalScreen> createState() => TerminalScreenState();
}

class TerminalScreenState extends State<TerminalScreen> with WidgetsBindingObserver {
  final List<String> output = [];
  final ScrollController _scrollController = ScrollController();

  // Command list
  final List<Map<String, dynamic>> commandList = [
    {'cmd': 'sno', 'desc': 'Set Serial Number', 'params': ['sno'], 'example': {'sno': '12345678'}},
    {'cmd': 'bv-og', 'desc': 'BV Calibration', 'params': ['0', '1.0'], 'example': {'0': 'bv_offset - 0', '1.0': 'bv_gain - 1.0'}},
    {'cmd': 'sv-og', 'desc': 'SV Calibration', 'params': ['0', '1.0'], 'example': {'0': 'sv_offset - 0', '1.0': 'sv_gain - 1.0'}},
    {'cmd': 'c01', 'desc': 'Station Info'},
    {
      'cmd': 'c02', 'desc': 'System Configs',
      'params': ['sid', 'mpm', 'upm', 'smn', 'dmn1', 'dmn2', 'sip1', 'sip2', 'drh', 'ucf', 'con', 'th', 'clk'],
      'example': {
        'sid': 'ECVENKAT0', 'mpm': '1', 'upm': '5', 'smn': '9440520222', 'dmn1': '9440520222', 'dmn2': '',
        'sip1': '183.82.2.251', 'sip2': '183.82.2.251', 'drh': '830', 'ucf': '0xd', 'con': 'A', 'th': '25', 'clk': 'i'
      }
    },
    {'cmd': 'c05', 'desc': 'FTP Configs', 'params': ['ftu', 'ftp', 'ftd', 'fts'], 'example': {'ftu': 'user', 'ftp': 'pass', 'ftd': '/SATYAG', 'fts': 'UPV3'}},
    {'cmd': 'c09', 'desc': 'THP Config', 'params': ['T', 'H', 'P'], 'example': {'T': '0.0 Temp Offset', 'H': '0.0 HUM Offset', 'P': '0.0 PR OffSet'}},
    {'cmd': 'c10', 'desc': 'Current Status'},
    {'cmd': 'c21', 'desc': 'Reset System'},
    {'cmd': 'c22', 'desc': 'Clear SD Card Log'},
    {'cmd': 'c24', 'desc': 'Rain Reset'},
  ];

  Map<String, String> paramInputs = {};
  Map<String, dynamic>? selectedCommand;
  bool isC02Modal = false;

  BluetoothCharacteristic? _notifyChar;
  StreamSubscription<List<int>>? _notifySubscription;
  late final Guid _char2a19 = Guid('2a19');
  bool _isSubscribed = false;
  StreamSubscription<BluetoothConnectionState>? _connectionStateSubscription;
  bool _subscribing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _listenToConnectionState();
  }

  @override
  void didUpdateWidget(TerminalScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.connectedDevice != widget.connectedDevice) {
      _connectionStateSubscription?.cancel();
      _listenToConnectionState();
    }
  }

  void _listenToConnectionState() {
    if (widget.connectedDevice != null) {
      _connectionStateSubscription = widget.connectedDevice!.connectionState.listen((state) {
        final result = {
          'connection_state': state == BluetoothConnectionState.connected ? 1 : 0,
        };
        _handleConnectionStateChanged(result);
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _notifySubscription?.cancel();
    _connectionStateSubscription?.cancel();
    _notifyChar?.setNotifyValue(false);
    _isSubscribed = false;
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    if (state == AppLifecycleState.resumed) {
      print('\n\n\n[s^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^');
      print('[TerminalScreen] App resumed');
      print('[e^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^');
      await _cleanupNotification();
      // Re-subscribe if still connected
      if (widget.connectedDevice != null && await widget.connectedDevice!.isConnected) {
        print('[@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@');
        print('[TerminalScreen] Device still connected, re-subscribing to notifications');
        await _subscribeToNotificationWithConnectedDevice();
      }
    } else if (state == AppLifecycleState.paused) {
      print('\n\n\n[s^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^');
      print('[TerminalScreen] App paused');
      print('[e^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^');
      await _cleanupNotification();
    }
  }

  Future<void> _cleanupNotification() async {
    _notifySubscription?.cancel();
    _notifySubscription = null;
    _isSubscribed = false;
    _subscribing = false;
    if (_notifyChar != null) {
      try {
        await _notifyChar!.setNotifyValue(false);
      } catch (_) {}
    }
  }

  Future<void> _subscribeToNotificationWithConnectedDevice() async {
    if (_subscribing || _isSubscribed) return;
    _subscribing = true;
    await _cleanupNotification();

    if (widget.connectedDevice == null || !(await widget.connectedDevice!.isConnected)) {
      print('No connected device or not connected.');
      _subscribing = false;
      return;
    }
    try {
      final char = BleManager().getCharacteristic(
        widget.connectedDevice!,
        serviceUuid: '180f',
        characteristicUuid: '2a19',
      );
      if (char == null) {
        print('Notify characteristic not found.');
        _subscribing = false;
        return;
      }
      print('Characteristic properties: notify=${char.properties.notify}');
      if (!char.properties.notify) {
        print('Characteristic does NOT support notifications.');
        _subscribing = false;
        return;
      }
      await char.setNotifyValue(true);
      _notifyChar = char;
      _isSubscribed = true;
      print('Subscribed to notifications on $_char2a19');
      _notifySubscription = char.onValueReceived.listen((value) {
        final txt = String.fromCharCodes(value).replaceAll('\x00', '');
        if (txt.isNotEmpty) {
          print(' when : "$txt"');
          setState(() {
            output.add(txt);
            if (output.length > 100) output.removeAt(0);
            print('Current output: $output');
          });
          _scrollToBottom();
        }
      });
    } catch (e) {
      setState(() {
        output.add('Error: $e');
      });
      print('Error subscribing to notifications: $e');
    }
    _subscribing = false;
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
  }

  void _showCommandModal() {
    setState(() {
      selectedCommand = null;
      paramInputs = {};
      isC02Modal = false;
    });
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _buildCommandListModal(),
    );
  }

  Widget _buildCommandListModal() {
    return Container(
      height: 500,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          const Text('Select Command', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          Expanded(
            child: ListView(
              children: commandList.map((cmdObj) {
                return ListTile(
                  title: Text('${cmdObj['cmd']} — ${cmdObj['desc']}'),
                  onTap: () {
                    Navigator.pop(context);
                    _onCommandSelect(cmdObj);
                  },
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  void _onCommandSelect(Map<String, dynamic> cmdObj) {
    setState(() {
      selectedCommand = cmdObj;
      paramInputs = {for (var p in (cmdObj['params'] ?? [])) p: ''};
      isC02Modal = cmdObj['cmd'] == 'c02';
    });
    _showParamModal();
  }

  void _showParamModal() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Enter Parameters for ${selectedCommand?['cmd']}'),
        content: isC02Modal
            ? SingleChildScrollView(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: (selectedCommand?['params'] ?? []).map<Widget>((pk) {
                    return SizedBox(
                      width: 120,
                      child: TextField(
                        decoration: InputDecoration(
                          labelText: pk,
                          hintText: selectedCommand?['example']?[pk]?.toString() ?? '',
                        ),
                        onChanged: (t) => paramInputs[pk] = t,
                      ),
                    );
                  }).toList(),
                ),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: (selectedCommand?['params'] ?? []).map<Widget>((pk) {
                  return TextField(
                    decoration: InputDecoration(
                      labelText: pk,
                      hintText: selectedCommand?['example']?[pk]?.toString() ?? '',
                    ),
                    onChanged: (t) => paramInputs[pk] = t,
                  );
                }).toList(),
              ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _handleSendCommand();
            },
            child: const Text('Send'),
          ),
        ],
      ),
    );
  }

  void _handleSendCommand() async {
    if (selectedCommand == null) return;
    String cmd = selectedCommand!['cmd'];
    final entries = paramInputs.entries.where((e) => e.value.isNotEmpty).toList();
    String full = '';
    if (cmd == 'c09') {
      final T = paramInputs['T'] ?? '0.0';
      final H = paramInputs['H'] ?? '0.0';
      final P = paramInputs['P'] ?? '0.0';
      full = '0x2A19:$cmd,THP=$T,$H,$P';
    } else {
      if (entries.isNotEmpty) {
        cmd += ',' + entries.map((e) => '${e.key}=${e.value}').join(',');
      }
      full = '0x2A19:$cmd';
    }
    setState(() {
      output.add('> $full');
      if (output.length > 100) output.removeAt(0);
    });

    if (widget.connectedDevice != null) {
      try {
        await BleManager().writeDataToDevice(
          widget.connectedDevice!,
          full,
          serviceUuid: '180f',
          characteristicUuid: '2a19',
        );
        setState(() {
          output.add("Command sent");
        });
      } catch (e) {
        setState(() {
          output.add("Send Command Error: $e");
        });
      }
    }
  }

  // Only subscribe after connection is established!
  void _handleConnectionStateChanged(Map<String, dynamic> result) async {
    final connectionState = result['connection_state'];
    if (connectionState == 1) { // 1 = connected
      await _cleanupNotification();
      await _subscribeToNotificationWithConnectedDevice();
    } else if (connectionState == 0) { // 0 = disconnected
      await _cleanupNotification();
      _notifyChar = null;
    }
  }
  
  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final width = media.size.width;
    final height = media.size.height;
    final isTablet = width > 600;

    return Scaffold(
      body: Container(
        color: const Color(0xFFF7F7F7),
        width: width,
        height: height,
        child: SafeArea(
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: isTablet ? width * 0.18 : 16,
              vertical: isTablet ? 40 : 24,
            ),
            child: Column(
              children: [
                SizedBox(height: isTablet ? 40 : 24),
                Expanded(
                  child: Container(
                    width: double.infinity,
                    constraints: BoxConstraints(
                      maxWidth: isTablet ? 600 : double.infinity,
                      minHeight: isTablet ? 400 : 260,
                      maxHeight: height * (isTablet ? 0.7 : 0.65),
                    ),
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: const Color(0xFF16163A),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.08),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: output.isEmpty
                        ? const Center(
                            child: Text(
                              'No output yet.\n\n',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Color(0xFFFFBF00),
                                fontFamily: 'monospace',
                                fontSize: 16,
                              ),
                            ),
                          )
                        : ListView.builder(
                            controller: _scrollController,
                            itemCount: output.length,
                            itemBuilder: (context, idx) {
                              print('Building output item: ${output[idx]}');
                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 2.5),
                                child: Text(
                                  output[idx],
                                  style: const TextStyle(
                                    color: Color(0xFFFFBF00),
                                    fontFamily: 'monospace',
                                    fontSize: 16,
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ),
                SizedBox(height: isTablet ? 32 : 18),
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: Color(0xFF4a90e2),
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.15),
                              blurRadius: 8,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: TextButton(
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            backgroundColor: Colors.transparent,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          onPressed: () => setState(() => output.clear()),
                          child: const Text(
                            'Clear',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                              letterSpacing: 1.1,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: Color(0xFF4a90e2),
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.15),
                              blurRadius: 8,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: TextButton(
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            backgroundColor: Colors.transparent,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          onPressed: _showCommandModal,
                          child: const Text(
                            'Command...',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                              letterSpacing: 1.1,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
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
