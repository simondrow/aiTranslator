import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_llama/flutter_llama.dart';

/// HY-MT1.5-1.8B 翻译器
/// 基于 llama.cpp (flutter_llama) 运行 GGUF 量化模型实现离线翻译。
///
/// 关键优化:
///   - 使用 [generateStream] 逐 token 生成，支持中途取消
///   - [stopGeneration] 可立即中断正在进行的推理，释放 CPU 资源
///   - 完整的 pipeline timing log 用于性能分析
class HymtTranslator {
  FlutterLlama? _llama;
  bool _isReady = false;
  String? _modelPath;

  /// 当前是否正在推理中
  bool _isGenerating = false;

  bool get isReady => _isReady;
  bool get isGenerating => _isGenerating;

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

  /// 翻译文本 (使用流式生成，支持中途取消)
  ///
  /// [srcLang] / [tgtLang] 使用 ISO 短代码 (zh, en, ja, ko)
  ///
  /// Pipeline timing log:
  ///   - T0: 开始构建 prompt
  ///   - T1: prompt 构建完成, 开始推理
  ///   - T2: 首 token 到达 (TTFT — Time To First Token)
  ///   - T3: 生成完成 (Total)
  Future<String> translate(String text, String srcLang, String tgtLang) async {
    if (!_isReady || _llama == null) {
      throw StateError('HY-MT 翻译引擎未初始化');
    }

    final totalSw = Stopwatch()..start();

    // T0: 构建 prompt
    final prompt = _buildFullPrompt(text, srcLang, tgtLang);
    final promptMs = totalSw.elapsedMilliseconds;

    final params = GenerationParams(
      prompt: prompt,
      temperature: 0.7,
      topP: 0.6,
      topK: 20,
      maxTokens: 512,
      repeatPenalty: 1.05,
      stopSequences: [
        '<｜hy_place\u2581holder\u2581no\u25812｜>', // EOS token
        '<｜hy_User｜>', // Prevent continuation
      ],
    );

    // T1: 开始推理
    _isGenerating = true;
    final buffer = StringBuffer();
    int tokenCount = 0;
    int ttftMs = -1;

    try {
      debugPrint(
        '[HymtTranslator] 推理开始 | prompt构建=${promptMs}ms | '
        '源文="${text.length > 40 ? '${text.substring(0, 40)}...' : text}"',
      );

      final stream = _llama!.generateStream(params);

      await for (final token in stream) {
        if (!_isGenerating) {
          // 推理被中断 (stopGeneration 已调用)
          debugPrint(
            '[HymtTranslator] 推理被中断 | 已生成$tokenCount 个token | '
            '耗时${totalSw.elapsedMilliseconds}ms',
          );
          break;
        }

        tokenCount++;
        buffer.write(token);

        // T2: 首 token
        if (tokenCount == 1) {
          ttftMs = totalSw.elapsedMilliseconds;
          debugPrint('[HymtTranslator] TTFT=${ttftMs}ms (首token到达)');
        }
      }
    } catch (e) {
      debugPrint('[HymtTranslator] 推理异常: $e');
      // 如果是因为 stopGeneration 导致的异常，不 rethrow
      if (_isGenerating) rethrow;
    } finally {
      _isGenerating = false;
    }

    totalSw.stop();
    final totalMs = totalSw.elapsedMilliseconds;
    final inferMs = totalMs - promptMs;
    final tokPerSec = tokenCount > 0 && inferMs > 0
        ? (tokenCount * 1000 / inferMs).toStringAsFixed(1)
        : '0';

    final result = _cleanOutput(buffer.toString());

    debugPrint(
      '[HymtTranslator] 推理完成 | 总耗时=${totalMs}ms | '
      'TTFT=${ttftMs}ms | 推理=${inferMs}ms | '
      '${tokenCount}tokens | ${tokPerSec}tok/s | '
      '"$text" → "$result"',
    );

    return result.isEmpty ? text : result;
  }

  /// 中断正在进行的推理
  ///
  /// 调用后 [generateStream] 将尽快停止产出 token，
  /// 已在 native 层排队的计算会被中止。
  Future<void> stopGeneration() async {
    if (!_isGenerating || _llama == null) return;

    debugPrint('[HymtTranslator] 请求中断推理');
    _isGenerating = false;
    try {
      await _llama!.stopGeneration();
      debugPrint('[HymtTranslator] 推理中断完成');
    } catch (e) {
      debugPrint('[HymtTranslator] 中断推理异常 (可忽略): $e');
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
    };
    return map[code] ?? code;
  }

  /// 释放资源
  Future<void> dispose() async {
    if (_isGenerating) {
      await stopGeneration();
    }
    if (_llama != null && _isReady) {
      try {
        await _llama!.unloadModel();
      } catch (_) {}
    }
    _isReady = false;
    _modelPath = null;
  }
}
