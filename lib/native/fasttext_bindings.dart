import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

// ============================================================
// fastText FFI 绑定
// 绑定 native/bridge/fasttext_bridge.c 中暴露的简化 C API
// 用于文字语种检测
// ============================================================

/// fastText 预测结果
class FastTextPrediction {
  final String label;
  final double confidence;

  const FastTextPrediction({required this.label, required this.confidence});
}

// ---- Native 类型定义 ----

/// 不透明句柄类型
final class AIFastTextContext extends Opaque {}

/// 预测结果结构体
final class AIFastTextResultNative extends Struct {
  external Pointer<Utf8> label;

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

typedef AIFastTextFreeNative = Void Function(
    Pointer<AIFastTextContext> ctx);
typedef AIFastTextFree = void Function(Pointer<AIFastTextContext> ctx);

typedef AIFastTextResultFreeNative = Void Function(
    Pointer<AIFastTextResultNative> result);
typedef AIFastTextResultFree = void Function(
    Pointer<AIFastTextResultNative> result);

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
      return DynamicLibrary.process();
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
  ///
  /// [text] 待检测文本
  /// 返回 [FastTextPrediction] 包含标签 (例如 "__label__zh") 和置信度
  FastTextPrediction predict(String text) {
    if (_ctx == null || _ctx == nullptr) {
      throw StateError('fastText 未初始化');
    }

    final textPtr = text.toNativeUtf8();
    try {
      final result = _predictFn(_ctx!, textPtr);
      final label = result.label.toDartString();
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
