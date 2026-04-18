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
/// 翻译调度策略:
///
///   1. **Debounce** — 文本输入: UI 400ms + provider 600ms ≈ 1s
///      语音输入: Page 层按有效字符增量控制，无 debounce
///
///   2. **Generation + StopGeneration** — 新请求到来时:
///      a) 递增 [_translateGeneration] 使旧结果过期
///      b) 调用 [_translationService.stopGeneration()] **立即中断**正在进行的 LLM 推理
///      c) 立即启动新翻译，无需等待旧推理完成
///
///   3. **文本去重** — 相同文本不重复翻译
///
///   4. **LLM 忙队列** — 如果 stopGeneration 后 LLM 尚未释放完毕，
///      暂存到 [_pendingText]，释放后 [_drainPending] 自动拾取
///
///   5. **保留上次译文** — 新翻译进行中 UI 继续显示旧译文，避免闪烁
class ConversationNotifier extends StateNotifier<ConversationState> {
  final AsrService _asrService;
  final TranslationService _translationService;
  final LanguageDetectService _languageDetectService;

  /// 翻译请求版本号
  int _translateGeneration = 0;

  /// 上一次提交翻译的原文（去重用）
  String _lastTranslatingText = '';

  /// 已锁定的翻译方向
  ({String source, String target})? _lockedDirection;

  /// 翻译 debounce 定时器 (仅文本输入)
  Timer? _translateDebounce;
  static const _translateDebounceDuration = Duration(milliseconds: 600);

  /// 当前是否有翻译任务正在 LLM 推理中
  bool _isLlmBusy = false;

  /// LLM 忙时积压的最新文本
  String? _pendingText;

  /// 整体 pipeline 计时 (从用户文本变化到翻译结果更新)
  final Stopwatch _pipelineSw = Stopwatch();

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

  Future<void> _initServices() async {
    try {
      await _languageDetectService.initialize();
      debugPrint('[ConversationNotifier] 语种检测服务初始化完成');
    } catch (e) {
      debugPrint('[ConversationNotifier] 语种检测初始化失败: $e');
    }

    try {
      final ready = await _translationService.tryAutoInitialize();
      debugPrint('[ConversationNotifier] 翻译引擎自动初始化: ${ready ? "成功" : "未就绪"}');
    } catch (e) {
      debugPrint('[ConversationNotifier] 翻译引擎自动初始化失败: $e');
    }

    try {
      final ready = await _asrService.tryAutoInitialize();
      debugPrint('[ConversationNotifier] ASR 引擎自动初始化: ${ready ? "成功" : "未就绪"}');
    } catch (e) {
      debugPrint('[ConversationNotifier] ASR 引擎自动初始化失败: $e');
    }
  }

  bool get isTranslationReady => _translationService.isEngineReady;
  bool get isAsrReady => _asrService.isInitialized;
  bool get isLlmBusy => _isLlmBusy;

  Future<void> initTranslationEngine(String modelDir) async {
    try {
      await _translationService.initialize(modelDir);
      debugPrint('[ConversationNotifier] 翻译引擎手动初始化: ${_translationService.isEngineReady}');
    } catch (e) {
      debugPrint('[ConversationNotifier] 翻译引擎手动初始化失败: $e');
    }
  }

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

  ({String source, String target}) _detectDirection(String text) {
    final detectResult = _languageDetectService.detectLanguage(text);
    final rawLang = detectResult.languageCode;

    if (_matchesLanguage(rawLang, state.myLanguage)) {
      return (source: state.myLanguage, target: state.theirLanguage);
    }
    if (_matchesLanguage(rawLang, state.theirLanguage)) {
      return (source: state.theirLanguage, target: state.myLanguage);
    }

    final detectedFamily = LanguageCodes.getFamily(rawLang);
    final myFamily = LanguageCodes.getFamily(state.myLanguage);
    final theirFamily = LanguageCodes.getFamily(state.theirLanguage);

    if (detectedFamily == theirFamily && detectedFamily != myFamily) {
      debugPrint('[ConversationNotifier] 语言族归属: $rawLang → ${state.theirLanguage} 侧');
      return (source: state.theirLanguage, target: state.myLanguage);
    }
    if (detectedFamily == myFamily && detectedFamily != theirFamily) {
      debugPrint('[ConversationNotifier] 语言族归属: $rawLang → ${state.myLanguage} 侧');
      return (source: state.myLanguage, target: state.theirLanguage);
    }

    return (source: state.myLanguage, target: state.theirLanguage);
  }

  // ============================================================
  // 翻译调度
  // ============================================================

  /// 文本输入场景: 带 debounce
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

    if (cleanText == _lastTranslatingText &&
        state.realtimeTranslation.isNotEmpty &&
        !_isLlmBusy) {
      return;
    }

    // 开始 pipeline 计时
    _pipelineSw
      ..reset()
      ..start();

    _translateDebounce?.cancel();

    // ★ 新请求到来时，立即中断正在进行的 LLM 推理
    if (_isLlmBusy) {
      debugPrint(
        '[ConversationNotifier] 新文本到达, 中断旧推理 + 暂存',
      );
      _translateGeneration++;
      _translationService.stopGeneration(); // fire-and-forget
      _pendingText = cleanText;
      return;
    }

    _translateDebounce = Timer(_translateDebounceDuration, () {
      debugPrint(
        '[ConversationNotifier] [pipeline] debounce触发 ${_pipelineSw.elapsedMilliseconds}ms',
      );
      _executeTranslation(cleanText);
    });
  }

  /// 语音场景: 无 debounce，Page 层控制调用时机
  void translateForVoice(String fullText) {
    final cleanText = cleanAsrText(fullText);
    if (cleanText.isEmpty) return;

    if (cleanText == _lastTranslatingText &&
        state.realtimeTranslation.isNotEmpty &&
        !_isLlmBusy) {
      return;
    }

    _pipelineSw
      ..reset()
      ..start();

    // ★ 中断旧推理
    if (_isLlmBusy) {
      _translateGeneration++;
      _translationService.stopGeneration();
      _pendingText = cleanText;
      debugPrint(
        '[ConversationNotifier] [语音] 中断旧推理, 暂存新文本',
      );
      return;
    }

    _executeTranslation(cleanText);
  }

  /// 实际执行翻译
  Future<void> _executeTranslation(String cleanText) async {
    if (cleanText == _lastTranslatingText &&
        state.realtimeTranslation.isNotEmpty) {
      return;
    }

    final gen = ++_translateGeneration;
    _lastTranslatingText = cleanText;
    _pendingText = null;

    if (mounted) state = state.copyWith(isDetecting: true);

    try {
      // 语种检测 (仅首次)
      final ({String source, String target}) dir;
      if (_lockedDirection != null) {
        dir = _lockedDirection!;
      } else {
        final lidSw = Stopwatch()..start();
        dir = _detectDirection(cleanText);
        lidSw.stop();
        _lockedDirection = dir;
        debugPrint(
          '[ConversationNotifier] [pipeline] 语种检测 ${lidSw.elapsedMilliseconds}ms: '
          '${dir.source} → ${dir.target}',
        );
      }

      if (gen != _translateGeneration || !mounted) return;

      state = state.copyWith(
        detectedSourceLang: dir.source,
        detectedTargetLang: dir.target,
        isDetecting: false,
        isTranslating: true,
      );

      debugPrint(
        '[ConversationNotifier] [pipeline] 翻译开始 gen=$gen | '
        'pipeline已过=${_pipelineSw.elapsedMilliseconds}ms | '
        '"${cleanText.length > 40 ? '${cleanText.substring(0, 40)}...' : cleanText}"',
      );

      _isLlmBusy = true;
      final translated = await _translationService.translate(
        cleanText,
        dir.source,
        dir.target,
      );
      _isLlmBusy = false;

      if (gen != _translateGeneration) {
        debugPrint(
          '[ConversationNotifier] [pipeline] 翻译过期 gen=$gen (当前=$_translateGeneration), 丢弃',
        );
        _drainPending();
        return;
      }

      if (!mounted) return;

      final pipelineMs = _pipelineSw.elapsedMilliseconds;
      _pipelineSw.stop();
      debugPrint(
        '[ConversationNotifier] [pipeline] ✅ 翻译完成 gen=$gen | '
        'pipeline总耗时=${pipelineMs}ms | '
        '"$translated"',
      );

      state = state.copyWith(
        realtimeTranslation: translated,
        isTranslating: false,
        isDetecting: false,
      );

      _drainPending();
    } catch (e) {
      _isLlmBusy = false;
      if (gen == _translateGeneration && mounted) {
        state = state.copyWith(isDetecting: false, isTranslating: false);
      }
      debugPrint('[ConversationNotifier] 翻译失败: $e');
      _drainPending();
    }
  }

  void _drainPending() {
    final pending = _pendingText;
    if (pending != null && pending.isNotEmpty) {
      _pendingText = null;
      debugPrint('[ConversationNotifier] [pipeline] 处理暂存文本');
      _executeTranslation(pending);
    }
  }

  /// 取消翻译 — 中断 LLM 推理 + 递增 generation
  void cancelTranslation() {
    _translateGeneration++;
    _translateDebounce?.cancel();
    _pendingText = null;
    if (_isLlmBusy) {
      _translationService.stopGeneration();
      _isLlmBusy = false;
    }
  }

  /// 取消翻译 + 清空状态 + 重置语种锁定
  void cancelAndClear() {
    _translateGeneration++;
    _translateDebounce?.cancel();
    _pendingText = null;
    _lockedDirection = null;
    _lastTranslatingText = '';
    if (_isLlmBusy) {
      _translationService.stopGeneration();
      _isLlmBusy = false;
    }
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

    final gen = ++_translateGeneration;
    _translateDebounce?.cancel();
    _pendingText = null;
    if (_isLlmBusy) {
      _translationService.stopGeneration();
    }

    state = state.copyWith(isProcessing: true);

    try {
      final dir = _lockedDirection ?? _detectDirection(text);

      debugPrint('[ConversationNotifier] sendTextMessage gen=$gen 开始');
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
        '[ConversationNotifier] sendTextMessage gen=$gen 完成 ${sw.elapsedMilliseconds}ms',
      );

      if (gen != _translateGeneration) {
        if (mounted) {
          state = state.copyWith(isProcessing: false, isTranslating: false);
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

  Future<String> transcribeAudio(String audioPath) async {
    try {
      final sw = Stopwatch()..start();
      final asrResult = await _asrService.transcribe(audioPath);
      sw.stop();
      final text = asrResult.text.trim();
      debugPrint(
        '[ConversationNotifier] [pipeline] ASR ${sw.elapsedMilliseconds}ms: '
        '"${text.length > 50 ? '${text.substring(0, 50)}...' : text}"',
      );
      return text;
    } catch (e) {
      debugPrint('[ConversationNotifier] transcribeAudio failed: $e');
      return '';
    }
  }

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

  static final _noiseTokenPattern = RegExp(
    r'\[(?:BLANK_AUDIO|blank_audio|music|Music|MUSIC|cow mooing|laughter|applause|noise|silence|Silence|NOISE)\]'
    r'|\((?:music|Music|laughter|applause|noise)\)'
    r'|<\|(?:nospeech|NOSPEECH|blank)\|>'
    r'|♪+'
    r'|\.{4,}',
    caseSensitive: false,
  );

  static String cleanAsrText(String text) {
    return text
        .replaceAll(_noiseTokenPattern, '')
        .replaceAll(RegExp(r'\s{2,}'), ' ')
        .trim();
  }

  static int countMeaningfulChars(String text) {
    int count = 0;
    for (final rune in text.runes) {
      if ((rune >= 0x4E00 && rune <= 0x9FFF) ||
          (rune >= 0x3400 && rune <= 0x4DBF) ||
          (rune >= 0x3040 && rune <= 0x309F) ||
          (rune >= 0x30A0 && rune <= 0x30FF) ||
          (rune >= 0xAC00 && rune <= 0xD7AF) ||
          (rune >= 0x0041 && rune <= 0x005A) ||
          (rune >= 0x0061 && rune <= 0x007A)) {
        count++;
      }
    }
    return count;
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
