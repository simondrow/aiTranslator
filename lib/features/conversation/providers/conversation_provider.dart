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

  const ConversationState({
    this.messages = const [],
    this.myLanguage = 'zh',
    this.theirLanguage = 'en',
    this.isProcessing = false,
  });

  ConversationState copyWith({
    List<Message>? messages,
    String? myLanguage,
    String? theirLanguage,
    bool? isProcessing,
  }) {
    return ConversationState(
      messages: messages ?? this.messages,
      myLanguage: myLanguage ?? this.myLanguage,
      theirLanguage: theirLanguage ?? this.theirLanguage,
      isProcessing: isProcessing ?? this.isProcessing,
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
        super(const ConversationState());

  /// 设置我的语言
  void setMyLanguage(String langCode) {
    state = state.copyWith(myLanguage: langCode);
  }

  /// 设置对方语言
  void setTheirLanguage(String langCode) {
    state = state.copyWith(theirLanguage: langCode);
  }

  /// 发送文本消息
  /// 流程: 检测语种 → 确定翻译方向 → 翻译 → 生成消息
  Future<void> sendTextMessage(String text) async {
    if (text.trim().isEmpty) return;

    state = state.copyWith(isProcessing: true);

    try {
      // 1. 检测输入语种
      final detectResult = await _languageDetectService.detectLanguage(text);
      final detectedLang = detectResult.languageCode;

      // 2. 确定翻译方向
      final bool isFromMe = _isMyLanguage(detectedLang);
      final String sourceLang = isFromMe ? state.myLanguage : state.theirLanguage;
      final String targetLang = isFromMe ? state.theirLanguage : state.myLanguage;

      // 3. 翻译
      final String translated = await _translationService.translate(
        text,
        LanguageCodes.getNllbCode(sourceLang),
        LanguageCodes.getNllbCode(targetLang),
      );

      // 4. 创建消息并添加到列表
      final message = Message(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        originalText: text,
        translatedText: translated,
        sourceLanguage: sourceLang,
        targetLanguage: targetLang,
        isFromMe: isFromMe,
        timestamp: DateTime.now(),
        inputType: InputType.text,
      );

      state = state.copyWith(
        messages: [...state.messages, message],
        isProcessing: false,
      );
    } catch (e) {
      state = state.copyWith(isProcessing: false);
      rethrow;
    }
  }

  /// 发送语音消息
  /// 流程: ASR → 检测语种 → 翻译 → 生成消息
  Future<void> sendVoiceMessage(String audioPath) async {
    state = state.copyWith(isProcessing: true);

    try {
      // 1. 语音识别
      final asrResult = await _asrService.transcribe(audioPath);
      final String text = asrResult.text;

      if (text.trim().isEmpty) {
        state = state.copyWith(isProcessing: false);
        return;
      }

      // 2. 检测语种 (优先使用 ASR 识别的语言，否则用文本检测)
      String detectedLang = asrResult.detectedLanguage;
      if (detectedLang.isEmpty) {
        final detectResult = await _languageDetectService.detectLanguage(text);
        detectedLang = detectResult.languageCode;
      }

      // 3. 确定翻译方向
      final bool isFromMe = _isMyLanguage(detectedLang);
      final String sourceLang = isFromMe ? state.myLanguage : state.theirLanguage;
      final String targetLang = isFromMe ? state.theirLanguage : state.myLanguage;

      // 4. 翻译
      final String translated = await _translationService.translate(
        text,
        LanguageCodes.getNllbCode(sourceLang),
        LanguageCodes.getNllbCode(targetLang),
      );

      // 5. 创建消息
      final message = Message(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        originalText: text,
        translatedText: translated,
        sourceLanguage: sourceLang,
        targetLanguage: targetLang,
        isFromMe: isFromMe,
        timestamp: DateTime.now(),
        inputType: InputType.voice,
      );

      state = state.copyWith(
        messages: [...state.messages, message],
        isProcessing: false,
      );
    } catch (e) {
      state = state.copyWith(isProcessing: false);
      rethrow;
    }
  }

  /// 清空消息
  void clearMessages() {
    state = state.copyWith(messages: []);
  }

  /// 判断检测到的语言是否为"我的语言"
  bool _isMyLanguage(String detectedLang) {
    // 简单匹配: 如果检测语言与 myLanguage 匹配（或前缀匹配）
    if (detectedLang == state.myLanguage) return true;
    if (detectedLang.startsWith(state.myLanguage)) return true;
    if (state.myLanguage.startsWith(detectedLang)) return true;
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
  return LanguageDetectService();
});

final conversationProvider =
    StateNotifierProvider<ConversationNotifier, ConversationState>((ref) {
  return ConversationNotifier(
    asrService: ref.watch(asrServiceProvider),
    translationService: ref.watch(translationServiceProvider),
    languageDetectService: ref.watch(languageDetectServiceProvider),
  );
});
