import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

// ============================================================
// fastText FFI 绑定
// 绑定 native/bridge/fasttext_bridge.cpp 中暴露的简化 C API
// ============================================================

/// fastText 预测结果
class FastTextPrediction {
  final String label;
  final double confidence;

  const FastTextPrediction({required this.label, required this.confidence});
}

// ---- Native 类型定义 ----

final class AIFastTextContext extends Opaque {}

final class AIFastTextResultNative extends Struct {
  external Pointer<Utf8> lang;

  @Float()
  external double confidence;
}

// ---- Native 函数类型定义 ----

typedef AIFastTextInitNative = Pointer<AIFastTextContext> Function(
    Pointer<Utf8> modelPath);
typedef AIFastTextInit = Pointer<AIFastTextContext> Function(
    Pointer<Utf8> modelPath);

typedef AIFastTextPredictNative = AIFastTextResultNative Function(
    Pointer<AIFastTextContext> ctx, Pointer<Utf8> text);
typedef AIFastTextPredict = AIFastTextResultNative Function(
    Pointer<AIFastTextContext> ctx, Pointer<Utf8> text);

typedef AIFastTextFreeNative = Void Function(Pointer<AIFastTextContext> ctx);
typedef AIFastTextFree = void Function(Pointer<AIFastTextContext> ctx);

/// FastText FFI 绑定封装
class FastTextBindings {
  late final DynamicLibrary _lib;
  Pointer<AIFastTextContext>? _ctx;

  late final AIFastTextInit _initFn;
  late final AIFastTextPredict _predictFn;
  late final AIFastTextFree _freeFn;

  FastTextBindings() {
    _lib = _loadLibrary();
    _initFn = _lib
        .lookup<NativeFunction<AIFastTextInitNative>>('ai_fasttext_init')
        .asFunction<AIFastTextInit>();
    _predictFn = _lib
        .lookup<NativeFunction<AIFastTextPredictNative>>(
            'ai_fasttext_predict')
        .asFunction<AIFastTextPredict>();
    _freeFn = _lib
        .lookup<NativeFunction<AIFastTextFreeNative>>('ai_fasttext_free')
        .asFunction<AIFastTextFree>();
  }

  /// 加载动态库
  static DynamicLibrary _loadLibrary() {
    if (Platform.isAndroid) {
      return DynamicLibrary.open('libai_fasttext.so');
    } else if (Platform.isIOS || Platform.isMacOS) {
      // iOS: 符号通过 -force_load 静态链接到 Runner
      // 先尝试 process()（release mode），再 fallback 到 executable()
      try {
        final lib = DynamicLibrary.process();
        lib.lookup('ai_fasttext_init'); // probe
        return lib;
      } catch (_) {
        try {
          final lib = DynamicLibrary.executable();
          lib.lookup('ai_fasttext_init'); // probe
          return lib;
        } catch (_) {
          // 最终尝试打开 Runner.debug.dylib（debug mode hot-reload）
          return DynamicLibrary.open('Runner.debug.dylib');
        }
      }
    } else if (Platform.isLinux) {
      return DynamicLibrary.open('libai_fasttext.so');
    } else if (Platform.isWindows) {
      return DynamicLibrary.open('ai_fasttext.dll');
    }
    throw UnsupportedError('不支持的平台: ${Platform.operatingSystem}');
  }

  /// 初始化 fastText 模型
  void init(String modelPath) {
    final pathPtr = modelPath.toNativeUtf8();
    try {
      _ctx = _initFn(pathPtr);
      if (_ctx == null || _ctx == nullptr) {
        throw Exception('fastText 模型初始化失败: $modelPath');
      }
    } finally {
      calloc.free(pathPtr);
    }
  }

  /// 预测文本语种
  FastTextPrediction predict(String text) {
    if (_ctx == null || _ctx == nullptr) {
      throw StateError('fastText 未初始化');
    }

    final textPtr = text.toNativeUtf8();
    try {
      final result = _predictFn(_ctx!, textPtr);
      final label = result.lang.toDartString();
      final confidence = result.confidence;
      return FastTextPrediction(label: label, confidence: confidence);
    } finally {
      calloc.free(textPtr);
    }
  }

  /// 释放资源
  void free() {
    if (_ctx != null && _ctx != nullptr) {
      _freeFn(_ctx!);
      _ctx = null;
    }
  }
}
