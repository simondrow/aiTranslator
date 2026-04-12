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

  /// 翻译请求版本号——每次新请求 +1，旧请求完成时对比，过期则丢弃
  int _translateGeneration = 0;

  /// 上一次提交翻译的原文（用于去重，避免相同文本重复翻译）
  String _lastTranslatingText = '';

  /// 已锁定的翻译方向（源 → 目标）
  ({String source, String target})? _lockedDirection;

  ConversationNotifier({
    required AsrService asrService,
    required TranslationService translationService,
    required LanguageDetectService languageDetectService,
  })  : _asrService = asrService,
        _translationService = translationService,
        _languageDetectService = languageDetectService,
        super(const ConversationState()) {
    Future.microtask(() => _initServices());
  }

  /// 初始化语种检测 + 翻译引擎 + ASR 引擎
  Future<void> _initServices() async {
    // 1. 语种检测
    try {
      await _languageDetectService.initialize();
      debugPrint('[ConversationNotifier] 语种检测服务初始化完成');
    } catch (e) {
      debugPrint('[ConversationNotifier] 语种检测初始化失败: $e');
      debugPrint('[ConversationNotifier] 将使用后备检测逻辑');
    }

    // 2. 翻译引擎
    try {
      final ready = await _translationService.tryAutoInitialize();
      debugPrint('[ConversationNotifier] 翻译引擎自动初始化: ${ready ? "成功" : "未就绪 (stub 模式)"}');
    } catch (e) {
      debugPrint('[ConversationNotifier] 翻译引擎自动初始化失败: $e');
    }

    // 3. ASR (whisper.cpp)
    try {
      final ready = await _asrService.tryAutoInitialize();
      debugPrint('[ConversationNotifier] ASR 引擎自动初始化: ${ready ? "成功" : "未就绪 (模型未下载)"}');
    } catch (e) {
      debugPrint('[ConversationNotifier] ASR 引擎自动初始化失败: $e');
    }
  }

  /// 翻译引擎是否真正就绪
  bool get isTranslationReady => _translationService.isEngineReady;

  /// ASR 引擎是否就绪
  bool get isAsrReady => _asrService.isInitialized;

  /// 手动初始化翻译引擎 (模型下载完成后调用)
  Future<void> initTranslationEngine(String modelDir) async {
    try {
      await _translationService.initialize(modelDir);
      debugPrint('[ConversationNotifier] 翻译引擎手动初始化: ${_translationService.isEngineReady}');
    } catch (e) {
      debugPrint('[ConversationNotifier] 翻译引擎手动初始化失败: $e');
    }
  }

  /// 手动初始化 ASR 引擎 (模型下载完成后调用)
  Future<void> initAsrEngine(String modelPath) async {
    try {
      await _asrService.initialize(modelPath);
      debugPrint('[ConversationNotifier] ASR 引擎手动初始化: ${_asrService.isInitialized}');
    } catch (e) {
      debugPrint('[ConversationNotifier] ASR 引擎手动初始化失败: $e');
    }
  }

  void setMyLanguage(String langCode) {
    state = state.copyWith(myLanguage: langCode);
    _lockedDirection = null;
    _lastTranslatingText = '';
  }

  void setTheirLanguage(String langCode) {
    state = state.copyWith(theirLanguage: langCode);
    _lockedDirection = null;
    _lastTranslatingText = '';
  }

  /// 检测语种并确定翻译方向
  ({String source, String target}) _detectDirection(String text) {
    final detectResult = _languageDetectService.detectLanguage(text);
    final rawLang = detectResult.languageCode;

    // 1. 精确匹配
    if (_matchesLanguage(rawLang, state.myLanguage)) {
      return (source: state.myLanguage, target: state.theirLanguage);
    }
    if (_matchesLanguage(rawLang, state.theirLanguage)) {
      return (source: state.theirLanguage, target: state.myLanguage);
    }

    // 2. 语言族归属
    final detectedFamily = LanguageCodes.getFamily(rawLang);
    final myFamily = LanguageCodes.getFamily(state.myLanguage);
    final theirFamily = LanguageCodes.getFamily(state.theirLanguage);

    if (detectedFamily == theirFamily && detectedFamily != myFamily) {
      debugPrint('[ConversationNotifier] 语言族归属: $rawLang → ${state.theirLanguage} 侧 (同族: $detectedFamily)');
      return (source: state.theirLanguage, target: state.myLanguage);
    }
    if (detectedFamily == myFamily && detectedFamily != theirFamily) {
      debugPrint('[ConversationNotifier] 语言族归属: $rawLang → ${state.myLanguage} 侧 (同族: $detectedFamily)');
      return (source: state.myLanguage, target: state.theirLanguage);
    }

    // 3. 默认
    return (source: state.myLanguage, target: state.theirLanguage);
  }

  /// 实时语种检测 + 翻译
  /// 每次调用会递增 generation，旧的翻译结果如果晚于新请求则丢弃
  Future<void> detectAndTranslate(String text) async {
    if (text.trim().isEmpty) {
      if (mounted) state = state.clearRealtime();
      return;
    }

    // 去重：文本与上次完全相同且已有翻译结果，跳过
    final cleanText = cleanAsrText(text);
    if (cleanText.isEmpty) {
      if (mounted) state = state.clearRealtime();
      return;
    }
    if (cleanText == _lastTranslatingText && state.realtimeTranslation.isNotEmpty) {
      debugPrint('[ConversationNotifier] 去重跳过 (文本相同): "${cleanText.length > 40 ? cleanText.substring(0, 40) + "..." : cleanText}"');
      return;
    }

    // 递增版本号，标记新请求
    final gen = ++_translateGeneration;
    _lastTranslatingText = cleanText;

    if (mounted) state = state.copyWith(isDetecting: true);

    try {
      // 语种检测：仅首次检测，之后锁定方向
      final ({String source, String target}) dir;
      if (_lockedDirection != null) {
        dir = _lockedDirection!;
      } else {
        dir = _detectDirection(text);
        _lockedDirection = dir;
        debugPrint('[ConversationNotifier] 语种方向已锁定: ${dir.source} → ${dir.target}');
      }

      // 检查是否已被新请求取代
      if (gen != _translateGeneration) {
        // 不更新 isTranslating，由最新请求负责
        return;
      }

      if (!mounted) return;
      state = state.copyWith(
        detectedSourceLang: dir.source,
        detectedTargetLang: dir.target,
        isDetecting: false,
        isTranslating: true,
      );

      debugPrint('[ConversationNotifier] 开始翻译 gen=$gen: "${cleanText.length > 40 ? cleanText.substring(0, 40) + "..." : cleanText}"');
      final sw = Stopwatch()..start();

      final translated = await _translationService.translate(
        cleanText,
        LanguageCodes.getNllbCode(dir.source),
        LanguageCodes.getNllbCode(dir.target),
      );

      sw.stop();
      debugPrint('[ConversationNotifier] 翻译完成 gen=$gen ${sw.elapsedMilliseconds}ms');

      // 再次检查：翻译完成时如果 generation 已过期，丢弃结果
      if (gen != _translateGeneration) {
        debugPrint('[ConversationNotifier] 翻译结果已过期 gen=$gen (当前: $_translateGeneration), 丢弃');
        return;
      }

      if (!mounted) return;
      state = state.copyWith(
        realtimeTranslation: translated,
        isTranslating: false,
        isDetecting: false,
      );
    } catch (e) {
      // 只有当前代才更新状态
      if (gen == _translateGeneration && mounted) {
        state = state.copyWith(isDetecting: false, isTranslating: false);
      }
      debugPrint('[ConversationNotifier] 实时检测翻译失败: $e');
    }
  }

  /// 取消进行中的翻译（递增 generation 使旧结果过期）
  void cancelTranslation() {
    _translateGeneration++;
  }

  /// 取消翻译 + 清空实时状态 + 重置语种锁定
  void cancelAndClear() {
    _translateGeneration++;
    _lockedDirection = null;
    _lastTranslatingText = '';
    if (mounted) state = state.clearRealtime();
  }

  void clearRealtime() {
    if (mounted) state = state.clearRealtime();
  }

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

  Future<void> sendTextMessage(String text) async {
    if (text.trim().isEmpty) return;

    // 取消进行中的实时翻译
    final gen = ++_translateGeneration;

    state = state.copyWith(isProcessing: true);

    try {
      // sendTextMessage 使用当前锁定方向或重新检测
      final dir = _lockedDirection ?? _detectDirection(text);

      debugPrint('[ConversationNotifier] sendTextMessage 翻译开始 gen=$gen');
      final sw = Stopwatch()..start();
      final translated = await _translationService.translate(
        text,
        LanguageCodes.getNllbCode(dir.source),
        LanguageCodes.getNllbCode(dir.target),
      );
      sw.stop();
      debugPrint('[ConversationNotifier] sendTextMessage 翻译完成 ${sw.elapsedMilliseconds}ms');

      // 如果被另一个 sendTextMessage 取代，丢弃
      // （注意：detectAndTranslate 不会递增 generation 超过 sendTextMessage 的 gen）
      if (gen != _translateGeneration) {
        if (mounted) state = state.copyWith(isProcessing: false, isTranslating: false);
        return;
      }

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
        isTranslating: false,
        isDetecting: false,
        detectedSourceLang: dir.source,
        detectedTargetLang: dir.target,
        realtimeTranslation: translated,
      );
    } catch (e) {
      state = state.copyWith(isProcessing: false, isTranslating: false, isDetecting: false);
      debugPrint('[ConversationNotifier] sendTextMessage 失败: $e');
    }
  }

  /// 发送语音消息
  Future<void> sendVoiceMessage(String audioPath) async {
    state = state.copyWith(isProcessing: true);

    try {
      // ASR: 语音 → 文本
      final asrResult = await _asrService.transcribe(audioPath);
      final String text = asrResult.text;

      if (text.trim().isEmpty) {
        state = state.copyWith(isProcessing: false);
        debugPrint('[ConversationNotifier] ASR 返回空文本');
        return;
      }

      debugPrint('[ConversationNotifier] ASR 识别结果: "$text" (lang: ${asrResult.detectedLanguage})');

      // 检测翻译方向
      final dir = _detectDirection(text);

      // 翻译
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
        isTranslating: false,
        isDetecting: false,
        detectedSourceLang: dir.source,
        detectedTargetLang: dir.target,
        realtimeTranslation: translated,
      );
    } catch (e) {
      state = state.copyWith(isProcessing: false);
      debugPrint('[ConversationNotifier] sendVoiceMessage 失败: $e');
    }
  }


  /// 仅做语音转文字（供流式录音调用）
  Future<String> transcribeAudio(String audioPath) async {
    try {
      final sw = Stopwatch()..start();
      final asrResult = await _asrService.transcribe(audioPath);
      sw.stop();
      final text = asrResult.text.trim();
      if (text.isNotEmpty) {
        debugPrint('[ConversationNotifier] transcribeAudio ${sw.elapsedMilliseconds}ms: "$text"');
      } else {
        debugPrint('[ConversationNotifier] transcribeAudio ${sw.elapsedMilliseconds}ms: (empty)');
      }
      return text;
    } catch (e) {
      debugPrint('[ConversationNotifier] transcribeAudio failed: $e');
      return '';
    }
  }

  /// 删除指定位置的消息
  void removeMessageAt(int index) {
    final updated = List<Message>.from(state.messages);
    if (index >= 0 && index < updated.length) {
      updated.removeAt(index);
      state = state.copyWith(messages: updated);
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


  /// 过滤 whisper 输出中的非语音标记
  /// [BLANK_AUDIO], [music], [Music], [cow mooing], (music), etc.
  static final _noiseTokenPattern = RegExp(
    r'\[(?:BLANK_AUDIO|blank_audio|music|Music|MUSIC|cow mooing|laughter|applause|noise|silence)\]'
    r'|\((?:music|Music|laughter|applause)\)',
    caseSensitive: false,
  );

  /// 清理 ASR 文本：移除噪音标记并整理空格
  static String cleanAsrText(String text) {
    return text
        .replaceAll(_noiseTokenPattern, '')
        .replaceAll(RegExp(r'\s{2,}'), ' ')
        .trim();
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
