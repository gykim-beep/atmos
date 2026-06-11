import 'package:flutter/material.dart';
import '../../src/rust/api/simple.dart' as rust_api;

class GlobalState extends ChangeNotifier {
  bool _isEngineRunning = false;
  List<String> _availableDevices = [];
  String _selectedDevice = "";
  
  // New State for Specs
  final List<String> _systemLogs = [];
  int _activeRoomId = 1;
  final Set<int> _lockedRoomIds = {};
  
  bool get isEngineRunning => _isEngineRunning;
  List<String> get availableDevices => _availableDevices;
  String get selectedDevice => _selectedDevice;
  List<String> get systemLogs => _systemLogs;
  int get activeRoomId => _activeRoomId;
  Set<int> get lockedRoomIds => _lockedRoomIds;

  GlobalState() {
    _initAudio();
  }

  Future<void> _initAudio() async {
    _availableDevices = await rust_api.getAvailableDevices();
    if (_availableDevices.isNotEmpty) {
      _selectedDevice = _availableDevices.first;
    }
    _addLog("System initialized. Devices scanned.");
    notifyListeners();
  }

  void _addLog(String msg) {
    final timestamp = DateTime.now().toIso8601String().substring(11, 19);
    _systemLogs.add("[$timestamp] $msg");
    if (_systemLogs.length > 100) {
      _systemLogs.removeAt(0);
    }
  }

  void clearLogs() {
    _systemLogs.clear();
    notifyListeners();
  }
  
  void setActiveRoom(int roomId) {
    _activeRoomId = roomId;
    _addLog("Active room changed to Room $roomId");
    notifyListeners();
  }

  void setRoomLocked(int roomId, bool locked) {
    if (locked) {
      _lockedRoomIds.add(roomId);
    } else {
      _lockedRoomIds.remove(roomId);
    }
    notifyListeners();
  }

  Future<void> toggleEngine() async {
    if (_isEngineRunning) {
      rust_api.stopAudioEngine();
      rust_api.stopOscServer();
      _isEngineRunning = false;
      _addLog("Audio Engine and OSC Server STOPPED.");
    } else {
      try {
        await rust_api.startAudioEngine();
        
        // Start OSC Stream
        final stream = rust_api.startOscServer(port: 9000);
        stream.listen((addr) {
           _addLog("OSC Recv: $addr");
        });
        
        _isEngineRunning = true;
        _addLog("Audio Engine and OSC Server STARTED on port 9000.");
      } catch (e) {
        debugPrint("Failed to start engine: $e");
        _addLog("Error starting engine: $e");
      }
    }
    notifyListeners();
  }
}
