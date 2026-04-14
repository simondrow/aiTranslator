import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa_onnx;

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
/// 使用 sherpa-onnx SenseVoice 实现离线语音识别。
/// SenseVoice 是 non-autoregressive 模型，推理速度极快（<1s per segment on mobile）。
class AsrService {
  sherpa_onnx.OfflineRecognizer? _recognizer;
  bool _isInitialized = false;
  String? _modelDir;

  bool get isInitialized => _isInitialized;

  /// 初始化 SenseVoice 模型
  ///
  /// [modelDir] 为 SenseVoice 模型目录，需包含 model.int8.onnx 和 tokens.txt
  Future<void> initialize(String modelDir) async {
    if (_isInitialized && _modelDir == modelDir) return;

    final modelPath = '$modelDir/model.int8.onnx';
    final tokensPath = '$modelDir/tokens.txt';

    // Verify model files exist
    final modelFile = File(modelPath);
    final tokensFile = File(tokensPath);
    if (!await modelFile.exists()) {
      debugPrint('[AsrService] model file not found: $modelPath');
      return;
    }
    if (!await tokensFile.exists()) {
      debugPrint('[AsrService] tokens file not found: $tokensPath');
      return;
    }

    _modelDir = modelDir;

    try {
      final senseVoice = sherpa_onnx.OfflineSenseVoiceModelConfig(
        model: modelPath,
        language: 'auto', // auto-detect: zh, en, ja, ko, yue
        useInverseTextNormalization: true,
      );

      final modelConfig = sherpa_onnx.OfflineModelConfig(
        senseVoice: senseVoice,
        tokens: tokensPath,
        debug: false,
        numThreads: 2,
      );

      final config = sherpa_onnx.OfflineRecognizerConfig(model: modelConfig);
      _recognizer = sherpa_onnx.OfflineRecognizer(config);
      _isInitialized = true;
      debugPrint('[AsrService] SenseVoice model loaded from: $modelDir');
    } catch (e) {
      debugPrint('[AsrService] failed to init SenseVoice: $e');
      _recognizer = null;
      _isInitialized = false;
    }
  }

  /// 尝试从默认 Documents 路径自动初始化
  Future<bool> tryAutoInitialize() async {
    if (_isInitialized) return true;

    try {
      final dir = await getApplicationDocumentsDirectory();
      final modelDir =
          '${dir.path}/models/${ModelInfo.senseVoiceModelDirName}';

      final modelFile = File('$modelDir/model.int8.onnx');
      if (await modelFile.exists()) {
        await initialize(modelDir);
        return _isInitialized;
      }
    } catch (e) {
      debugPrint('[AsrService] tryAutoInitialize failed: $e');
    }
    return false;
  }

  /// 对音频文件进行语音识别
  ///
  /// SenseVoice 推理极快（non-autoregressive），通常 <500ms per 3s segment。
  /// 不需要 compute() Isolate。
  Future<AsrResult> transcribe(String audioPath) async {
    // Lazy init: model may have been downloaded after initial check
    if (!_isInitialized || _recognizer == null) {
      debugPrint('[AsrService] not initialized, attempting lazy init...');
      await tryAutoInitialize();
    }

    if (!_isInitialized || _recognizer == null) {
      debugPrint(
          '[AsrService] SenseVoice still not initialized, returning empty result');
      return const AsrResult(text: '', detectedLanguage: '');
    }

    try {
      final sw = Stopwatch()..start();
      debugPrint('[AsrService] transcription started: $audioPath');

      // Read WAV file
      final waveData = sherpa_onnx.readWave(audioPath);

      // Create stream & feed audio
      final stream = _recognizer!.createStream();
      stream.acceptWaveform(
        samples: waveData.samples,
        sampleRate: waveData.sampleRate,
      );

      // Decode — SenseVoice is non-autoregressive, this is very fast
      _recognizer!.decode(stream);

      // Get result
      final result = _recognizer!.getResult(stream);
      stream.free();

      sw.stop();

      final text = result.text.trim();
      // SenseVoice auto-detects language but doesn't expose it via result.lang
      // Use simple heuristic; downstream fastText LID will handle it anyway
      final detectedLang = _inferLanguage(text);

      final preview = text.length > 60 ? '${text.substring(0, 60)}...' : text;
      debugPrint(
          '[AsrService] transcription completed in ${sw.elapsedMilliseconds}ms: '
          '"$preview" (lang: $detectedLang)');

      return AsrResult(text: text, detectedLanguage: detectedLang);
    } catch (e) {
      debugPrint('[AsrService] transcription failed: $e');
      return const AsrResult(text: '', detectedLanguage: '');
    }
  }

  /// 简单语言推断（基于字符 Unicode 范围分析）
  /// SenseVoice 不直接输出语言标签，使用启发式判断作为后备
  String _inferLanguage(String text) {
    if (text.isEmpty) return '';

    int cjkCount = 0;
    int latinCount = 0;
    int japaneseCount = 0;
    int koreanCount = 0;

    for (final codeUnit in text.runes) {
      if ((codeUnit >= 0x4E00 && codeUnit <= 0x9FFF) ||
          (codeUnit >= 0x3400 && codeUnit <= 0x4DBF)) {
        cjkCount++;
      } else if ((codeUnit >= 0x0041 && codeUnit <= 0x005A) ||
          (codeUnit >= 0x0061 && codeUnit <= 0x007A)) {
        latinCount++;
      } else if ((codeUnit >= 0x3040 && codeUnit <= 0x309F) ||
          (codeUnit >= 0x30A0 && codeUnit <= 0x30FF)) {
        japaneseCount++;
      } else if (codeUnit >= 0xAC00 && codeUnit <= 0xD7AF) {
        koreanCount++;
      }
    }

    final total = cjkCount + latinCount + japaneseCount + koreanCount;
    if (total == 0) return '';

    if (japaneseCount > 0 && japaneseCount >= cjkCount) return 'ja';
    if (koreanCount > total * 0.3) return 'ko';
    if (cjkCount > latinCount) return 'zh';
    if (latinCount > 0) return 'en';
    return 'zh';
  }

  /// 释放资源
  void dispose() {
    _recognizer?.free();
    _recognizer = null;
    _isInitialized = false;
  }
}
