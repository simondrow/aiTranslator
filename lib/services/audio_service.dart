import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

/// Audio recording service
/// Config: 16kHz, 16-bit, mono PCM/WAV (whisper.cpp required format)
class AudioService {
  final AudioRecorder _recorder = AudioRecorder();
  bool _isRecording = false;

  /// Whether currently recording
  bool get isRecording => _isRecording;

  /// Start recording
  /// Format: WAV, 16kHz, 16-bit, mono
  Future<void> startRecording() async {
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
    debugPrint('[AudioService] Start recording: $filePath');
  }

  /// Stop recording and return audio file path
  Future<String> stopRecording() async {
    if (!_isRecording) {
      return '';
    }

    final path = await _recorder.stop();
    _isRecording = false;

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

  /// Release resources
  void dispose() {
    _recorder.dispose();
  }
}
