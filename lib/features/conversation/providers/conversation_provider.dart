import 'dart:async';

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
///
/// 翻译调度策略 (解决连续输入场景下的浪费问题):
///
///   1. **Debounce** — 文本变更后等待一段时间再触发翻译。
///      UI 层 [ConversationPage] 有 400ms debounce；
///      本类 [detectAndTranslate] 内部再做一次 _translateDebounce
///      (默认 600ms) 防止短时间内连续调用实际发起翻译。
///
///   2. **Generation** — 每次新翻译请求递增 [_translateGeneration]，
///      完成时检查：若 generation 已过期说明有更新的请求，丢弃结果。
///
///   3. **文本去重** — 与上次提交翻译的原文比较，完全相同则跳过。
///
///   4. **保留上次结果** — 新翻译进行中时，UI 继续显示上一次的译文
///      (state.realtimeTranslation 不清空)，避免翻译中画面闪烁。
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

  /// 翻译 debounce 定时器
  /// 当连续调用 detectAndTranslate 时，只有最后一次会真正启动翻译。
  Timer? _translateDebounce;

  /// 翻译 debounce 时长。
  /// 语音场景下每 3 秒来一段 ASR，400ms UI debounce + 600ms 翻译 debounce
  /// ≈ 1 秒后触发翻译，留出足够的文本稳定窗口。
  static const _translateDebounceDuration = Duration(milliseconds: 600);

  /// 当前是否有翻译任务正在 LLM 推理中
  bool _isLlmBusy = false;

  /// debounce 期间积压的最新文本（在 LLM 忙时也暂存）
  String? _pendingText;

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

    // 3. ASR (SenseVoice via sherpa-onnx)
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

  /// 手动初始化 ASR 引擎 — SenseVoice (模型下载完成后调用)
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

  // ============================================================
  // 实时翻译调度 (debounce + generation + queue)
  // ============================================================

  /// 实时语种检测 + 翻译
  ///
  /// 调度策略:
  ///   - 内部 debounce [_translateDebounceDuration]，连续快速调用只保留最后一次。
  ///   - 如果 LLM 正在推理中，将文本暂存 [_pendingText]，
  ///     等当前推理结束后自动拾取最新文本继续翻译。
  ///   - 新文本与上次完全相同且已有结果，跳过。
  Future<void> detectAndTranslate(String text) async {
    if (text.trim().isEmpty) {
      if (mounted) state = state.clearRealtime();
      return;
    }

    final cleanText = cleanAsrText(text);
    if (cleanText.isEmpty) {
      if (mounted) state = state.clearRealtime();
      return;
    }

    // 去重：文本与上次完全相同且已有翻译结果，跳过
    if (cleanText == _lastTranslatingText &&
        state.realtimeTranslation.isNotEmpty &&
        !_isLlmBusy) {
      return;
    }

    // 取消之前的 debounce
    _translateDebounce?.cancel();

    // 如果 LLM 正在推理，将新文本暂存，等推理结束后自动处理
    if (_isLlmBusy) {
      _pendingText = cleanText;
      debugPrint(
        '[ConversationNotifier] LLM 忙, 暂存文本: '
        '"${cleanText.length > 30 ? '${cleanText.substring(0, 30)}...' : cleanText}"',
      );
      // 递增 generation 使正在进行的翻译结果过期
      _translateGeneration++;
      return;
    }

    // Debounce: 等待文本稳定后再实际翻译
    _translateDebounce = Timer(_translateDebounceDuration, () {
      _executeTranslation(cleanText);
    });
  }

  /// 实际执行翻译 (debounce 后 / pending 恢复时调用)
  Future<void> _executeTranslation(String cleanText) async {
    // 再次去重
    if (cleanText == _lastTranslatingText &&
        state.realtimeTranslation.isNotEmpty) {
      return;
    }

    final gen = ++_translateGeneration;
    _lastTranslatingText = cleanText;
    _pendingText = null;

    if (mounted) state = state.copyWith(isDetecting: true);

    try {
      // 语种检测：仅首次检测，之后锁定方向
      final ({String source, String target}) dir;
      if (_lockedDirection != null) {
        dir = _lockedDirection!;
      } else {
        dir = _detectDirection(cleanText);
        _lockedDirection = dir;
        debugPrint(
          '[ConversationNotifier] 语种方向已锁定: ${dir.source} → ${dir.target}',
        );
      }

      if (gen != _translateGeneration || !mounted) return;

      // 不清空 realtimeTranslation —— 保留上一次译文，避免 UI 闪烁
      state = state.copyWith(
        detectedSourceLang: dir.source,
        detectedTargetLang: dir.target,
        isDetecting: false,
        isTranslating: true,
      );

      debugPrint(
        '[ConversationNotifier] 开始翻译 gen=$gen: '
        '"${cleanText.length > 40 ? '${cleanText.substring(0, 40)}...' : cleanText}"',
      );
      final sw = Stopwatch()..start();

      _isLlmBusy = true;
      final translated = await _translationService.translate(
        cleanText,
        dir.source,
        dir.target,
      );
      _isLlmBusy = false;

      sw.stop();
      debugPrint(
        '[ConversationNotifier] 翻译完成 gen=$gen ${sw.elapsedMilliseconds}ms',
      );

      // 检查 generation 是否过期
      if (gen != _translateGeneration) {
        debugPrint(
          '[ConversationNotifier] 翻译结果已过期 gen=$gen '
          '(当前: $_translateGeneration), 丢弃',
        );
        // 有暂存文本，立即处理
        _drainPending();
        return;
      }

      if (!mounted) return;
      state = state.copyWith(
        realtimeTranslation: translated,
        isTranslating: false,
        isDetecting: false,
      );

      // 翻译完成后检查是否有暂存文本
      _drainPending();
    } catch (e) {
      _isLlmBusy = false;
      if (gen == _translateGeneration && mounted) {
        state = state.copyWith(isDetecting: false, isTranslating: false);
      }
      debugPrint('[ConversationNotifier] 实时检测翻译失败: $e');
      _drainPending();
    }
  }

  /// 如果有暂存文本，立即启动新一轮翻译（无 debounce）
  void _drainPending() {
    final pending = _pendingText;
    if (pending != null && pending.isNotEmpty) {
      _pendingText = null;
      debugPrint('[ConversationNotifier] 处理暂存文本');
      _executeTranslation(pending);
    }
  }

  /// 取消进行中的翻译（递增 generation 使旧结果过期）
  void cancelTranslation() {
    _translateGeneration++;
    _translateDebounce?.cancel();
    _pendingText = null;
  }

  /// 取消翻译 + 清空实时状态 + 重置语种锁定
  void cancelAndClear() {
    _translateGeneration++;
    _translateDebounce?.cancel();
    _pendingText = null;
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
    _translateDebounce?.cancel();
    _pendingText = null;

    state = state.copyWith(isProcessing: true);

    try {
      final dir = _lockedDirection ?? _detectDirection(text);

      debugPrint('[ConversationNotifier] sendTextMessage 翻译开始 gen=$gen');
      final sw = Stopwatch()..start();

      _isLlmBusy = true;
      final translated = await _translationService.translate(
        text,
        dir.source,
        dir.target,
      );
      _isLlmBusy = false;

      sw.stop();
      debugPrint(
        '[ConversationNotifier] sendTextMessage 翻译完成 ${sw.elapsedMilliseconds}ms',
      );

      if (gen != _translateGeneration) {
        if (mounted) {
          state = state.copyWith(
            isProcessing: false,
            isTranslating: false,
          );
        }
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
      _isLlmBusy = false;
      state = state.copyWith(
        isProcessing: false,
        isTranslating: false,
        isDetecting: false,
      );
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

      debugPrint(
        '[ConversationNotifier] ASR 识别结果: "$text" '
        '(lang: ${asrResult.detectedLanguage})',
      );

      final dir = _detectDirection(text);

      _isLlmBusy = true;
      final translated = await _translationService.translate(
        text,
        dir.source,
        dir.target,
      );
      _isLlmBusy = false;

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
      _isLlmBusy = false;
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
        debugPrint(
          '[ConversationNotifier] transcribeAudio ${sw.elapsedMilliseconds}ms: "$text"',
        );
      } else {
        debugPrint(
          '[ConversationNotifier] transcribeAudio ${sw.elapsedMilliseconds}ms: (empty)',
        );
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

  /// 过滤 ASR 输出中的非语音标记
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
