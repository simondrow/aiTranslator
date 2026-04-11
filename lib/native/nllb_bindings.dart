import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

// ============================================================
// NLLB (CTranslate2) FFI 绑定
// 绑定 native/bridge/nllb_bridge.c 中暴露的简化 C API
//
// 注意: CTranslate2 本身是 C++ 库，nllb_bridge.c 是对其进行
// C 封装的桥接层，以便 dart:ffi 调用。
// ============================================================

// ---- Native 类型定义 ----

/// 不透明句柄类型
final class AINllbContext extends Opaque {}

// ---- Native 函数类型定义 ----

typedef AINllbInitNative = Pointer<AINllbContext> Function(
    Pointer<Utf8> modelPath);
typedef AINllbInit = Pointer<AINllbContext> Function(
    Pointer<Utf8> modelPath);

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

/// NLLB FFI 绑定封装
class NllbBindings {
  late final DynamicLibrary _lib;
  Pointer<AINllbContext>? _ctx;

  late final AINllbInit _initFn;
  late final AINllbTranslate _translateFn;
  late final AINllbFree _freeFn;
  late final AINllbFreeString _freeStringFn;

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
        .lookup<NativeFunction<AINllbFreeStringNative>>(
            'ai_nllb_free_string')
        .asFunction<AINllbFreeString>();
  }

  /// 加载动态库
  static DynamicLibrary _loadLibrary() {
    if (Platform.isAndroid) {
      return DynamicLibrary.open('libai_nllb.so');
    } else if (Platform.isIOS || Platform.isMacOS) {
      return DynamicLibrary.process();
    } else if (Platform.isLinux) {
      return DynamicLibrary.open('libai_nllb.so');
    } else if (Platform.isWindows) {
      return DynamicLibrary.open('ai_nllb.dll');
    }
    throw UnsupportedError('不支持的平台: ${Platform.operatingSystem}');
  }

  /// 初始化 NLLB 模型
  void init(String modelPath) {
    final pathPtr = modelPath.toNativeUtf8();
    try {
      _ctx = _initFn(pathPtr);
      if (_ctx == null || _ctx == nullptr) {
        throw Exception('NLLB 模型初始化失败: $modelPath');
      }
    } finally {
      calloc.free(pathPtr);
    }
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
