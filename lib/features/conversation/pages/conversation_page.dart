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

  /// 流式 ASR 状态
  Timer? _segmentTimer;
  String _streamingAsrText = '';
  bool _isTranscribing = false;
  static const _segmentInterval = Duration(seconds: 3);

  /// 录音按钮动画
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  /// 防抖定时器
  Timer? _debounceTimer;
  static const _debounceDuration = Duration(milliseconds: 400);

  /// 上一次的文本内容（用于判断文本是否真正变化，忽略光标移动）
  String _previousText = '';

  @override
  void initState() {
    super.initState();
    _ttsService.initialize();
    _textController.addListener(_onTextChanged);
    _textFocusNode.addListener(_onFocusChanged);
    // 启动后自动下载 whisper 模型（如尚未下载）
    Future.microtask(() => _ensureWhisperDownloaded());

    // 录音脉冲动画
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  Future<void> _ensureWhisperDownloaded() async {
    await Future.delayed(const Duration(seconds: 1));
    if (!mounted) return;
    final modelState = ref.read(modelManagerProvider);
    if (!modelState.isWhisperReady && !modelState.isDownloading) {
      debugPrint('[ConversationPage] 自动触发 whisper 模型下载');
      ref.read(modelManagerProvider.notifier).downloadWhisperIfNeeded();
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

    final ready = await ModelDownloadTrigger.ensureNllbReady(context, ref);

    if (ready) {
      final modelDir =
          await ref.read(modelManagerProvider.notifier).getNllbModelDir();
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

    if (text.isEmpty) {
      _debounceTimer?.cancel();
      ref.read(conversationProvider.notifier).cancelAndClear();
      if (_isCompleted) setState(() => _isCompleted = false);
      setState(() {});
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

  void _clearAll() {
    _debounceTimer?.cancel();
    ref.read(conversationProvider.notifier).cancelAndClear();
    _previousText = '';
    setState(() {
      _textController.clear();
      _isCompleted = false;
      _streamingAsrText = '';
    });
  }

  void _onFocusChanged() {
    if (_textFocusNode.hasFocus) return;

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

    await _ensureModelReady();

    // 确保 whisper 模型后台下载
    final modelState = ref.read(modelManagerProvider);
    if (!modelState.isWhisperReady && !modelState.isDownloading) {
      ref.read(modelManagerProvider.notifier).downloadWhisperIfNeeded();
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

    // 停止定时器和动画
    _segmentTimer?.cancel();
    _segmentTimer = null;
    _pulseController.stop();
    _pulseController.reset();

    setState(() => _isRecording = false);

    try {
      // 停止录音并处理最后一段
      final path = await _audioService.stopRecording();
      if (path.isNotEmpty) {
        await _transcribeSegment(path, isFinal: true);
      }

      // 最终文本 — 使用统一的噪音过滤
      final finalText = ConversationNotifier.cleanAsrText(_streamingAsrText);
      if (finalText.isNotEmpty) {
        final notifier = ref.read(conversationProvider.notifier);
        final currentState = ref.read(conversationProvider);

        if (currentState.realtimeTranslation.isNotEmpty) {
          // 已有实时翻译结果，直接 commit，不重新翻译
          debugPrint('[ConversationPage] 语音结束: 复用已有翻译结果');
          notifier.commitTranslation(finalText);
          setState(() {
            _textController.text = finalText;
            _isCompleted = true;
          });
        } else {
          // 没有翻译结果（可能 debounce 还没触发），做一次翻译
          debugPrint('[ConversationPage] 语音结束: 无已有翻译，执行最终翻译');
          await notifier.sendTextMessage(finalText);
          final newState = ref.read(conversationProvider);
          if (newState.messages.isNotEmpty) {
            setState(() {
              _textController.text = newState.messages.last.originalText;
              _isCompleted = true;
            });
          }
        }
      } else {
        debugPrint('[ConversationPage] 录音结束但无识别结果');
      }
    } catch (e) {
      debugPrint('[ConversationPage] Stop recording failed: $e');
    } finally {
      _isStopping = false;
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
  Future<void> _transcribeSegment(String audioPath,
      {bool isFinal = false}) async {
    _isTranscribing = true;

    try {
      final notifier = ref.read(conversationProvider.notifier);
      final asrResult = await notifier.transcribeAudio(audioPath);

      // 过滤 [BLANK_AUDIO], [music], [cow mooing] 等无效标记
      final cleanResult = ConversationNotifier.cleanAsrText(asrResult);

      if (cleanResult.isNotEmpty) {
        _streamingAsrText +=
            (_streamingAsrText.isEmpty ? '' : ' ') + cleanResult;

        if (mounted) {
          // 先更新 _previousText 再设 controller，
          // 让 _onTextChanged 感知到内容变化并走 debounce 翻译，不会重复
          final newText = _streamingAsrText;
          _previousText = ''; // 强制 _onTextChanged 识别为内容变化
          setState(() {
            _textController.text = newText;
            _textController.selection = TextSelection.fromPosition(
              TextPosition(offset: _textController.text.length),
            );
          });
          // 翻译完全由 _onTextChanged 的 debounce 统一触发，不再手动调用
        }
      }
    } catch (e) {
      debugPrint('[ConversationPage] Transcription failed: $e');
    } finally {
      _isTranscribing = false;
    }
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
    // 切换语言后清空翻译结果，重置语种锁定
    ref.read(conversationProvider.notifier).cancelAndClear();
    _previousText = '';
    setState(() {
      _isCompleted = false;
      _textController.clear();
    });
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
                onTap: () {
                  Clipboard.setData(
                      ClipboardData(text: _textController.text));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('已复制原文'),
                      duration: Duration(seconds: 1),
                    ),
                  );
                },
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
        if (_textController.text.isNotEmpty && !_isCompleted && !_isRecording)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: IconButton(
              icon: const Icon(Icons.close, size: 22),
              color: AppTheme.textSecondary,
              onPressed: _clearAll,
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
        const _ProcessingIndicator()
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
              onTap: () {
                Clipboard.setData(
                    ClipboardData(text: state.realtimeTranslation));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('已复制翻译结果'),
                    duration: Duration(seconds: 1),
                  ),
                );
              },
            ),
          ],
        ),
      ],
    ];
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
