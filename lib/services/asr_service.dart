import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../native/whisper_bindings.dart';
import '../features/model_manager/models/model_info.dart';

/// ASR 识别结果
class AsrResult {
  final String text;
  final String detectedLanguage;

  const AsrResult({
    required this.text,
    required this.detectedLanguage,
  });
}

/// 语音识别服务
/// 使用 whisper.cpp 通过 dart:ffi 实现离线语音识别。
/// Whisper 模型未加载时返回空结果。
class AsrService {
  WhisperBindings? _bindings;
  bool _isInitialized = false;
  String? _modelPath;

  bool get isInitialized => _isInitialized;

  /// 初始化 Whisper 模型
  Future<void> initialize(String modelPath) async {
    if (_isInitialized && _modelPath == modelPath) return;

    // Verify model file exists
    final file = File(modelPath);
    if (!await file.exists()) {
      debugPrint('[AsrService] model file not found: $modelPath');
      return;
    }

    _modelPath = modelPath;

    try {
      _bindings = WhisperBindings();
      _bindings!.init(modelPath);
      _isInitialized = true;
      debugPrint('[AsrService] Whisper model loaded: $modelPath');
    } catch (e) {
      debugPrint('[AsrService] failed to init whisper: $e');
      _bindings = null;
      _isInitialized = false;
    }
  }

  /// 尝试从默认 Documents 路径自动初始化
  Future<bool> tryAutoInitialize() async {
    if (_isInitialized) return true;

    try {
      final dir = await getApplicationDocumentsDirectory();
      final modelPath =
          '${dir.path}/models/${ModelInfo.whisperModelDirName}/${ModelInfo.whisperModelFileName}';

      final file = File(modelPath);
      if (await file.exists()) {
        await initialize(modelPath);
        return _isInitialized;
      }
    } catch (e) {
      debugPrint('[AsrService] tryAutoInitialize failed: $e');
    }
    return false;
  }

  /// 对音频文件进行语音识别
  ///
  /// Whisper 未初始化时返回空结果（stub 模式）。
  Future<AsrResult> transcribe(String audioPath) async {
    if (!_isInitialized || _bindings == null) {
      debugPrint('[AsrService] whisper not initialized, returning empty result');
      return const AsrResult(text: '', detectedLanguage: '');
    }

    try {
      // Run transcription in a separate isolate to avoid blocking the UI
      final result = await compute(_transcribeInIsolate, _TranscribeArgs(
        modelPath: _modelPath!,
        audioPath: audioPath,
      ));
      return result;
    } catch (e) {
      debugPrint('[AsrService] transcription failed: $e');
      return const AsrResult(text: '', detectedLanguage: '');
    }
  }

  /// 释放资源
  void dispose() {
    _bindings?.free();
    _bindings = null;
    _isInitialized = false;
  }
}

/// Isolate 参数
class _TranscribeArgs {
  final String modelPath;
  final String audioPath;

  const _TranscribeArgs({
    required this.modelPath,
    required this.audioPath,
  });
}

/// 在 Isolate 中执行的转写函数
AsrResult _transcribeInIsolate(_TranscribeArgs args) {
  final bindings = WhisperBindings();
  bindings.init(args.modelPath);

  try {
    final result = bindings.transcribe(args.audioPath);
    return AsrResult(
      text: result.text,
      detectedLanguage: result.language,
    );
  } finally {
    bindings.free();
  }
}
