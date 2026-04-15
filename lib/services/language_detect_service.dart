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

  /// 置信度阈值: 低于此值则认为 fastText 检测不可靠，
  /// 回退到基于 Unicode 的启发式检测。
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
  ///
  /// 策略:
  ///   1. fastText 检测；若置信度 >= [confidenceThreshold] 直接采纳。
  ///   2. 置信度不足时，回退到 Unicode 启发式 [_fallbackDetect]。
  ///      短文本（< 10 字符）或含大量非 ASCII 字符的文本中
  ///      fastText 经常误判为 en，此分支可有效纠正。
  LanguageDetectResult detectLanguage(String text) {
    if (!_isInitialized || _bindings == null) {
      return _fallbackDetect(text);
    }

    if (text.trim().isEmpty) {
      return const LanguageDetectResult(
        languageCode: 'und',
        confidence: 0.0,
      );
    }

    try {
      final result = _bindings!.predict(text);

      String langCode = result.label;
      if (langCode.startsWith('__label__')) {
        langCode = langCode.replaceFirst('__label__', '');
      }

      final confidence = result.confidence;

      // 置信度不足 → 回退启发式
      if (confidence < confidenceThreshold) {
        debugPrint(
          '[LanguageDetectService] 低置信度 fastText: '
          '$langCode ($confidence), 回退启发式',
        );
        final fallback = _fallbackDetect(text);
        debugPrint(
          '[LanguageDetectService] 启发式结果: '
          '${fallback.languageCode} (${fallback.confidence})',
        );
        return fallback;
      }

      return LanguageDetectResult(
        languageCode: langCode,
        confidence: confidence,
      );
    } catch (e) {
      debugPrint('[LanguageDetectService] 语种检测失败: $e');
      return _fallbackDetect(text);
    }
  }

  /// 基于 Unicode 码欵的后备语种检测
  ///
  /// 统计文本中各文字系统占比，选择占比最高的语种。
  /// 对短文本（几个汉字/假名/谚文）极其可靠。
  LanguageDetectResult _fallbackDetect(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      return const LanguageDetectResult(languageCode: 'und', confidence: 0.0);
    }

    int cjkCount = 0; // 汉字 (CJK Unified + Ext-A)
    int hiraCount = 0; // 平假名
    int kataCount = 0; // 片假名
    int korCount = 0; // 谚文音节 + 字母
    int latinCount = 0; // 基础拉丁字母

    for (final rune in trimmed.runes) {
      if ((rune >= 0x4E00 && rune <= 0x9FFF) ||
          (rune >= 0x3400 && rune <= 0x4DBF)) {
        cjkCount++;
      } else if (rune >= 0x3040 && rune <= 0x309F) {
        hiraCount++;
      } else if (rune >= 0x30A0 && rune <= 0x30FF) {
        kataCount++;
      } else if ((rune >= 0xAC00 && rune <= 0xD7AF) ||
          (rune >= 0x1100 && rune <= 0x11FF)) {
        korCount++;
      } else if ((rune >= 0x0041 && rune <= 0x005A) ||
          (rune >= 0x0061 && rune <= 0x007A)) {
        latinCount++;
      }
    }

    final japCount = hiraCount + kataCount;
    final total = cjkCount + japCount + korCount + latinCount;
    if (total == 0) {
      return const LanguageDetectResult(languageCode: 'en', confidence: 0.3);
    }

    // 日文特征字符（平/片假名）优先判定
    if (japCount > 0) {
      return LanguageDetectResult(
        languageCode: 'ja',
        confidence: (japCount + cjkCount) / total.clamp(1, total).toDouble(),
      );
    }
    if (korCount > 0) {
      return LanguageDetectResult(
        languageCode: 'ko',
        confidence: korCount / total.clamp(1, total).toDouble(),
      );
    }
    if (cjkCount > 0) {
      return LanguageDetectResult(
        languageCode: 'zh',
        confidence: cjkCount / total.clamp(1, total).toDouble(),
      );
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
