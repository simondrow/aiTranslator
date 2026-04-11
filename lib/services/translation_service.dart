import 'package:flutter/foundation.dart';

import '../native/nllb_bindings.dart';
import '../utils/language_codes.dart';

/// 翻译服务
/// 使用 NLLB-200-distilled-600M 通过 CTranslate2 + dart:ffi 实现离线翻译。
/// NLLB 模型未加载时使用 stub 返回占位结果。
class TranslationService {
  NllbBindings? _bindings;
  bool _isInitialized = false;
  String? _modelPath;

  bool get isInitialized => _isInitialized;

  /// 初始化 NLLB 模型
  Future<void> initialize(String modelPath) async {
    if (_isInitialized && _modelPath == modelPath) return;

    _modelPath = modelPath;
    _bindings = NllbBindings();
    _bindings!.init(modelPath);
    _isInitialized = true;
    debugPrint('[TranslationService] NLLB 模型已加载: $modelPath');
  }

  /// 翻译文本
  ///
  /// NLLB 未初始化时返回 stub 结果: "[译文] 原文"
  Future<String> translate(
    String text,
    String fromLang,
    String toLang,
  ) async {
    if (fromLang == toLang) {
      return text;
    }

    if (!_isInitialized || _bindings == null) {
      // Stub 模式: NLLB 模型未下载时提供占位翻译
      debugPrint('[TranslationService] stub 模式 ($fromLang → $toLang)');
      return _stubTranslate(text, fromLang, toLang);
    }

    try {
      final result = await compute(
        _translateInIsolate,
        _TranslateArgs(
          modelPath: _modelPath!,
          text: text,
          fromLang: fromLang,
          toLang: toLang,
        ),
      );
      return result;
    } catch (e) {
      debugPrint('[TranslationService] 翻译失败: $e');
      rethrow;
    }
  }

  /// Stub 翻译 — NLLB 模型未加载时的占位实现
  String _stubTranslate(String text, String fromLang, String toLang) {
    // 获取目标语言的可读名称
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
    _bindings?.free();
    _bindings = null;
    _isInitialized = false;
  }
}

/// NLLB 语言代码映射表
class NllbLanguageMap {
  NllbLanguageMap._();

  static const Map<String, String> codeMap = {
    'zh': 'zho_Hans',
    'en': 'eng_Latn',
    'ja': 'jpn_Jpan',
    'ko': 'kor_Hang',
    'fr': 'fra_Latn',
    'de': 'deu_Latn',
    'ru': 'rus_Cyrl',
    'es': 'spa_Latn',
    'it': 'ita_Latn',
  };

  static String toNllbCode(String shortCode) {
    return codeMap[shortCode] ?? 'eng_Latn';
  }
}

/// Isolate 参数
class _TranslateArgs {
  final String modelPath;
  final String text;
  final String fromLang;
  final String toLang;

  const _TranslateArgs({
    required this.modelPath,
    required this.text,
    required this.fromLang,
    required this.toLang,
  });
}

/// 在 Isolate 中执行的翻译函数
String _translateInIsolate(_TranslateArgs args) {
  final bindings = NllbBindings();
  bindings.init(args.modelPath);

  try {
    return bindings.translate(args.text, args.fromLang, args.toLang);
  } finally {
    bindings.free();
  }
}
