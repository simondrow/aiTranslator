import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

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
/// 使用 fastText (lid.176.ftz) 通过 dart:ffi 实现语种识别。
/// 模型文件打包在 assets/models/ 中，首次使用时复制到应用文档目录。
class LanguageDetectService {
  FastTextBindings? _bindings;
  bool _isInitialized = false;

  /// 置信度阈值: 低于此值则认为检测不可靠
  static const double confidenceThreshold = 0.5;

  /// 资产中的模型路径
  static const String _assetModelPath = 'assets/models/lid.176.ftz';

  /// 模型文件名
  static const String _modelFileName = 'lid.176.ftz';

  bool get isInitialized => _isInitialized;

  /// 初始化 fastText 模型。
  /// 自动将 assets 中的模型复制到文档目录（FFI 需要文件系统路径）。
  Future<void> initialize() async {
    if (_isInitialized) return;

    final modelPath = await _ensureModelFile();
    _bindings = FastTextBindings();
    _bindings!.init(modelPath);
    _isInitialized = true;
    debugPrint('[LanguageDetectService] fastText 模型已加载: $modelPath');
  }

  /// 确保模型文件存在于文档目录，如不存在则从 assets 复制
  Future<String> _ensureModelFile() async {
    final appDir = await getApplicationDocumentsDirectory();
    final modelFile = File('${appDir.path}/models/$_modelFileName');

    if (!await modelFile.exists()) {
      debugPrint('[LanguageDetectService] 从 assets 复制模型文件...');
      await modelFile.parent.create(recursive: true);
      final data = await rootBundle.load(_assetModelPath);
      await modelFile.writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        flush: true,
      );
      debugPrint('[LanguageDetectService] 模型复制完成: ${modelFile.path}');
    }

    return modelFile.path;
  }

  /// 检测文本语种
  ///
  /// [text] 待检测的文本
  /// 返回 [LanguageDetectResult] 包含语种代码和置信度
  LanguageDetectResult detectLanguage(String text) {
    if (!_isInitialized || _bindings == null) {
      // 未初始化时使用简单启发式: 判断是否包含 CJK 字符
      return _fallbackDetect(text);
    }

    if (text.trim().isEmpty) {
      return const LanguageDetectResult(
        languageCode: 'und',
        confidence: 0.0,
      );
    }

    try {
      // FFI 调用在主 isolate 中执行（fastText predict 非常快，< 1ms）
      final result = _bindings!.predict(text);

      // fastText 输出格式为 "__label__xx"，提取语种代码
      String langCode = result.label;
      if (langCode.startsWith('__label__')) {
        langCode = langCode.replaceFirst('__label__', '');
      }

      final detectResult = LanguageDetectResult(
        languageCode: langCode,
        confidence: result.confidence,
      );

      if (detectResult.confidence < confidenceThreshold) {
        debugPrint(
          '[LanguageDetectService] 低置信度检测: '
          '${detectResult.languageCode} (${detectResult.confidence})',
        );
      }

      return detectResult;
    } catch (e) {
      debugPrint('[LanguageDetectService] 语种检测失败: $e');
      return _fallbackDetect(text);
    }
  }

  /// 简单的后备语种检测（当 FFI 不可用时）
  LanguageDetectResult _fallbackDetect(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      return const LanguageDetectResult(languageCode: 'und', confidence: 0.0);
    }

    // 检查是否包含 CJK 字符
    final cjkRegex = RegExp(r'[\u4e00-\u9fff\u3400-\u4dbf]');
    final japRegex = RegExp(r'[\u3040-\u309f\u30a0-\u30ff]');
    final korRegex = RegExp(r'[\uac00-\ud7af\u1100-\u11ff]');
    final cyrRegex = RegExp(r'[\u0400-\u04ff]');

    if (japRegex.hasMatch(trimmed)) {
      return const LanguageDetectResult(languageCode: 'ja', confidence: 0.7);
    }
    if (korRegex.hasMatch(trimmed)) {
      return const LanguageDetectResult(languageCode: 'ko', confidence: 0.7);
    }
    if (cjkRegex.hasMatch(trimmed)) {
      return const LanguageDetectResult(languageCode: 'zh', confidence: 0.7);
    }
    if (cyrRegex.hasMatch(trimmed)) {
      return const LanguageDetectResult(languageCode: 'ru', confidence: 0.6);
    }

    // 默认英文
    return const LanguageDetectResult(languageCode: 'en', confidence: 0.5);
  }

  /// 释放资源
  void dispose() {
    _bindings?.free();
    _bindings = null;
    _isInitialized = false;
  }
}
