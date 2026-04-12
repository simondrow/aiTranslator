import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

/// Audio recording service
/// Config: 16kHz, 16-bit, mono PCM/WAV (whisper.cpp required format)
class AudioService {
  final AudioRecorder _recorder = AudioRecorder();
  bool _isRecording = false;
  String? _currentPath;

  /// Whether currently recording
  bool get isRecording => _isRecording;

  /// Current recording file path
  String? get currentPath => _currentPath;

  /// Start recording
  /// Format: WAV, 16kHz, mono, 16-bit
  Future<String> startRecording() async {
    // Check permission
    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) {
      throw Exception('No microphone permission');
    }

    // Generate recording file path
    final dir = await getTemporaryDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final filePath = '${dir.path}/recording_$timestamp.wav';

    // Start recording: 16kHz, mono, 16-bit
    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.wav,
        sampleRate: 16000,
        numChannels: 1,
        bitRate: 256000,
      ),
      path: filePath,
    );

    _isRecording = true;
    _currentPath = filePath;
    debugPrint('[AudioService] Start recording: $filePath');
    return filePath;
  }

  /// Stop recording and return audio file path
  Future<String> stopRecording() async {
    if (!_isRecording) {
      return '';
    }

    final path = await _recorder.stop();
    _isRecording = false;
    _currentPath = null;

    if (path == null || path.isEmpty) {
      debugPrint('[AudioService] Recording stopped but no file path');
      return '';
    }

    // Verify file exists
    final file = File(path);
    if (!await file.exists()) {
      debugPrint('[AudioService] Recording file not found: $path');
      return '';
    }

    final fileSize = await file.length();
    debugPrint('[AudioService] Recording done: $path ($fileSize bytes)');
    return path;
  }

  /// Stop current recording and immediately start a new one (for segment-based streaming).
  /// Returns the path of the completed segment (or empty string if failed).
  Future<String> rotateRecording() async {
    if (!_isRecording) return '';

    // Stop current
    final path = await _recorder.stop();
    _isRecording = false;

    // Immediately start new recording
    final dir = await getTemporaryDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final newPath = '${dir.path}/recording_$timestamp.wav';

    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.wav,
        sampleRate: 16000,
        numChannels: 1,
        bitRate: 256000,
      ),
      path: newPath,
    );
    _isRecording = true;
    _currentPath = newPath;

    if (path == null || path.isEmpty) return '';

    final file = File(path);
    if (!await file.exists()) return '';

    final fileSize = await file.length();
    debugPrint('[AudioService] Segment done: $path ($fileSize bytes)');

    // Skip very short segments (< 2KB = ~60ms, likely silence)
    if (fileSize < 2000) {
      debugPrint('[AudioService] Segment too short, skipping');
      return '';
    }

    return path;
  }

  /// Release resources
  void dispose() {
    _recorder.dispose();
  }
}
