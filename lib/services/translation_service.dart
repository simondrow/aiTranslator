import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'translation_isolate.dart';
import '../utils/language_codes.dart';

/// 翻译服务
/// 使用 NLLB-200-distilled-600M ONNX quantized 模型实现离线翻译。
/// 翻译在后台 Isolate 中执行，不阻塞 UI 线程。
/// 模型未加载时使用 stub 返回占位结果。
class TranslationService {
  TranslationIsolate? _isolate;
  bool _isInitialized = false;
  bool _isInitializing = false;
  String? _modelDir;

  bool get isInitialized => _isInitialized;

  /// 检查引擎是否真正就绪 (ONNX 模型已加载，非 stub)
  bool get isEngineReady => _isolate?.isReady ?? false;

  /// 初始化 NLLB 模型（在后台 Isolate 中加载）
  /// [modelDir] ONNX 模型目录 (包含 encoder/decoder onnx + tokenizer.json)
  Future<void> initialize(String modelDir) async {
    if (_isInitialized && _modelDir == modelDir && isEngineReady) return;
    if (_isInitializing) return;

    _isInitializing = true;
    _modelDir = modelDir;

    // 检查必要文件
    final requiredFiles = [
      'encoder_model_quantized.onnx',
      'decoder_model_merged_quantized.onnx',
      'tokenizer.json',
    ];

    for (final fname in requiredFiles) {
      if (!File('$modelDir/$fname').existsSync()) {
        debugPrint('[TranslationService] 缺少文件: $modelDir/$fname');
        debugPrint('[TranslationService] 将以 stub 模式运行');
        _isInitialized = true;
        _isInitializing = false;
        return;
      }
    }

    try {
      _isolate?.dispose();
      _isolate = TranslationIsolate();
      final ok = await _isolate!.initialize(modelDir);
      _isInitialized = true;

      if (ok) {
        debugPrint('[TranslationService] NLLB 后台 Isolate 已就绪');
      } else {
        debugPrint('[TranslationService] NLLB 初始化失败，将以 stub 模式运行');
        _isolate?.dispose();
        _isolate = null;
      }
    } catch (e) {
      debugPrint('[TranslationService] NLLB 初始化失败: $e');
      debugPrint('[TranslationService] 将以 stub 模式运行');
      _isolate?.dispose();
      _isolate = null;
      _isInitialized = true;
    } finally {
      _isInitializing = false;
    }
  }

  /// 尝试从默认下载目录自动初始化
  Future<bool> tryAutoInitialize() async {
    if (_isInitialized && isEngineReady) return true;

    try {
      final appDir = await getApplicationDocumentsDirectory();
      final modelDir = '${appDir.path}/models/nllb-onnx';

      // 检查关键模型文件是否存在
      final encoder = File('$modelDir/encoder_model_quantized.onnx');
      final decoder = File('$modelDir/decoder_model_merged_quantized.onnx');
      final tokenizer = File('$modelDir/tokenizer.json');

      if (encoder.existsSync() && decoder.existsSync() && tokenizer.existsSync()) {
        await initialize(modelDir);
        return isEngineReady;
      }
    } catch (e) {
      debugPrint('[TranslationService] 自动初始化失败: $e');
    }
    return false;
  }

  /// 翻译文本（在后台 Isolate 中执行，不阻塞 UI）
  ///
  /// NLLB 未初始化时返回 stub 结果: "[目标语言] 原文"
  Future<String> translate(
    String text,
    String fromLang,
    String toLang,
  ) async {
    if (fromLang == toLang) {
      return text;
    }

    if (!_isInitialized || _isolate == null || !_isolate!.isReady) {
      // Stub 模式: NLLB 模型未下载时提供占位翻译
      debugPrint('[TranslationService] stub 模式 ($fromLang → $toLang)');
      return _stubTranslate(text, fromLang, toLang);
    }

    try {
      return await _isolate!.translate(text, fromLang, toLang);
    } catch (e) {
      debugPrint('[TranslationService] 翻译失败: $e');
      return _stubTranslate(text, fromLang, toLang);
    }
  }

  /// Stub 翻译 — NLLB 模型未加载时的占位实现
  String _stubTranslate(String text, String fromLang, String toLang) {
    final targetName = _nllbToDisplayName(toLang);
    return '[$targetName] $text';
  }

  /// NLLB 代码转显示名称
  String _nllbToDisplayName(String nllbCode) {
    const map = {
      'zho_Hans': '中文',
      'eng_Latn': 'English',
      'jpn_Jpan': '日本語',
      'kor_Hang': '한국어',
      'fra_Latn': 'Français',
      'deu_Latn': 'Deutsch',
      'rus_Cyrl': 'Русский',
      'spa_Latn': 'Español',
      'ita_Latn': 'Italiano',
    };
    return map[nllbCode] ?? nllbCode;
  }

  /// 便捷方法: 使用短语言代码进行翻译
  Future<String> translateWithShortCodes(
    String text,
    String fromCode,
    String toCode,
  ) async {
    final fromNllb = LanguageCodes.getNllbCode(fromCode);
    final toNllb = LanguageCodes.getNllbCode(toCode);
    return translate(text, fromNllb, toNllb);
  }

  /// 释放资源
  void dispose() {
    _isolate?.dispose();
    _isolate = null;
    _isInitialized = false;
  }
}
