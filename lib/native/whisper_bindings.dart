import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

// ============================================================
// whisper.cpp FFI 绑定
// 绑定 native/bridge/whisper_bridge.c 中暴露的简化 C API
// ============================================================

/// Whisper 转写结果
class WhisperResult {
  final String text;
  final String language;

  const WhisperResult({required this.text, required this.language});
}

// ---- Native 类型定义 ----

/// 不透明句柄类型
final class AIWhisperContext extends Opaque {}

/// 转写结果结构体
final class AIWhisperResultNative extends Struct {
  external Pointer<Utf8> text;
  external Pointer<Utf8> lang;
}

// ---- Native 函数类型定义 ----

typedef AIWhisperInitNative = Pointer<AIWhisperContext> Function(
    Pointer<Utf8> modelPath);
typedef AIWhisperInit = Pointer<AIWhisperContext> Function(
    Pointer<Utf8> modelPath);

typedef AIWhisperTranscribeNative = AIWhisperResultNative Function(
    Pointer<AIWhisperContext> ctx, Pointer<Utf8> audioPath);
typedef AIWhisperTranscribe = AIWhisperResultNative Function(
    Pointer<AIWhisperContext> ctx, Pointer<Utf8> audioPath);

typedef AIWhisperFreeNative = Void Function(
    Pointer<AIWhisperContext> ctx);
typedef AIWhisperFree = void Function(Pointer<AIWhisperContext> ctx);

typedef AIWhisperResultFreeNative = Void Function(
    Pointer<AIWhisperResultNative> result);
typedef AIWhisperResultFree = void Function(
    Pointer<AIWhisperResultNative> result);

/// Whisper FFI 绑定封装
class WhisperBindings {
  late final DynamicLibrary _lib;
  Pointer<AIWhisperContext>? _ctx;

  late final AIWhisperInit _initFn;
  late final AIWhisperTranscribe _transcribeFn;
  late final AIWhisperFree _freeFn;

  WhisperBindings() {
    _lib = _loadLibrary();
    _initFn = _lib
        .lookup<NativeFunction<AIWhisperInitNative>>('ai_whisper_init')
        .asFunction<AIWhisperInit>();
    _transcribeFn = _lib
        .lookup<NativeFunction<AIWhisperTranscribeNative>>(
            'ai_whisper_transcribe')
        .asFunction<AIWhisperTranscribe>();
    _freeFn = _lib
        .lookup<NativeFunction<AIWhisperFreeNative>>('ai_whisper_free')
        .asFunction<AIWhisperFree>();
  }

  /// 加载动态库
  static DynamicLibrary _loadLibrary() {
    if (Platform.isAndroid) {
      return DynamicLibrary.open('libai_whisper.so');
    } else if (Platform.isIOS || Platform.isMacOS) {
      return DynamicLibrary.process();
    } else if (Platform.isLinux) {
      return DynamicLibrary.open('libai_whisper.so');
    } else if (Platform.isWindows) {
      return DynamicLibrary.open('ai_whisper.dll');
    }
    throw UnsupportedError('不支持的平台: ${Platform.operatingSystem}');
  }

  /// 初始化 whisper 模型
  void init(String modelPath) {
    final pathPtr = modelPath.toNativeUtf8();
    try {
      _ctx = _initFn(pathPtr);
      if (_ctx == null || _ctx == nullptr) {
        throw Exception('Whisper 模型初始化失败: $modelPath');
      }
    } finally {
      calloc.free(pathPtr);
    }
  }

  /// 转写音频文件
  WhisperResult transcribe(String audioPath) {
    if (_ctx == null || _ctx == nullptr) {
      throw StateError('Whisper 未初始化');
    }

    final audioPathPtr = audioPath.toNativeUtf8();
    try {
      final result = _transcribeFn(_ctx!, audioPathPtr);
      final text = result.text.toDartString();
      final lang = result.lang.toDartString();

      return WhisperResult(text: text, language: lang);
    } finally {
      calloc.free(audioPathPtr);
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
