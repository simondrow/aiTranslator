import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/message.dart';
import '../../../services/asr_service.dart';
import '../../../services/translation_service.dart';
import '../../../services/language_detect_service.dart';
import '../../../utils/language_codes.dart';

/// 对话状态
class ConversationState {
  final List<Message> messages;
  final String myLanguage;
  final String theirLanguage;
  final bool isProcessing;

  /// 实时翻译相关状态
  final String? detectedSourceLang;
  final String? detectedTargetLang;
  final String realtimeTranslation;
  final bool isDetecting;
  final bool isTranslating;

  const ConversationState({
    this.messages = const [],
    this.myLanguage = 'zh',
    this.theirLanguage = 'en',
    this.isProcessing = false,
    this.detectedSourceLang,
    this.detectedTargetLang,
    this.realtimeTranslation = '',
    this.isDetecting = false,
    this.isTranslating = false,
  });

  ConversationState copyWith({
    List<Message>? messages,
    String? myLanguage,
    String? theirLanguage,
    bool? isProcessing,
    String? detectedSourceLang,
    String? detectedTargetLang,
    String? realtimeTranslation,
    bool? isDetecting,
    bool? isTranslating,
  }) {
    return ConversationState(
      messages: messages ?? this.messages,
      myLanguage: myLanguage ?? this.myLanguage,
      theirLanguage: theirLanguage ?? this.theirLanguage,
      isProcessing: isProcessing ?? this.isProcessing,
      detectedSourceLang: detectedSourceLang ?? this.detectedSourceLang,
      detectedTargetLang: detectedTargetLang ?? this.detectedTargetLang,
      realtimeTranslation: realtimeTranslation ?? this.realtimeTranslation,
      isDetecting: isDetecting ?? this.isDetecting,
      isTranslating: isTranslating ?? this.isTranslating,
    );
  }

  /// 清空检测/翻译状态
  ConversationState clearRealtime() {
    return ConversationState(
      messages: messages,
      myLanguage: myLanguage,
      theirLanguage: theirLanguage,
      isProcessing: false,
    );
  }
}

/// 对话状态管理器
class ConversationNotifier extends StateNotifier<ConversationState> {
  final AsrService _asrService;
  final TranslationService _translationService;
  final LanguageDetectService _languageDetectService;

  ConversationNotifier({
    required AsrService asrService,
    required TranslationService translationService,
    required LanguageDetectService languageDetectService,
  })  : _asrService = asrService,
        _translationService = translationService,
        _languageDetectService = languageDetectService,
        super(const ConversationState()) {
    _initLanguageDetect();
  }

  /// 初始化语种检测（从 assets 复制模型并加载）
  Future<void> _initLanguageDetect() async {
    try {
      await _languageDetectService.initialize();
      debugPrint('[ConversationNotifier] 语种检测服务初始化完成');
    } catch (e) {
      debugPrint('[ConversationNotifier] 语种检测初始化失败: $e');
      debugPrint('[ConversationNotifier] 将使用后备检测逻辑');
    }
  }

  void setMyLanguage(String langCode) {
    state = state.copyWith(myLanguage: langCode);
  }

  void setTheirLanguage(String langCode) {
    state = state.copyWith(theirLanguage: langCode);
  }

  /// 检测语种并确定翻译方向
  /// 限制结果为 myLanguage / theirLanguage 二选一
  ({String source, String target}) _detectDirection(String text) {
    final detectResult = _languageDetectService.detectLanguage(text);
    final rawLang = detectResult.languageCode;

    if (_matchesLanguage(rawLang, state.theirLanguage)) {
      return (source: state.theirLanguage, target: state.myLanguage);
    }
    // 默认: 识别为 myLanguage（包括无法识别时）
    return (source: state.myLanguage, target: state.theirLanguage);
  }

  /// 实时语种检测 + 翻译（边输入边调用）
  Future<void> detectAndTranslate(String text) async {
    if (text.trim().isEmpty) {
      if (mounted) state = state.clearRealtime();
      return;
    }

    if (mounted) state = state.copyWith(isDetecting: true);

    try {
      final dir = _detectDirection(text);

      if (!mounted) return;
      state = state.copyWith(
        detectedSourceLang: dir.source,
        detectedTargetLang: dir.target,
        isDetecting: false,
        isTranslating: true,
      );

      final translated = await _translationService.translate(
        text,
        LanguageCodes.getNllbCode(dir.source),
        LanguageCodes.getNllbCode(dir.target),
      );

      if (!mounted) return;
      state = state.copyWith(
        realtimeTranslation: translated,
        isTranslating: false,
      );
    } catch (e) {
      debugPrint('[ConversationNotifier] 实时检测翻译失败: $e');
      if (mounted) {
        state = state.copyWith(isDetecting: false, isTranslating: false);
      }
    }
  }

  /// 清除实时翻译状态
  void clearRealtime() {
    if (mounted) state = state.clearRealtime();
  }

  /// 完成输入 — 将当前实时翻译结果保存为消息
  void commitTranslation(String originalText) {
    if (originalText.trim().isEmpty) return;
    if (state.realtimeTranslation.isEmpty) return;

    final message = Message(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      originalText: originalText,
      translatedText: state.realtimeTranslation,
      sourceLanguage: state.detectedSourceLang ?? state.myLanguage,
      targetLanguage: state.detectedTargetLang ?? state.theirLanguage,
      isFromMe: state.detectedSourceLang == state.myLanguage,
      timestamp: DateTime.now(),
      inputType: InputType.text,
    );

    state = state.copyWith(
      messages: [...state.messages, message],
    );
  }

  /// 发送文本消息（完整流程: 检测 → 翻译 → 保存）
  Future<void> sendTextMessage(String text) async {
    if (text.trim().isEmpty) return;

    state = state.copyWith(isProcessing: true);

    try {
      final dir = _detectDirection(text);

      final translated = await _translationService.translate(
        text,
        LanguageCodes.getNllbCode(dir.source),
        LanguageCodes.getNllbCode(dir.target),
      );

      final message = Message(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        originalText: text,
        translatedText: translated,
        sourceLanguage: dir.source,
        targetLanguage: dir.target,
        isFromMe: dir.source == state.myLanguage,
        timestamp: DateTime.now(),
        inputType: InputType.text,
      );

      state = state.copyWith(
        messages: [...state.messages, message],
        isProcessing: false,
        detectedSourceLang: dir.source,
        detectedTargetLang: dir.target,
        realtimeTranslation: translated,
      );
    } catch (e) {
      state = state.copyWith(isProcessing: false);
      debugPrint('[ConversationNotifier] sendTextMessage 失败: $e');
    }
  }

  /// 发送语音消息
  Future<void> sendVoiceMessage(String audioPath) async {
    state = state.copyWith(isProcessing: true);

    try {
      final asrResult = await _asrService.transcribe(audioPath);
      final String text = asrResult.text;

      if (text.trim().isEmpty) {
        state = state.copyWith(isProcessing: false);
        return;
      }

      final dir = _detectDirection(text);

      final translated = await _translationService.translate(
        text,
        LanguageCodes.getNllbCode(dir.source),
        LanguageCodes.getNllbCode(dir.target),
      );

      final message = Message(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        originalText: text,
        translatedText: translated,
        sourceLanguage: dir.source,
        targetLanguage: dir.target,
        isFromMe: dir.source == state.myLanguage,
        timestamp: DateTime.now(),
        inputType: InputType.voice,
      );

      state = state.copyWith(
        messages: [...state.messages, message],
        isProcessing: false,
        detectedSourceLang: dir.source,
        detectedTargetLang: dir.target,
        realtimeTranslation: translated,
      );
    } catch (e) {
      state = state.copyWith(isProcessing: false);
      debugPrint('[ConversationNotifier] sendVoiceMessage 失败: $e');
    }
  }

  void clearMessages() {
    state = state.copyWith(messages: []);
  }

  bool _matchesLanguage(String detected, String target) {
    if (detected == target) return true;
    if (detected.startsWith(target)) return true;
    if (target.startsWith(detected)) return true;
    return false;
  }
}

/// Providers
final asrServiceProvider = Provider<AsrService>((ref) {
  return AsrService();
});

final translationServiceProvider = Provider<TranslationService>((ref) {
  return TranslationService();
});

final languageDetectServiceProvider = Provider<LanguageDetectService>((ref) {
  final service = LanguageDetectService();
  ref.onDispose(() => service.dispose());
  return service;
});

final conversationProvider =
    StateNotifierProvider<ConversationNotifier, ConversationState>((ref) {
  return ConversationNotifier(
    asrService: ref.watch(asrServiceProvider),
    translationService: ref.watch(translationServiceProvider),
    languageDetectService: ref.watch(languageDetectServiceProvider),
  );
});
