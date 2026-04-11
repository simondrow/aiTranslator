import 'package:flutter/foundation.dart';

import '../native/whisper_bindings.dart';

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
/// 使用 whisper.cpp 通过 dart:ffi 实现离线诵音识别
class AsrService {
  WhisperBindings? _bindings;
  bool _isInitialized = false;
  String? _modelPath;

  /// 初始化 Whisper 模型
  Future<void> initialize(String modelPath) async {
    if (_isInitialized && _modelPath == modelPath) return;

    _modelPath = modelPath;
    _bindings = WhisperBindings();
    _bindings!.init(modelPath);
    _isInitialized = true;
    debugPrint('[AsrService] Whisper 模型已加载: $modelPath');
  }

  /// 对音频文件进行语音识别
  ///
  /// [audioPath] 音频文件路径，要求 16kHz, 16-bit, mono WAV
  /// 返回 [AsrResult] 包含识别文本和检测到的语言
  Future<AsrResult> transcribe(String audioPath) async {
    if (!_isInitialized || _bindings == null) {
      throw StateError('AsrService 未初始化，请先调用 initialize()');
    }

    try {
      // 在 isolate 中执行转写以避免阻塞 UI
      final result = await compute(_transcribeInIsolate, _TranscribeArgs(
        modelPath: _modelPath!,
        audioPath: audioPath,
      ));
      return result;
    } catch (e) {
      debugPrint('[AsrService] 转写失败: $e');
      rethrow;
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
