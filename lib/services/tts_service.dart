import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// TTS 语音合成服务
/// 使用系统 TTS 引擎 (flutter_tts)
class TtsService {
  final FlutterTts _flutterTts = FlutterTts();
  bool _isInitialized = false;

  /// 语言代码到 TTS locale 的映射
  static const Map<String, String> _ttsLocaleMap = {
    'zh': 'zh-CN',
    'en': 'en-US',
    'ja': 'ja-JP',
    'ko': 'ko-KR',
    'fr': 'fr-FR',
    'de': 'de-DE',
    'ru': 'ru-RU',
    'es': 'es-ES',
    'it': 'it-IT',
  };

  /// 初始化 TTS 引擎
  Future<void> initialize() async {
    if (_isInitialized) return;

    await _flutterTts.setVolume(1.0);
    await _flutterTts.setSpeechRate(0.5);
    await _flutterTts.setPitch(1.0);

    _flutterTts.setStartHandler(() {
      debugPrint('[TtsService] TTS 播放开始');
    });

    _flutterTts.setCompletionHandler(() {
      debugPrint('[TtsService] TTS 播放完成');
    });

    _flutterTts.setErrorHandler((msg) {
      debugPrint('[TtsService] TTS 错误: $msg');
    });

    _isInitialized = true;
    debugPrint('[TtsService] TTS 初始化完成');
  }

  /// 朗读文本
  ///
  /// [text] 要朗读的文本
  /// [languageCode] 短语言代码 (例如 "zh", "en")
  Future<void> speak(String text, String languageCode) async {
    if (!_isInitialized) {
      await initialize();
    }

    // 设置语言
    final locale = _ttsLocaleMap[languageCode] ?? 'en-US';
    final result = await _flutterTts.setLanguage(locale);
    if (result != 1) {
      debugPrint('[TtsService] 设置语言失败: $locale');
    }

    // 开始朗读
    await _flutterTts.speak(text);
  }

  /// 停止朗读
  Future<void> stop() async {
    await _flutterTts.stop();
  }

  /// 获取可用的 TTS 语言列表
  Future<List<String>> getAvailableLanguages() async {
    final languages = await _flutterTts.getLanguages;
    return List<String>.from(languages ?? []);
  }

  /// 释放资源
  void dispose() {
    _flutterTts.stop();
  }
}
