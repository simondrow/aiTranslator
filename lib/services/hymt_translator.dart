import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_llama/flutter_llama.dart';

/// HY-MT1.5-1.8B 翻译器
/// 基于 llama.cpp (flutter_llama) 运行 GGUF 量化模型实现离线翻译。
/// 无需额外 Isolate — flutter_llama 原生异步执行推理。
class HymtTranslator {
  FlutterLlama? _llama;
  bool _isReady = false;
  String? _modelPath;

  bool get isReady => _isReady;

  /// 初始化 HY-MT 模型
  /// [ggufPath] 指向 .gguf 文件的完整路径
  Future<void> initialize(String ggufPath) async {
    if (_isReady && _modelPath == ggufPath) return;

    if (!File(ggufPath).existsSync()) {
      debugPrint('[HymtTranslator] 模型文件不存在: $ggufPath');
      return;
    }

    try {
      _llama = FlutterLlama.instance;

      final config = LlamaConfig(
        modelPath: ggufPath,
        nThreads: 4,
        nGpuLayers: 0, // CPU only (Vulkan disabled for cross-compilation)
        contextSize: 1024, // Translation needs short context
        batchSize: 512,
        useGpu: false, // CPU + ARM NEON
        verbose: false,
      );

      debugPrint('[HymtTranslator] 加载模型: $ggufPath');
      final ok = await _llama!.loadModel(config);

      if (ok) {
        _isReady = true;
        _modelPath = ggufPath;
        debugPrint('[HymtTranslator] ✅ 模型加载成功');
      } else {
        debugPrint('[HymtTranslator] ❌ 模型加载失败');
      }
    } catch (e, st) {
      debugPrint('[HymtTranslator] 初始化失败: $e');
      debugPrint('[HymtTranslator] $st');
      _isReady = false;
    }
  }

  /// 构建 HY-MT prompt
  /// 中文相关翻译用中文 prompt，其余用英文 prompt
  String _buildPrompt(String text, String srcLang, String tgtLang) {
    final targetName = _langDisplayName(tgtLang);

    if (srcLang == 'zh' || tgtLang == 'zh') {
      // ZH<=>XX prompt template (official)
      return '将以下文本翻译为$targetName，注意只需要输出翻译后的结果，不要额外解释：\n\n$text';
    } else {
      // XX<=>XX prompt template (official)
      return 'Translate the following segment into $targetName, without additional explanation.\n\n$text';
    }
  }

  /// 构建带 chat template 的完整 prompt
  String _buildFullPrompt(String text, String srcLang, String tgtLang) {
    final userContent = _buildPrompt(text, srcLang, tgtLang);
    // HY-MT chat template:
    // <｜hy_begin▁of▁sentence｜><｜hy_User｜>{content}<｜hy_Assistant｜>
    return '<｜hy_begin\u2581of\u2581sentence｜><｜hy_User｜>$userContent<｜hy_Assistant｜>';
  }

  /// 翻译文本
  /// [srcLang] / [tgtLang] 使用 ISO 短代码 (zh, en, ja, ko, fr, de, ...)
  Future<String> translate(String text, String srcLang, String tgtLang) async {
    if (!_isReady || _llama == null) {
      throw StateError('HY-MT 翻译引擎未初始化');
    }

    final stopwatch = Stopwatch()..start();
    final prompt = _buildFullPrompt(text, srcLang, tgtLang);

    try {
      final params = GenerationParams(
        prompt: prompt,
        temperature: 0.7,
        topP: 0.6,
        topK: 20,
        maxTokens: 512,
        repeatPenalty: 1.05,
        stopSequences: [
          '<｜hy_place\u2581holder\u2581no\u25812｜>',   // EOS token
          '<｜hy_User｜>',                                // Prevent continuation
        ],
      );

      final response = await _llama!.generate(params);
      stopwatch.stop();

      final result = _cleanOutput(response.text);
      debugPrint('[HymtTranslator] 翻译完成 (${stopwatch.elapsedMilliseconds}ms, '
          '${response.tokensGenerated} tokens, '
          '${response.tokensPerSecond.toStringAsFixed(1)} tok/s): '
          '"$text" -> "$result"');

      return result.isEmpty ? text : result;
    } catch (e) {
      debugPrint('[HymtTranslator] 翻译失败: $e');
      rethrow;
    }
  }

  /// 清理模型输出
  String _cleanOutput(String raw) {
    var text = raw.trim();
    // Remove any stray special tokens
    text = text.replaceAll(RegExp(r'<｜[^｜]*｜>'), '').trim();
    // Remove leading/trailing quotes if present
    if ((text.startsWith('"') && text.endsWith('"')) ||
        (text.startsWith("'") && text.endsWith("'"))) {
      text = text.substring(1, text.length - 1).trim();
    }
    return text;
  }

  /// 语言代码到显示名称 (用于 prompt)
  String _langDisplayName(String code) {
    const map = {
      'zh': '中文',
      'en': 'English',
      'ja': '日本語',
      'ko': '한국어',
      'fr': 'French',
      'de': 'German',
      'ru': 'Russian',
      'es': 'Spanish',
      'it': 'Italian',
      'th': 'Thai',
      'vi': 'Vietnamese',
      'pt': 'Portuguese',
      'ar': 'Arabic',
      'tr': 'Turkish',
      'ms': 'Malay',
      'id': 'Indonesian',
    };
    return map[code] ?? code;
  }

  /// 释放资源
  Future<void> dispose() async {
    if (_llama != null && _isReady) {
      try {
        await _llama!.unloadModel();
      } catch (_) {}
    }
    _isReady = false;
    _modelPath = null;
  }
}
