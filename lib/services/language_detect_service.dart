import 'package:flutter/foundation.dart';

import '../native/fasttext_bindings.dart';

/// 语种检测结果
class LanguageDetectResult {
  final String languageCode;
  final double confidence;

  const LanguageDetectResult({
    required this.languageCode,
    required this.confidence,
  });
}

/// 语种检测服务
/// 使用 fastText 通过 dart:ffi 实现语种识别
class LanguageDetectService {
  FastTextBindings? _bindings;
  bool _isInitialized = false;
  String? _modelPath;

  /// 置信度阈值: 低于此值则认为检测不可靠
  static const double confidenceThreshold = 0.7;

  /// 初始化 fastText 模型
  Future<void> initialize(String modelPath) async {
    if (_isInitialized && _modelPath == modelPath) return;

    _modelPath = modelPath;
    _bindings = FastTextBindings();
    _bindings!.init(modelPath);
    _isInitialized = true;
    debugPrint('[LanguageDetectService] fastText 模型已加载: $modelPath');
  }

  /// 检测文本语种
  ///
  /// [text] 待检测的文本
  /// 返回 [LanguageDetectResult] 包含语种代码和置信度
  Future<LanguageDetectResult> detectLanguage(String text) async {
    if (!_isInitialized || _bindings == null) {
      throw StateError('LanguageDetectService 未初始化，请先调用 initialize()');
    }

    if (text.trim().isEmpty) {
      return const LanguageDetectResult(
        languageCode: 'und',
        confidence: 0.0,
      );
    }

    try {
      final result = await compute(
        _detectInIsolate,
        _DetectArgs(modelPath: _modelPath!, text: text),
      );

      // 如果置信度低于阈值，记录警告
      if (result.confidence < confidenceThreshold) {
        debugPrint(
          '[LanguageDetectService] 低置信度检测: '
          '${result.languageCode} (${result.confidence})',
        );
      }

      return result;
    } catch (e) {
      debugPrint('[LanguageDetectService] 语种检测失败: $e');
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
class _DetectArgs {
  final String modelPath;
  final String text;

  const _DetectArgs({required this.modelPath, required this.text});
}

/// 在 Isolate 中执行的语种检测函数
LanguageDetectResult _detectInIsolate(_DetectArgs args) {
  final bindings = FastTextBindings();
  bindings.init(args.modelPath);

  try {
    final result = bindings.predict(args.text);

    // fastText 输出格式为 "__label__xx"，提取语种代码
    String langCode = result.label;
    if (langCode.startsWith('__label__')) {
      langCode = langCode.replaceFirst('__label__', '');
    }

    return LanguageDetectResult(
      languageCode: langCode,
      confidence: result.confidence,
    );
  } finally {
    bindings.free();
  }
}
