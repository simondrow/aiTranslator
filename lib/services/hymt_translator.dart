import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_llama/flutter_llama.dart';

/// HY-MT1.5-1.8B 翻译器
/// 基于 llama.cpp (flutter_llama) 运行 GGUF 量化模型实现离线翻译。
///
/// 关键优化:
///   - 使用 [generateStream] 逐 token 生成，支持中途取消
///   - [stopGeneration] 可立即中断正在进行的推理，释放 CPU 资源
///   - 完整的 pipeline timing log 用于性能分析
///
/// ⚠️ 绕过 FlutterLlama.generateStream() 的竞态 bug:
///   flutter_llama 1.1.2 的 generateStream() 先调用 MethodChannel
///   再订阅 EventChannel，导致 native 端 eventSink 为 null。
///   本类直接操作底层 channel，确保先订阅再调用。
///
/// ⚠️ EventChannel 残留 endOfStream 问题:
///   stopGeneration 后 native 端通过 mainHandler.post 发送 endOfStream,
///   该事件可能延迟到达，被下一次 receiveBroadcastStream 的 onDone 捕获，
///   导致 Completer 立即完成、0 tokens。
///   解决方案: 使用 MethodChannel 的 result 回调来判断推理是否真正完成,
///   而不是依赖 EventChannel 的 onDone。
class HymtTranslator {
  FlutterLlama? _llama;
  bool _isReady = false;
  String? _modelPath;

  /// 当前是否正在推理中
  bool _isGenerating = false;

  /// 底层 channel (绕过 FlutterLlama.generateStream 的竞态 bug)
  static const MethodChannel _channel = MethodChannel('flutter_llama');
  static const EventChannel _eventChannel =
      EventChannel('flutter_llama/stream');

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
        nGpuLayers: 0,
        contextSize: 1024,
        batchSize: 512,
        useGpu: false,
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

  /// 构建 HY-MT prompt (遵循官方 prompt 模板)
  ///
  /// ZH<=>XX: 中文 prompt + 中文语言名称
  /// XX<=>XX: 英文 prompt + 英文语言名称
  String _buildPrompt(String text, String srcLang, String tgtLang) {
    if (srcLang == 'zh' || tgtLang == 'zh') {
      final targetNameCn = _langNameChinese(tgtLang);
      return '将以下文本翻译为$targetNameCn，注意只需要输出翻译后的结果，不要额外解释：\n\n$text';
    } else {
      final targetNameEn = _langNameEnglish(tgtLang);
      return 'Translate the following segment into $targetNameEn, without additional explanation.\n\n$text';
    }
  }

  /// 构建带 chat template 的完整 prompt
  String _buildFullPrompt(String text, String srcLang, String tgtLang) {
    final userContent = _buildPrompt(text, srcLang, tgtLang);
    return '<｜hy_begin\u2581of\u2581sentence｜><｜hy_User｜>$userContent<｜hy_Assistant｜>';
  }

  /// 翻译文本 (使用流式生成，支持中途取消)
  ///
  /// 核心策略:
  ///   1. 先订阅 EventChannel 接收 token
  ///   2. 再调 MethodChannel 发起推理
  ///   3. 用 MethodChannel 的 result 回调判断推理完成 (不依赖 onDone)
  ///   4. stopGeneration 后等待一帧让残留 endOfStream 排掉再开新推理
  Future<String> translate(String text, String srcLang, String tgtLang) async {
    if (!_isReady || _llama == null) {
      throw StateError('HY-MT 翻译引擎未初始化');
    }

    // 等待一帧，让上一次 stopGeneration 的 mainHandler.post(endOfStream)
    // 排出消息队列，避免污染本次 EventChannel 订阅
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final totalSw = Stopwatch()..start();

    final prompt = _buildFullPrompt(text, srcLang, tgtLang);
    final promptMs = totalSw.elapsedMilliseconds;

    final paramsMap = <String, dynamic>{
      'prompt': prompt,
      'temperature': 0.7,
      'topP': 0.6,
      'topK': 20,
      'maxTokens': 512,
      'repeatPenalty': 1.05,
    };

    _isGenerating = true;
    final buffer = StringBuffer();
    int tokenCount = 0;
    int ttftMs = -1;

    try {
      debugPrint(
        '[HymtTranslator] 推理开始 | prompt构建=${promptMs}ms | '
        '源文="${text.length > 40 ? '${text.substring(0, 40)}...' : text}"',
      );

      final completer = Completer<void>();
      StreamSubscription<dynamic>? subscription;

      // Step 1: 先订阅 EventChannel 收集 token
      subscription = _eventChannel.receiveBroadcastStream().listen(
        (dynamic token) {
          if (!_isGenerating) {
            subscription?.cancel();
            if (!completer.isCompleted) completer.complete();
            return;
          }

          if (token is String) {
            tokenCount++;
            buffer.write(token);

            if (tokenCount == 1) {
              ttftMs = totalSw.elapsedMilliseconds;
              debugPrint('[HymtTranslator] TTFT=${ttftMs}ms (首token到达)');
            }
          }
        },
        onDone: () {
          // onDone 可能是残留的 endOfStream，也可能是真正结束
          // 只在 completer 未完成时才 complete
          debugPrint('[HymtTranslator] EventChannel onDone (tokens=$tokenCount)');
          if (!completer.isCompleted) completer.complete();
        },
        onError: (dynamic error) {
          debugPrint('[HymtTranslator] EventChannel 错误: $error');
          if (!completer.isCompleted) completer.complete();
        },
      );

      // Step 2: 等一帧确保 onListen 已触发 (native eventSink 赋值)
      await Future<void>.delayed(Duration.zero);

      // Step 3: 调用 MethodChannel 发起推理
      // MethodChannel 的 result.success(null) 在 native 推理完成后回调
      // 同时设置 completer，这样即使 onDone 丢失也能正确结束
      _channel.invokeMethod<void>('generateStream', paramsMap).then((_) {
        debugPrint('[HymtTranslator] MethodChannel 推理回调完成 (tokens=$tokenCount)');
        // 给 EventChannel 最后的 token 事件一点时间排完
        Future<void>.delayed(const Duration(milliseconds: 20), () {
          if (!completer.isCompleted) completer.complete();
        });
      }).catchError((dynamic e) {
        debugPrint('[HymtTranslator] generateStream MethodChannel 错误: $e');
        if (!completer.isCompleted) completer.complete();
      });

      // Step 4: 等待推理完成 (onDone 或 MethodChannel result，谁先到谁算)
      await completer.future;
      subscription.cancel();
    } catch (e) {
      debugPrint('[HymtTranslator] 推理异常: $e');
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

    // 翻译结果为空时不回退到原文，返回空串让上层处理
    return result;
  }

  /// 中断正在进行的推理
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
    text = text.replaceAll(RegExp(r'<｜[^｜]*｜>'), '').trim();
    if ((text.startsWith('"') && text.endsWith('"')) ||
        (text.startsWith("'") && text.endsWith("'"))) {
      text = text.substring(1, text.length - 1).trim();
    }
    return text;
  }

  /// 语言代码到中文名称 (用于 ZH<=>XX prompt 模板)
  String _langNameChinese(String code) {
    const map = {
      'zh': '中文',
      'en': '英语',
      'ja': '日语',
      'ko': '韩语',
      'fr': '法语',
      'de': '德语',
      'es': '西班牙语',
      'pt': '葡萄牙语',
      'ru': '俄语',
      'ar': '阿拉伯语',
      'th': '泰语',
      'vi': '越南语',
      'it': '意大利语',
      'ms': '马来语',
      'id': '印尼语',
    };
    return map[code] ?? code;
  }

  /// 语言代码到英文名称 (用于 XX<=>XX prompt 模板)
  String _langNameEnglish(String code) {
    const map = {
      'zh': 'Chinese',
      'en': 'English',
      'ja': 'Japanese',
      'ko': 'Korean',
      'fr': 'French',
      'de': 'German',
      'es': 'Spanish',
      'pt': 'Portuguese',
      'ru': 'Russian',
      'ar': 'Arabic',
      'th': 'Thai',
      'vi': 'Vietnamese',
      'it': 'Italian',
      'ms': 'Malay',
      'id': 'Indonesian',
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
