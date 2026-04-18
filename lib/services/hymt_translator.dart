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

  /// 构建 HY-MT prompt
  String _buildPrompt(String text, String srcLang, String tgtLang) {
    final targetName = _langDisplayName(tgtLang);

    if (srcLang == 'zh' || tgtLang == 'zh') {
      return '将以下文本翻译为$targetName，注意只需要输出翻译后的结果，不要额外解释：\n\n$text';
    } else {
      return 'Translate the following segment into $targetName, without additional explanation.\n\n$text';
    }
  }

  /// 构建带 chat template 的完整 prompt
  String _buildFullPrompt(String text, String srcLang, String tgtLang) {
    final userContent = _buildPrompt(text, srcLang, tgtLang);
    return '<｜hy_begin\u2581of\u2581sentence｜><｜hy_User｜>$userContent<｜hy_Assistant｜>';
  }

  /// 翻译文本 (使用流式生成，支持中途取消)
  Future<String> translate(String text, String srcLang, String tgtLang) async {
    if (!_isReady || _llama == null) {
      throw StateError('HY-MT 翻译引擎未初始化');
    }

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

      // ⚠️ 关键修复: 先订阅 EventChannel，再调用 MethodChannel
      // flutter_llama 1.1.2 的 generateStream() 存在竞态条件:
      //   它先 invokeMethod('generateStream') 再 receiveBroadcastStream()
      //   导致 native 端 eventSink 为 null → NO_EVENT_SINK 错误
      //
      // 正确顺序:
      //   1. receiveBroadcastStream() → 触发 native onListen → eventSink 就绪
      //   2. invokeMethod('generateStream') → native 通过 eventSink 发送 token

      final completer = Completer<void>();
      StreamSubscription<dynamic>? subscription;

      // Step 1: 先订阅 EventChannel
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
          if (!completer.isCompleted) completer.complete();
        },
        onError: (dynamic error) {
          debugPrint('[HymtTranslator] EventChannel 错误: $error');
          if (!completer.isCompleted) completer.complete();
        },
      );

      // Step 2: 等一帧确保 onListen 已触发
      await Future<void>.delayed(Duration.zero);

      // Step 3: 调用 MethodChannel 发起推理
      // 注意: native 端 result.success 在推理全部完成后才回调,
      // 所以不 await invokeMethod (否则会阻塞到推理结束才继续)。
      // token 通过 EventChannel 实时推送, 用 completer 等 onDone 即可。
      _channel.invokeMethod<void>('generateStream', paramsMap).catchError((e) {
        debugPrint('[HymtTranslator] generateStream MethodChannel 错误: $e');
        if (!completer.isCompleted) completer.complete();
      });

      // Step 4: 等待 EventChannel 流结束 (onDone / onError)
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

    return result.isEmpty ? text : result;
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

  /// 语言代码到显示名称
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
