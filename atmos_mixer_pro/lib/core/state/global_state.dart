import 'package:flutter/material.dart';
import '../src/rust/api/simple.dart' as rust_api;

class GlobalState extends ChangeNotifier {
  bool _isEngineRunning = false;
  List<String> _availableDevices = [];
  String _selectedDevice = "";
  
  bool get isEngineRunning => _isEngineRunning;
  List<String> get availableDevices => _availableDevices;
  String get selectedDevice => _selectedDevice;

  GlobalState() {
    _initAudio();
  }

  Future<void> _initAudio() async {
    _availableDevices = await rust_api.getAvailableDevices();
    if (_availableDevices.isNotEmpty) {
      _selectedDevice = _availableDevices.first;
    }
    notifyListeners();
  }

  Future<void> toggleEngine() async {
    if (_isEngineRunning) {
      rust_api.stopAudioEngine();
      _isEngineRunning = false;
    } else {
      try {
        await rust_api.startAudioEngine();
        _isEngineRunning = true;
      } catch (e) {
        debugPrint("Failed to start engine: $e");
      }
    }
    notifyListeners();
  }
}
