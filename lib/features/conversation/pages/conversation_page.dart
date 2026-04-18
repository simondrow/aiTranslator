import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../../../services/audio_service.dart';
import '../../../services/tts_service.dart';
import '../../../services/model_download_trigger.dart';
import '../../../utils/language_codes.dart';
import '../../model_manager/providers/model_manager_provider.dart';
import '../providers/conversation_provider.dart';
import '../widgets/language_bar.dart';
import 'conversation_mode_page.dart';

/// 主页 — Google Translate 风格
class ConversationPage extends ConsumerStatefulWidget {
  const ConversationPage({super.key});

  @override
  ConsumerState<ConversationPage> createState() => _ConversationPageState();
}

class _ConversationPageState extends ConsumerState<ConversationPage>
    with SingleTickerProviderStateMixin {
  final TextEditingController _textController = TextEditingController();
  final FocusNode _textFocusNode = FocusNode();
  final AudioService _audioService = AudioService();
  final TtsService _ttsService = TtsService();

  bool _isRecording = false;
  bool _isCompleted = false;
  bool _firstInteraction = true;
  bool _isStopping = false; // 正在停止录音中（防止重复停止）
  bool _stopRequested = false; // 录音停止已请求，正在进行的非final ASR应丢弃
  int _recordingGeneration = 0; // 录音会话版本号，每次新录音/停止/重置时递增

  /// 流式 ASR 状态
  Timer? _segmentTimer;
  String _streamingAsrText = '';
  bool _isTranscribing = false;
  static const _segmentInterval = Duration(seconds: 3);

  /// 录音按钮动画
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  /// 防抖定时器 (文本输入场景)
  Timer? _debounceTimer;
  static const _debounceDuration = Duration(milliseconds: 400);

  /// 上一次的文本内容（用于判断文本是否真正变化，忽略光标移动）
  String _previousText = '';

  // ============================================================
  // 语音翻译节奏控制
  // ============================================================

  /// 上次触发语音翻译时的源文本快照
  /// 新 ASR 段到达后，对比当前完整文本与此快照，
  /// 只有 **有效字符增量** 达到阈值才触发新一轮翻译。
  String _lastVoiceTranslateSnapshot = '';

  /// 有效字符增量阈值 — 新增多少个有意义字符后才触发翻译
  /// CJK 2 字 ≈ 一个短词；Latin 4 字母 ≈ 一个单词
  static const _voiceTranslateMinDelta = 2;

  /// 录音期间是否有翻译正在进行/已完成
  /// 用于停止录音时判断：如果已有翻译且最终文本无增量，直接 commit
  bool _hasVoiceTranslation = false;

  @override
  void initState() {
    super.initState();
    _ttsService.initialize();
    _textController.addListener(_onTextChanged);
    _textFocusNode.addListener(_onFocusChanged);
    // 启动后自动下载 whisper 模型（如尚未下载）
    Future.microtask(() => _ensureAsrDownloaded());

    // 录音脉冲动画
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  Future<void> _ensureAsrDownloaded() async {
    await Future.delayed(const Duration(seconds: 1));
    if (!mounted) return;
    final modelState = ref.read(modelManagerProvider);
    if (!modelState.isSenseVoiceReady && !modelState.isDownloading) {
      debugPrint('[ConversationPage] 自动触发 SenseVoice 模型下载');
      ref.read(modelManagerProvider.notifier).downloadSenseVoiceIfNeeded();
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _segmentTimer?.cancel();
    _pulseController.dispose();
    _textController.removeListener(_onTextChanged);
    _textFocusNode.removeListener(_onFocusChanged);
    _textController.dispose();
    _textFocusNode.dispose();
    _audioService.dispose();
    _ttsService.dispose();
    super.dispose();
  }

  // ============================================================
  // Model download
  // ============================================================

  Future<bool> _ensureModelReady() async {
    if (!_firstInteraction) return true;
    _firstInteraction = false;

    final notifier = ref.read(conversationProvider.notifier);
    if (notifier.isTranslationReady) return true;

    final ready = await ModelDownloadTrigger.ensureTranslationReady(context, ref);

    if (ready) {
      final modelDir =
          await ref.read(modelManagerProvider.notifier).getHymtModelDir();
      await notifier.initTranslationEngine(modelDir);
    } else {
      _firstInteraction = true;
    }
    return ready;
  }

  // ============================================================
  // Text input
  // ============================================================

  void _onTextChanged() {
    final text = _textController.text;

    // 忽略纯光标移动（文本内容未变化）
    if (text == _previousText) return;
    _previousText = text;

    // 录音期间由 _transcribeSegment 直接驱动翻译，
    // 不走 _onTextChanged → debounce 路径，避免双重触发
    if (_isRecording) return;

    if (text.isEmpty) {
      _debounceTimer?.cancel();
      ref.read(conversationProvider.notifier).cancelAndClear();
      setState(() => _isCompleted = false);
      return;
    }

    if (_isCompleted) setState(() => _isCompleted = false);

    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounceDuration, () async {
      final currentText = _textController.text.trim();
      if (currentText.isNotEmpty) {
        await _ensureModelReady();
        ref.read(conversationProvider.notifier).detectAndTranslate(currentText);
      }
    });
    setState(() {});
  }

  Future<void> _onSubmitted(String _) async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    _debounceTimer?.cancel();
    _textFocusNode.unfocus();

    final notifier = ref.read(conversationProvider.notifier);

    // 取消进行中的翻译，发起最终翻译
    notifier.cancelTranslation();
    await notifier.sendTextMessage(text);
    setState(() => _isCompleted = true);
  }

  /// 完全重置回初始状态（X 按钮 / 清空）
  /// 取消所有后台 ASR/翻译任务，清空输入和结果，收起键盘
  void _resetToInitial() {
    debugPrint('[ConversationPage] 重置到初始状态');
    // 1. 取消所有定时器
    _debounceTimer?.cancel();
    _segmentTimer?.cancel();
    _segmentTimer = null;

    // 2. 如果正在录音，停止录音（不处理最后一段）
    if (_isRecording) {
      _pulseController.stop();
      _pulseController.reset();
      _audioService.stopRecording(); // fire and forget
    }

    // 3. 取消所有 ASR 和翻译任务
    _stopRequested = true;
    _isTranscribing = false;
    _recordingGeneration++; // 使所有残留 ASR 结果过期
    ref.read(conversationProvider.notifier).cancelAndClear();

    // 4. 收起键盘
    _textFocusNode.unfocus();

    // 5. 清空所有 UI 状态
    _previousText = '';
    setState(() {
      _textController.clear();
      _isRecording = false;
      _isCompleted = false;
      _isStopping = false;
      _stopRequested = false;
      _streamingAsrText = '';
      _lastVoiceTranslateSnapshot = '';
      _hasVoiceTranslation = false;
      _firstInteraction = true; // 允许下次交互重新触发模型下载检查
    });
  }

  void _onFocusChanged() {
    if (_textFocusNode.hasFocus) {
      // 获取焦点时退出完成态，进入编辑模式（显示 X 按钮）
      if (_isCompleted) {
        debugPrint('[ConversationPage] 输入框获取焦点, 退出完成态');
        setState(() => _isCompleted = false);
      } else {
        setState(() {});
      }
      return;
    }

    final text = _textController.text.trim();
    if (text.isEmpty) return;
    if (_isCompleted) return;

    _debounceTimer?.cancel();

    final state = ref.read(conversationProvider);
    final notifier = ref.read(conversationProvider.notifier);

    if (state.realtimeTranslation.isNotEmpty) {
      notifier.commitTranslation(text);
      setState(() => _isCompleted = true);
    } else if (!state.isTranslating && !state.isDetecting) {
      notifier.sendTextMessage(text).then((_) {
        if (mounted) setState(() => _isCompleted = true);
      });
    }
  }

  // ============================================================
  // Streaming voice recording
  // ============================================================

  Future<void> _startVoiceRecording() async {
    // 先清理之前的状态，确保干净开始
    _debounceTimer?.cancel();
    _segmentTimer?.cancel();
    _isTranscribing = false;
    _streamingAsrText = '';
    _lastVoiceTranslateSnapshot = '';
    _hasVoiceTranslation = false;

    await _ensureModelReady();

    // 确保 SenseVoice 模型后台下载
    final modelState = ref.read(modelManagerProvider);
    if (!modelState.isSenseVoiceReady && !modelState.isDownloading) {
      ref.read(modelManagerProvider.notifier).downloadSenseVoiceIfNeeded();
    }

    try {
      _textFocusNode.unfocus();

      // 如果上一次录音的 AudioService 还处于录音态（异常情况），先停止
      if (_audioService.isRecording) {
        await _audioService.stopRecording();
      }

      await _audioService.startRecording();

      ref.read(conversationProvider.notifier).cancelAndClear();

      _previousText = '';
      setState(() {
        _isRecording = true;
        _isCompleted = false;
        _isStopping = false;
        _stopRequested = false;
        _recordingGeneration++;
        _streamingAsrText = '';
        _textController.text = '';
      });

      // 启动脉冲动画
      _pulseController.repeat(reverse: true);

      // 启动分段定时器
      _segmentTimer?.cancel();
      _segmentTimer = Timer.periodic(_segmentInterval, (_) {
        _processSegment();
      });
    } catch (e) {
      debugPrint('[ConversationPage] Start recording failed: $e');
      // start failed, nothing to clean up
    }
  }

  Future<void> _stopVoiceRecording() async {
    if (!_isRecording) return;
    _isStopping = true;
    _stopRequested = true; // 标记：让正在进行的非final ASR丢弃结果

    // 停止定时器和动画
    _segmentTimer?.cancel();
    _segmentTimer = null;
    _pulseController.stop();
    _pulseController.reset();

    // 取消进行中的翻译 debounce（文本输入的，不影响语音翻译的 LLM 任务）
    _debounceTimer?.cancel();

    setState(() => _isRecording = false);

    try {
      // 停止录音并处理最后一段
      debugPrint('[ConversationPage] 语音停止: 处理最后一段音频');
      final path = await _audioService.stopRecording();
      if (path.isNotEmpty) {
        await _transcribeSegment(path, isFinal: true);
      }

      // 最终文本
      final finalText = ConversationNotifier.cleanAsrText(_streamingAsrText);
      if (finalText.isEmpty) {
        debugPrint('[ConversationPage] 录音结束但无识别结果');
        return;
      }

      final notifier = ref.read(conversationProvider.notifier);
      final currentState = ref.read(conversationProvider);

      // 判断最终文本相比上次翻译是否有增量
      final finalMeaningful =
          ConversationNotifier.countMeaningfulChars(finalText);
      final snapshotMeaningful =
          ConversationNotifier.countMeaningfulChars(_lastVoiceTranslateSnapshot);
      final delta = finalMeaningful - snapshotMeaningful;

      if (_hasVoiceTranslation &&
          currentState.realtimeTranslation.isNotEmpty &&
          delta < _voiceTranslateMinDelta) {
        // 已有翻译结果且最终文本无有意义增量，直接 commit
        debugPrint(
          '[ConversationPage] 语音结束: 无增量 (delta=$delta), 复用已有翻译',
        );
        notifier.commitTranslation(finalText);
        setState(() {
          _textController.text = finalText;
          _isCompleted = true;
        });
      } else {
        // 有增量或无已有翻译，触发最终翻译
        debugPrint(
          '[ConversationPage] 语音结束: 有增量 (delta=$delta), 执行最终翻译',
        );
        // 取消可能正在进行的旧翻译，用最终全文做翻译
        notifier.cancelTranslation();
        await notifier.sendTextMessage(finalText);
        final newState = ref.read(conversationProvider);
        if (newState.messages.isNotEmpty) {
          setState(() {
            _textController.text = newState.messages.last.originalText;
            _isCompleted = true;
          });
        }
      }
    } catch (e) {
      debugPrint('[ConversationPage] Stop recording failed: $e');
    } finally {
      _isStopping = false;
      _stopRequested = false;
      _recordingGeneration++; // 递增版本号，使所有残留的 ASR Isolate 结果过期
      debugPrint('[ConversationPage] 录音会话结束, gen=$_recordingGeneration');
      if (mounted) setState(() {});
    }
  }

  /// 处理一个录音分段
  Future<void> _processSegment() async {
    if (!_isRecording || _isTranscribing) return;

    try {
      final segmentPath = await _audioService.rotateRecording();
      if (segmentPath.isNotEmpty) {
        await _transcribeSegment(segmentPath);
      }
    } catch (e) {
      debugPrint('[ConversationPage] Segment processing failed: $e');
    }
  }

  /// 转写一段音频并更新 UI
  ///
  /// 语音翻译节奏策略:
  ///   1. ASR 识别完成后，先清理噪音标记
  ///   2. 检查有效字符数（< 1 则丢弃，视为纯噪音）
  ///   3. 追加到 _streamingAsrText，更新输入框
  ///   4. 与上次翻译快照对比有效字符增量:
  ///      增量 >= [_voiceTranslateMinDelta] 且 LLM 空闲 → 触发翻译
  ///      增量不够 或 LLM 忙 → 跳过 (LLM 完成后会从 pending queue 拿最新文本)
  Future<void> _transcribeSegment(String audioPath,
      {bool isFinal = false}) async {
    _isTranscribing = true;
    final myGen = _recordingGeneration; // 捕获当前录音会话版本

    try {
      // 如果录音已停止且不是最后一段，直接丢弃
      if (_stopRequested && !isFinal) {
        debugPrint('[ConversationPage] ASR 任务被跳过 (非final段, 录音已停止)');
        return;
      }

      final notifier = ref.read(conversationProvider.notifier);
      final asrResult = await notifier.transcribeAudio(audioPath);

      // ASR 完成后检查：录音会话是否已过期
      if (myGen != _recordingGeneration) {
        debugPrint('[ConversationPage] ASR 结果丢弃 (录音会话已过期 gen=$myGen, 当前=$_recordingGeneration): "$asrResult"');
        return;
      }

      // 清理噪音标记
      final cleanResult = ConversationNotifier.cleanAsrText(asrResult);

      // 有效字符过少 → 纯噪音段，丢弃
      final meaningfulCount =
          ConversationNotifier.countMeaningfulChars(cleanResult);
      if (meaningfulCount < 1) {
        debugPrint(
          '[ConversationPage] ASR 段丢弃 (有效字符=$meaningfulCount): "$cleanResult"',
        );
        return;
      }

      if (cleanResult.isNotEmpty) {
        _streamingAsrText +=
            (_streamingAsrText.isEmpty ? '' : ' ') + cleanResult;

        if (mounted) {
          final newText = _streamingAsrText;
          _previousText = newText; // 同步 _previousText，防止 _onTextChanged 重入
          setState(() {
            _textController.text = newText;
            _textController.selection = TextSelection.fromPosition(
              TextPosition(offset: _textController.text.length),
            );
          });

          // ---- 语音翻译节奏控制 ----
          // 只有在非 isFinal 段时才在录音期间触发翻译
          // isFinal 段由 _stopVoiceRecording 统一处理
          if (!isFinal && !_stopRequested) {
            _maybeTranslateVoice(newText);
          }
        }
      }
    } catch (e) {
      debugPrint('[ConversationPage] Transcription failed: $e');
    } finally {
      _isTranscribing = false;
    }
  }

  /// 语音录音期间的翻译节奏控制
  ///
  /// 对比当前全文与上次翻译快照的有效字符增量，
  /// 增量足够大且 LLM 空闲时才触发翻译。
  void _maybeTranslateVoice(String currentFullText) {
    final notifier = ref.read(conversationProvider.notifier);

    final currentMeaningful =
        ConversationNotifier.countMeaningfulChars(currentFullText);
    final snapshotMeaningful =
        ConversationNotifier.countMeaningfulChars(_lastVoiceTranslateSnapshot);
    final delta = currentMeaningful - snapshotMeaningful;

    if (delta < _voiceTranslateMinDelta) {
      debugPrint(
        '[ConversationPage] 语音翻译跳过: 增量不足 (delta=$delta < $_voiceTranslateMinDelta)',
      );
      return;
    }

    // 记录快照（即使 LLM 忙也更新，避免下次段又重复判断增量）
    _lastVoiceTranslateSnapshot = currentFullText;
    _hasVoiceTranslation = true;

    // 通过 translateForVoice 调度 (无 debounce，LLM 忙时自动暂存)
    debugPrint(
      '[ConversationPage] 语音翻译触发: delta=$delta, 文本长度=${currentFullText.length}',
    );
    notifier.translateForVoice(currentFullText);
  }

  void _toggleVoiceRecording() {
    if (_isRecording) {
      if (_isStopping) return; // 防止重复停止
      _stopVoiceRecording();
    } else {
      _startVoiceRecording();
    }
  }

  // ============================================================
  // Navigation & TTS
  // ============================================================

  void _copyToClipboard(String text, String message) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 1)),
    );
  }

  void _openHistory() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const HistoryPage()),
    );
  }

  void _speakSource() {
    final text = _textController.text.trim();
    if (text.isEmpty) return;
    final state = ref.read(conversationProvider);
    final lang = state.detectedSourceLang ?? state.myLanguage;
    _ttsService.speak(text, lang);
  }

  void _speakTarget() {
    final state = ref.read(conversationProvider);
    if (state.realtimeTranslation.isEmpty) return;
    final lang = state.detectedTargetLang ?? state.theirLanguage;
    _ttsService.speak(state.realtimeTranslation, lang);
  }

  void _onLanguageChanged() async {
    await _ensureModelReady();

    final currentText = _textController.text.trim();
    final notifier = ref.read(conversationProvider.notifier);

    if (currentText.isNotEmpty) {
      // 有输入内容 → 保留文本，用新语言约束重新检测+翻译
      _previousText = currentText;
      notifier.retranslate(currentText);
      setState(() => _isCompleted = false);
    } else {
      // 无输入 → 正常清空
      notifier.cancelAndClear();
      _previousText = '';
      setState(() => _isCompleted = false);
    }
  }

  // ============================================================
  // Build
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(conversationProvider);
    final hasInput = _textController.text.isNotEmpty;
    final hasTranslation = state.realtimeTranslation.isNotEmpty;
    final isWorking = state.isDetecting || state.isTranslating;

    return Scaffold(
      backgroundColor: AppTheme.surfaceWhite,
      appBar: AppBar(
        backgroundColor: AppTheme.surfaceWhite,
        leading: IconButton(
          icon: const Icon(Icons.history, size: 26),
          tooltip: '历史对话',
          onPressed: _isRecording ? null : _openHistory,
        ),
        centerTitle: true,
        title: const Text(
          'AI Translator',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: AppTheme.textPrimary,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.download_outlined, size: 26),
            tooltip: '模型管理',
            onPressed: _isRecording
                ? null
                : () => Navigator.of(context).pushNamed('/model_download'),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () => _textFocusNode.unfocus(),
              behavior: HitTestBehavior.opaque,
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 16),
                    _buildSourceArea(state),
                    if (hasInput || hasTranslation || isWorking)
                      ..._buildTranslationArea(state),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
          ),
          _buildBottomArea(state),
        ],
      ),
    );
  }

  /// 源文区域
  Widget _buildSourceArea(ConversationState state) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 完成态: 源语种标签
        if (_isCompleted && state.detectedSourceLang != null) ...[
          Text(
            LanguageCodes.getDisplayName(state.detectedSourceLang!),
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: AppTheme.secondaryBlue,
            ),
          ),
          const SizedBox(height: 8),
        ],

        // 录音中 hint 或 文本输入
        if (_isRecording && _textController.text.isEmpty)
          _buildRecordingHint()
        else
          _buildTextInput(),

        // 完成态: 🔊 📋
        if (_isCompleted && state.realtimeTranslation.isNotEmpty) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              _ActionBtn(icon: Icons.volume_up_outlined, onTap: _speakSource),
              const Spacer(),
              _ActionBtn(
                icon: Icons.copy_outlined,
                onTap: () => _copyToClipboard(_textController.text, '已复制原文'),
              ),
            ],
          ),
        ],
      ],
    );
  }

  /// 录音中提示文字
  Widget _buildRecordingHint() {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 8),
      child: Text(
        '请开始说话...',
        style: TextStyle(
          fontSize: 28,
          color: AppTheme.textHint,
          height: 1.3,
          fontWeight: FontWeight.w400,
        ),
      ),
    );
  }

  /// 文本输入框
  Widget _buildTextInput() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: TextField(
            controller: _textController,
            focusNode: _textFocusNode,
            maxLines: 6,
            minLines: 1,
            readOnly: _isRecording, // 录音中输入框只读
            style: const TextStyle(
              fontSize: 28,
              color: AppTheme.textPrimary,
              height: 1.3,
              fontWeight: FontWeight.w400,
            ),
            decoration: const InputDecoration(
              hintText: '输入文字',
              hintStyle: TextStyle(
                fontSize: 28,
                color: AppTheme.textHint,
                height: 1.3,
                fontWeight: FontWeight.w400,
              ),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              filled: false,
              contentPadding: EdgeInsets.zero,
              isDense: true,
            ),
            textInputAction: TextInputAction.done,
            onSubmitted: _onSubmitted,
          ),
        ),
        if ((_textController.text.isNotEmpty || _textFocusNode.hasFocus) &&
            !_isCompleted && !_isRecording)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: IconButton(
              icon: const Icon(Icons.close, size: 22),
              color: AppTheme.textSecondary,
              onPressed: _resetToInitial,
              visualDensity: VisualDensity.compact,
            ),
          ),
      ],
    );
  }

  /// 分隔线 + 译文区域
  List<Widget> _buildTranslationArea(ConversationState state) {
    return [
      const SizedBox(height: 12),
      Container(
        height: 2,
        decoration: BoxDecoration(
          color: AppTheme.secondaryBlue.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(1),
        ),
      ),
      const SizedBox(height: 16),

      // 完成态: 目标语种标签
      if (_isCompleted && state.detectedTargetLang != null) ...[
        Text(
          LanguageCodes.getDisplayName(state.detectedTargetLang!),
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: AppTheme.secondaryBlue,
          ),
        ),
        const SizedBox(height: 8),
      ],

      // 翻译中 / 译文
      if (state.isDetecting || state.isTranslating)
        _buildTranslatingIndicator(state)
      else if (state.realtimeTranslation.isNotEmpty)
        Text(
          state.realtimeTranslation,
          style: const TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w500,
            color: AppTheme.targetTextColor,
            height: 1.3,
          ),
        ),

      // 完成态: 译文 🔊 📋
      if (_isCompleted && state.realtimeTranslation.isNotEmpty) ...[
        const SizedBox(height: 8),
        Row(
          children: [
            _ActionBtn(icon: Icons.volume_up_outlined, onTap: _speakTarget),
            const Spacer(),
            _ActionBtn(
              icon: Icons.copy_outlined,
              onTap: () => _copyToClipboard(state.realtimeTranslation, '已复制翻译结果'),
            ),
          ],
        ),
      ],
    ];
  }

  /// 翻译中指示器 — 如果有上一次译文则同时显示，否则只显示 spinner
  Widget _buildTranslatingIndicator(ConversationState state) {
    if (state.realtimeTranslation.isNotEmpty) {
      // 有上一次译文 → 显示译文 + 小 spinner
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            state.realtimeTranslation,
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w500,
              color: AppTheme.targetTextColor.withValues(alpha: 0.7),
              height: 1.3,
            ),
          ),
          const SizedBox(height: 8),
          const Row(
            children: [
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 1.5),
              ),
              SizedBox(width: 8),
              Text(
                '更新中...',
                style: TextStyle(fontSize: 14, color: AppTheme.textSecondary),
              ),
            ],
          ),
        ],
      );
    }
    return const _ProcessingIndicator();
  }

  /// 底部区域: 语言栏 + 麦克风/停止按钮
  Widget _buildBottomArea(ConversationState state) {
    return Container(
      decoration: BoxDecoration(
        color: _isRecording
            ? const Color(0xFF1A1A2E) // 录音时深色背景
            : AppTheme.backgroundGrey,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 拖拽指示条
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: _isRecording
                        ? Colors.white.withValues(alpha: 0.3)
                        : Colors.grey[350],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // 语言栏（录音时置灰）
              LanguageBar(
                onLanguageChanged: _onLanguageChanged,
                enabled: !_isRecording,
              ),
              const SizedBox(height: 20),

              // 麦克风 / 停止按钮
              _buildMicButton(),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  /// 麦克风 / 停止按钮
  Widget _buildMicButton() {
    if (_isRecording) {
      // 录音中 — 停止按钮 + 脉冲动画
      return AnimatedBuilder(
        animation: _pulseAnimation,
        builder: (context, child) {
          return GestureDetector(
            onTap: _toggleVoiceRecording,
            child: Transform.scale(
              scale: _pulseAnimation.value,
              child: Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.redAccent.withValues(alpha: 0.15),
                  border: Border.all(
                    color: Colors.redAccent.withValues(alpha: 0.3),
                    width: 3,
                  ),
                ),
                child: Center(
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: Colors.redAccent,
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      );
    } else {
      // 正常 — 麦克风按钮
      return GestureDetector(
        onTap: _toggleVoiceRecording,
        child: Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFFD3E3FD),
            boxShadow: [
              BoxShadow(
                color: AppTheme.secondaryBlue.withValues(alpha: 0.15),
                blurRadius: 12,
                spreadRadius: 1,
              ),
            ],
          ),
          child: const Icon(
            Icons.mic,
            color: AppTheme.secondaryBlue,
            size: 36,
          ),
        ),
      );
    }
  }
}

/// 操作按钮（🔊 📋）
class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _ActionBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Icon(icon, size: 22, color: AppTheme.textSecondary),
      ),
    );
  }
}

/// 翻译中指示器
class _ProcessingIndicator extends StatelessWidget {
  const _ProcessingIndicator();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        SizedBox(width: 12),
        Text(
          '翻译中...',
          style: TextStyle(fontSize: 20, color: AppTheme.textSecondary),
        ),
      ],
    );
  }
}
