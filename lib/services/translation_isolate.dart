import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart';

import 'nllb_onnx_translator.dart';

/// Isolate 通信消息类型
class _InitMsg {
  final String modelDir;
  final SendPort replyPort;
  _InitMsg(this.modelDir, this.replyPort);
}

class _TranslateMsg {
  final String text;
  final String srcLang;
  final String tgtLang;
  final SendPort replyPort;
  _TranslateMsg(this.text, this.srcLang, this.tgtLang, this.replyPort);
}

class _DisposeMsg {}

/// 后台 Isolate 翻译服务
/// 在独立 Isolate 中运行 NllbOnnxTranslator，避免阻塞 UI 线程
class TranslationIsolate {
  Isolate? _isolate;
  SendPort? _commandPort;
  bool _isReady = false;

  bool get isReady => _isReady;

  /// 启动后台 Isolate 并初始化模型
  Future<bool> initialize(String modelDir) async {
    if (_isReady && _commandPort != null) return true;

    try {
      final readyPort = ReceivePort();

      _isolate = await Isolate.spawn(
        _workerMain,
        readyPort.sendPort,
      );

      // 等待 worker 就绪，获取其 SendPort
      _commandPort = await readyPort.first as SendPort;
      readyPort.close();

      // 发送初始化请求
      final initReply = ReceivePort();
      _commandPort!.send(_InitMsg(modelDir, initReply.sendPort));
      final ok = await initReply.first;
      initReply.close();

      _isReady = ok == true;
      debugPrint('[TranslationIsolate] 后台 Isolate 初始化${_isReady ? "成功" : "失败"}');
      return _isReady;
    } catch (e) {
      debugPrint('[TranslationIsolate] 启动失败: $e');
      return false;
    }
  }

  /// 在后台 Isolate 中执行翻译（不阻塞 UI）
  Future<String> translate(String text, String srcLang, String tgtLang) async {
    if (!_isReady || _commandPort == null) {
      throw StateError('翻译 Isolate 未初始化');
    }

    final replyPort = ReceivePort();
    _commandPort!.send(_TranslateMsg(text, srcLang, tgtLang, replyPort.sendPort));

    final result = await replyPort.first;
    replyPort.close();

    if (result is String) return result;
    if (result is Map && result['error'] != null) {
      throw Exception(result['error']);
    }
    return text;
  }

  void dispose() {
    try {
      _commandPort?.send(_DisposeMsg());
    } catch (_) {}
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _commandPort = null;
    _isReady = false;
  }

  /// Isolate Worker 入口
  static void _workerMain(SendPort mainPort) {
    final commandPort = ReceivePort();
    mainPort.send(commandPort.sendPort);

    NllbOnnxTranslator? translator;

    commandPort.listen((msg) async {
      if (msg is _InitMsg) {
        try {
          translator = NllbOnnxTranslator();
          await translator!.initialize(msg.modelDir);
          msg.replyPort.send(translator!.isReady);
        } catch (e) {
          debugPrint('[TranslationIsolate Worker] init error: $e');
          msg.replyPort.send(false);
        }
      } else if (msg is _TranslateMsg) {
        try {
          if (translator == null || !translator!.isReady) {
            msg.replyPort.send({'error': '引擎未就绪'});
            return;
          }
          final result = await translator!.translate(
            msg.text, msg.srcLang, msg.tgtLang,
          );
          msg.replyPort.send(result);
        } catch (e) {
          msg.replyPort.send({'error': e.toString()});
        }
      } else if (msg is _DisposeMsg) {
        translator?.dispose();
        translator = null;
        commandPort.close();
      }
    });
  }
}
