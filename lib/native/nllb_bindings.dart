import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

// ============================================================
// NLLB (CTranslate2) FFI 绑定
// 绑定 native/bridge/nllb_bridge.cpp 中暴露的 C API
//
// API:
//   ai_nllb_init(model_dir, sp_model_path) → ctx
//   ai_nllb_translate(ctx, text, src_lang, tgt_lang) → char*
//   ai_nllb_free_string(char*)
//   ai_nllb_free(ctx)
//   ai_nllb_is_ready(ctx) → int
// ============================================================

// ---- Native 类型定义 ----

/// 不透明句柄类型
final class AINllbContext extends Opaque {}

// ---- Native 函数类型定义 ----

// ai_nllb_init(const char* model_dir, const char* sp_model_path)
typedef AINllbInitNative = Pointer<AINllbContext> Function(
    Pointer<Utf8> modelDir, Pointer<Utf8> spModelPath);
typedef AINllbInit = Pointer<AINllbContext> Function(
    Pointer<Utf8> modelDir, Pointer<Utf8> spModelPath);

// ai_nllb_translate(ctx, text, src_lang, tgt_lang)
typedef AINllbTranslateNative = Pointer<Utf8> Function(
  Pointer<AINllbContext> ctx,
  Pointer<Utf8> text,
  Pointer<Utf8> srcLang,
  Pointer<Utf8> tgtLang,
);
typedef AINllbTranslate = Pointer<Utf8> Function(
  Pointer<AINllbContext> ctx,
  Pointer<Utf8> text,
  Pointer<Utf8> srcLang,
  Pointer<Utf8> tgtLang,
);

typedef AINllbFreeNative = Void Function(Pointer<AINllbContext> ctx);
typedef AINllbFree = void Function(Pointer<AINllbContext> ctx);

typedef AINllbFreeStringNative = Void Function(Pointer<Utf8> str);
typedef AINllbFreeString = void Function(Pointer<Utf8> str);

typedef AINllbIsReadyNative = Int32 Function(Pointer<AINllbContext> ctx);
typedef AINllbIsReady = int Function(Pointer<AINllbContext> ctx);

/// NLLB FFI 绑定封装
class NllbBindings {
  late final DynamicLibrary _lib;
  Pointer<AINllbContext>? _ctx;

  late final AINllbInit _initFn;
  late final AINllbTranslate _translateFn;
  late final AINllbFree _freeFn;
  late final AINllbFreeString _freeStringFn;
  late final AINllbIsReady _isReadyFn;

  NllbBindings() {
    _lib = _loadLibrary();
    _initFn = _lib
        .lookup<NativeFunction<AINllbInitNative>>('ai_nllb_init')
        .asFunction<AINllbInit>();
    _translateFn = _lib
        .lookup<NativeFunction<AINllbTranslateNative>>('ai_nllb_translate')
        .asFunction<AINllbTranslate>();
    _freeFn = _lib
        .lookup<NativeFunction<AINllbFreeNative>>('ai_nllb_free')
        .asFunction<AINllbFree>();
    _freeStringFn = _lib
        .lookup<NativeFunction<AINllbFreeStringNative>>('ai_nllb_free_string')
        .asFunction<AINllbFreeString>();
    _isReadyFn = _lib
        .lookup<NativeFunction<AINllbIsReadyNative>>('ai_nllb_is_ready')
        .asFunction<AINllbIsReady>();
  }

  /// 加载动态库 — 三级 iOS fallback (与 fastText 同模式)
  static DynamicLibrary _loadLibrary() {
    if (Platform.isAndroid) {
      return DynamicLibrary.open('libai_nllb.so');
    } else if (Platform.isIOS || Platform.isMacOS) {
      // Level 1: DynamicLibrary.process() — symbols linked into main binary
      try {
        final lib = DynamicLibrary.process();
        lib.lookup('ai_nllb_init'); // probe
        return lib;
      } catch (_) {
        debugPrint('[NllbBindings] process() lookup failed, trying executable()');
      }
      // Level 2: DynamicLibrary.executable()
      try {
        final lib = DynamicLibrary.executable();
        lib.lookup('ai_nllb_init'); // probe
        return lib;
      } catch (_) {
        debugPrint('[NllbBindings] executable() lookup failed, trying Runner.debug.dylib');
      }
      // Level 3: Flutter debug dylib
      return DynamicLibrary.open('Runner.debug.dylib');
    } else if (Platform.isLinux) {
      return DynamicLibrary.open('libai_nllb.so');
    } else if (Platform.isWindows) {
      return DynamicLibrary.open('ai_nllb.dll');
    }
    throw UnsupportedError('不支持的平台: ${Platform.operatingSystem}');
  }

  /// 初始化 NLLB 模型
  /// [modelDir] CTranslate2 模型目录 (包含 model.bin 等)
  /// [spModelPath] sentencepiece.bpe.model 路径
  void init(String modelDir, String spModelPath) {
    final dirPtr = modelDir.toNativeUtf8();
    final spPtr = spModelPath.toNativeUtf8();
    try {
      _ctx = _initFn(dirPtr, spPtr);
      if (_ctx == null || _ctx == nullptr) {
        throw Exception('NLLB 模型初始化失败: $modelDir');
      }
    } finally {
      calloc.free(dirPtr);
      calloc.free(spPtr);
    }
  }

  /// 检查引擎是否真正就绪 (非 stub 模式)
  bool get isReady {
    if (_ctx == null || _ctx == nullptr) return false;
    return _isReadyFn(_ctx!) != 0;
  }

  /// 翻译文本
  ///
  /// [text] 待翻译文本
  /// [srcLang] 源语言 NLLB 代码 (例如 "zho_Hans")
  /// [tgtLang] 目标语言 NLLB 代码 (例如 "eng_Latn")
  String translate(String text, String srcLang, String tgtLang) {
    if (_ctx == null || _ctx == nullptr) {
      throw StateError('NLLB 未初始化');
    }

    final textPtr = text.toNativeUtf8();
    final srcPtr = srcLang.toNativeUtf8();
    final tgtPtr = tgtLang.toNativeUtf8();

    try {
      final resultPtr = _translateFn(_ctx!, textPtr, srcPtr, tgtPtr);
      if (resultPtr == nullptr) {
        throw Exception('NLLB 翻译返回空结果');
      }

      final result = resultPtr.toDartString();
      _freeStringFn(resultPtr); // 释放 native 分配的字符串
      return result;
    } finally {
      calloc.free(textPtr);
      calloc.free(srcPtr);
      calloc.free(tgtPtr);
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
