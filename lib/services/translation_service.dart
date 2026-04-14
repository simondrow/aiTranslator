import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'hymt_translator.dart';

/// 翻译服务
/// 使用 HY-MT1.5-1.8B (GGUF via llama.cpp) 实现离线翻译。
/// 推理在 native 层异步执行，不阻塞 UI 线程。
/// 模型未加载时使用 stub 返回占位结果。
class TranslationService {
  HymtTranslator? _translator;
  bool _isInitialized = false;
  bool _isInitializing = false;
  String? _modelPath;

  bool get isInitialized => _isInitialized;

  /// 检查引擎是否真正就绪 (GGUF 模型已加载)
  bool get isEngineReady => _translator?.isReady ?? false;

  /// 初始化 HY-MT 翻译模型
  /// [modelDir] 模型目录 (包含 .gguf 文件)
  Future<void> initialize(String modelDir) async {
    if (_isInitialized && _modelPath == modelDir && isEngineReady) return;
    if (_isInitializing) return;

    _isInitializing = true;
    _modelPath = modelDir;

    // 查找 GGUF 文件
    final ggufFile = _findGgufFile(modelDir);
    if (ggufFile == null) {
      debugPrint('[TranslationService] 未找到 GGUF 文件: $modelDir');
      debugPrint('[TranslationService] 将以 stub 模式运行');
      _isInitialized = true;
      _isInitializing = false;
      return;
    }

    try {
      _translator = HymtTranslator();
      await _translator!.initialize(ggufFile);
      _isInitialized = true;

      if (_translator!.isReady) {
        debugPrint('[TranslationService] HY-MT 翻译引擎已就绪');
      } else {
        debugPrint('[TranslationService] HY-MT 初始化失败，将以 stub 模式运行');
        _translator = null;
      }
    } catch (e) {
      debugPrint('[TranslationService] HY-MT 初始化失败: $e');
      debugPrint('[TranslationService] 将以 stub 模式运行');
      _translator = null;
      _isInitialized = true;
    } finally {
      _isInitializing = false;
    }
  }

  /// 在 modelDir 中查找 .gguf 文件
  String? _findGgufFile(String modelDir) {
    final dir = Directory(modelDir);
    if (!dir.existsSync()) return null;

    try {
      final files = dir.listSync().whereType<File>();
      for (final f in files) {
        if (f.path.endsWith('.gguf')) return f.path;
      }
    } catch (_) {}
    return null;
  }

  /// 尝试从默认下载目录自动初始化
  Future<bool> tryAutoInitialize() async {
    if (_isInitialized && isEngineReady) return true;

    try {
      final appDir = await getApplicationDocumentsDirectory();
      final modelDir = '${appDir.path}/models/hymt';

      // 检查是否有 GGUF 文件
      final ggufFile = _findGgufFile(modelDir);
      if (ggufFile != null) {
        await initialize(modelDir);
        return isEngineReady;
      }
    } catch (e) {
      debugPrint('[TranslationService] 自动初始化失败: $e');
    }
    return false;
  }

  /// 翻译文本
  /// [fromLang] / [toLang] 使用 ISO 短代码 (zh, en, ja, ko, ...)
  /// HY-MT 原生支持短代码，无需转换
  Future<String> translate(
    String text,
    String fromLang,
    String toLang,
  ) async {
    if (fromLang == toLang) {
      return text;
    }

    if (!_isInitialized || _translator == null || !_translator!.isReady) {
      // Stub 模式
      debugPrint('[TranslationService] stub 模式 ($fromLang → $toLang)');
      return _stubTranslate(text, fromLang, toLang);
    }

    try {
      return await _translator!.translate(text, fromLang, toLang);
    } catch (e) {
      debugPrint('[TranslationService] 翻译失败: $e');
      return _stubTranslate(text, fromLang, toLang);
    }
  }

  /// Stub 翻译 — 模型未加载时的占位实现
  String _stubTranslate(String text, String fromLang, String toLang) {
    final targetName = _langDisplayName(toLang);
    return '[$targetName] $text';
  }

  String _langDisplayName(String code) {
    const map = {
      'zh': '中文',
      'en': 'English',
      'ja': '日本語',
      'ko': '한국어',
      'fr': 'Français',
      'de': 'Deutsch',
      'ru': 'Русский',
      'es': 'Español',
      'it': 'Italiano',
      'th': 'ภาษาไทย',
      'vi': 'Tiếng Việt',
    };
    return map[code] ?? code;
  }

  /// 释放资源
  void dispose() {
    _translator?.dispose();
    _translator = null;
    _isInitialized = false;
  }
}
